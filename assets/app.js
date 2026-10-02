// Caffeine Media: menu, apps dropdown, credits reel, copy-email, back-to-top.
(function () {
  var $ = function (s) { return document.querySelector(s); };
  var reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

  var yr = $('#yr');
  if (yr) yr.textContent = new Date().getFullYear();

  // Mobile menu and the Apps & Games dropdown are <details> disclosures;
  // this only adds closing on outside click, Escape and link taps.
  var more = $('#more'), drop = $('#appsDropdown');
  if (more) {
    more.addEventListener('toggle', function () { document.body.style.overflow = more.open ? 'hidden' : ''; });
    more.addEventListener('click', function (e) { if (e.target.closest('.menu a')) more.open = false; });
    addEventListener('resize', function () { if (innerWidth > 900) more.open = false; });
  }
  document.addEventListener('click', function (e) {
    if (drop && drop.open && !drop.contains(e.target)) drop.open = false;
  });
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    [more, drop].forEach(function (d) {
      if (d && d.open) { d.open = false; d.querySelector('summary').focus(); }
    });
  });

  // Credits reel arrows
  var track = $('#track'), prev = $('#prev'), next = $('#next');
  if (track && prev && next) {
    var step = function () { return track.firstElementChild.offsetWidth + 18; };
    var sync = function () {
      prev.disabled = track.scrollLeft < 4;
      next.disabled = track.scrollLeft > track.scrollWidth - track.clientWidth - 4;
    };
    var go = function (dir) { track.scrollBy({ left: dir * step(), behavior: reduced ? 'auto' : 'smooth' }); };
    prev.addEventListener('click', function () { go(-1); });
    next.addEventListener('click', function () { go(1); });
    track.addEventListener('scroll', sync, { passive: true });
    addEventListener('resize', sync);
    requestAnimationFrame(sync);
  }

  // Copy email
  var flash = $('#flash'), timer;
  function say(msg) {
    flash.textContent = msg;
    flash.classList.add('is-on');
    clearTimeout(timer);
    timer = setTimeout(function () { flash.classList.remove('is-on'); }, 2400);
  }
  var copy = $('#copyMail');
  if (copy && flash) {
    copy.addEventListener('click', function () {
      var addr = 'hello@thecaffeinemediacompany.com';
      if (navigator.clipboard) {
        navigator.clipboard.writeText(addr).then(function () { say('Email address copied'); }, function () { say(addr); });
      } else {
        say(addr);
      }
    });
  }

  // Back to top
  var top = $('#toTop');
  if (top) {
    addEventListener('scroll', function () { top.classList.toggle('is-on', scrollY > 900); }, { passive: true });
    top.addEventListener('click', function () { scrollTo({ top: 0, behavior: reduced ? 'auto' : 'smooth' }); });
  }

  // Only one FAQ answer open at a time
  var qas = document.querySelectorAll('.qa');
  qas.forEach(function (d) {
    d.addEventListener('toggle', function () {
      if (d.open) qas.forEach(function (o) { if (o !== d) o.open = false; });
    });
  });
})();
