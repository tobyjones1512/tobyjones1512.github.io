---
name: Caffeine Media
description: Studio and app pages printed like a cine film carton, with a flat ink face and a ruled spec panel.
colors:
  carton-yellow: "#F2B705"
  process-red: "#C8211A"
  carton-black: "#16110E"
  board-white: "#FAFAF7"
  spec-grey: "#55504B"
  ash-on-black: "#CFC8C1"
  ink-line: "#3A332E"
  pure-white: "#FFFFFF"
typography:
  display:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(3.25rem, 11.2vw, 7.25rem)"
    fontWeight: 850
    lineHeight: 0.84
    letterSpacing: "-0.005em"
    fontVariation: "'wdth' 64"
  headline:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(2.75rem, 7vw, 6rem)"
    fontWeight: 800
    lineHeight: 0.9
    letterSpacing: "-0.005em"
    fontVariation: "'wdth' 64"
  title:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "1.75rem"
    fontWeight: 800
    lineHeight: 0.9
    letterSpacing: "-0.005em"
    fontVariation: "'wdth' 64"
  numeral:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "4rem"
    fontWeight: 800
    lineHeight: 0.9
    fontFeature: "'tnum' 1"
    fontVariation: "'wdth' 64"
  subhead:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "1.5rem"
    fontWeight: 750
    lineHeight: 1.15
    fontVariation: "'wdth' 75"
  body:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 400
    lineHeight: 1.55
  lede:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "1.1875rem"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "0.8125rem"
    fontWeight: 650
    lineHeight: 1.3
    letterSpacing: "0.06em"
    fontVariation: "'wdth' 75"
rounded:
  none: "0px"
spacing:
  gutter: "clamp(16px, 4vw, 40px)"
  section: "clamp(64px, 9vw, 128px)"
  cell: "24px"
  stack: "10px"
  container: "1240px"
  film-edge: "26px"
components:
  button-ink:
    backgroundColor: "{colors.carton-black}"
    textColor: "{colors.board-white}"
    rounded: "{rounded.none}"
    padding: "14px 22px"
    height: "52px"
  button-ink-hover:
    backgroundColor: "{colors.carton-yellow}"
    textColor: "{colors.carton-black}"
  button-red:
    backgroundColor: "{colors.process-red}"
    textColor: "{colors.pure-white}"
    rounded: "{rounded.none}"
    padding: "14px 22px"
    height: "52px"
  button-red-hover:
    backgroundColor: "{colors.carton-yellow}"
    textColor: "{colors.carton-black}"
  button-paper:
    backgroundColor: "{colors.board-white}"
    textColor: "{colors.carton-black}"
    rounded: "{rounded.none}"
    padding: "14px 22px"
    height: "52px"
  button-paper-hover:
    backgroundColor: "{colors.carton-black}"
    textColor: "{colors.board-white}"
  nav-bar:
    backgroundColor: "{colors.carton-black}"
    textColor: "{colors.board-white}"
    height: "64px"
  nav-cta:
    backgroundColor: "{colors.process-red}"
    textColor: "{colors.pure-white}"
    padding: "12px 16px 11px"
  square-control:
    backgroundColor: "{colors.carton-black}"
    textColor: "{colors.carton-yellow}"
    size: "48px"
  square-control-hover:
    backgroundColor: "{colors.process-red}"
    textColor: "{colors.pure-white}"
  spec-cell:
    backgroundColor: "{colors.board-white}"
    textColor: "{colors.carton-black}"
    rounded: "{rounded.none}"
    padding: "clamp(22px, 3vw, 34px)"
  spec-cell-field:
    backgroundColor: "{colors.carton-yellow}"
    textColor: "{colors.carton-black}"
  spec-cell-ink:
    backgroundColor: "{colors.carton-black}"
    textColor: "{colors.board-white}"
  tag:
    textColor: "{colors.carton-black}"
    typography: "{typography.label}"
    padding: "4px 9px 3px"
  store-badge:
    backgroundColor: "{colors.carton-black}"
    textColor: "{colors.board-white}"
    padding: "10px 18px 10px 14px"
    height: "56px"
  contact-card:
    backgroundColor: "{colors.carton-black}"
    textColor: "{colors.board-white}"
    padding: "20px"
  contact-card-hover:
    backgroundColor: "{colors.carton-yellow}"
    textColor: "{colors.carton-black}"
---

# Design System: Caffeine Media

## Overview

**Creative North Star: "The Film Stock Carton"**

Every page is printed like the cardboard carton a reel of cine film shipped in. The front is a loud, flat ink face: whole fields of one colour, a huge condensed-caps title, a solid red band. Behind it sits the back of the box: a dense, ruled spec panel where services, formats, credits and steps are set as cells divided by 2px black rules. Sprocket-hole strips run between sections as structure, not ornament.

