# Caffeine Media - website

Static site. No build step, no dependencies, no framework. Open `index.html` and it works.

```
index.html                the whole page
assets/styles.css         all styling, for the studio pages and every app page
assets/app.js             studio page interactions
assets/cookie-consent.js  cookie notice + Google Analytics (loads on first scroll/tap)
assets/fonts/archivo.woff2  self-hosted Archivo, subset to Latin
assets/logo*.png/webp     stacked lockup (hero)
assets/mark*.png/webp     cup + filmstrip mark (nav, footer, contact)
assets/favicon.png        browser tab icon
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
- **Adding a service** - copy any `<article class="spec__cell">` block in the
  services section. `spec__cell--wide` spans two columns.
- **Adding a credit** - copy any `<article class="frame">` in the credits reel.
  `frame--lit` is the yellow highlighted frame.
- **Colours and type** are CSS variables at the top of `styles.css`. Each app
  page sets its own accent with `style="--field: #..."` on `<body>`.
- **Images** - pages load the `.webp` copies; the original PNG/JPGs stay for
  app icons, Open Graph and as sources. Screenshots have a `-400.webp` copy for
  phones.
- **Motion** is limited to the film strips advancing as you scroll, and it
  switches off under `prefers-reduced-motion`.

## Content source

Copy for the work, studio, awards and training sections is drawn from Toby's CV
(`~/Documents/Resumes/Resume.pdf`). If the CV changes, those three sections are
the ones to update.
