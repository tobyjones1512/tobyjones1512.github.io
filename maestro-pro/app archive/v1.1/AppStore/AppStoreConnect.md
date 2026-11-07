# Maestro Pro: App Store Connect pack

Paste each block into the field named in its heading. Character limits are Apple's. All copy is British English.

## Before you submit (blockers)

1. **Subscriptions are not in the app yet.** The website sells Free, Performer and Professional, but there is no StoreKit code or feature gating in the app. Apple will reject (guideline 3.1.1) an app that describes paid plans it cannot sell, and the review notes below say the app is free. Either build the in-app purchases first, or submit version 1.0 as a fully free app and take the pricing section off the website until the plans exist. The subscription section further down is ready for when they do.
2. **Camera permission.** `NSCameraUsageDescription` is set, but the website says camera scanning is a future feature. Remove the key and the hidden scanner entry point, or finish the feature, so the permission string matches what the app does.
3. **Push notifications entitlement.** `Play Along.entitlements` has `aps-environment`. The app does not use push, so remove it unless you plan to.
4. **Bundle ID** stays `com.tobyjones.PlayAlong` (iCloud continuity). Create the App Store Connect record with that ID and the name "Maestro Pro".
5. **Screenshots for Mac** in `AppStore/Mac` are built from simulator captures laid out at Mac window proportions, with a window frame added. Apple expects screenshots from the real platform, so capture real Mac Catalyst windows and replace them. Note that `SecureContent` (Security.swift) blanks the score and lyrics in real screenshots with no setting to turn it off, so a Cmd+Shift+5 capture will show an empty page. Add a debug or hidden switch for it, or build a screenshot configuration, before capturing on a real device or Mac.
6. Check the education page's volume-purchasing wording and the iPad model list on the website against Apple's current terms.

## App information

| Field | Value |
|---|---|
| Name (30) | Maestro Pro |
| Subtitle (30) | Sheet music that plays along |
| Bundle ID | com.tobyjones.PlayAlong |
| SKU | maestropro-1 |
| Primary language | English (U.K.) |
| Primary category | Music |
| Secondary category | Education |
| Platforms | iPad, Mac (Mac Catalyst), iPhone (iPhone and iPhone Duo outer display: a sheet music viewer only). |
| Minimum OS | iPadOS 17, macOS 14 |
| Copyright | 2026 Toby Jones |
| Version | 1.0 (build 1) |
| Price | Free (with in-app purchases once they exist) |
| Content rights | Does not contain, show or access third-party content except as the user supplies or searches for it (see review notes) |

## URLs

| Field | URL |
|---|---|
| Support URL | https://thecaffeinemediacompany.com/maestro-pro/support.html |
| Marketing URL | https://thecaffeinemediacompany.com/maestro-pro/ |
| Privacy Policy URL | https://thecaffeinemediacompany.com/maestro-pro/privacy.html |
| Terms of Use (EULA) | Apple's standard licence agreement, or add your own page before the paid plans launch |

## Promotional text (170, can change without a new version)

Read it, hear it, play it. Notes light as they sound, lyrics move in time, and the page turns itself. Slow down, loop a bar, change key.

## Description (4000)

Maestro Pro is sheet music that plays along with you.

Open a score and press play. Every note lights as it sounds, a soft wash marks the bar, and the page scrolls or curls over exactly when you need it. Slow a hard passage right down without changing the pitch, loop a few bars, count yourself in, switch on a metronome, or transpose the whole piece for your clarinet, trumpet or saxophone. The score is typeset again in the new key, not just relabelled.

BRING YOUR OWN MUSIC
Import PDF, MusicXML (.musicxml, .xml, .mxl), MIDI and karaoke (.mid, .kar) files, lyrics (.lrc, .txt) and CD+Graphics karaoke (.cdg). Import a whole folder at once. Keep your library on your device or in your own iCloud Drive so it is on all your devices.

SEARCH FOR SCORES
Search Scores finds free scores from a built-in classical and jazz catalogue and from the wider web, so you can start playing in a minute.

BACKING TRACKS AND LYRICS
Add a backing track, or play along with a song from your Apple Music subscription. Match its key and tempo, stack several tracks, and see the words scroll in time. Duets and group songs give each singer a colour, and the lyrics show a pause during a long break.

PRACTISE PROPERLY
- Wait for Me: the score waits until you play the right note.
- A tuner and a steady-note trainer.
- Record yourself against the score and see every wrong note, late entry and bar to work on.
- Scales and arpeggios made on demand, in any key.
- Mark up the page with Apple Pencil. Your ink is included when you export a PDF.

