// Shared on every page: Google Analytics plus the cookie notice.
// GA is held back until the visitor first scrolls, taps or types, so it never
// slows the first paint. Dismissing the notice is remembered on this device.
(function () {
  var started = false;
  function startGA() {
    if (started) return;
    started = true;
    window.dataLayer = window.dataLayer || [];
    window.gtag = function () { dataLayer.push(arguments); };
    gtag('js', new Date());
    gtag('config', 'G-QCV7XEQ8QT');
    var s = document.createElement('script');
    s.async = true;
    s.src = 'https://www.googletagmanager.com/gtag/js?id=G-QCV7XEQ8QT';
    document.head.appendChild(s);
  }
  ['scroll', 'pointerdown', 'keydown', 'touchstart'].forEach(function (ev) {
    addEventListener(ev, startGA, { once: true, passive: true });
  });

  var KEY = 'cookieNoticeDismissed';
  try {
    if (localStorage.getItem(KEY) === '1') return;
  } catch (e) {
    return;
  }

  var el = document.createElement('div');
  el.className = 'cookie-note';
  el.setAttribute('role', 'region');
  el.setAttribute('aria-label', 'Cookie notice');
  el.innerHTML =
    '<p>We use Google Analytics to count visits and see how the site is used. Neither we nor Google use it for advertising or targeting. Dismissing this records your choice on this device only. <a href="privacy.html">Privacy Policy</a></p>' +
    '<button type="button">Got it</button>';
  document.body.appendChild(el);
  el.querySelector('button').addEventListener('click', function () {
    try { localStorage.setItem(KEY, '1'); } catch (e) {}
    el.remove();
  });
})();
