const AuthorizeNet = require('authorizenet');
const ApiContracts = AuthorizeNet.APIContracts;
const ApiControllers = AuthorizeNet.APIControllers;
const Constants = AuthorizeNet.Constants;

const ALLOWED_ORIGINS = [
  'https://tobyjones.ca',
  'https://www.tobyjones.ca',
  'https://tobyjones1512.github.io'
];

module.exports = async (req, res) => {
  // CORS setup
  const requestOrigin = (req.headers.origin || '').toLowerCase();
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

  const { opaqueData, email } = req.body || {};

  if (!opaqueData?.dataValue || !opaqueData?.dataDescriptor || !email) {
    return res.status(400).json({ success: false, message: 'Missing required fields.' });
  }

  // Authorize.net credentials
  const AUTH_LOGIN_ID = process.env.AUTHORIZENET_API_LOGIN_ID;
  const AUTH_TXN_KEY = process.env.AUTHORIZENET_TRANSACTION_KEY || process.env.AUTHORIZENET_CLIENT_KEY;

  if (!AUTH_LOGIN_ID || !AUTH_TXN_KEY) {
    return res.status(500).json({ success: false, message: 'Payment system not configured.' });
  }

  // Configure Authorize.net environment
  const env = process.env.AUTHORIZENET_ENV === 'production' ? Constants.endpoint.production : Constants.endpoint.sandbox;

  // Create merchant auth
  const merchantAuth = new ApiContracts.MerchantAuthenticationType();
  merchantAuth.setName(AUTH_LOGIN_ID);
  merchantAuth.setTransactionKey(AUTH_TXN_KEY);

  // Search for transactions from the last 2 years
  const startDate = new Date();
  startDate.setFullYear(startDate.getFullYear() - 2);
  const formattedStartDate = startDate.toISOString().split('T')[0];
  const formattedEndDate = new Date().toISOString().split('T')[0];

  // Get settled batches - correct double 't' in "Settled"
  const batchRequest = new ApiContracts.GetSettledBatchListRequest();
  batchRequest.setMerchantAuthentication(merchantAuth);
  batchRequest.setFirstSettlementDate(formattedStartDate);
  batchRequest.setLastSettlementDate(formattedEndDate);

  return new Promise((resolve) => {
    const batchCtrl = new ApiControllers.GetSettledBatchListController(batchRequest.getJSON());
    batchCtrl.setEnvironment(env);

    batchCtrl.execute(() => {
      const apiResponse = batchCtrl.getResponse();
      const response = new ApiContracts.GetSettledBatchListResponse(apiResponse);

      if (response.getMessages().getResultCode() !== ApiContracts.MessageTypeEnum.OK) {
        return resolve(res.status(500).json({ success: false, message: 'Failed to fetch transactions.' }));
      }

      const batches = response.getBatchList().getBatch();
      const purchasedApps = new Set();

      // Process each batch
      const batchPromises = batches.map(batch => {
        return new Promise((batchResolve) => {
          const batchId = batch.getBatchId();
          const txnRequest = new ApiContracts.GetTransactionListRequest();
          txnRequest.setMerchantAuthentication(merchantAuth);
          txnRequest.setBatchId(batchId);

          const txnCtrl = new ApiControllers.GetTransactionListController(txnRequest.getJSON());
          txnCtrl.setEnvironment(env);

          txnCtrl.execute(() => {
            const txnResponse = txnCtrl.getResponse();
            const txnListResponse = new ApiContracts.GetTransactionListResponse(txnResponse);

            if (txnListResponse.getMessages().getResultCode() === ApiContracts.MessageTypeEnum.OK) {
              const transactions = txnListResponse.getTransactions().getTransaction();
              transactions.forEach(txn => {
                // Check if transaction is settled and email matches
                if (txn.getTransactionStatus() === 'settledSuccessfully') {
                  const txnEmail = txn.getBillTo()?.getEmail()?.toLowerCase();
                  if (txnEmail === email.toLowerCase()) {
                    // Check order description to determine app
                    const description = txn.getOrder()?.getDescription()?.toLowerCase() || '';
                    if (description.includes('iptv manager')) purchasedApps.add('iptv-manager');
                    if (description.includes('scheduling')) purchasedApps.add('scheduling');
                    if (description.includes('budgeting')) purchasedApps.add('budgeting');
                    if (description.includes('call sheets')) purchasedApps.add('call-sheets');
                    if (description.includes('filmmakers kit')) purchasedApps.add('filmmakers-kit');
                  }
                }
              });
            }
            batchResolve();
          });
        });
      });

      Promise.all(batchPromises).then(() => {
        resolve(res.status(200).json({ success: true, apps: Array.from(purchasedApps) }));
      }).catch(err => {
        resolve(res.status(500).json({ success: false, message: 'Error processing transactions.' }));
      });
    });
  });
};