The system is flat, square and printed. Depth comes from colour fields butting against each other and from rules, never from shadow or blur. Type has two voices from one variable family: a narrow, heavy, uppercase display voice for titles and numerals, and the same family at full width as a sturdy reading sans. One stylesheet serves the studio pages and every app microsite; each app swaps only the field colour for its icon's accent.

The world refuses the cream paper, rounded cards and soft gradient bento that studio templates ship. Board white was deliberately cooled away from cream for that reason.

**Key Characteristics:**
- Flat colour fields that run edge to edge, one field colour per page.
- Square corners on every surface; only app icon images keep their iOS rounding.
- 2px currentColor rules build grids, tables and dividers.
- Condensed uppercase display (64% width, weight 800-850, line-height under 1).
- Sprocket film-edge strips (26px) separate major sections and advance with scroll.
- Hover inverts fills; nothing lifts or glows.

## Colors

A printed carton palette: one saturated field colour, one process red, black ink and a cool white board.

### Primary
- **Carton Yellow** (`--field`): owns whole fields (hero face, about section, highlighted spec cells, the lit frame, accent price card) and every hover fill. On dark surfaces it colours labels, numerals and focus rings. On app microsites `--field` is set on `<body>` to the app's icon accent and replaces yellow everywhere; nothing else changes.

### Secondary
- **Process Red**: bands under the hero, the contact section, the nav call-to-action, red buttons, the live tally, and large numerals on light or yellow ground. Shipped darker than first planned so red numerals hold 3:1 on yellow. Text on red is pure white.

### Neutral
- **Carton Black**: ink for all text on light ground, the nav bar, footer, restoration and tinted sections, the 2px rules (as currentColor), focus rings on light ground, and the sprocket strip.
- **Board White**: the reading ground for body sections, legal and support pages, and contact "ways".
- **Spec Grey**: secondary copy on board white (section subheads, cell descriptions, FAQ answers). Not used on field colours; copy on a field switches to Carton Black.
- **Ash on Black**: secondary copy on Carton Black surfaces.
- **Ink Line**: 1px dividers inside black surfaces (mobile sheet, restoration steps, footer base).
- On light ground, thin dividers are Carton Black at 22-25% alpha (the hairline rule).

### Named Rules
**The One Field Rule.** A page has exactly one field colour, held in `--field`. Never introduce a second accent; app pages change the field and nothing else.

**The Field Text Rule.** Text sitting on a field colour or on red is Carton Black or white at full strength, never Spec Grey.

## Typography

**Display Font:** Archivo, condensed (wdth 64%), self-hosted variable subset (wdth 62-100, wght 400-850), with Helvetica Neue, Arial fallback
**Body Font:** Archivo at normal width
**Label Font:** Archivo at wdth 75%

**Character:** One grotesque family stretched two ways: tall, packed, uppercase edge-code lettering for anything that names or counts, and a plain, sturdy text face for reading.

### Hierarchy
- **Display** (850, clamp(3.25rem, 11.2vw, 7.25rem), 0.84): the homepage hero title and contact title only. App heroes run slightly smaller (clamp(3rem, 8.5vw, 6.75rem), 0.86); the 404 code goes to 14rem.
- **Headline** (800, clamp(2.75rem, 7vw, 6rem), 0.9, balanced wrap): section heads, legal and support page titles.
- **Title** (800, 1.5-2.5rem, 0.9): cell, frame, tile and step headings. Always condensed uppercase.
- **Numeral** (800, 3-4.5rem, tabular): step numbers, rule numbers, tally counts. Red on light or yellow ground, field colour on black.
- **Subhead** (750, 1.25-1.5rem, wdth 75%): FAQ questions and legal/support card headings.
- **Body** (400, 1.0625rem, 1.55): all reading copy, held to 46-68ch.
- **Lede** (400, 1.1875rem, 1.5): hero and about introductions.
- **Label** (650, 0.8125rem, 0.06em tracking, uppercase, wdth 75%): spec-cell tags, frame metadata, nav links, chips, captions, table values.

### Named Rules
**The Two Widths Rule.** Condensed uppercase names and counts things; normal width explains things. Never set running prose in the condensed voice, and never set a heading in the normal-width voice.

**The Tabular Numeral Rule.** Every number that is part of a sequence or tally uses tabular figures.

## Layout

Content sits in a 1240px container with a fluid gutter (clamp(16px, 4vw, 40px)); colour fields and film strips bleed full width outside it. Sections are separated by a generous fluid block (clamp(64px, 9vw, 128px)). Section heads use a 7:5 split with the headline left and the subhead right, aligned to the baseline end; they stack under 760px.

The spec panel is the core grid: three equal columns (two under 900px, one under 600px), cells bordered right and bottom with the panel bordered top and left, so every cell is ruled on all four sides at 2px. Cells can span two columns or two rows. Column sets (process, about, pricing, personas) use a top rule and vertical rules between siblings, with 24px cell padding, dropping to stacked rules on mobile.

