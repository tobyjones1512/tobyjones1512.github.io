const AuthorizeNet = require("authorizenet");
const { kv } = require("@vercel/kv");

const ApiContracts = AuthorizeNet.APIContracts;
const ApiControllers = AuthorizeNet.APIControllers;
const Constants = AuthorizeNet.Constants;

const ALLOWED_ORIGINS = [
  "https://tobyjones.ca",
  "https://www.tobyjones.ca",
  "https://tobyjones1512.github.io",
];

const PRODUCTS = {
  "scheduling":     { prefix: "SCHED", download: "/downloads/scheduling.zip" },
  "call-sheets":    { prefix: "CALLS", download: "/downloads/call-sheets.zip" },
  "budgeting":      { prefix: "BUDGT", download: "/downloads/budgeting.zip" },
  "filmmakers-kit": { prefix: "FMKIT", download: "/downloads/filmmakers-kit.zip" },
};

function generateSerialKey(prefix) {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const seg = () =>
    Array.from({ length: 4 }, () => chars[Math.floor(Math.random() * chars.length)]).join("");
  return `${prefix}-${seg()}-${seg()}-${seg()}`;
}

module.exports = async (req, res) => {
  const requestOrigin = (req.headers.origin || "").toLowerCase();
  let corsOrigin = ALLOWED_ORIGINS[0];
  if (requestOrigin) {
    const normOrigin = requestOrigin.endsWith("/") ? requestOrigin.slice(0, -1) : requestOrigin;
    const match = ALLOWED_ORIGINS.find((o) => {
      const normAllowed = o.endsWith("/") ? o.slice(0, -1) : o;
      return normOrigin === normAllowed;
    });
    if (match) corsOrigin = normOrigin;
  }

  res.setHeader("Access-Control-Allow-Origin", corsOrigin);
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Vary", "Origin");

  const AUTH_LOGIN_ID = process.env.AUTHORIZENET_API_LOGIN_ID;
  const AUTH_TXN_KEY =
    process.env.AUTHORIZENET_TRANSACTION_KEY || process.env.AUTHORIZENET_CLIENT_KEY;

  if (!AUTH_LOGIN_ID || !AUTH_TXN_KEY) {
    console.error("Authorize.Net credentials missing");
    return res.status(500).json({
      success: false,
      message:
        "Payment is not yet configured. If you are the site owner, please add the AUTHORIZENET_API_LOGIN_ID, AUTHORIZENET_CLIENT_KEY, and CHARGE_URL GitHub Secrets and re-run the GitHub Actions deployment workflow.",
    });
  }

  if (req.method === "OPTIONS") return res.status(200).end();

  if (req.method !== "POST") {
    return res.status(405).json({ success: false, message: "Method not allowed." });
  }

  const { opaqueData, amount, taxAmount, currency, billing, description, product } =
    req.body || {};

  if (!opaqueData?.dataValue || !opaqueData?.dataDescriptor) {
    return res.status(400).json({ success: false, message: "Invalid payment token." });
  }

  const parsedAmount = parseFloat(amount);
  if (!parsedAmount || parsedAmount < 0.01) {
    return res.status(400).json({ success: false, message: "Invalid amount." });
  }

  const env =
    process.env.AUTHORIZENET_ENV === "production"
      ? Constants.endpoint.production
      : Constants.endpoint.sandbox;

  const merchantAuth = new ApiContracts.MerchantAuthenticationType();
  merchantAuth.setName(AUTH_LOGIN_ID);
  merchantAuth.setTransactionKey(AUTH_TXN_KEY);

  const opaqueDataType = new ApiContracts.OpaqueDataType();
  opaqueDataType.setDataDescriptor(opaqueData.dataDescriptor);
  opaqueDataType.setDataValue(opaqueData.dataValue);

  const paymentType = new ApiContracts.PaymentType();
  paymentType.setOpaqueData(opaqueDataType);

  const billTo = new ApiContracts.CustomerAddressType();
  billTo.setFirstName((billing?.firstName || "").slice(0, 50));
  billTo.setLastName((billing?.lastName || "").slice(0, 50));
  billTo.setZip((billing?.zip || "").slice(0, 20));

  const txnRequest = new ApiContracts.TransactionRequestType();
  txnRequest.setTransactionType(ApiContracts.TransactionTypeEnum.AUTHCAPTURETRANSACTION);
  txnRequest.setPayment(paymentType);
  txnRequest.setAmount(parsedAmount.toFixed(2));
  txnRequest.setBillTo(billTo);

  if (taxAmount && parseFloat(taxAmount) > 0) {
    const taxType = new ApiContracts.ExtendedAmountType();
    taxType.setAmount(parseFloat(taxAmount).toFixed(2));
    taxType.setName("Tax");
    txnRequest.setTax(taxType);
  }

  if (billing?.email) {
    const customerData = new ApiContracts.CustomerDataType();
    customerData.setEmail(billing.email.slice(0, 255));
    txnRequest.setCustomer(customerData);
  }

  const orderDetails = new ApiContracts.OrderType();
  orderDetails.setDescription(description || "Purchase");
  txnRequest.setOrder(orderDetails);

  const createRequest = new ApiContracts.CreateTransactionRequest();
  createRequest.setMerchantAuthentication(merchantAuth);
  createRequest.setTransactionRequest(txnRequest);

  return new Promise((resolve) => {
    const ctrl = new ApiControllers.CreateTransactionController(createRequest.getJSON());
    ctrl.setEnvironment(env);

    ctrl.execute(async () => {
      const apiResponse = ctrl.getResponse();
      const response = new ApiContracts.CreateTransactionResponse(apiResponse);

      if (
        response &&
        response.getMessages().getResultCode() === ApiContracts.MessageTypeEnum.OK
      ) {
        const txnResponse = response.getTransactionResponse();

        if (txnResponse && txnResponse.getMessages()) {
          const txnId = txnResponse.getTransId();

          // Extract last 4 digits from masked account number (e.g. "XXXX1234")
          const accountNum = txnResponse.getAccountNumber() || "";
          const last4 = accountNum.replace(/\D/g, "").slice(-4) || accountNum.slice(-4);

          // Generate serial key and persist to KV
          let serialKey = null;
          if (product && PRODUCTS[product] && last4) {
            const { prefix, download } = PRODUCTS[product];
            serialKey = generateSerialKey(prefix);
            const record = {
              product,
              key: serialKey,
              txnId,
              downloadUrl: download,
              email: billing?.email || "",
              createdAt: new Date().toISOString(),
            };
            try {
              const existing = (await kv.get(`keys:last4:${last4}`)) || [];
              existing.push(record);
              await kv.set(`keys:last4:${last4}`, existing);
            } catch (kvErr) {
              // KV failure is non-fatal — charge succeeded, log and continue
              console.error("KV write error:", kvErr);
            }
          }

          resolve(
            res.status(200).json({
              success: true,
              transactionId: txnId,
              serialKey,
            })
          );
        } else {
          const errCode =
            txnResponse?.getErrors()?.getError()?.[0]?.getErrorCode() || "UNKNOWN";
          const errText =
            txnResponse?.getErrors()?.getError()?.[0]?.getErrorText() || "Transaction declined.";
          resolve(
            res.status(402).json({ success: false, message: `${errText} (${errCode})` })
          );
        }
      } else {
        const errText =
          response?.getMessages()?.getMessage()?.[0]?.getText() || "Payment failed.";
        resolve(res.status(402).json({ success: false, message: errText }));
      }
    });
  });
};
