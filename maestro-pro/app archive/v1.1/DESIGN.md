# Design

## World
A practice room at night: a dark leather desk under a reading lamp, a sheet of real paper on it, and a graphite faceplate with hardware keys and an amber display. Materials are drawn, not flat: leather has pebbling and stitching, paper has fibre and a curved binding edge, metal is brushed and bevelled, keys sink when pressed. In the light styles the desk becomes pale leather; the hardware stays graphite.

## Materials (Skeuo.swift)
- **Settings**: every texture belongs to a material (paper, desk, leather buttons, metal), each with its own strength in Settings > Surfaces (0 to 200%), plus a master switch and a page shadow/curl strength.
- **Texture**: three seeded procedural tiles (grain, brushed, leather) drawn once into transparent relief, so they lie on any colour with a plain blend. Off in High Contrast.
- **StageBackground**: the style's stage colour as leather, lit from above, darker at the corners.
- **PaperSheet**: cream or black paper, fibre, binding shade on the left, three-layer shadow (contact, mid, far).
- **MetalPlate**: brushed graphite with a top sheen, bevel and four screws. Used by the transport bar, the editor palette and the quick menu.
- **KeyStyle**: a raised hardware key; `lit(true)` lights a lamp line along its bottom edge. DomeStyle is the round brass-rimmed play key.
- **Recessed / LCDText / DisplayGlass**: pressed-in displays, unlit segments showing through, scan lines.
- **LeatherPad / BrassPlate**: stitched leather tiles; brass for the one main action on a screen.
- **engraved / embossed**: type pressed in or standing proud.

## Colour
Leather browns from the style; amber accent is the lamp (never a glow, only lit edges and digits); ivory lettering on dark, brown on light. Brass is for metal fittings only.

## Type
Baskerville (as in the engraved scores) for display lettering, engraved. SF for controls and lists. Display digits are monospaced.

## Rules
- Depth always has an offset and a blur; no zero-offset coloured halos.
- System navigation, lists, toggles, pickers and sheets stay native; the materials dress the custom surfaces around them.
- Contrast: ivory on dark leather, dark ink on paper; lit amber on near-black glass.

## App icons
Eighteen icon sets (`Tools/make-icons.swift` draws them all: run it after changing a design). Each has light, dark and tinted variants in `Assets.xcassets/Icon-*.appiconset`, with `AppIcon` the primary; `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS` ships the rest as alternates. `IconPreview-*` image sets feed the chooser in Settings (`AppIcons.swift`).
