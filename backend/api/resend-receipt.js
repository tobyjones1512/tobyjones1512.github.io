// Lightweight Resend Receipt API endpoint
// POST /api/resend-receipt
// Body: { orderId: string, email?: string }
// CORS: allow common origins used by this repo
const ALLOWED_ORIGINS = [
  'https://tobyjones.ca',
  'https://www.tobyjones.ca',
  'https://tobyjones1512.github.io',
];

module.exports = async (req, res) => {
  const requestOrigin = (req.headers.origin || '').toLowerCase();
  let corsOrigin = ALLOWED_ORIGINS[0];
  if (requestOrigin) {
    const normOrigin = requestOrigin.endsWith('/') ? requestOrigin.slice(0, -1) : requestOrigin;
    const match = ALLOWED_ORIGINS.find((o) => {
      const normAllowed = o.endsWith('/') ? o.slice(0, -1) : o;
      return normOrigin === normAllowed;
    });
    if (match) corsOrigin = normOrigin;
  }

  res.setHeader('Access-Control-Allow-Origin', corsOrigin);
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Vary', 'Origin');

  if (req.method === 'OPTIONS') return res.status(200).end();
  // Optional API key authentication for this endpoint (enable via env var)
  const REQUIRED_API_KEY = process.env.RESEND_RECEIPT_API_KEY;
  if (REQUIRED_API_KEY) {
    const providedKey = (req.headers['x-api-key'] || '').trim() || (req.headers['authorization'] || '').replace(/^Bearer\s+/i, '').trim();
    const internalCall = (req.headers['x-internal-call'] || '0') === '1';
    if (internalCall) {
      if (!providedKey) {
        return res.status(401).json({ success: false, message: 'Missing API key.' });
      }
      if (providedKey !== REQUIRED_API_KEY) {
        return res.status(403).json({ success: false, message: 'Invalid API key.' });
      }
    }
  }
  if (req.method !== 'POST') {
    return res.status(405).json({ success: false, message: 'Method not allowed.' });
  }

  const { orderId, email } = req.body || {};
  if (!orderId) {
    return res.status(400).json({ success: false, message: 'Missing orderId.' });
  }

  // In a real implementation, trigger the backend's receipt email workflow here.
  // For now, simulate success and return provided data for visibility.
  // You can replace the simulated action with actual mailer logic as soon as available.
  console.log('Resend receipt requested for order', orderId, 'to', email);

  // Simulated success response
  return res.status(200).json({ success: true, orderId, email, message: 'Receipt resend initiated.' });
};
