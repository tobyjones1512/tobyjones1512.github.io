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
  "scheduling":     { prefix: "SCHED", name: "Scheduling",     download: "/downloads/scheduling.zip" },
  "call-sheets":    { prefix: "CALLS", name: "Call Sheets",    download: "/downloads/call-sheets.zip" },
  "budgeting":      { prefix: "BUDGT", name: "Budgeting",      download: "/downloads/budgeting.zip" },
  "filmmakers-kit": { prefix: "FMKIT", name: "Filmmakers Kit", download: "/downloads/filmmakers-kit.zip" },
  "iptv-manager":     { prefix: "IPTV",  name: "IPTV Manager",     download: "/downloads/iptv-manager.zip" },
};

function generateSerialKey(prefix) {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const seg = () =>
    Array.from({ length: 4 }, () => chars[Math.floor(Math.random() * chars.length)]).join("");
  return `${prefix}-${seg()}-${seg()}-${seg()}`;
}

async function sendKeyEmail({ email, firstName, productName, serialKey, downloadUrl, isBundle }) {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey || !email) return;

  const name = firstName ? firstName : "there";
  const redownloadUrl = "https://tobyjones.ca/software/redownload/";
  const fullDownload = `https://tobyjones.ca${downloadUrl}`;

  const bundleNote = isBundle
    ? `<p style="color:#1d1d1f;margin:0 0 24px;">This key activates all three apps: Scheduling, Budgeting, and Call Sheets.</p>`
    : "";

  const downloadSection = isBundle
    ? `<p style="margin:0 0 8px;"><a href="https://tobyjones.ca/downloads/scheduling.zip" style="color:#0071e3;text-decoration:none;font-weight:600;">Download Scheduling →</a></p>
       <p style="margin:0 0 8px;"><a href="https://tobyjones.ca/downloads/budgeting.zip" style="color:#0071e3;text-decoration:none;font-weight:600;">Download Budgeting →</a></p>
       <p style="margin:0 0 24px;"><a href="https://tobyjones.ca/downloads/call-sheets.zip" style="color:#0071e3;text-decoration:none;font-weight:600;">Download Call Sheets →</a></p>`
    : `<p style="margin:0 0 24px;"><a href="${fullDownload}" style="display:inline-block;padding:14px 32px;background:#0071e3;color:#fff;text-decoration:none;border-radius:980px;font-weight:600;">Download ${productName}</a></p>`;

  const html = `<!DOCTYPE html><html><body style="margin:0;padding:0;background:#f5f5f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">
<div style="max-width:560px;margin:40px auto;background:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 2px 20px rgba(0,0,0,0.07);">
  <div style="background:linear-gradient(135deg,#1a1a2e 0%,#0f3460 100%);padding:40px 40px 32px;text-align:center;">
    <p style="margin:0;font-size:13px;font-weight:600;letter-spacing:0.12em;text-transform:uppercase;color:rgba(255,255,255,0.55);">Toby Jones Software</p>
    <h1 style="margin:12px 0 0;font-size:28px;font-weight:700;color:#ffffff;letter-spacing:-0.02em;">Your Licence Key</h1>
  </div>
  <div style="padding:40px;">
    <p style="color:#1d1d1f;margin:0 0 24px;">Hi ${name}, thanks for purchasing <strong>${productName}</strong>. Here's your serial key:</p>
    <div style="background:#f5f5f7;border-radius:12px;padding:24px;text-align:center;margin:0 0 24px;">
      <p style="margin:0 0 6px;font-size:11px;font-weight:600;letter-spacing:0.1em;text-transform:uppercase;color:#86868b;">Serial Key</p>
      <p style="margin:0;font-family:'SF Mono',Monaco,'Courier New',monospace;font-size:20px;font-weight:700;letter-spacing:0.06em;color:#1d1d1f;">${serialKey}</p>
    </div>
    ${bundleNote}
    ${downloadSection}
    <hr style="border:none;border-top:1px solid #e8e8ed;margin:0 0 24px;">
    <p style="font-size:13px;color:#86868b;margin:0 0 8px;">Keep this email — you'll need your key if you reinstall. Lost it? Retrieve it at <a href="${redownloadUrl}" style="color:#0071e3;text-decoration:none;">${redownloadUrl}</a></p>
    <p style="font-size:13px;color:#86868b;margin:0;">© ${new Date().getFullYear()} Toby Jones. All rights reserved.</p>
  </div>
</div>
</body></html>`;

  await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "Toby Jones Software <noreply@tobyjones.ca>",
      to: [email],
      subject: `Your ${productName} Licence Key`,
      html,
    }),
  });
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
            const { prefix, name: productName, download } = PRODUCTS[product];
            serialKey = txnId.split('').reverse().join('');
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
              console.error("KV write error:", kvErr);
            }

            // Send licence key email — non-fatal
            sendKeyEmail({
              email: billing?.email,
              firstName: billing?.firstName,
              productName,
              serialKey,
              downloadUrl: download,
              isBundle: product === "filmmakers-kit",
            }).catch((e) => console.error("Email send error:", e));
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
