/* Shared cookie / local-storage notice. Google Analytics is loaded on this
   site; this banner lets visitors opt out of measurement cookies and records
   the choice (via localStorage, on this device only). */
(function () {
  'use strict';

  var KEY = 'cookieNoticeDismissed';
  try {
    if (localStorage.getItem(KEY) === '1') return;
  } catch (e) {
    return; // storage unavailable (private mode etc.) — don't force the banner
  }

  document.addEventListener('DOMContentLoaded', function () {
    var el = document.createElement('div');
    el.className = 'cookie-note';
    el.setAttribute('role', 'region');
    el.setAttribute('aria-label', 'Cookie notice');
    el.innerHTML =
      '<p>We use Google Analytics to count visits and see how the site is used. Neither we nor Google use it for advertising or targeting. Dismissing this records your choice on this device only. <a href="privacy.html">Privacy Policy</a></p>' +
      '<div class="cookie-note__actions">' +
        '<button type="button" class="cookie-note__accept">Got it</button>' +
      '</div>';
    document.body.appendChild(el);

    el.querySelector('.cookie-note__accept').addEventListener('click', function () {
      try { localStorage.setItem(KEY, '1'); } catch (e) {}
      el.remove();
    });
  });
})();
