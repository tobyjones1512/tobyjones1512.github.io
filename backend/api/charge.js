/**
 * Vercel Serverless Function — Authorize.net charge endpoint (backend folder)
 *
 * This file is the canonical location for the Vercel API route in the backend
 * folder. The root api/charge.js route will be wired via vercel.json rewrite
 * to point to this file to keep all backend code together.
 */

const AuthorizeNet = require("authorizenet");

const ApiContracts = AuthorizeNet.APIContracts;
const ApiControllers = AuthorizeNet.APIControllers;
const Constants = AuthorizeNet.Constants;

const ALLOWED_ORIGINS = [
  "https://tobyjones.ca",
  "https://www.tobyjones.ca",
  "https://tobyjones1512.github.io",
];

module.exports = async (req, res) => {
  // Compute CORS upfront so error paths still include headers
  const requestOrigin = (req.headers.origin || "").toLowerCase();
  // Robust origin check: tolerate trailing slashes and minor variations
  let corsOrigin = ALLOWED_ORIGINS[0];
  if (requestOrigin) {
    const normOrigin = requestOrigin.endsWith("/")
      ? requestOrigin.slice(0, -1)
      : requestOrigin;
    const match = ALLOWED_ORIGINS.find((o) => {
      const normAllowed = o.endsWith("/") ? o.slice(0, -1) : o;
      return normOrigin === normAllowed;
    });
    if (match) {
      corsOrigin = normOrigin;
    }
  }

  // CORS
  res.setHeader("Access-Control-Allow-Origin", corsOrigin);
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Vary", "Origin");

  // Normalize/prepare credential sources for GitHub Actions secrets compatibility
  const AUTH_LOGIN_ID = process.env.AUTHORIZENET_API_LOGIN_ID;
  const AUTH_TXN_KEY =
    process.env.AUTHORIZENET_TRANSACTION_KEY ||
    process.env.AUTHORIZENET_CLIENT_KEY;
  // If credentials are missing, return a clear, actionable error to the frontend
  // The frontend will surface this to the user as "Payment is not yet configured.."
  if (!AUTH_LOGIN_ID || !AUTH_TXN_KEY) {
    console.error(
      "Authorize.Net credentials missing: AUTHORIZENET_API_LOGIN_ID or AUTHORIZENET_TRANSACTION_KEY/CLIENT_KEY not set",
    );
    return res.status(500).json({
      success: false,
      message:
        "Payment is not yet configured. If you are the site owner, please add the AUTHORIZENET_API_LOGIN_ID, AUTHORIZENET_CLIENT_KEY, and CHARGE_URL GitHub Secrets and re-run the GitHub Actions deployment workflow.",
    });
  }

  if (req.method === "OPTIONS") {
    return res.status(200).end();
  }

  if (req.method !== "POST") {
    return res
      .status(405)
      .json({ success: false, message: "Method not allowed." });
  }

  const { opaqueData, amount, taxAmount, currency, billing, description } =
    req.body || {};

  // Basic input validation
  if (!opaqueData?.dataValue || !opaqueData?.dataDescriptor) {
    return res
      .status(400)
      .json({ success: false, message: "Invalid payment token." });
  }

  const parsedAmount = parseFloat(amount);
  if (!parsedAmount || parsedAmount < 0.01) {
    return res.status(400).json({ success: false, message: "Invalid amount." });
  }

  // Configure Authorize.net environment
  const env =
    process.env.AUTHORIZENET_ENV === "production"
      ? Constants.endpoint.production
      : Constants.endpoint.sandbox;

  const merchantAuth = new ApiContracts.MerchantAuthenticationType();
  merchantAuth.setName(AUTH_LOGIN_ID);
  merchantAuth.setTransactionKey(AUTH_TXN_KEY);

  // Opaque payment data (from Accept.js nonce)
  const opaqueDataType = new ApiContracts.OpaqueDataType();
  opaqueDataType.setDataDescriptor(opaqueData.dataDescriptor);
  opaqueDataType.setDataValue(opaqueData.dataValue);

  const paymentType = new ApiContracts.PaymentType();
  paymentType.setOpaqueData(opaqueDataType);

  // Billing address
  const billTo = new ApiContracts.CustomerAddressType();
  billTo.setFirstName((billing?.firstName || "").slice(0, 50));
  billTo.setLastName((billing?.lastName || "").slice(0, 50));
  billTo.setZip((billing?.zip || "").slice(0, 20));

  // Transaction request
  const txnRequest = new ApiContracts.TransactionRequestType();
  txnRequest.setTransactionType(
    ApiContracts.TransactionTypeEnum.AUTHCAPTURETRANSACTION,
  );
  txnRequest.setPayment(paymentType);
  txnRequest.setAmount(parsedAmount.toFixed(2));
  txnRequest.setBillTo(billTo);

  // Optional: attach tax if provided
  if (taxAmount && parseFloat(taxAmount) > 0) {
    const taxType = new ApiContracts.ExtendedAmountType();
    taxType.setAmount(parseFloat(taxAmount).toFixed(2));
    taxType.setName("Tax");
    txnRequest.setTax(taxType);
  }

  // Optional: attach customer email for receipt
  if (billing?.email) {
    const customerData = new ApiContracts.CustomerDataType();
    customerData.setEmail(billing.email.slice(0, 255));
    txnRequest.setCustomer(customerData);
  }

  // Order description
  const orderDetails = new ApiContracts.OrderType();
  orderDetails.setDescription(description || "Purchase");
  txnRequest.setOrder(orderDetails);

  const createRequest = new ApiContracts.CreateTransactionRequest();
  createRequest.setMerchantAuthentication(merchantAuth);
  createRequest.setTransactionRequest(txnRequest);

  return new Promise((resolve) => {
    const ctrl = new ApiControllers.CreateTransactionController(
      createRequest.getJSON(),
    );
    ctrl.setEnvironment(env);

    ctrl.execute(() => {
      const apiResponse = ctrl.getResponse();
      const response = new ApiContracts.CreateTransactionResponse(apiResponse);

      if (
        response &&
        response.getMessages().getResultCode() ===
          ApiContracts.MessageTypeEnum.OK
      ) {
        const txnResponse = response.getTransactionResponse();

        if (txnResponse && txnResponse.getMessages()) {
          resolve(
            res.status(200).json({
              success: true,
              transactionId: txnResponse.getTransId(),
            }),
          );
        } else {
          const errCode =
            txnResponse?.getErrors()?.getError()?.[0]?.getErrorCode() ||
            "UNKNOWN";
          const errText =
            txnResponse?.getErrors()?.getError()?.[0]?.getErrorText() ||
            "Transaction declined.";
          resolve(
            res
              .status(402)
              .json({ success: false, message: `${errText} (${errCode})` }),
          );
        }
      } else {
        const errText =
          response?.getMessages()?.getMessage()?.[0]?.getText() ||
          "Payment failed.";
        resolve(res.status(402).json({ success: false, message: errText }));
      }
    });
  });
};
