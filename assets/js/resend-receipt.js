// Shared frontend for resending receipts across thank-you pages
(function(){
  function render(container) {
    if (!container) return
    const orderId = (new URLSearchParams(window.location.search)).get('orderId') || container.dataset.orderId || '';
    container.innerHTML = `
      <div class="resend-card" style="border:1px solid #d2d7; border-radius:12px; padding:12px 14px; display:flex; flex-direction:column; align-items:flex-start; gap:8px;">
        <label for="rr-email" style="font-size:12px; font-weight:700; text-transform:uppercase; letter-spacing:.15em; color:#777;">Resend receipt</label>
        <input id="rr-email" placeholder="Email to receive receipt (optional)" style="width:100%; padding:8px 10px; border:1px solid #d2d7; border-radius:6px;" />
        <button id="rr-btn" class="btn" style="background:#0071e3; color:white; border:0; padding:8px 14px; border-radius:8px; font-weight:700;">Resend Receipt</button>
        <div id="rr-status" class="rr-status" style="font-size:13px; color:#666; margin-top:6px;"></div>
      </div>`
    // attach handler
    const btn = document.getElementById('rr-btn')
    const status = document.getElementById('rr-status')
    btn.addEventListener('click', async () => {
      const email = document.getElementById('rr-email').value
      status.textContent = 'Sending...'
      try {
        const r = await fetch('/api/resend-receipt', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ orderId, email })
        })
        const data = await r.json()
        status.textContent = data.success ? 'Receipt resend initiated.' : ('Error: ' + (data.message || 'Unknown error'))
      } catch (e) {
        status.textContent = 'Network error: ' + (e?.message || e)
      }
    })
  }
  document.addEventListener('DOMContentLoaded', () => {
    const containers = document.querySelectorAll('[data-resend-container]')
    containers.forEach(c => render(c))
  })
})()
