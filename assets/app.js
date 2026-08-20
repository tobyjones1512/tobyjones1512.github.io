/* ═══════════════════════════════════════════════════════════
   Caffeine Media - interactions
   Vanilla JS, no dependencies. Everything degrades gracefully.
   ═══════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  var $  = function (s, c) { return (c || document).querySelector(s); };
  var $$ = function (s, c) { return Array.prototype.slice.call((c || document).querySelectorAll(s)); };

  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ── Current year ─────────────────────────────────────── */
  var yr = $('#yr');
  if (yr) yr.textContent = new Date().getFullYear();

  /* ── Scroll reveal ────────────────────────────────────── */
  var risers = $$('[data-rise]');
  if ('IntersectionObserver' in window && !reduced) {
    var riseObs = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) {
          e.target.classList.add('is-in');
          riseObs.unobserve(e.target);
        }
      });
    }, { rootMargin: '0px 0px -12% 0px', threshold: 0.06 });
    risers.forEach(function (el) { riseObs.observe(el); });
  } else {
    risers.forEach(function (el) { el.classList.add('is-in'); });
  }

  /* ── Nav: translucency, hide-on-scroll-down, progress ──── */
  var nav      = $('#nav');
  var fill     = $('#scrollFill');
  var toTop    = $('#toTop');
  var lastY    = window.scrollY;
  var ticking  = false;

  function onScroll() {
    var y   = window.scrollY;
    var doc = document.documentElement;
    var max = doc.scrollHeight - window.innerHeight;

    if (fill) fill.style.width = (max > 0 ? (y / max) * 100 : 0) + '%';

    if (nav) {
      nav.classList.toggle('is-top', y < 20);
      // Hide when scrolling down past the hero, show on any upward scroll.
      if (!sheetOpen) {
        if (y > 420 && y > lastY + 4)      nav.classList.add('is-hidden');
        else if (y < lastY - 4 || y < 200) nav.classList.remove('is-hidden');
      }
    }

    if (toTop) toTop.classList.toggle('is-on', y > 900);

    lastY = y;
    ticking = false;
  }

  window.addEventListener('scroll', function () {
    if (!ticking) { window.requestAnimationFrame(onScroll); ticking = true; }
  }, { passive: true });
  onScroll();

  if (toTop) {
    toTop.addEventListener('click', function () {
      window.scrollTo({ top: 0, behavior: reduced ? 'auto' : 'smooth' });
    });
  }

  /* ── Mobile sheet ─────────────────────────────────────── */
  var burger    = $('#burger');
  var sheet     = $('#sheet');
  var sheetOpen = false;

  function setSheet(open) {
    if (!sheet || !burger) return;
    sheetOpen = open;
    burger.setAttribute('aria-expanded', String(open));
    burger.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
    if (open) {
      sheet.hidden = false;
      nav.classList.remove('is-hidden');
      requestAnimationFrame(function () { sheet.classList.add('is-open'); });
      document.body.style.overflow = 'hidden';
    } else {
      sheet.classList.remove('is-open');
      document.body.style.overflow = '';
      window.setTimeout(function () { if (!sheetOpen) sheet.hidden = true; }, 320);
    }
  }

  if (burger) burger.addEventListener('click', function () { setSheet(!sheetOpen); });
  if (sheet)  $$('a', sheet).forEach(function (a) {
    a.addEventListener('click', function () { setSheet(false); });
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && sheetOpen) { setSheet(false); burger.focus(); }
  });
  window.addEventListener('resize', function () {
    if (window.innerWidth > 900 && sheetOpen) setSheet(false);
  });

  /* ── Active nav link ──────────────────────────────────── */
  var navLinks = $$('.nav__links a');
  var sections = navLinks
    .map(function (a) { return document.getElementById(a.getAttribute('href').slice(1)); })
    .filter(Boolean);

  if ('IntersectionObserver' in window && sections.length) {
    var secObs = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        navLinks.forEach(function (a) {
          a.classList.toggle('is-active', a.getAttribute('href') === '#' + e.target.id);
        });
      });
    }, { rootMargin: '-45% 0px -50% 0px' });
    sections.forEach(function (s) { secObs.observe(s); });
  }

  /* ── Pinned restoration sequence ──────────────────────── */
  var pin      = $('#restore');
  var steps    = $$('.step');
  var fLabel   = $('#frameLabel');
  var fNoise   = $('#frameNoise');
  var fFrame   = $('#frame');
  var fTC      = $('#frameTC');
  var labels   = ['CAPTURE', 'CLEAN', 'DELIVER'];
  var codes    = ['00:04:12:08', '00:11:47:22', '01:02:00:00'];
  var noiseOp  = [0.5, 0.2, 0.03];
  var pinIndex = -1;

  function updatePin() {
    if (!pin || !steps.length) return;
    if (window.innerWidth <= 900) {           // stacked layout: everything on
      steps.forEach(function (s) { s.classList.add('is-on'); });
      return;
    }

    var rect  = pin.getBoundingClientRect();
    var total = pin.offsetHeight - window.innerHeight;
    if (total <= 0) return;

    var p = Math.min(Math.max(-rect.top / total, 0), 0.9999);
    var i = Math.floor(p * steps.length);
    if (i === pinIndex) return;
    pinIndex = i;

    steps.forEach(function (s, n) { s.classList.toggle('is-on', n === i); });
    if (fLabel) fLabel.textContent = labels[i] || labels[0];
    if (fTC)    fTC.textContent    = codes[i]  || codes[0];
    if (fFrame) fFrame.dataset.stage = String(i);
    if (fNoise) fNoise.style.opacity = noiseOp[i] != null ? noiseOp[i] : 0.5;
  }

  var pinTick = false;
  window.addEventListener('scroll', function () {
    if (!pinTick) { window.requestAnimationFrame(function () { updatePin(); pinTick = false; }); pinTick = true; }
  }, { passive: true });
  window.addEventListener('resize', function () { pinIndex = -1; updatePin(); });
  updatePin();

  /* ── Work gallery arrows ──────────────────────────────── */
  var track = $('#track');
  var prev  = $('#prev');
  var next  = $('#next');

  function step() {
    var card = $('.card', track);
    return card ? card.getBoundingClientRect().width + 16 : 340;
  }
  function syncArrows() {
    if (!track || !prev || !next) return;
    var max = track.scrollWidth - track.clientWidth - 2;
    prev.disabled = track.scrollLeft <= 2;
    next.disabled = track.scrollLeft >= max;
  }
  if (track && prev && next) {
    prev.addEventListener('click', function () { track.scrollBy({ left: -step(), behavior: reduced ? 'auto' : 'smooth' }); });
    next.addEventListener('click', function () { track.scrollBy({ left:  step(), behavior: reduced ? 'auto' : 'smooth' }); });
    track.addEventListener('scroll', function () { window.requestAnimationFrame(syncArrows); }, { passive: true });
    window.addEventListener('resize', syncArrows);
    syncArrows();
  }

  /* ── Count-up stats ───────────────────────────────────── */
  var counters = $$('[data-count]');
  if (counters.length) {
    if (reduced || !('IntersectionObserver' in window)) {
      counters.forEach(function (el) { el.textContent = el.dataset.count; });
    } else {
      var cObs = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (!e.isIntersecting) return;
          cObs.unobserve(e.target);
          var el     = e.target;
          var target = parseInt(el.dataset.count, 10) || 0;
          var start  = performance.now();
          var dur    = 1100;
          (function frame(now) {
            var t = Math.min((now - start) / dur, 1);
            var eased = 1 - Math.pow(1 - t, 3);
            el.textContent = Math.round(eased * target);
            if (t < 1) requestAnimationFrame(frame);
          })(start);
        });
      }, { threshold: 0.5 });
      counters.forEach(function (el) { cObs.observe(el); });
    }
  }

  /* ── Toast + copy email ───────────────────────────────── */
  var toast = $('#toast');
  var toastTimer;
  function say(msg) {
    if (!toast) return;
    toast.textContent = msg;
    toast.classList.add('is-on');
    window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(function () { toast.classList.remove('is-on'); }, 2400);
  }

  var copyBtn = $('#copyMail');
  if (copyBtn) {
    copyBtn.addEventListener('click', function (e) {
      e.preventDefault();
      e.stopPropagation();
      var addr = 'hello@thecaffeinemediacompany.com';
      var done = function () { say('Email address copied'); };
      var fail = function () { say(addr); };

      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(addr).then(done).catch(fail);
      } else {
        var ta = document.createElement('textarea');
        ta.value = addr;
        ta.setAttribute('readonly', '');
        ta.style.cssText = 'position:fixed;top:-1000px;opacity:0';
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand('copy'); done(); } catch (err) { fail(); }
        document.body.removeChild(ta);
      }
    });
  }

  /* ── Only one FAQ open at a time ──────────────────────── */
  var qas = $$('.qa');
  qas.forEach(function (d) {
    d.addEventListener('toggle', function () {
      if (!d.open) return;
      qas.forEach(function (o) { if (o !== d) o.open = false; });
    });
  });

  /* ── Subtle pointer parallax on the hero glow ─────────── */
  var glow = $('.hero__glow');
  if (glow && !reduced && window.matchMedia('(pointer: fine)').matches) {
    window.addEventListener('mousemove', function (e) {
      if (window.scrollY > window.innerHeight) return;
      var x = (e.clientX / window.innerWidth  - 0.5) * 34;
      var y = (e.clientY / window.innerHeight - 0.5) * 20;
      glow.style.translate = 'calc(-50% + ' + x.toFixed(1) + 'px) ' + y.toFixed(1) + 'px';
    }, { passive: true });
  }

})();
