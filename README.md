# Caffeine Media - website

Static site. No build step, no dependencies, no framework. Open `index.html` and it works.

```
index.html          the whole page
assets/styles.css   all styling
assets/app.js       all interactions
assets/logo.png     stacked lockup (hero)
assets/mark.png     cup + filmstrip mark (nav, footer, contact)
assets/favicon.png  browser tab icon
```

## Preview locally

```bash
python3 -m http.server 4321
```

Then open http://localhost:4321

## Deploy to GitHub Pages

Copy `index.html` and `assets/` into the `caffeinemedia` repo (which already has a
`CNAME` for `thecaffeinemediacompany.com`), commit and push. Pages serves it as-is.

## Editing notes

- **Contact details** appear in four places: the hero buttons, the contact cards,
  the footer, and the JSON-LD block in `<head>`. Search for
  `thecaffeinemediacompany` to catch them all.
- **The iMessage links** use `imessage://hello@thecaffeinemediacompany.com`. These
  open Messages on iPhone, iPad and Mac. On Windows and Android nothing happens,
  which is why the email option sits right beside it.
- **Adding a service** - copy any `<article class="tile">` block in the services
  section. `tile--wide` spans two columns, `tile--tall` spans two rows.
- **Adding a credit** - copy any `<article class="card">` in the work gallery.
  `card--feature` is the dark highlighted variant.
- **Colours and type** are all CSS variables at the top of `styles.css`.
  Headings use SF Pro on Apple devices and fall back to Manrope elsewhere.
- **Animations** respect `prefers-reduced-motion`, so anyone who has motion
  reduced in their system settings gets a still, fully readable page.

## Content source

Copy for the work, studio, awards and training sections is drawn from Toby's CV
(`~/Documents/Resumes/Resume.pdf`). If the CV changes, those three sections are
the ones to update.