Horizontal reels (credits, screenshots) scroll with mandatory snap, aligned to the container edge. The studio nav collapses to a full-screen black sheet under 900px.

### Named Rules
**The Ruled Grid Rule.** Groups of items are divided by 2px rules in a shared grid, not separated into floating cards with gaps.

## Elevation & Depth

Flat. There is no elevation shadow anywhere in the system. Depth comes from stacked colour fields (yellow face, red band, black strip), from rules, and from the sprocket edge whose holes show the surface behind. A 100vmax box-shadow in the field colour is used only as a full-bleed fill technique on app heroes, not as depth. The disabled square control draws its outline with an inset 2px shadow, which reads as a border.

### Named Rules
**The Printed Flat Rule.** Nothing floats. States change fill and colour; they never add shadow, blur or lift beyond a 1px press-down on buttons.

## Shapes

Square corners on every surface: buttons, cells, cards, chips, menus, toasts, badges and screenshots. Borders are 2px solid currentColor (1.5px on small tool chips, 4px on gallery screenshots, 8px black frame on hero phone shots). The only rounded shapes are app icon images, which keep an iOS-style mask (about 22% of their size), and the 7px round dot inside the live tally. Small 7px squares act as bullets and separators.

### Named Rules
**The Square Corner Rule.** Radius is 0 on every UI surface. App icons are artwork, not UI, and keep their own rounding.

## Components

### Buttons
Blocky, inked and decisive.
- **Shape:** square (0), 2px border matching the fill, minimum 52px tall, 14px 22px padding, condensed uppercase at 1.25rem with an optional 20px inline SVG icon.
- **Ink:** black fill, board-white text. **Red:** process-red fill, white text. **Paper:** board-white fill, black text.
- **Hover / Focus:** ink and red invert to the field colour with black text; paper inverts to black. 0.15s colour transition. Active presses down 1px. Focus is a 3px outline offset 3px, black on light ground and field colour on dark ground.
- **Square control:** 48px black square with a field-coloured chevron; turns red on hover; disabled becomes an outlined empty square.

### Chips
- **Style:** transparent, 2px currentColor border, label type, 4px 9px padding (tool chips are 1.5px and 0.75rem). Used for toolkits, price tags, sensors and control legends. Never filled, never rounded.

### Cards / Containers
- **Spec cell:** no own border radius or shadow; shares 2px rules with neighbours. Padding clamp(22px, 3vw, 34px). Variants fill with the field colour or with black.
- **Frame (credits reel):** board-white or field-coloured panel 360px wide on a black strip edged by sprockets; a label row with year and place sits over a 2px rule.
- **Contact way / contact card:** solid board-white or black block with a 32px icon column; black versions invert to the field colour on hover.

### Inputs / Fields
No form inputs exist. Contact is by iMessage and email links.

### Navigation
- **Studio:** sticky 64px black bar; mark plus condensed brand at left; label-type links with a 2px field-coloured underline on hover; red call-to-action block that turns field-coloured on hover. An apps dropdown hangs as a black panel with a 2px field border and no top border. Under 900px a two-bar burger opens a full-height black sheet with 2.5rem condensed links.
- **App microsites:** same black bar with the app icon and in-page links; wraps under 640px.

### Sprocket Film Edge (signature)
A 26px strip of black with rounded-rect holes, tiled from an inline SVG, whose holes show the colour behind. It closes the hero, edges the credits reel top and bottom, opens the contact section and footer, and closes each app hero. Where scroll-driven animation is supported and motion is allowed, it slides horizontally as the page scrolls.

### Tally and Steps
Numbered sequences pair a large tabular condensed numeral with a title and body, divided by rules. The live tally is a small red label block with a white dot.

### Cookie Notice
Black bar fixed at the bottom, max 560px, 2px field-coloured border, square field-coloured button in condensed caps.

## Do's and Don'ts

### Do:
- **Do** set the page's accent only through `--field`, and on app pages set it on `<body>` from the app icon.
- **Do** build groups as a ruled grid with 2px currentColor rules, top/left on the container and right/bottom on the cells.
- **Do** set headings, numerals and buttons in condensed uppercase Archivo (wdth 64%, weight 800-850, line-height 0.84-0.9).
- **Do** use the sprocket film edge (26px) to divide major colour fields.
- **Do** invert fills on hover (black to field, red to field, paper to black) with a 0.15s colour transition.
- **Do** keep Spec Grey on board white only; switch to Carton Black on field colours and Ash on Black on black.

### Don't:
- **Don't** round UI corners; radius stays 0 except on app icon artwork.
- **Don't** use drop shadows, blur or soft colour gradients for depth.
- **Don't** use cream or warm off-white grounds; the reading ground is the cool board white.
- **Don't** add a second accent colour beside the field colour and process red.
- **Don't** float items as separate gapped cards when they belong in a ruled panel.
- **Don't** put small uppercase labels above headings as kickers; labels belong inside cells and data rows.
