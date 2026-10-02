// Caffeine Media: menu, apps dropdown, credits reel, copy-email, back-to-top.
(function () {
  var $ = function (s) { return document.querySelector(s); };
  var reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

  var yr = $('#yr');
  if (yr) yr.textContent = new Date().getFullYear();

  // Mobile sheet
  var burger = $('#burger'), sheet = $('#sheet');
  function setSheet(open) {
    burger.setAttribute('aria-expanded', open);
    burger.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
    sheet.hidden = !open;
    document.body.style.overflow = open ? 'hidden' : '';
  }
  if (burger && sheet) {
    burger.addEventListener('click', function () { setSheet(sheet.hidden); });
    sheet.addEventListener('click', function (e) { if (e.target.closest('a')) setSheet(false); });
    addEventListener('resize', function () { if (innerWidth > 900 && !sheet.hidden) setSheet(false); });
  }

  // Apps & Games dropdown
  var drop = $('#appsDropdown'), trigger = $('#appsTrigger');
  function setDrop(open) {
    drop.classList.toggle('is-open', open);
    trigger.setAttribute('aria-expanded', open);
  }
  if (drop && trigger) {
    trigger.addEventListener('click', function () { setDrop(!drop.classList.contains('is-open')); });
    document.addEventListener('click', function (e) { if (!drop.contains(e.target)) setDrop(false); });
  }

  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    if (sheet && !sheet.hidden) { setSheet(false); burger.focus(); }
    if (drop && drop.classList.contains('is-open')) { setDrop(false); trigger.focus(); }
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
  var toast = $('#toast'), timer;
  function say(msg) {
    toast.textContent = msg;
    toast.classList.add('is-on');
    clearTimeout(timer);
    timer = setTimeout(function () { toast.classList.remove('is-on'); }, 2400);
  }
  var copy = $('#copyMail');
  if (copy && toast) {
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
