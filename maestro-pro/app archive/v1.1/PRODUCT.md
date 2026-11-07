# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack
SwiftUI, iPadOS 18.6+ and Mac Catalyst. No third-party packages; Bravura (SIL OFL) bundled for engraving.

## Users
(Inferred from the brief, not interviewed.) Musicians practising a piece: score on an iPad on a music stand or a Mac beside an instrument, hands busy, glancing at the screen.

## Product Purpose
Import sheet music (PDF, MusicXML / MXL) and an optional backing track, then follow along: each note lights for exactly as long as it should sound, the page scrolls itself, and an optional playhead shows where the player should be.

## Positioning
A play-along reader that treats the printed page as the instrument's display, timed to the backing track.

## Capabilities and Constraints
- MusicXML timing is exact. PDF timing is read on-device from the page: note values (open/filled heads, stems, beams/flags, dots) and rests give exact rhythms and the metre; bars that don't add up (tuplets, unusual engraving) fall back to printed spacing, and the inspector says how many bars were read exactly.
- Backing track sync: BPM (to 0.01) + start offset; practice speed scales both. "Lock Tempo Here" on a later downbeat fits the BPM to the recording so long pieces don't drift.
- PDFs are also read into MusicXML (pitches from clef, key signature and accidentals; saved as converted.musicxml, exportable). The original key shows the PDF itself; other keys engrave the converted music.
- Key: transpose by semitone or pick a key from a menu; the score is respelled with accidentals redone, and the track can pitch-shift to match.
- Match Key & Tempo to Track: reads the recording's tempo (onset autocorrelation, to 0.01 BPM) and key (Krumhansl profiles), sets the tempo and transposes the score into the track's key.
- Dark sheet music: black paper, white ink.
- Imports are copied into the app's library (coordinated read, so iCloud-only files download first); deleting the originals is safe.
- Intro: up to 16 empty bars before bar 1, shown as rest bars above page 1; the backing track starts with the first of them.
- Library: search by title; playlists (ordered, reorderable) in the sidebar.
- Hands-free use: big targets, keyboard shortcuts on Mac (space = play).
- Score editor (MusicXML and copies of PDFs): eight modes (Notes, Rests, Marks, Dynamics, Bars, Form, Erase, Draw), a tap-for-options quick menu, triplets, ties, accidentals, articulations, repeats, endings, jumps (Segno, Coda, D.C./D.S. al Coda/Fine), tempo marks, dynamics and hairpins. The editor keeps every bar complete by the time signature; Free Editing turns that help off. Undo and redo work with the system's gestures.
- Playback follows the score: tempo marks change the pace (unless ignored), dynamics and hairpins set each note's loudness, and each staff can have its own instrument (piano, organ, guitar, bass, flute, clarinet, saxes, trumpet).
- Medleys: copy, cut, paste and duplicate bars in the editor, or insert bars from any other score in the library; each piece keeps its own key, metre and tempo.
- Listening: a tuner with a hold-a-steady-note exercise, and Wait for Me, where the score waits until you play each note in tune and for long enough (no backing track).
- Record Myself: record a take, then review it with the right note green and the note you played green or red.
- Written review of a take (Apple Intelligence when available), with tappable bars and notes that light in the music.
- Several backing tracks, each switchable and levelled; Reduce Vocals; Apple Music songs and lyrics; Set-Lists with estimated duration.
- Pages turn like a book (switchable); shortcuts for the Mac, all customisable.
- Practice aids: tap tempo, loop a section, [ and ] for practice speed.
- Notation also covers slurs, grace notes, ornaments, fingering, arpeggios, breath marks, octave lines and pedal marks.
- Chord view (advanced): the piece as a bar-by-bar chart of chords, from the file's chord symbols or worked out from the notes, following playback.
- Lyrics: files (.lrc/.txt/.kar) and CD+G karaoke; words print under the notes of an engraved score.
- Sharing: MusicXML, PDF and print from the library menu; Free Scores and the Modern Jazz Fake Book download on request; the app takes files from the share sheet.
- The toolbars are customisable on iPad and Mac; in-app Help covers every feature.

## Brand Commitments
"Should look like a proper Apple-made Pro app, feel expensive, plenty of animations." (user brief)
Later brief: skeuomorphic and professional, not flat; leather and metal (see DESIGN.md).

## Product Principles
- The score is the hero; chrome recedes while playing.
- Timing truth over decoration: highlights follow the written rhythm, and the app says when it had to estimate.
- Glanceable from a music stand.
