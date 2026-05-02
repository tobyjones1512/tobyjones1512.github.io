/**
 * Vercel Serverless Function — Authorize.net charge endpoint (backend folder)
 *
 * This file is the canonical location for the Vercel API route in the backend
 * folder. The root api/charge.js route will be wired via vercel.json rewrite
 * to point to this file to keep all backend code together.
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
  // Compute CORS upfront so error paths still include headers
  const requestOrigin = (req.headers.origin || '').toLowerCase();
  // Robust origin check: tolerate trailing slashes and minor variations
  let corsOrigin = ALLOWED_ORIGINS[0];
  if (requestOrigin) {
    const normOrigin = requestOrigin.endsWith('/') ? requestOrigin.slice(0, -1) : requestOrigin;
    const match = ALLOWED_ORIGINS.find((o) => {
      const normAllowed = o.endsWith('/') ? o.slice(0, -1) : o;
      return normOrigin === normAllowed;
    });
    if (match) {
      corsOrigin = normOrigin;
    }
  }

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

  const { opaqueData, amount, taxAmount, tipAmount, discount, currency, billing, description } = req.body || {};

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
  txnRequest.setAmount(parsedAmount.toFixed(2));
  txnRequest.setBillTo(billTo);

  // ── Line Items ──────────────────────────────────────
  const lineItems = new ApiContracts.ArrayOfLineItem();

  // Calculate license amount (total - tax - tip)
  const licenseAmt = parseFloat(parsedAmount) - (parseFloat(taxAmount) || 0) - (parseFloat(tipAmount) || 0);

  // Item 1: IPTV Manager License
  const lineItem1 = new ApiContracts.LineItemType();
  lineItem1.setItemId('1');
  lineItem1.setName('IPTV Manager License');
  lineItem1.setDescription('One-time licence - macOS & Windows');
  lineItem1.setQuantity(1);
  lineItem1.setUnitPrice(licenseAmt.toFixed(2));
  lineItem1.setTaxable(false);
  lineItems.getLineItem().push(lineItem1);

  // Item 2: Tax (if applicable)
  if (taxAmount && parseFloat(taxAmount) > 0) {
    const taxType = new ApiContracts.ExtendedAmountType();
    taxType.setAmount(parseFloat(taxAmount).toFixed(2));
    taxType.setName('HST');
    taxType.setDescription('Harmonized Sales Tax');
    txnRequest.setTax(taxType);

    const lineItem2 = new ApiContracts.LineItemType();
    lineItem2.setItemId('2');
    lineItem2.setName('HST (13%)');
    lineItem2.setDescription('Harmonized Sales Tax');
    lineItem2.setQuantity(1);
    lineItem2.setUnitPrice(parseFloat(taxAmount).toFixed(2));
    lineItem2.setTaxable(false);
    lineItems.getLineItem().push(lineItem2);
  }

  // Item 3: Tip (if applicable, tax-exempt)
  if (tipAmount && parseFloat(tipAmount) > 0) {
    const lineItem3 = new ApiContracts.LineItemType();
    lineItem3.setItemId('3');
    lineItem3.setName('Tip');
    lineItem3.setDescription('Optional tip (tax-exempt)');
    lineItem3.setQuantity(1);
    lineItem3.setUnitPrice(parseFloat(tipAmount).toFixed(2));
    lineItem3.setTaxable(false);
    lineItems.getLineItem().push(lineItem3);
    txnRequest.setTaxExempt(true);
  }

  txnRequest.setLineItems(lineItems);

  // Optional: attach customer email for receipt
  if (billing?.email) {
    const customerData = new ApiContracts.CustomerDataType();
    customerData.setEmail(billing.email.slice(0, 255));
    txnRequest.setCustomer(customerData);
  }

  // Order description (use custom description from request, or default)
  const orderDetails = new ApiContracts.OrderType();
  let fullDescription = description || 'Purchase';
  if (discount && parseFloat(discount) > 0) {
    fullDescription += ` (Discount: $${parseFloat(discount).toFixed(2)})`;
  }
  orderDetails.setDescription(fullDescription);
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
