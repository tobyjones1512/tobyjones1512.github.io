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

  if (req.method === "OPTIONS") return res.status(200).end();

  if (req.method !== "POST") {
    return res.status(405).json({ success: false, message: "Method not allowed." });
  }

  const AUTH_LOGIN_ID = process.env.AUTHORIZENET_API_LOGIN_ID;
  const AUTH_TXN_KEY =
    process.env.AUTHORIZENET_TRANSACTION_KEY || process.env.AUTHORIZENET_CLIENT_KEY;

  if (!AUTH_LOGIN_ID || !AUTH_TXN_KEY) {
    return res.status(500).json({ success: false, message: "Payment system not configured." });
  }

  const { opaqueData } = req.body || {};

  if (!opaqueData?.dataValue || !opaqueData?.dataDescriptor) {
    return res.status(400).json({ success: false, message: "Invalid payment token." });
  }

  const env =
    process.env.AUTHORIZENET_ENV === "production"
      ? Constants.endpoint.production
      : Constants.endpoint.sandbox;

  const merchantAuth = new ApiContracts.MerchantAuthenticationType();
  merchantAuth.setName(AUTH_LOGIN_ID);
  merchantAuth.setTransactionKey(AUTH_TXN_KEY);

  // $1 auth-only to identify the card without charging
  const opaqueDataType = new ApiContracts.OpaqueDataType();
  opaqueDataType.setDataDescriptor(opaqueData.dataDescriptor);
  opaqueDataType.setDataValue(opaqueData.dataValue);

  const paymentType = new ApiContracts.PaymentType();
  paymentType.setOpaqueData(opaqueDataType);

  const orderDetails = new ApiContracts.OrderType();
  orderDetails.setDescription("Redownload Serial Key Verification. WILL NOT CAPTURE.");

  const txnRequest = new ApiContracts.TransactionRequestType();
  txnRequest.setTransactionType(ApiContracts.TransactionTypeEnum.AUTHONLYTRANSACTION);
  txnRequest.setPayment(paymentType);
  txnRequest.setAmount("1.00");
  txnRequest.setTaxExempt(true);
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
        !response ||
        response.getMessages().getResultCode() !== ApiContracts.MessageTypeEnum.OK
      ) {
        const errText =
          response?.getMessages()?.getMessage()?.[0]?.getText() || "Card verification failed.";
        return resolve(res.status(402).json({ success: false, message: errText }));
      }

      const txnResponse = response.getTransactionResponse();

      if (!txnResponse || !txnResponse.getMessages()) {
        const errCode =
          txnResponse?.getErrors()?.getError()?.[0]?.getErrorCode() || "UNKNOWN";
        const errText =
          txnResponse?.getErrors()?.getError()?.[0]?.getErrorText() || "Card verification declined.";
        return resolve(
          res.status(402).json({ success: false, message: `${errText} (${errCode})` })
        );
      }

      const authTxnId = txnResponse.getTransId();
      const accountNum = txnResponse.getAccountNumber() || "";
      const last4 = accountNum.replace(/\D/g, "").slice(-4) || accountNum.slice(-4);

      // Void the $1 auth immediately so no hold remains on the card
      voidTransaction(merchantAuth, env, authTxnId).catch((e) =>
        console.error("Void failed for auth txn", authTxnId, e)
      );

      if (!last4 || last4.length < 4) {
        return resolve(
          res.status(400).json({ success: false, message: "Could not read card details." })
        );
      }

      // Look up serial keys stored under this card's last 4 digits
      let purchases = [];
      try {
        purchases = (await kv.get(`keys:last4:${last4}`)) || [];
      } catch (kvErr) {
        console.error("KV read error:", kvErr);
        return resolve(
          res.status(500).json({ success: false, message: "Could not retrieve purchases." })
        );
      }

      if (purchases.length === 0) {
        return resolve(
          res.status(200).json({
            success: true,
            purchases: [],
            message: "No purchases found for this card.",
          })
        );
      }

      resolve(res.status(200).json({ success: true, purchases }));
    });
  });
};

function voidTransaction(merchantAuth, env, txnId) {
  return new Promise((resolve, reject) => {
    const voidTxn = new ApiContracts.TransactionRequestType();
    voidTxn.setTransactionType(ApiContracts.TransactionTypeEnum.VOIDTRANSACTION);
    voidTxn.setRefTransId(txnId);

    const voidRequest = new ApiContracts.CreateTransactionRequest();
    voidRequest.setMerchantAuthentication(merchantAuth);
    voidRequest.setTransactionRequest(voidTxn);

    const ctrl = new ApiControllers.CreateTransactionController(voidRequest.getJSON());
    ctrl.setEnvironment(env);
    ctrl.execute(() => {
      const r = ctrl.getResponse();
      const resp = new ApiContracts.CreateTransactionResponse(r);
      if (resp?.getMessages()?.getResultCode() === ApiContracts.MessageTypeEnum.OK) {
        resolve();
      } else {
        reject(new Error("Void response not OK"));
      }
    });
  });
}
