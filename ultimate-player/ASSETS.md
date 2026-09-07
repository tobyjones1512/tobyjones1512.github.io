# Ultimate Player - Assets Required

The Ultimate Player page has been created with the following structure. You need to add the following image assets:

## Required Assets

### App Icon
- **File**: `assets/app-icon.png` (and favicon.png)
- **Size**: 1024x1024px (minimum)
- **Format**: PNG with transparency recommended
- **Usage**: Header logo, hero section, doc pages
- **Note**: Use the "Light Alt.png" icon you mentioned

### Screenshots (in `assets/screenshots/`)
1. **hero-screen.jpg** - Main hero screenshot showing iPhone and Apple TV experience
2. **library.jpg** - Library view with organized media
3. **playback.jpg** - 3D video playback interface
4. **conversion.jpg** - AI 3D conversion settings
5. **tv.jpg** - Apple TV full-screen experience

**Recommended sizes**:
- Hero screenshot: 600x800px (will be rotated 1.5deg, max-width 300px on mobile)
- Gallery screenshots: 500x1000px (displayed at various sizes, 4 columns on desktop)

## File Structure
```
ultimate-player/
├── index.html           # Main landing page
├── support.html         # Support & FAQ
├── privacy.html         # Privacy Policy
├── ASSETS.md           # This file
└── assets/
    ├── app-icon.png    # Main app icon
    ├── favicon.png     # Tab favicon (can be same as app-icon.png)
    └── screenshots/
        ├── hero-screen.jpg
        ├── library.jpg
        ├── playback.jpg
        ├── conversion.jpg
        └── tv.jpg
```

## Design Notes

The page uses a modern tech color scheme:
- **Primary Color**: Cyan (#00D9FF) - Used for headings, buttons, and accents
- **Dark Background**: #0F1419 - Deep blue/black for a sleek look
- **Secondary Accent**: Purple (#7C3AED) - Accent tiles and highlights
- **Light Text**: #E8ECEF - Readable on dark backgrounds

The design matches the Remy page structure but with:
- Dark mode aesthetic suitable for media/entertainment
- Feature bento grid (6 tiles)
- Why Choose Ultimate Player section (3 items)
- Screenshots gallery (4 images)
- What's Included feature groups (3 sections)
- Perfect For personas (3 cards)

## Navigation
Pages are linked together:
- index.html → support.html, privacy.html
- support.html → index.html, privacy.html
- privacy.html → index.html, support.html

No pricing section (as requested - no mention of pricing).
