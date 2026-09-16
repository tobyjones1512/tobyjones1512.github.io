/* Shared cookie / local-storage notice. No tracking cookies are set by
   this site — this banner exists to be upfront about that and to record
   (via localStorage, on this device only) that it's been dismissed. */
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
      '<p>This site doesn’t use advertising or tracking cookies. Dismissing this keeps a note of that on your device only. <a href="privacy.html">Privacy Policy</a></p>' +
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