WRITE AND EDIT
Fix a wrong note, add a harmony or write something new. Touch a note and slide it up or down, scribble over it to rub it out, tap a length to change it. The editor keeps beams, ties and bar lengths tidy for you. Every save is a version you can return to: try an idea on a branch, merge it back bar by bar, and push the whole history to your own GitHub repository.

PLAY TOGETHER
Connect up to eight devices so everyone plays in perfect time, each from their own part, in their own key and on their own instrument.

SHARE AND PRINT
Export MusicXML or PDF, print, make a video of the music following along, or send a Maestro Pro file to another player.

MADE FOR TEACHING
A patient practice partner for students, and a quicker way for tutors to prepare parts and run an ensemble.

PRIVACY
No accounts and no adverts. Your scores and recordings stay on your device and in your own iCloud. Anonymous, privacy-friendly usage counts help improve the app, and the app uses the internet otherwise only when you ask it to.

Maestro Pro was made by Toby Jones in England.

## Keywords (100, comma separated, no spaces)

sheet music,musicxml,score,piano,practice,karaoke,lyrics,backing track,metronome,tuner,scales,midi,pdf

## What's New (version 1.0)

Welcome to Maestro Pro.

## Screenshots and banners

| Slot | Size | File |
|---|---|---|
| iPad 13-inch (up to 10) | 2732 x 2048 | `AppStore/iPad/1-play.png` to `6-search.png`, in order |
| Mac (up to 10) | 2880 x 1800 | `AppStore/Mac/1-play.png` to `4-practise.png`, in order |
| Header / feature image | 5244 x 2950 | `AppStore/Header-5244x2950.png` |
| Search banner | 5244 x 2950 | `AppStore/SearchBanner-5244x2950.png` |

Rebuild any time with `python3 Tools/make-store-shots.py` (sources are in `AppStore/raw`).

