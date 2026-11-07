import SwiftUI

/// The in-depth guide: every part of the app, one topic per page.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Topic: Identifiable {
        let id: String, symbol: String
        let intro: String
        let sections: [(title: String, body: [String])]
        var title: String { id }
    }

    /// The shortcuts as they come, one line per group.
    private static var shortcutLines: [String] {
        ["Playback", "View", "Tools"].map { group in
            group + ": " + ShortcutAction.allCases.filter { $0.group == group }.map { "\($0.title) \($0.defaultChord.label)" }.joined(separator: ", ") + "."
        }
    }

    private static let topics: [Topic] = [
        Topic(id: "Getting Started", symbol: "sparkles",
              intro: "Maestro Pro is a working tool for musicians: it reads your scores and follows them to the note, turns pages hands-free, rehearses with a backing track, a song from Apple Music, the built-in instrument or a metronome, and lets you write and revise the music itself.",
              sections: [
                ("The first minute", [
                    "Tap Import Score on the home screen (or the + button, then Import Score) and choose a PDF, MusicXML file or any other supported file. It appears in your library on the left; tap it to open it.",
                    "Press the big Play button at the bottom. The music plays and follows along. Tap anywhere on the music to start from there, or drag the progress bar.",
                    "Nothing yet to play? Choose Open Sample on the home screen, or Search Scores to download classical pieces and jazz tunes, or to search the web."]),
                ("Simple and Advanced mode", [
                    "Settings has a Mode switch. Simple mode keeps the screen to what most people need. Advanced mode adds the library tools, Play Together, the staff-by-staff controls and the Customise Every Colour page.",
                    "Everything described in this guide is available in Advanced mode; each topic says when a control only appears there."]),
                ("The toolbar", [
                    "On an iPad the toolbar keeps the few controls used most (open, zoom, backing tracks and sound, annotate, edit) and puts everything else in the More menu at its end: tools at the top, then the page, what shows while playing, the words, and the backing tracks last. A Mac shows every control as its own button.",
                    "Settings is in the library only, so it is not on the score's toolbar. To get back to the library, show the sidebar with the button at the top left."]),
                ("Customising the toolbar", [
                    "On iPad, touch and hold the toolbar (or tap the ⋯ at its end and choose Customise Toolbar) to drag controls on or off the bar; on a Mac, choose View ▸ Customize Toolbar. The Inspector button always stays.",
                    "On a narrow screen the controls fold into one More menu instead."]),
                ("The screen", [
                    "On a wide screen the library is a sidebar on the left and the score fills the rest. While a piece plays the library hides itself, to give the music room (turn this off in Settings).",
                    "On a smaller screen, or in a narrow Split View window, the toolbar folds into one More menu and a Library button appears at the top left to take you back to the library.",
                    "A Mac runs the same app: files can be opened with Command-O, and there are Playback and View menus with keyboard shortcuts."])]),
        Topic(id: "Your Library", symbol: "books.vertical",
              intro: "Everything you import lives in the library and stays on the device. It is also kept in iCloud when iCloud Drive is on.",
              sections: [
                ("Bringing music in", [
                    "Import Score takes PDF, MusicXML (.musicxml, .xml, .mxl), MIDI and karaoke (.mid, .kar), lyrics (.lrc, .txt), CD+Graphics karaoke (.cdg) and Maestro Pro (.maestropro) files. Several can be chosen at once.",
                    "You can also drag files from the Files app straight onto the window, or choose Maestro Pro from the share sheet of another app (Files, Mail, Safari, Messages…) to import what you are looking at.",
                    "Import Folder reads every supported file in a folder. In Settings, Link a Folder keeps a folder in step with the library so new files appear by themselves.",
                    "New Blank Score starts an empty score to write yourself: you choose the name, time signature, key, number of bars, staves (treble, bass or piano) and tempo.",
                    "Lyrics with Backing: choose a backing track and the app finds its timed lyrics online, for a karaoke-style screen. You can also choose a lyrics file along with the backing track."]),
                ("Search Scores", [
                    "Search Scores has three tabs. Classical lists pieces that are built in. Jazz lists about 2,400 tunes in six volumes: only the list is in the app, a tune downloads when you tap Add, or tap Add All to take the whole collection (about 40 MB, needs the internet).",
                    "Internet searches the web, and GitHub, for MusicXML files: type a composer or piece. Results come from other people's pages, so check that a score is free to use before you add it.",
                    "A tick shows what you already have."]),
                ("Finding and organising", [
                    "Search at the top of the library finds titles. Settings chooses how the library is sorted.",
                    "Set-Lists show how many scores they hold and about how long they run (the backing track's length, or the notes at the score's tempo; PDFs without a track are not timed). Press and hold a score for Rename, Edit Title on Sheet (the heading printed on the music, separate from its name in the library), Add to Set-List, Share, Duplicate and Delete from Library. Duplicate makes a full copy, with its backing track, lyrics and drawings, to edit or build a medley in without touching the original. Set-Lists group scores for a rehearsal or a gig.",
                    "Share with Another Player makes a .maestropro file that carries the score and its backing track. Another Maestro Pro user who opens it gets all of it."])]),
        Topic(id: "Playing a Score", symbol: "play.circle",
              intro: "The bar at the bottom controls playback; the toolbar and the Inspector change how it looks and sounds.",
              sections: [
                ("Playback controls", [
                    "Play and Pause, skip back and forward by bar, and a progress bar you can drag. The counter shows the bar, beat and time.",
                    "Tap the music to jump there. On a Mac, Space plays and pauses, the arrow keys skip bars, Return goes to the start and K turns the metronome on or off.",
                    "Practice Speed slows a piece down or speeds it up without changing the pitch. Type any percentage from 10 to 400 in the box, or use the slider (50 to 150).",
                    "The tempo is the score's own (from its printed metronome mark) unless you set one: typing a BPM, tapping it or matching a backing track makes it your own, and the Custom Tempo switch under the tempo goes back to the score's. Tap Tempo: tap the tempo (the note and number beside the metronome) and a pad opens with a big Tap key. Tap it in time with the beat; the tempo appears from the second tap and updates with every tap, and a few more make it steadier. It is set as you tap. With a keyboard, the space bar taps while the key is focused. The same pad is under Tempo in the Inspector.",
                    "Loop: in the Inspector, Loop plays the bars you choose over and over, to practise a hard passage. On a Mac or with a keyboard, [ slows the practice speed and ] speeds it up.",
                    "Count In plays a bar of clicks before the music. Lead-in Bars sets how many bars of introduction come before bar 1, so a backing track with an intro lines up. The Metronome clicks on every beat."]),
                ("What follows the music", [
                    "Show While Playing (the sparkle button) chooses how playback is shown: Highlight Notes lights each note as it sounds, Highlight Bar tints the bar, and Moving Line draws a line across the page. With all three off, only the bar counter and page turns follow.",
                    "Follow Playback scrolls the page for you. Dark Sheet Music shows white music on black, kinder in a dim room.",
                    "Zoom changes the size of the notation; the bars reflow to fit. Pinching also works. Highlight colour is in Settings."]),
                ("Turning pages like a book", [
                    "By default the music shows one page at a time and turns it like the page of a book, with a curl, when playback reaches the next page. Follow Playback decides whether it turns by itself. You can also drag a page to turn it by hand, or use Page Up and Page Down.",
                    "Turn Pages Like a Book can be switched off in Settings ▸ Sheet Music, in the Zoom menu, or in the View menu on a Mac. The music then scrolls down the page instead, with all the pages in one column. Reduce Motion turns the page without the curl.",
                    "While you draw with Annotate, dragging does not turn pages, so the pencil is free. With a page shown whole there is no scrolling inside it; use Zoom to change the size of the notation."]),
                ("Key and transposing", [
                    "In the Inspector, Key has the key of your instrument (concert pitch, B♭, E♭, or B♭ tenor). The score is shown transposed to match, so a trumpet player reads what a trumpet plays.",
                    "Transpose moves the whole piece up or down by semitones. The Key menu lists each key with its relative minor, for example C / A minor; choose one and the score moves the shortest way to it.",
                    "With a backing track, Shift Backing Track decides whether the backing track moves with the score."]),
                ("Chord view (Advanced mode)", [
                    "The Chord View button (a grid of squares) in the toolbar, or More ▸ Chord View, shows the piece as a chart of chords, a cell for each bar, with repeat signs, endings and jumps. The bar playing is lit and the chart scrolls to follow; tap a bar to play from it.",
                    "If the file carries chord symbols they are shown as written. Otherwise the app works the chords out from the notes, two to a bar in 4/4 and one to a bar in 3/4 and 6/8: triads, diminished, augmented and seventh chords, with a slash when the bass is not the root. It is a guess, best with a bass line or accompaniment, and a bare melody gets a plausible triad.",
                    "The chords move with the key you have chosen, spelled with flats or sharps to match. Use Zoom for bigger or smaller chords."]),
                ("Notation that is shown", [
                    "Besides notes, rests, accidentals, ties, tuplets, repeats, endings, segno, coda and the rest, scores show slurs, grace notes (small slashed notes that sound just before the main note), trills, mordents and turns, fingering numbers, arpeggio waves, breath marks and caesuras, octave lines (8va, 8vb, 15ma, 15mb) and pedal marks (Ped. and the release star).",
                    "Slurs and ornaments are drawn but do not change how the built-in instrument plays (a trill sounds as a plain note). They are saved and exported with the score. Grace notes do sound, a hair before the beat.",
                    "A score with several slurs open at once on one staff draws the most recent, and an octave line is shown without changing the sound."]),
                ("Lyrics under the notes", [
                    "Adding a lyrics file to a score leaves the music on screen and prints the words under the notes, in a row of their own that the staves are spaced out to make room for. The syllable being sung lights up as it plays. Words Under the Notes can be turned off, and Show Lyrics Instead of Music switches to the big lyrics screen.",
                ]),
                ("Dynamics", [
                    "Dynamics (ppp to fff) and crescendo and diminuendo hairpins in a score set how loud the built-in instrument plays: a note is as loud as the last dynamic, and a hairpin changes it steadily towards the next dynamic. A score with no dynamics plays at one even level.",
                    "You can add them in the score editor's Dynamics mode, and they are saved with the score."]),
                ("The tempo", [
                    "Tempo is in beats per minute. Type it, step it, or drag the slider. With a backing track, Lock Tempo Here sets the tempo from where you tap on a downbeat.",
                    "Metre tells the app how many beats are in a bar. It is found automatically from MusicXML files; for PDFs the app asks when it cannot tell.",
                    "If a score has tempo marks (♩ = 96) they change the pace of the built-in instrument from that bar on. A backing track keeps its own tempo."])]),
        Topic(id: "Tuner & Wait for Me", symbol: "tuningfork",
              intro: "Maestro Pro can listen through the microphone: to tune your instrument, to train a steady note, and to wait for you to play a score note by note. Sound is analysed on the device and is never recorded or sent anywhere.",
              sections: [
                ("The tuner", [
                    "Open the Tuner from the home screen, the + menu, Settings ▸ Listening, or the tuning fork in a score's toolbar. Play a note: the display shows its name, how many cents sharp or flat it is (a cent is a hundredth of a semitone), and the frequency. The needle sits in the green zone when you are in tune, and the trace below shows the last eight seconds.",
                    "If your instrument is set to B♭ or E♭ in the Inspector, the written note is shown too. Play Reference Note sounds the note you are aiming for. A = 440 Hz can be changed (415 to 466) for baroque or orchestral tuning."]),
                ("Hold a steady note", [
                    "Under the tuner, the ring fills while you keep a note in tune. Choose Any Note, or one particular note to hold; choose how close counts as in tune (Strict ±5¢, Normal ±10¢, Relaxed ±20¢) and the goal (5 to 30 seconds). It shows your best time and how steady your pitch was.",
                    "A wobble or a different note starts the time again. Goals are counted for you, so you can try to beat them."]),
                ("Wait for Me", [
                    "Wait for Me is a practice mode where the music waits for you. Open a score and choose Wait for Me (the ear icon, or More ▸ Wait for Me). The score stops on the first note. It moves on only when you play that note, in the right octave and in tune, and hold it for the right length of time at the current tempo and practice speed.",
                    "The panel above the playback bar shows the note to play, a pitch meter (the dot should sit in the green zone) and a bar that fills as you hold it. It says if you are sharp, flat, or playing a different note. Hear the note plays it for you; Back and Skip move one note; the sliders button chooses the part to follow (a piano score has two), how strict to be, how much of each note must be held, and whether any octave is accepted (useful for voices).",
                    "A repeated note needs a fresh start, so let the first one stop before the next. At the end you see your accuracy and how far from the notes you were on average. Chords count when you play any one of their notes; this mode follows one line at a time.",
                    "A backing track stays silent while Wait for Me is on (the score waits, so a backing track could not keep up). Pressing Play ends it."]),
                ("Microphone tips", [
                    "Settings ▸ Listening has Microphone Sensitivity: turn it up in a quiet room or for a soft instrument, and down if it picks up noise. A quiet room works best, and a single note at a time. Wait for Me and the tuner need microphone permission; if you said no, turn it on in the device's Settings ▸ Privacy ▸ Microphone."])]),
        Topic(id: "Record & Review", symbol: "record.circle",
              intro: "Record yourself playing a score, then review the take with the notes lit: green where you should have been, red where you actually were. It listens through the microphone, so it works with any instrument or your voice.",
              sections: [
                ("Recording", [
                    "Choose Record (the round record button in the toolbar, or More ▸ Record Myself, or ⌘R on a Mac). After the count-in the score plays and you play along. Press Stop, or pause, when you have finished.",
                    "While you record the built-in instrument and the metronome are muted, so the microphone hears only you. If the score has a backing track the app asks first, because the microphone would hear it: choose Mute It and Record (it comes back afterwards), or Record Anyway if you use headphones. The recording bar has a Mute It button too. The first time, the app asks to use the microphone.",
                    "Recordings are kept with the score, so they are copied when you duplicate it. Each one is compressed to well under a megabyte a minute."]),
                ("Reviewing", [
                    "When you stop, the review opens at once. Earlier recordings are in the Record menu, newest first. Press Play to hear the recording while the score follows it, or drag the slider to any moment.",
                    "The green note is the note you should be playing at that moment. The note you actually played is lit too: green when it was the right note at the right time, red when it was late, early or a different note from the one due. If you fall behind or run ahead, however far, the note you should be on is green and the one you are still playing is red.",
                    "If you played a note that is not in the music near there, the note due is green and the strip shows the pitch you played. The summary gives how many notes you played right.",
                    "The sliders button chooses the part to judge (a piano score has two), how strict the timing is (Strict, Normal or Relaxed), how close in pitch counts, and whether any octave is accepted. Changing them re-judges the same recording. Delete This Recording removes it."]),
                ("Written review", [
                    "The sparkles button in the review writes a short review: how many notes were right, where you fell behind or rushed, whether you were sharp or flat, and which bars and notes gave trouble. It is plain and to the point.",
                    "Places in the review (bars and notes, shown with a note or barline) are links. Tap one and the recording jumps to that moment, the notes light blue in the music, and the page turns or scrolls to it. The row of numbered blocks shows every bar coloured by how it went, and each is a link too.",
                    "On a device with Apple Intelligence the review is put into wording by the on-device model, and nothing leaves the device. The facts always come from the app's own analysis, and any rewording that changes a number or a place is thrown away. Without Apple Intelligence the app writes it itself. Write Again asks for new wording."]),
                ("What to expect", [
                    "It listens for one note at a time, so chords count when you play any one of their notes. Timing is judged from the clock of the score, not from the sound of the recording, so a very slow or fast take is judged against the tempo you recorded at.",
                    "Take it as a guide. A noisy room, a weak signal, or an instrument whose octave is hard to hear can make notes look wrong; Microphone Sensitivity in Settings ▸ Listening helps."])]),
        Topic(id: "Backing Tracks & Sound", symbol: "waveform",
              intro: "A backing track is a recording that plays with the score. The built-in instrument can play the notes on the page too.",
              sections: [
                ("Several tracks", [
                    "A score can have more than one backing track, for example a rhythm section and a separate guide vocal. Add the first with Add Backing Track, then use Add Another Backing Track in the Inspector or the sound menu. They all play together, in time with the score.",
                    "Under Backing Tracks & Sound each track has its own switch, to turn it off without removing it, and its own level from -24 to +12 decibels. The first track is the one the score keeps time with, and Match Key & Tempo and the track editor work on it. The other tracks follow its speed and key, but not its edit lanes, and should be recordings that start together with it.",
                    "Reduce Vocals, on any track, cuts the singer down in a stereo recording by cancelling what is in the middle. It leaves a mono track, can take some middle instruments with it, and can't remove a voice from a mono recording."]),
                ("Apple Music", [
                    "Add From Apple Music (Inspector, Backing Tracks & Sound) searches the whole of Apple Music (and your own library) as you type, and plays the song you choose along with the score, in time. It needs an Apple Music subscription and permission to use Apple Music, and the app's own sounds, such as the instrument, mix with the song. Get the Lyrics fetches the words when Apple offers them for the song, which it does not for every song or account, and they then work like any lyrics file.",
                    "Lyrics from Apple Music (the + menu, or the home screen) opens a song's words on their own screen, with the song playing along.",
                    "Apple Music only lets an app start and stop a song, not read its sound. So the song can't be pitch-shifted and the singer can't be taken out of it. For that, add the song as an audio file you own and use Reduce Vocals. If the song drifts, move Bar 1 Starts At."]),
                ("Adding a track", [
                    "Choose Add Backing Track in the Inspector or toolbar and pick an audio file. The app listens to it and sets the score's tempo and key to match, so it starts in time.",
                    "If the score does not line up, drag the marker on the track to where bar 1 begins, or delay the track. Delay Start can be in seconds or in bars. If it drifts later in the piece, tap Lock Tempo on a downbeat further along.",
                    "Match Key & Tempo to Track runs the listening again at any time."]),
                ("Editing the track", [
                    "Edit Backing Track shows the backing track as a waveform with three lanes: Volume, Tempo and Pitch. Add points on a lane and drag them to change that setting over time.",
                    "Each point can be a straight line or a smooth S-curve. Use it to fade in or out, to ease a tempo change, or to correct a track that is slightly out of tune."]),
                ("The built-in instrument", [
                    "Play Score As picks the voice that plays the notes on the page (or Off): piano, organ, guitar, bass, flute, clarinet, saxophones or trumpet. In the Inspector, Instrument Gain and Backing Track Gain each set a level from -24 to +12 decibels for that score, so you can balance the instrument against the backing track; the arrow resets to 0. Settings has the starting volume for the instrument. It plays along with any backing track.",
                    "A score with more than one staff has a Staves panel in the Inspector: give each staff its own instrument, for example Bass on the bass-clef staff and Piano on the other. Staves left on Same as Above use the main one.",
                    "Turn Metronome on in the Inspector or with K on a Mac if you want clicks with it."])]),
        Topic(id: "Writing & Editing Music", symbol: "music.quarternote.3",
              intro: "The score editor changes the notes in a MusicXML score. A PDF is first read by the app, and the editor works on a copy of what it read. Open it with Edit Score (the music-note-list button; in Simple mode it appears for scores you created).",
              sections: [
                ("The nine modes", [
                    "The strip at the bottom of the editor has one mode for each kind of job, so the controls for a job are together. Swipe the strip for the rest.",
                    "Notes: touch a rest and slide up or down to choose the pitch; lift to put a note there, as long as the length chosen below. Drag a note up or down to move it. Scribble back and forth over a note to rub it out. Select a note, then tap a length to change how long it lasts.",
                    "Rests: tap a note to turn it into a rest of the chosen length. Tap a rest to select it and change its length, or use the bin to take it off the page (the bar keeps its length).",
                    "Marks: tap a note, then add a sharp, flat or natural, tie it to the next note, or give it staccato, accent, tenuto, marcato or a fermata. Tap one again to take it off.",
                    "Dynamics: tap a note (the dynamic goes at that note) or a bar (at its start), then choose ppp to fff. Crescendo and Diminuendo put a hairpin over the bar; Longer and Shorter stretch it over more bars.",
                    "Bars: repeat signs, and adding or deleting a bar. Expand Repeats writes the piece out as it is played.",
                    "Form: first and second time bars, jumps (Segno, Coda, To Coda, D.C., D.S., Fine) and tempo marks.",
                    "Medley: drag across bars to choose them, then Copy, Cut, Paste, Duplicate or Delete, or Insert from Score to take bars from another score in your library.",
                    "Erase: touch or drag over notes and rests. A note becomes a rest; a rest comes off the page. Double-tap Apple Pencil to switch to the eraser and back.",
                    "Draw: write over the music with Apple Pencil, with pen, marker, pencil and colour tools. The ink stays on the page."]),
                ("Building a medley", [
                    "In Medley mode, touch a bar and drag across more to choose a run of bars. Copy keeps them on the clipboard, which stays when you leave and open another score, so you can copy in one piece and paste into another. Paste puts them in after the chosen bars, or at the end if none are chosen.",
                    "Insert from Score lists your library: pick a score, choose its From and To bars, and they go in at the same place. Match My Key moves the new bars into the key of the music they follow.",
                    "The new bars keep their own key, time signature and tempo (a tempo mark appears where the pace changes), and your music takes its own back after them. A staff the copied music lacks rests; a staff your piece lacks is left out. Everything can be undone.",
                    "Duplicate repeats the chosen bars straight after themselves. Cut is Copy followed by Delete; the last bar of a piece always stays."]),
                ("The quick menu", [
                    "Tap a note and a small menu hangs over it with what you most often want: sharp, flat, natural, tie, dot, a dynamic, and turn it into a rest. Tap a rest for shorter, longer and remove. Tap an empty part of a bar for repeat start and end, add a bar and delete the bar.",
                    "Tap anywhere else to put it away. It works with a finger as well as the Pencil."]),
                ("Lengths, dots, triplets and ties", [
                    "The note buttons choose semibreve, minim, crotchet, quaver and semiquaver lengths. The dot makes a length half as long again. The 3 makes triplets: three notes in the time of two, shown with a bracket and a 3.",
                    "Tie joins the selected note to the next one, so they sound as one long note. With help on, the next note takes the same pitch; if there is no next note you are told. Tap Tie again to remove it. Ties are drawn across barlines too, and a tied note plays once.",
                    "Sharp, Flat and Natural set an accidental on the selected note; Key returns it to what the key signature says."]),
                ("What the editor does for you", [
                    "By default the editor looks after the bar. A note never runs past the barline. A longer note takes over what follows it in the bar; a shorter one leaves rests, written the way a copyist would (on the beat, not across it). Beams are added for you, and a short bar is filled with rests when you save.",
                    "Everything follows the time signature of the score, so 6/8 groups in dotted beats and 3/4 in three.",
                    "Free Editing (Options, top right) turns all of that off. A note is exactly as long as you choose, never clips to the bar, never overwrites its neighbours, and leaves no rests behind. A bar can hold too many or too few beats. Touch empty space in a bar to add a note after the last one. Nothing is tidied when you save."]),
                ("Bars, repeats and tempo", [
                    "Select a bar in Bars mode. Start and End put repeat signs on it (End cycles twice, three and four times). 1st Time Bar and 2nd Time Bar put a bracket over it; Bracket Longer and Shorter stretch it over neighbouring bars; No Time Bar removes it.",
                    "Jumps adds Segno, Coda, To Coda, Fine, and D.C. or D.S. plain, al Coda or al Fine. Put the Segno where a D.S. returns to, To Coda in the bar where the music leaps, and Coda on the bar it leaps to. Playback follows them: after a D.C. or D.S. it does not repeat sections, plays the last ending, then jumps from To Coda to the Coda (or stops at Fine).",
                    "Expand Repeats writes the piece out as it is played, with every repeat, ending and jump as its own bars.",
                    "Tempo sets a printed ♩ = mark on the bar; playback follows it from there.",
                    "Add Bar After and Delete Bar change the length of the piece."]),
                ("Undo, saving and sharing", [
                    "Undo and Redo are in the panel, and Command-Z / Shift-Command-Z, a three-finger swipe or shaking the iPad work too. In Draw mode the Undo and Redo there undo the drawing.",
                    "Save keeps your changes; Cancel asks before throwing them away. Restore the Original Score in Options brings back what you imported.",
                    "Edit with Apple Pencil Only (Options) stops fingers from changing notes, so a hand resting on the page does no harm."])]),
        Topic(id: "Lyrics & Karaoke", symbol: "quote.bubble",
              intro: "Lyrics scroll in time with the music like in Apple Music, and CD+Graphics karaoke files show their built-in pictures.",
              sections: [
                ("Lyrics files", [
                    "Add a .lrc file (timed lines) or a .txt file to a score from the Lyrics menu. Karaoke MIDI (.kar) files contain their own words.",
                    "Show Lyrics Instead of Music swaps the page for the words. Animate Syllables swells each syllable as it is sung, and Show Syllable Progress fills it. Typeface, size, alignment and blur for lines not being sung are in Settings.",
                    "A lyrics-only item (no notation) has its own screen with a transport bar and an optional backing track. Lyrics in seconds or in bars can be chosen when the file has no timing."]),
                ("Singers and breaks", [
                    "For duets, Assign Singers gives each line to a singer; Match Singers finds them from the song's page on Genius. One singer, or one singer plus everyone, stays on the left; two or more are split left and right, each with their own colour.",
                    "Show one singer's lines with the Singer filter. While the other singer sings, a gap shows an ellipsis. Progress Bar in Breaks in Settings swaps the dots for a bar that fills across the gap."]),
                ("CD+Graphics (.cdg)", [
                    "A .cdg file is the picture track of a karaoke disc: it draws coloured words and backgrounds on a small screen. The app plays it from the file's own timing. Add the song's audio as a backing track if you have it."])]),
        Topic(id: "Share, Export & Print", symbol: "square.and.arrow.up",
              intro: "Get a score, or a video of it, out of the app.",
              sections: [
                ("Share menu", [
                    "Press and hold a score in the library and choose Share. It has Export as MusicXML, Export as PDF and Print.",
                    "MusicXML opens in MuseScore, Finale, Sibelius, Dorico, Notion and most other notation apps. For a PDF score it is the music the app read from the page.",
                    "PDF is the printed page. A PDF score is passed on as it is; any other score is typeset in the key currently shown. Print opens the system print dialog.",
                    "In the share sheet you can also Save to Files, AirDrop, email or message the file."]),
                ("Other ways out", [
                    "Share with Another Player (Advanced mode, same menu) makes a .maestropro file with the score and its backing track for another Maestro Pro user.",
                    "Export Video turns a score into a movie of the music following along, with the sound.",
                    "Maestro Pro is also offered in the share sheet of other apps for files it can open, and imports them."])]),
        Topic(id: "Play Together", symbol: "person.2.wave.2",
              intro: "Up to eight devices running Maestro Pro can play in time with each other (Advanced mode).",
              sections: [
                ("Connecting", [
                    "Open your parts, then one person chooses Play Together, then Start a Session. Everyone else chooses Join a Session and picks that device. The host is asked to allow each player in. Allow the Local Network permission if asked.",
                    "Play, pause, seek and tempo changes on any device are mirrored on all of them, so a teacher and students, or a whole ensemble, stay in step. Each player keeps their own part, key and instrument; devices line up bar by bar.",
                    "Up to eight devices can join one session. The Nudge slider moves your sound earlier or later if you use wireless speakers or headphones."])]),
        Topic(id: "Version History & GitHub", symbol: "clock.arrow.circlepath",
              intro: "Save versions of a score, try ideas on branches, merge them back, and keep it all on GitHub.",
              sections: [
                ("Versions and branches", [
                    "In the score editor, tap History. Save Version keeps a snapshot you can go back to. Saving in the editor also records one. New Branch starts a separate line of edits, from now or from any earlier version, so you can try something without touching the main score.",
                    "Roll Back to This Version restores an earlier snapshot as a new version, so nothing is lost and you can undo the roll back. Switching branches first saves your unsaved edits.",
                    "Merge brings another branch into the current one, bar by bar. A bar changed on only one branch comes across; a bar changed on both clashes, and you choose to keep yours or take theirs. Bars are matched by number, so a bar added or removed early on one branch can make the rest show as clashes."]),
                ("Spin Off", [
                    "Spin Off as New Score turns any version, or a branch's latest version, into a score of its own in your library with a fresh history."]),
                ("GitHub", [
                    "In History, choose Connect to a GitHub Repository and enter owner/repository. Push to GitHub sends every version and branch as a real Git commit and branch, with the score as one MusicXML file. Pull from GitHub brings in versions made elsewhere.",
                    "It needs a GitHub token with read and write access to the repository's contents. Add it in Tracks from GitHub, under Access Token. It is kept in your Keychain.",
                    "A branch that has gone separate ways on GitHub arrives as name-github, so you can merge it. PDF scores have no history; editing a PDF saves a separate copy."])]),
        Topic(id: "Scales & Arpeggios", symbol: "pianokeys",
              intro: "Practice material made on demand.",
              sections: [
                ("Making a scale", [
                    "Choose Scales & Arpeggios on the home screen, pick the kind (major, minor, blues, arpeggios and more) and a key. A score is created for it and added to the library, ready to play, transpose and slow down."])]),
        Topic(id: "Annotating", symbol: "pencil.tip.crop.circle",
              intro: "Mark up the page like a paper part.",
              sections: [
                ("Drawing on the page", [
                    "Turn on Annotate in the toolbar and draw with Apple Pencil using the tool palette: pens, markers, pencil, colours and an eraser. Ink is saved with the score and shows while you play.",
                    "Each zoom size keeps its own drawing so it stays lined up with the music.",
                    "Export as PDF and Print include your ink for the key and zoom you are viewing."])]),
        Topic(id: "Keyboard Shortcuts", symbol: "keyboard",
              intro: "On a Mac nearly everything has a keyboard shortcut, shown in the Playback, Score and View menus. On an iPad with a keyboard, hold the Command key to see them. Every shortcut can be changed.",
              sections: [
                ("Changing a shortcut", [
                    "Open Settings ▸ Keyboard Shortcuts. Click a shortcut, then press the keys you want to use instead. Delete takes the shortcut away, and Escape leaves it as it was. A shortcut that is already in use moves to the action you give it to, and the page says so. The arrow next to a shortcut puts it back, and Reset All to Defaults puts them all back.",
                    "Single keys (like the space bar) only work when you are not typing in a box."]),
                ("The shortcuts at the start", Self.shortcutLines)]),
        Topic(id: "Settings & Accessibility", symbol: "gearshape",
              intro: "Settings has the choices that apply everywhere.",
              sections: [
                ("Look and feel", [
                    "Appearance is light, dark or follow the system. Highlight Colour chooses the colour that lights up playing notes; the toolbar uses your accent colour. Advanced mode has Customise Every Colour.",
                    "Zoom, dark sheet music, follow playback and the three highlights have defaults here, which any score can override."]),
                ("App icon", [
                    "Settings has an App Icon grid: the original, paper, midnight, brass, sunset and forest looks, the Union Flag, Pride and Trans Pride, and one for each instrument (piano, organ, acoustic guitar, bass, flute, clarinet, alto and tenor saxophone, trumpet). Tap one and iPadOS switches the icon and tells you so.",
                    "Every icon comes in light, dark and tinted versions, so it follows your Home Screen style. A Mac keeps one Dock icon, so the grid is only on iPad."]),
                ("Surfaces", [
                    "The paper, desk, buttons and control panels are drawn as real materials. Under Surfaces you can turn Paper Grain, Page Shadow and Curl, Desk Leather, Leather Buttons and Brushed Metal up or down on their own (up to double), or switch Realistic Surfaces off for a flatter look. High Contrast turns them off as well."]),
                ("Playing", [
                    "Keep the Screen On While Playing, hide the library while playing, metronome and count-in on by default, start playing when a score opens, a default practice speed, and the default instrument."]),
                ("Accessibility", [
                    "App Text Size, Bold Text, High Contrast, Larger Playback Controls and Reduce Motion.",
                    "Flash on the Beat and Tap on the Beat (haptics) make the pulse visible and tangible. Announce Bars with VoiceOver reads the bar number as it goes by.",
                    "Controls have VoiceOver labels and hints."])]),
        Topic(id: "Troubleshooting", symbol: "wrench.and.screwdriver",
              intro: "If something is not right, check here first.",
              sections: [
                ("Common questions", [
                    "A PDF plays the wrong number of beats: set Crotchet Beats per Bar in the Inspector, or answer the metre question the first time it opens.",
                    "Wait for Me or the Tuner says it can't hear me: allow the microphone in the device's Settings ▸ Privacy ▸ Microphone, then raise Microphone Sensitivity in Settings ▸ Listening. Play one note at a time and keep other sound down. If it still hears the wrong octave, try Accept Any Octave.",
                    "Notes in a PDF look wrongly read: only printed notation can be read, and scans need to be straight and clear. For a scan the app cannot read well, import a MusicXML file instead; many are free online.",
                    "A backing track starts late or early: drag the track marker, or use Delay Start. Use Match Key & Tempo to Track to listen again.",
                    "Band-in-a-Box files cannot be read (a closed format). In Band-in-a-Box, save as MusicXML for the notation and as audio for the backing.",
                    "Import Score does nothing or shows a file greyed out: choose All Files in the Files browser, or drag the file onto the window.",
                    "Jazz tunes need the internet the first time you add them.",
                    "An overfull bar in the editor: turn Free Editing off, or delete a note and the editor will tidy the bar."])]),
    ]

    var body: some View {
        NavigationStack {
            List(Self.topics) { topic in
                NavigationLink {
                    topicPage(topic)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(topic.title)).font(.headline)
                            Text(LocalizedStringKey(topic.intro)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    } icon: { Image(systemName: topic.symbol).foregroundStyle(Theme.accent).frame(width: 28) }
                }
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func topicPage(_ topic: Topic) -> some View {
        List {
            Section { Text(LocalizedStringKey(topic.intro)).font(.callout) }
            ForEach(topic.sections, id: \.title) { section in
                Section(LocalizedStringKey(section.title)) {
                    ForEach(section.body, id: \.self) { Text(LocalizedStringKey($0)).font(.callout).padding(.vertical, 2) }
                }
            }
        }
        .navigationTitle(LocalizedStringKey(topic.title))
        .navigationBarTitleDisplayMode(.inline)
    }
}
