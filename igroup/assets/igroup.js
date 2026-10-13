// iGroup page: the hero plays one loop on a single clock. Pages, then Keynote, snap onto the
// Safari window and join its tab bar; the tabs take turns in front; then they part and it starts again.
// Nothing here is clickable: it is a picture of what iGroup does.

const stage = document.getElementById('stage');
const main = stage.querySelector('[data-app=safari]');
const strip = main.querySelector('.win__tabs');
const loose = [...stage.querySelectorAll('.stage__win--loose')];
const titles = { pages: 'Launch Notes', keynote: 'Autumn Launch' };

function show(app) {
  for (const t of strip.children) t.classList.toggle('is-on', t.dataset.for === app);
  for (const p of main.querySelectorAll('[data-pane]')) p.hidden = p.dataset.pane !== app;
}

const offset = win => `translate(${main.offsetLeft - win.offsetLeft}px, ${main.offsetTop - win.offsetTop}px)`;

function join(win, flash = true) {
  const app = win.dataset.app;
  win.classList.toggle('is-flash', flash);
  setTimeout(() => {
    win.classList.remove('is-flash');
    win.style.transform = offset(win);
    win.classList.add('is-joined');
    const tab = document.createElement('span');
    tab.className = 'tab';
    tab.dataset.for = app;
    tab.innerHTML = `<i class="glyph glyph--${app}"></i>${titles[app]}`;
    strip.append(tab);
    show(app);
  }, flash ? 180 : 0);
}

function part() {
  for (const t of [...strip.children].slice(1)) t.remove();
  show('safari');
  for (const w of loose) { w.classList.remove('is-joined'); w.style.transform = ''; }
}

// Keep joined windows parked on the group when the layout reflows.
addEventListener('resize', () => loose.filter(w => w.classList.contains('is-joined')).forEach(w => { w.style.transform = offset(w); }));

if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
  loose.forEach(w => join(w, false));
} else {
  // One clock: each step fires at its beat, and the loop restarts after the last one.
  const beats = [
    [900, () => join(loose[0])],
    [2400, () => join(loose[1])],
    [4200, () => show('safari')],
    [5600, () => show('pages')],
    [7000, () => show('keynote')],
    [8800, part],
  ];
  const loop = () => beats.forEach(([t, step]) => setTimeout(step, t));
  loop();
  setInterval(loop, 10200);
}

document.getElementById('yr').textContent = new Date().getFullYear();