Localised sets (English, French, German, Spanish, Chinese, Japanese, Swedish, Portuguese, Italian) are in `AppStore/Screenshots/<Language>/<Device>/`, numbered in upload order: iPhone (4, 1206 x 2622), iPhone Duo (4, 1398 x 2034, one of the Duo's supported sizes along with 2034 x 1398, 2007 x 2853 and 2853 x 2007), iPad (8, 2732 x 2048) and Mac (6, 2880 x 1800). The paywall captures for review and marketing are in `AppStore/Paywalls/`. Rebuild with `python3 Tools/make-localised-shots.py` (sources in `AppStore/raw2`; the simulator launch flags `-seed -shot 1 -shotprices -open <title>` are DEBUG only).

Translated store text (name, subtitle, promo, description, keywords, What's New and in-app purchase names) is in `AppStore/Localised/<Language>.md`, checked against Apple's character limits by `python3 Tools/make-localised-text.py`. The app's own text is localised into the same nine languages through `Play Along/Localizable.xcstrings` and `Play Along/InfoPlist.xcstrings`, generated by `python3 Tools/make-app-strings.py` from `Tools/translations/` (`sources.json` plus one `<lang>.txt` per language, `index|translation` lines). Edit the `.txt` files and rerun the script rather than the catalogs. SwiftUI literals, the paywall, plain Swift strings (via `String(localized:)` or `LocalizedStringKey`) and the Help guide are covered. Still English: written-review text, instrument and scale names, engraving and import error messages, and the shortcut lines in Help. Translations need native review.

## App Review information

**Contact:** Toby Jones, hello@thecaffeinemediacompany.com (add your phone number in App Store Connect).

**Sign-in required:** No. The app has no accounts. Leave "Sign-in required" unticked.

**Notes for the reviewer** (paste as is):

> Maestro Pro is a sheet music reader and player for iPad and Mac (Mac Catalyst). It has no accounts and no sign-in.
>
> To try it: open the app, tap "Open Sample" on the start screen to load a built-in score, then press play. The notes light as they sound. The slider icon at the top right opens the Inspector for tempo, loop, key and instrument. "Scales & Arpeggios" makes practice material with no files needed.
>
> Permissions, all requested only when the matching feature is used:
> - Microphone: the Tuner, Wait for Me (listening for the note you play) and Record. Audio is processed on the device and never uploaded.
> - Local network: Play Together, which links up to eight nearby devices using Apple's MultipeerConnectivity framework (Bonjour service _playalong-sync) so they play in time. Needs two devices to demonstrate; it is not required for review of any other feature.
> - Apple Music: optional. Plays a song from the user's own subscription next to a score and shows its lyrics through MusicKit. It needs an Apple Music subscription to demonstrate.
>
> Network use, always user-initiated: "Search Scores" (Classical and Jazz tabs use a built-in list of free scores; the Internet tab searches the web and lists MusicXML files hosted on public sites and GitHub), lyrics lookups (LRCLIB) and singer matching (Genius). The app does not host or sell any score. Users import their own files or download freely available ones from the site that hosts them, and are responsible for the rights to what they import.
>
> GitHub sync (Professional features): the user can connect a score to their own GitHub repository using a personal access token they create. The token is stored in the Keychain and sent only to api.github.com. This needs a GitHub account and token to demonstrate, and is optional.
>
> iCloud: optional iCloud Drive storage (container iCloud.com.tobyjones.PlayAlong) so the library appears on the user's other devices.
>
> Content protection: scores and lyrics are deliberately hidden from system screenshots and screen recordings, and playback pauses during a recording, to protect the sheet music and lyrics users import. This is intentional and applies to those screens only. Everything else can be captured normally.
>
> Subscriptions: [DELETE THIS PARAGRAPH IF THE PLANS ARE NOT IN THE BUILD. If they are: "Free, Performer and Professional are auto-renewing subscriptions in one group, each with a one-week free trial. The Free plan needs no purchase. Use the sandbox account to try them. Restore Purchases is in Settings."]
>
> The app does not use the camera, location, contacts, photos or tracking.

**Attachment:** none needed. Optional: a 30 second screen recording of play, Inspector and the editor.

## Age rating answers

All "None" / "No": cartoon or fantasy violence, realistic violence, sexual content, nudity, profanity, horror, alcohol/tobacco/drugs, gambling, contests, medical advice, unrestricted web access (the Internet tab shows a list of links and downloads files, it is not a general browser; if you consider it one, answer "Yes" and expect 17+ not to apply, as it is a search of music files), user-generated content (none shared between users). Expected rating: 4+.

## App Privacy ("nutrition label")

Declare usage data. Maestro Pro has no accounts or advertising, but it sends anonymous usage events through Aptabase (EU-hosted, no IP storage, no persistent device ID). Answer "Yes, we collect data" and declare:

- **Usage Data > Product Interaction:** not linked to the user, not used for tracking, purpose "Analytics".
- **Diagnostics** is not needed unless you add crash reporting.
- **Other Data** (public feedback posted to the Fider board) is typed by the user and posted on request, not collected in the background. Optionally declare **User Content > Other User Content** (not linked, "App Functionality") if you want to be cautious.

Everything else: not collected. Re-check Aptabase's own documentation for the exact categories before submitting.

Tracking: No. Required-reason APIs: declare in the privacy manifest if Xcode's report asks (UserDefaults, file timestamp and disk space APIs are the usual ones). Run Product, Archive, then "Generate Privacy Report" to confirm.

## Export compliance

Uses only standard encryption (HTTPS, Keychain, the encrypted Play Together link). Answer "Yes, uses encryption" then "Exempt: only standard encryption". Add `ITSAppUsesNonExemptEncryption = NO` to the build settings to skip the question on every upload.

## In-app purchases (for when they are built)

Subscription group: **Maestro Pro Plans**

| Product ID | Reference name | Duration | UK price |
|---|---|---|---|
| com.tobyjones.MaestroPro.Performer.weekly | App Unlock - Performer - Weekly | 1 week | £8.00 |
| com.tobyjones.MaestroPro.Performer.annual | App Unlock - Performer - Annual | 1 year | £100.00 |
| com.tobyjones.MaestroPro.Professional.weekly | App Unlock - Professional - Weekly | 1 week | £10.00 |
| com.tobyjones.MaestroPro.Professional.annual | App Unlock - Professional - Annual | 1 year | £120.00 |

No intro offers. Level order in the group (highest first): Professional Annual, Professional Weekly, Performer Annual, Performer Weekly. The old monthly products are no longer offered. The lifetime unlock (`com.tobyjones.MaestroPro.Professional.life`, non-consumable, Professional) stays on sale, shown at the bottom of every paywall.

Localised display names and descriptions (English U.K.):

- Performer: "Everything except the score editor." Notes, bars and moving-line highlighting, internet services, the equaliser and other tools, backing tracks and Apple Music, Play Together and recording.
- Professional: "Everything, including the editor." Adds the score editor, version history and GitHub sync.

Free needs no product: viewing the sheet music of up to 3 scores. Playback and everything else need Performer or Professional.

Subscription review screenshot: a capture of the plan screen once it exists. The app must show price, period, renewal and cancellation wording and links to Terms and Privacy on the purchase screen.

## TestFlight

Beta app description: "Maestro Pro is sheet music that plays along. Please try importing your own scores, playing, slowing down and looping, and tell me about anything that looks wrong on your iPad or Mac."

What to test (build 1): "Open Sample, then press play. Try the Inspector, importing a MusicXML or PDF file, the Tuner, and Search Scores. On a Mac, press Cmd+E on a score to open the editor."

Feedback email: hello@thecaffeinemediacompany.com
