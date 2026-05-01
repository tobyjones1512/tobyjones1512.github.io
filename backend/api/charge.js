/**
 * Vercel Serverless Function — Authorize.net charge endpoint
 *
 * Deploy this backend separately from GitHub Pages:
 *   1. Push the /backend folder to a new GitHub repo (or the same one)
 *   2. Import the project at vercel.com
 *   3. Set environment variables in the Vercel dashboard:
 *        AUTHORIZENET_API_LOGIN_ID  — your API Login ID
 *        AUTHORIZENET_TRANSACTION_KEY — your Transaction Key  (KEEP SECRET)
 *        AUTHORIZENET_ENV           — "sandbox" or "production"
 *        ALLOWED_ORIGIN             — https://tobyjones.ca (your site URL)
 *   4. Copy the deployed function URL into the GitHub Secret CHARGE_URL
 *      e.g. https://your-project.vercel.app/api/charge
 *
 * The Transaction Key must NEVER appear in client-side code.
 */

const AuthorizeNet = require('authorizenet');

const ApiContracts  = AuthorizeNet.APIContracts;
const ApiControllers = AuthorizeNet.APIControllers;
const SDKConstants  = AuthorizeNet.SDKConstants;

module.exports = async (req, res) => {
  const allowedOrigin = process.env.ALLOWED_ORIGIN || 'https://tobyjones.ca';

  // CORS
  res.setHeader('Access-Control-Allow-Origin', allowedOrigin);
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ success: false, message: 'Method not allowed.' });
  }

  const { opaqueData, amount, currency, billing } = req.body || {};

  // Basic input validation
  if (!opaqueData?.dataValue || !opaqueData?.dataDescriptor) {
    return res.status(400).json({ success: false, message: 'Invalid payment token.' });
  }

  const parsedAmount = parseFloat(amount);
  if (!parsedAmount || parsedAmount < 0.01) {
    return res.status(400).json({ success: false, message: 'Invalid amount.' });
  }

  // Configure Authorize.net environment
  const env = process.env.AUTHORIZENET_ENV === 'production'
    ? SDKConstants.endpoint.production
    : SDKConstants.endpoint.sandbox;

  const merchantAuth = new ApiContracts.MerchantAuthenticationType();
  merchantAuth.setName(process.env.AUTHORIZENET_API_LOGIN_ID);
  merchantAuth.setTransactionKey(process.env.AUTHORIZENET_TRANSACTION_KEY);

  // Opaque payment data (from Accept.js nonce)
  const opaqueDataType = new ApiContracts.OpaqueDataType();
  opaqueDataType.setDataDescriptor(opaqueData.dataDescriptor);
  opaqueDataType.setDataValue(opaqueData.dataValue);

  const paymentType = new ApiContracts.PaymentType();
  paymentType.setOpaqueData(opaqueDataType);

  // Billing address
  const billTo = new ApiContracts.CustomerAddressType();
  billTo.setFirstName((billing?.firstName || '').slice(0, 50));
  billTo.setLastName((billing?.lastName  || '').slice(0, 50));
  billTo.setZip((billing?.zip || '').slice(0, 20));

  // Transaction request
  const txnRequest = new ApiContracts.TransactionRequestType();
  txnRequest.setTransactionType(ApiContracts.TransactionTypeEnum.AUTHCAPTURETRANSACTION);
  txnRequest.setPayment(paymentType);
  txnRequest.setAmount(parsedAmount.toFixed(2));
  txnRequest.setBillTo(billTo);

  // Optional: attach customer email for receipt
  if (billing?.email) {
    const customerData = new ApiContracts.CustomerDataType();
    customerData.setEmail(billing.email.slice(0, 255));
    txnRequest.setCustomer(customerData);
  }

  // Order description
  const orderDetails = new ApiContracts.OrderType();
  orderDetails.setDescription('IPTV Manager Licence');
  txnRequest.setOrder(orderDetails);

  const createRequest = new ApiContracts.CreateTransactionRequest();
  createRequest.setMerchantAuthentication(merchantAuth);
  createRequest.setTransactionRequest(txnRequest);

  return new Promise((resolve) => {
    const ctrl = new ApiControllers.CreateTransactionController(createRequest.getJSON());
    ctrl.setEnvironment(env);

    ctrl.execute(() => {
      const apiResponse = ctrl.getResponse();
      const response    = new ApiContracts.CreateTransactionResponse(apiResponse);

      if (
        response &&
        response.getMessages().getResultCode() === ApiContracts.MessageTypeEnum.OK
      ) {
        const txnResponse = response.getTransactionResponse();

        if (txnResponse && txnResponse.getMessages()) {
          resolve(res.status(200).json({
            success:       true,
            transactionId: txnResponse.getTransId()
          }));
        } else {
          const errCode = txnResponse?.getErrors()?.getError()?.[0]?.getErrorCode() || 'UNKNOWN';
          const errText = txnResponse?.getErrors()?.getError()?.[0]?.getErrorText() || 'Transaction declined.';
          resolve(res.status(402).json({ success: false, message: `${errText} (${errCode})` }));
        }
      } else {
        const errText = response?.getMessages()?.getMessage()?.[0]?.getText() || 'Payment failed.';
        resolve(res.status(402).json({ success: false, message: errText }));
      }
    });
  });
};
