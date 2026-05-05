const AuthorizeNet = require("authorizenet");
const ApiContracts = AuthorizeNet.APIContracts;
const ApiControllers = AuthorizeNet.APIControllers;
const Constants = AuthorizeNet.Constants;

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Vary", "Origin");

  if (req.method === "OPTIONS") return res.status(200).end();
  if (req.method !== "POST") {
    return res.status(405).json({ success: false, message: "Method not allowed." });
  }

  const { transactionId } = req.body || {};
  if (!transactionId) {
    return res.status(400).json({ success: false, message: "Missing transactionId." });
  }

  const AUTH_LOGIN_ID = process.env.AUTHORIZENET_API_LOGIN_ID;
  const AUTH_TXN_KEY = process.env.AUTHORIZENET_TRANSACTION_KEY || process.env.AUTHORIZENET_CLIENT_KEY;

  if (!AUTH_LOGIN_ID || !AUTH_TXN_KEY) {
    return res.status(500).json({ success: false, message: "Authorize.Net credentials missing." });
  }

  const env = process.env.AUTHORIZENET_ENV === "production"
    ? Constants.endpoint.production
    : Constants.endpoint.sandbox;

  const merchantAuth = new ApiContracts.MerchantAuthenticationType();
  merchantAuth.setName(AUTH_LOGIN_ID);
  merchantAuth.setTransactionKey(AUTH_TXN_KEY);

  const getRequest = new ApiContracts.GetTransactionDetailsRequest();
  getRequest.setMerchantAuthentication(merchantAuth);
  getRequest.setTransId(transactionId);

  const apiCall = new Promise((resolve) => {
    const ctrl = new ApiControllers.GetTransactionDetailsController(getRequest.getJSON());
    ctrl.setEnvironment(env);

    ctrl.execute(() => {
      const apiResponse = ctrl.getResponse();
      const response = new ApiContracts.GetTransactionDetailsResponse(apiResponse);

      if (response && response.getMessages().getResultCode() === ApiContracts.MessageTypeEnum.OK) {
        const txn = response.getTransaction();
        resolve(res.status(200).json({
          success: true,
          data: {
            transId: txn.getTransId(),
            submitTimeUTC: txn.getSubmitTimeUTC(),
            submitTimeLocal: txn.getSubmitTimeLocal(),
            transactionStatus: txn.getTransactionStatus(),
            invoiceNumber: txn.getInvoiceNumber(),
            authAmount: txn.getAuthAmount(),
            settleAmount: txn.getSettleAmount(),
            accountNumber: txn.getAccountNumber(),
            accountType: txn.getAccountType(),
            firstName: txn.getFirstName(),
            lastName: txn.getLastName(),
            email: txn.getCustomer() ? txn.getCustomer().getEmail() : null,
            orderDescription: txn.getOrder() ? txn.getOrder().getDescription() : null,
          }
        }));
      } else {
        const err = response?.getMessages()?.getMessage()?.[0];
        resolve(res.status(400).json({
          success: false,
          message: err ? `${err.getText()} (${err.getCode()})` : "Failed to get transaction details."
        }));
      }
    });
  });

  // Ensure we always respond before the client's read timeout fires.
  const deadline = new Promise((resolve) =>
    setTimeout(() => resolve(
      res.status(504).json({ success: false, message: "Request to payment gateway timed out. Please try again." })
    ), 8000)
  );

  return Promise.race([apiCall, deadline]);
};
