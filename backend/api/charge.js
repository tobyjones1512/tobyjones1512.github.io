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

const ApiContracts   = AuthorizeNet.APIContracts;
const ApiControllers = AuthorizeNet.APIControllers;
const Constants      = AuthorizeNet.Constants;

const ALLOWED_ORIGINS = [
  'https://tobyjones.ca',
  'https://www.tobyjones.ca',
  'https://tobyjones1512.github.io'
];

module.exports = async (req, res) => {
  const requestOrigin = req.headers.origin || '';
  const corsOrigin = ALLOWED_ORIGINS.includes(requestOrigin)
    ? requestOrigin
    : ALLOWED_ORIGINS[0];

  // CORS
  res.setHeader('Access-Control-Allow-Origin', corsOrigin);
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Vary', 'Origin');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ success: false, message: 'Method not allowed.' });
  }

  const { opaqueData, amount, currency, billing, description, taxAmount, discountAmount, tipAmount } = req.body || {};

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
    ? Constants.endpoint.production
    : Constants.endpoint.sandbox;

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

  // Calculate amounts (tax-exempt items won't have tax)
  const parsedTipAmount = parseFloat(tipAmount) || 0;
  const parsedTaxAmount = parseFloat(taxAmount) || 0;
  const parsedDiscountAmount = parseFloat(discountAmount) || 0;

  txnRequest.setAmount(parsedAmount.toFixed(2));
  txnRequest.setBillTo(billTo);

  // Tax (VAT/Tax line item) - only if taxAmount > 0
  if (parsedTaxAmount > 0) {
    const taxType = new ApiContracts.ExtendedAmountType();
    taxType.setName('HST Tax');
    taxType.setAmount(parsedTaxAmount.toFixed(2));
    taxType.setDescription('HST 13%');
    txnRequest.setTax(taxType);
  }

  // Tip (Tax-Exempt - added as a separate line item)
  if (parsedTipAmount > 0) {
    const tipLineItem = new ApiContracts.LineItemType();
    tipLineItem.setItemId('TIP');
    tipLineItem.setName('Tip (Tax-Exempt)');
    tipLineItem.setDescription('Optional tip - tax exempt');
    tipLineItem.setQuantity(1);
    tipLineItem.setUnitPrice(parsedTipAmount.toFixed(2));
    tipLineItem.setTaxable(false);  // Mark as tax-exempt in Authorize.net
    txnRequest.addLineItems(tipLineItem);
  }

  // Discount amount
  if (parsedDiscountAmount > 0) {
    const discountType = new ApiContracts.ExtendedAmountType();
    discountType.setName('AMEX Discount');
    discountType.setAmount(parsedDiscountAmount.toFixed(2));
    discountType.setDescription('AMEX 25% Discount');
    txnRequest.setShipping(discountType); // Using shipping field for discount display
  }

  // Optional: attach customer email for receipt
  if (billing?.email) {
    const customerData = new ApiContracts.CustomerDataType();
    customerData.setEmail(billing.email.slice(0, 255));
    txnRequest.setCustomer(customerData);
  }

  // Order description (use custom description from request, or default)
  const orderDetails = new ApiContracts.OrderType();
  orderDetails.setDescription(description || 'Purchase');
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
