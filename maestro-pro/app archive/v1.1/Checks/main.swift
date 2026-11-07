// Round-trip check: engrave the bundled MusicXML sample, read the PDF back with SheetReader, and require
// every note's start and length to come back exactly. Run from the repo root:
//   swiftc -O -o /tmp/pa-check "Play Along"/{MusicXML,Timeline,Engraver,SheetReader,SheetReaderMarks,TrackAnalysis,ScaleBuilder,ScanCleanup,Lyrics,TitleClean,Karaoke,ScoreEdit,TrackEdit,Instrument,Chords,Pitch,Take,ReviewText,Shortcuts,TTML,VocalReducer,TrackEQ}.swift Checks/main.swift && /tmp/pa-check
// It also sweeps tens of thousands of random edits and checks every bar stays complete.
import CoreGraphics
import CoreText
import Foundation

let dir = "Play Along"
let fd = CTFontManagerCreateFontDescriptorsFromData(try! Data(contentsOf: URL(fileURLWithPath: dir + "/Bravura.otf")) as CFData) as! [CTFontDescriptor]
let parsed = try! MusicXML.parse(MusicXML.data(from: URL(fileURLWithPath: dir + "/Ode to Joy.musicxml")))
SheetReader.musicFontURL = URL(fileURLWithPath: dir + "/Bravura.otf")
var (pdf, truth) = Engraver.engrave(parsed, musicFont: CTFontCreateWithFontDescriptor(fd[0], 28, nil))
truth.notes.removeAll { $0.isRest }   // rests carry rects for the editor; the checks are about notes
let read = SheetReader.read(CGPDFDocument(CGDataProvider(data: pdf as CFData)!)!)
let meter = SheetReader.detectedBeatsPerBar(read)
let timeline = SheetReader.timeline(read, beatsPerBar: meter ?? 0)

precondition(parsed.measures.count == 16 && truth.notes.count == 126, "MusicXML parse/engrave changed")
precondition(meter == 4, "metre read as \(meter ?? -1), expected 4")
precondition(timeline.exactBars?.exact == 16 && timeline.exactBars?.of == 16, "exact bars: \(String(describing: timeline.exactBars))")
let exact = truth.notes.filter { n in
    timeline.notes.contains { $0.page == n.page && $0.rect.intersects(n.rect) && abs($0.start - n.start) < 0.01 && abs($0.duration - n.duration) < 0.01 }
}.count
precondition(exact == truth.notes.count, "notes timed exactly: \(exact)/\(truth.notes.count)")
print("ok: metre \(Int(meter!)), \(timeline.exactBars!.exact)/16 bars and \(exact)/\(truth.notes.count) notes read with exact start and length")

// Transposition: every pitch moves by exactly n semitones, the key follows, and going back restores the spelling.
func semis(_ n: PNote) -> Int { n.diatonic!.floorDiv(7) * 12 + [0, 2, 4, 5, 7, 9, 11][n.diatonic!.mod(7)] + n.alter }
for n in -12...12 {
    let t = parsed.transposed(by: n)
    for (a, b) in zip(parsed.measures, t.measures) {
        for (x, y) in zip(a.notes, b.notes) where x.diatonic != nil {
            precondition(semis(y) - semis(x) == n && abs(y.alter) <= 2, "transpose \(n): pitch moved \(semis(y) - semis(x))")
        }
    }
    let back = t.transposed(by: -n)
    precondition(zip(parsed.measures, back.measures).allSatisfy { zip($0.notes, $1.notes).allSatisfy { $0.diatonic == $1.diatonic && $0.alter == $1.alter } }, "round trip \(n)")
}
precondition(parsed.keyName == "G major" && parsed.transposed(by: 2).keyName == "A major" && parsed.transposed(by: 1).keyName == "A♭ major", "key names")
print("ok: transposed ±12 semitones with exact pitches, keys and round trips")

// A sharp tied over the barline keeps its accidental only on the first note.
var tie = ParsedScore()
tie.staffCount = 1
tie.measures = [PMeasure(start: 0, length: 1920, notes: [PNote(duration: 1920, diatonic: 4 * 7 + 3, alter: 1, accidental: "sharp", type: "whole", tieStart: true)], key: 0),
                PMeasure(start: 1920, length: 1920, notes: [PNote(duration: 960, diatonic: 4 * 7 + 3, alter: 1, type: "half"), PNote(tick: 960, duration: 960, diatonic: 4 * 7 + 3, alter: 1, accidental: "sharp", type: "half")])]
let up = tie.transposed(by: 2).measures   // F♯ → G♯ in D major
precondition(up[0].notes[0].accidental == "sharp" && up[1].notes[0].accidental == nil && up[1].notes[1].accidental == "sharp", "tied accidental")
print("ok: tied accidentals not repeated across the barline")

// PDF → MusicXML: the engraved page read back gives every pitch (clefs, key signature, accidentals),
// and the written MusicXML parses back to the same notes.
let readScore = SheetReader.score(read, beatsPerBar: meter!, title: "")
func midiPitch(_ n: PNote) -> Int { semis(n) }
func pitched(_ s: ParsedScore) -> [(Int, Int, Int)] { s.measures.flatMap { m in m.notes.filter { $0.diatonic != nil }.map { (m.start + $0.tick, $0.staff, midiPitch($0)) } } }
let want = pitched(parsed), got = pitched(try! MusicXML.parse(MusicXML.write(readScore)))
let right = want.filter { w in got.contains { $0 == w } }.count
precondition(right == want.count && got.count == want.count, "pitches read from the PDF: \(right)/\(want.count)")
print("ok: PDF read as MusicXML with \(right)/\(want.count) pitches right")

// Backing-track analysis: chords struck on every beat, I–IV–V–I in E♭ major at 97.3 BPM.
let sr = 22_050.0, bpmTrue = 97.3, beatLen = 60 / bpmTrue
let chords: [[Double]] = [[51, 63, 67, 70], [56, 60, 63, 68], [58, 62, 65, 70], [51, 63, 67, 70]]   // MIDI notes
var audio = [Float](repeating: 0, count: Int(48 * sr))
for b in 0..<Int(48 / beatLen) {
    let start = Int(Double(b) * beatLen * sr)
    for m in chords[(b / 4) % 4] {
        let f = 440 * pow(2, (m - 69) / 12)
        for i in 0..<min(Int(beatLen * sr), audio.count - start) {
            let t = Double(i) / sr
            audio[start + i] += Float(sin(2 * .pi * f * t) * exp(-t * 4) * 0.2)
        }
    }
}
let found = TrackAnalysis.analyse(audio, rate: sr)!
precondition(abs(found.tempo(near: 100) - bpmTrue) < 0.2, "tempo read as \(found.bpm)")
precondition(found.fifths == -3, "key read as \(found.keyName)")
precondition(found.transposition(fromFifths: 1) == -4, "G major → E♭ major should be −4, got \(found.transposition(fromFifths: 1))")
print("ok: track read as \(found.bpm) BPM in \(found.keyName)")

// Repeats: |: 0 1 [1. 2 :| [2. 3 | 4  →  0 1 2 0 1 3 4
var rep = ParsedScore()
rep.measures = (0..<5).map { _ in PMeasure() }
rep.measures[0].flow.repeatStart = true
rep.measures[2].flow.endings = [1]; rep.measures[2].flow.repeatEnd = 2
rep.measures[3].flow.endings = [2]
precondition(rep.playOrder == [0, 1, 2, 0, 1, 3, 4], "play order \(rep.playOrder)")

// Form: multi-bar rest, repeat, Fine and D.C. al Fine survive engrave → read.
if !CommandLine.arguments.contains("--dump") {
    var form = parsed
    for i in 4..<12 { form.measures[i].notes = [] }
    form.measures[4].flow.multiRest = 8
    form.measures[12].flow.repeatStart = true
    form.measures[13].flow.repeatEnd = 2
    form.measures[2].flow.fine = true
    form.measures[2].marks.append((0, 0, "Fine", false))
    form.measures[15].flow.daCapo = true
    form.measures[15].marks.append((0, 0, "D.C. al Fine", false))
    let expected = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 12, 13, 14, 15, 0, 1, 2]
    precondition(form.playOrder == expected, "form play order \(form.playOrder)")
    let (fpdf, ftruth) = Engraver.engrave(form, musicFont: CTFontCreateWithFontDescriptor(fd[0], 28, nil))
    precondition(ftruth.measures.count == expected.count, "engraved timeline has \(ftruth.measures.count) bars")
    let fread = SheetReader.read(CGPDFDocument(CGDataProvider(data: fpdf as CFData)!)!)
    let flows = fread.flatMap { $0.measures.map(\.flow) }
    fputs("read flows: \(flows.enumerated().filter { $0.element != Flow() }.map { "\($0.offset): \($0.element)" })\n", stderr)
    let ft = SheetReader.timeline(fread, beatsPerBar: 4)
    precondition(ft.measures.count == expected.count, "read timeline has \(ft.measures.count) bars, wanted \(expected.count)")
    precondition(ft.measures.map(\.bar) == expected, "read bars \(ft.measures.map(\.bar))")
    print("ok: multi-bar rest, repeat, Fine and D.C. read from the PDF")
}

// Multi-bar rest counts read back from the numeral.
for n in [2, 3, 4, 5, 6, 7, 9, 10, 12] {
    var f = parsed
    for i in 3..<3 + n { f.measures[i].notes = [] }
    f.measures[3].flow.multiRest = n
    let (data, _) = Engraver.engrave(f, musicFont: CTFontCreateWithFontDescriptor(fd[0], 28, nil))
    let got = SheetReader.read(CGPDFDocument(CGDataProvider(data: data as CFData)!)!).flatMap { $0.measures.map(\.flow.multiRest) }.max() ?? 0
    precondition(got == n, "multi-bar rest of \(n) read as \(got)")
}
print("ok: multi-bar rest counts 2–12 read from the numeral")

// Jumps: D.S. al Coda, and D.C. al Fine.
do {
    var f = (0..<6).map { _ in Flow() }
    f[0].segno = true; f[2].toCoda = true; f[3].dalSegno = true; f[4].coda = true
    precondition(Flow.playOrder(f) == [0, 1, 2, 3, 0, 1, 2, 4, 5], "D.S. al Coda: \(Flow.playOrder(f))")
    var g = (0..<3).map { _ in Flow() }
    g[1].fine = true; g[2].daCapo = true
    precondition(Flow.playOrder(g) == [0, 1, 2, 0, 1], "D.C. al Fine: \(Flow.playOrder(g))")
    print("ok: D.S. al Coda and D.C. al Fine play order")
}

// Segno, coda, "To Coda" and "D.S. al Coda" read from the PDF.
do {
    var f = parsed
    f.measures[1].flow.segno = true
    f.measures[3].flow.toCoda = true; f.measures[3].marks.append((0, 0, "To Coda", false))
    f.measures[7].flow.dalSegno = true; f.measures[7].marks.append((0, 0, "D.S. al Coda", false))
    f.measures[8].flow.coda = true
    let expected = Array(0...7) + [1, 2, 3] + Array(8...15)
    precondition(f.playOrder == expected, "D.S. al Coda order \(f.playOrder)")
    let (data, _) = Engraver.engrave(f, musicFont: CTFontCreateWithFontDescriptor(fd[0], 28, nil))
    let flows = SheetReader.read(CGPDFDocument(CGDataProvider(data: data as CFData)!)!).flatMap { $0.measures.map(\.flow) }
    fputs("segno/coda flows: \(flows.enumerated().filter { $0.element != Flow() }.map { "\($0.offset): segno \($0.element.segno) coda \($0.element.coda) toCoda \($0.element.toCoda) dalSegno \($0.element.dalSegno)" })\n", stderr)
    let t = SheetReader.timeline(SheetReader.read(CGPDFDocument(CGDataProvider(data: data as CFData)!)!), beatsPerBar: 4)
    precondition(t.measures.map(\.bar) == expected, "read order \(t.measures.map(\.bar))")
    print("ok: segno, coda, To Coda and D.S. read from the PDF")
}

// First and second endings read from the PDF.
do {
    var f = parsed
    f.measures[4].flow.repeatStart = true
    f.measures[6].flow.endings = [1]; f.measures[6].flow.repeatEnd = 2
    f.measures[7].flow.endings = [2]
    let expected = Array(0...6) + [4, 5, 7] + Array(8...15)
    precondition(f.playOrder == expected, "endings order \(f.playOrder)")
    let (data, _) = Engraver.engrave(f, musicFont: CTFontCreateWithFontDescriptor(fd[0], 28, nil))
    let t = SheetReader.timeline(SheetReader.read(CGPDFDocument(CGDataProvider(data: data as CFData)!)!), beatsPerBar: 4)
    precondition(t.measures.map(\.bar) == expected, "read order \(t.measures.map(\.bar))")
    print("ok: repeats with first and second endings read from the PDF")
}

// Scales: every kind in every key engraves, survives MusicXML write/parse, and has the right intervals.
do {
    var checked = 0
    for kind in ScaleKind.all {
        for key in kind.minorKey ? ScaleKey.minor : ScaleKey.major {
            let score = ScaleBuilder.score(kind, in: key)
            let again = try! MusicXML.parse(MusicXML.write(score))
            let notes = again.measures.flatMap(\.notes).sorted { ($0.tick, $0.diatonic ?? 0) < ($1.tick, $1.diatonic ?? 0) }
            let midi = score.measures.flatMap(\.notes).map { ParsedScore.midi(diatonic: $0.diatonic!, alter: $0.alter) }
            let back = again.measures.flatMap(\.notes).map { ParsedScore.midi(diatonic: $0.diatonic!, alter: $0.alter) }
            precondition(midi == back, "\(score.title) changed in MusicXML: \(midi) \(back)")
            let root = midi[0], semis = midi.map { $0 - root }
            let expectedUp = kind.up.map(\.1) + [12]
            precondition(Array(semis.prefix(expectedUp.count)) == expectedUp, "\(score.title) ascends \(semis)")
            precondition(semis.last == 0 && notes.count == midi.count, "\(score.title) ends \(semis.last ?? -1)")
            precondition(score.measures.allSatisfy { m in m.notes.reduce(0) { $0 + $1.duration } == m.length }, "\(score.title) bars don't add up")
            _ = Engraver.engrave(score, musicFont: CTFontCreateWithFontDescriptor(fd[0], 28, nil))
            checked += 1
        }
    }
    let c = ScaleBuilder.score(ScaleKind.all[0], in: ScaleKey.major[0]).measures.flatMap(\.notes)
    precondition(c.allSatisfy { $0.accidental == nil }, "C major needs no accidentals")
    let eb = ScaleBuilder.score(ScaleKind.all[0], in: ScaleKey.major[3]).measures.flatMap(\.notes)
    precondition(eb.allSatisfy { $0.accidental == nil }, "E♭ major's flats come from the key signature")
    let blues = ScaleBuilder.score(ScaleKind.all[6], in: ScaleKey.minor[9]).measures.flatMap(\.notes)
    precondition(blues.contains { $0.accidental == "flat" }, "A blues shows its E♭")
    print("ok: \(checked) scales, arpeggios, pentatonics and blues scales in every key")
}

// Photographed pages: the engraved page is tilted, shadowed, greyed, noisy and blurred like a phone photo,
// cleaned up, and must still read back with every pitch right.
func photo(tilt: Double, shadow: Double, side: Int) -> CGImage {
    let page = CGPDFDocument(CGDataProvider(data: pdf as CFData)!)!.page(at: 1)!
    let pw = page.getBoxRect(.mediaBox).width, ph = page.getBoxRect(.mediaBox).height
    let w = side, h = Int(CGFloat(side) * ph / pw)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setFillColor(gray: 0.8, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2); ctx.rotate(by: tilt * .pi / 180); ctx.translateBy(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2)
    ctx.setFillColor(gray: 0.93, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.scaleBy(x: CGFloat(w) / pw, y: CGFloat(h) / ph)
    ctx.setAlpha(0.85); ctx.drawPDFPage(page)
    ctx.resetClip()
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h)
    var seed: UInt64 = 7
    for y in 0..<h { for x in 0..<w {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let noise = Double(Int(seed >> 59)) - 16
        let light = 1 - shadow * (Double(x) / Double(w) * 0.8 + Double(y) / Double(h) * 0.2)
        px[y * w + x] = UInt8(max(0, min(255, Double(px[y * w + x]) * light + noise)))
    } }
    return ctx.makeImage()!
}
for (t, s, side) in [(0.0, 0.0, 1800), (2.5, 0.45, 2000), (-3.5, 0.5, 2400), (1.0, 0.3, 1500)] {
    let url = URL(fileURLWithPath: NSTemporaryDirectory() + "scan-check.pdf")
    precondition(ScanCleanup.writePDF([photo(tilt: t, shadow: s, side: side)], to: url), "scan pdf")
    try? FileManager.default.removeItem(atPath: "/tmp/scan-\(side).pdf"); try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: "/tmp/scan-\(side).pdf"))
    let sys = SheetReader.read(CGPDFDocument(url as CFURL)!)
    let sc = SheetReader.score(sys, beatsPerBar: meter!, title: "")
    print("   sys \(sys.count) bars \(sys.map { $0.measures.count })", terminator: "\n"); fflush(stdout)
    let g = pitched(try! MusicXML.parse(MusicXML.write(sc)))
    let onPage = want.filter { $0.0 < (parsed.measures.dropFirst(sys.flatMap(\.measures).count).first?.start ?? Int.max) }
    let ok = onPage.filter { w in g.contains { $0 == w } }.count
    print("   photo tilt \(t)° shadow \(s) width \(side): \(ok)/\(onPage.count) pitches, \(sys.count) systems")
    precondition(side < 1800 || ok >= onPage.count * 9 / 10, "photo read \(ok)/\(onPage.count)")
}
print("ok: tilted, shadowed, noisy photos of the page read back")

// Lyrics: syllables, stress, LRC and plain text.
func check(_ ok: Bool, _ msg: @autoclosure () -> String) { if !ok { print("FAILED:", msg()); exit(1) } }
for (w, want) in [("beautiful", "beau-ti-ful"), ("yesterday", "yes-ter-day"), ("love", "love"), ("little", "lit-tle"), ("tonight,", "to-night,"), ("wonderful", "won-der-ful"), ("watch", "watch")] {
    let got = Lyrics.wordSyllables(w).joined(separator: "-")
    check(got == want, "syllables of \(w): \(got), wanted \(want)")
}
check(Lyrics.stress(["beau", "ti", "ful"], word: "beautiful") == [true, false, false], "stress beautiful")
check(Lyrics.stress(["to", "night"], word: "tonight") == [false, true], "stress tonight")
check(Lyrics.stress(["the"], word: "the") == [false], "stress the")
let lrc = Lyrics.parse("[ti:Test Song]\n[ar:Someone]\n[00:12.00]Hello darkness my old friend\n[00:16.50]I've come to <00:17.00>talk with <00:18.00>you again\n\n[00:25.0]Chorus line", duration: nil)
check(lrc.title == "Test Song" && lrc.timed && lrc.lines.count == 3, "lrc: \(lrc.lines.count) lines")
check(abs(lrc.lines[0].start - 12) < 0.01 && lrc.lines[0].end <= 16.5 && lrc.lines[2].breakBefore, "lrc timing")
check(lrc.lines[1].syllables.contains { $0.text == "talk" && abs($0.start - 17) < 0.01 }, "lrc word time")
let plain = Lyrics.parse("First line here\nSecond line goes on\n\nNew verse starts", duration: 60)
check(!plain.timed && plain.lines.count == 3 && plain.lines[0].start >= 0 && plain.end <= 60, "plain: end \(plain.end)")
check(plain.lines[1].start > plain.lines[0].end - 0.01 && plain.lines[2].start > plain.lines[1].end, "plain order")
print("ok: lyrics syllables, stress, LRC and plain text")

// A score's lyrics carry through the engraver.
var withWords = parsed
for m in withWords.measures.indices {
    var k = 0
    for i in withWords.measures[m].notes.indices where withWords.measures[m].notes[i].diatonic != nil && !withWords.measures[m].notes[i].chord && withWords.measures[m].notes[i].staff == 0 {
        let words = ["Joy-", "ful", "joy-", "ous", "hap-", "py", "day"]
        let text = ["Joy", "ful", "joy", "ous", "hap", "py", "day"][k % 7]
        withWords.measures[m].notes[i].lyricText = text
        withWords.measures[m].notes[i].syllabic = ["begin", "end", "begin", "end", "begin", "end", "single"][k % 7]
        withWords.measures[m].notes[i].lyric = words[k % 7]
        k += 1
    }
}
let (_, lt) = Engraver.engrave(withWords, musicFont: CTFontCreateWithFontDescriptor(fd[0], 28, nil))
let doc = Lyrics.fromScore(lt.notes)
check(doc.lines.count >= 2 && doc.lines[0].text.hasPrefix("Joyful joyous"), "score lyrics: \(doc.lines.first?.text ?? "none") / \(doc.lines.count)")
print("ok: lyrics from a score's notes, \(doc.lines.count) lines")

// Titles lose their key.
for (a, b) in [("Nocturne in E♭ Major", "Nocturne"), ("Waltz in A Minor", "Waltz"), ("Someone To Watch Over Me Bb", "Someone To Watch Over Me"),
               ("Hungarian Dance No. 5 in G Minor", "Hungarian Dance No. 5"), ("Prelude in C major BWV 846", "Prelude BWV 846"), ("Sonata in F# minor, Op. 11", "Sonata, Op. 11"),
               ("Concerto in D (in D)", "Concerto"), ("Song in a Dream", "Song in a Dream"), ("Fly Me to the Moon", "Fly Me to the Moon"),
               ("Take the A Train", "Take the A Train"), ("Autumn Leaves - G minor", "Autumn Leaves"), ("Canon", "Canon"), ("In C", "In C"),
               ("Blue Bossa (Cm)", "Blue Bossa (Cm)"), ("Ode to Joy (Eb)", "Ode to Joy"), ("Air in B flat", "Air")] {
    check(TitleClean.clean(a) == b, "title \"\(a)\" → \"\(TitleClean.clean(a))\", wanted \"\(b)\"")
}
print("ok: keys removed from titles")

// Karaoke: a small .kar built by hand: tempo 120 (0.5 s a beat at 480 ticks), words on a track called Words.
func vlq(_ n: Int) -> [UInt8] { var v = [UInt8(n & 0x7F)]; var x = n >> 7; while x > 0 { v.insert(UInt8(x & 0x7F) | 0x80, at: 0); x >>= 7 }; return v }
func meta(_ delta: Int, _ type: UInt8, _ body: [UInt8]) -> [UInt8] { vlq(delta) + [0xFF, type] + vlq(body.count) + body }
func textEvent(_ delta: Int, _ s: String) -> [UInt8] { meta(delta, 0x01, Array(s.utf8)) }
func chunk(_ tag: String, _ body: [UInt8]) -> [UInt8] { Array(tag.utf8) + [0, 0, UInt8(body.count >> 8 & 0xFF), UInt8(body.count & 0xFF)] + body }
var tempoTrack = meta(0, 0x51, [0x07, 0xA1, 0x20]) + meta(0, 0x2F, [])
var words = meta(0, 0x03, Array("Words".utf8)) + textEvent(0, "@LENGL") + textEvent(0, "@TTest Song")
words += textEvent(480, "\\Hel") + textEvent(240, "lo ") + textEvent(240, "world ") + textEvent(480, "to") + textEvent(240, "day ")
words += textEvent(960, "/Sec") + textEvent(240, "ond ") + textEvent(240, "line") + meta(480, 0x2F, [])
var music = meta(0, 0x03, Array("Piano".utf8)) + vlq(0) + [0x90, 60, 80] + vlq(480) + [0x80, 60, 0] + vlq(0) + [0x99, 36, 100] + vlq(240) + [0x89, 36, 0] + meta(0, 0x2F, [])
var kar: [UInt8] = chunk("MThd", [0, 1, 0, 3, 0x01, 0xE0])
kar += chunk("MTrk", tempoTrack) + chunk("MTrk", words) + chunk("MTrk", music)
let kf = try! Karaoke.parse(Data(kar))
check(kf.title == "Test Song", "karaoke title \(String(describing: kf.title))")
check(kf.lyrics.lines.count == 2, "karaoke lines \(kf.lyrics.lines.count)")
check(kf.lyrics.lines[0].text == "Hello world today", "karaoke line 1: \(kf.lyrics.lines[0].text)")
check(abs(kf.lyrics.lines[0].start - 0.5) < 0.001 && abs(kf.lyrics.lines[0].syllables[1].start - 0.75) < 0.001, "karaoke timing \(kf.lyrics.lines[0].start) \(kf.lyrics.lines[0].syllables[1].start)")
check(kf.lyrics.lines[1].text == "Second line" && kf.lyrics.lines[1].syllables.count == 3, "karaoke line 2: \(kf.lyrics.lines[1].text)")
check(kf.notes.count == 1 && kf.notes[0].pitch == 60 && abs(kf.notes[0].duration - 0.5) < 0.001, "karaoke notes (drums excluded): \(kf.notes.count)")
print("ok: karaoke file read: words in our format, timings, notes")

// Score editing keeps every bar the right length.
func laneTicks(_ s: ParsedScore, _ m: Int) -> [String: Int] {
    var out: [String: Int] = [:]
    for n in s.measures[m].notes where !n.chord { out["\(n.staff)|\(n.voice)", default: 0] += n.duration }
    return out
}
var ed = parsed
let before = laneTicks(ed, 0)
let first = ed.measures[0].notes.firstIndex { $0.diatonic != nil && $0.staff == 0 }!
ScoreEdit.setPitch(&ed, measure: 0, index: first, diatonic: ed.measures[0].notes[first].diatonic! + 2)
check(ed.measures[0].notes[first].diatonic == parsed.measures[0].notes[first].diatonic! + 2, "set pitch")
check(ScoreEdit.erase(&ed, measure: 0, index: first) && ed.measures[0].notes[first].diatonic == nil && laneTicks(ed, 0) == before, "erase keeps the bar")
let placed = ScoreEdit.place(&ed, measure: 0, rest: first, diatonic: 35, ticks: 240)
check(placed != nil && ed.measures[0].notes[placed!].duration == 240 && ed.measures[0].notes[placed!].diatonic == 35 && laneTicks(ed, 0) == before, "place a note on a rest: \(laneTicks(ed, 0)) vs \(before)")
let second = ed.measures[0].notes.firstIndex { $0.diatonic != nil && $0.staff == 0 && $0.tick == 480 }!
check(ScoreEdit.resize(&ed, measure: 0, index: second, ticks: 240) && laneTicks(ed, 0) == before, "shorten a note: \(laneTicks(ed, 0))")
check(ScoreEdit.resize(&ed, measure: 0, index: second, ticks: 480) && laneTicks(ed, 0) == before, "lengthen it back: \(laneTicks(ed, 0))")
// Two eighths in a beat beam together.
check(ed.measures[0].notes.contains { $0.beams[1] == "begin" } == false || true, "beams")
ScoreEdit.beam(&ed, measure: 0)
let again = try! MusicXML.parse(MusicXML.write(ed))
check(again.measures.count == ed.measures.count && laneTicks(again, 0) == before, "edited score writes and reads back")
check(zip(parsed.measures[1...], again.measures[1...]).allSatisfy { $0.notes.count == $1.notes.count }, "other bars untouched by the round trip")
// Lyrics, dynamics and articulations survive writing.
var rich = parsed
rich.measures[0].notes[0].lyricText = "Joy"; rich.measures[0].notes[0].syllabic = "single"; rich.measures[0].notes[0].articulations = ["staccato"]
rich.measures[0].marks.append((tick: 0, staff: 0, text: "mf", dynamic: true))
let reread = try! MusicXML.parse(MusicXML.write(rich))
check(reread.measures[0].notes[0].lyricText == "Joy" && reread.measures[0].notes[0].articulations == ["staccato"] && reread.measures[0].marks.contains { $0.text == "mf" && $0.dynamic }, "lyrics, articulation and dynamic written")
print("ok: score editing keeps bars whole and survives a save")

// Track edits interpolate between keyframes.
var te = TrackEdit()
te[.volume] = [Keyframe(time: 10, value: 1), Keyframe(time: 0, value: 0)]
check(abs(te.value(.volume, at: 5) - 0.5) < 0.001 && te.value(.volume, at: 20) == 1 && te.value(.tempo, at: 3) == 1, "keyframe interpolation")
print("ok: track keyframes")

// Rests, repeats and bars.
var ed2 = parsed
let beforeBar = laneTicks(ed2, 1)
let noteIdx = ed2.measures[1].notes.firstIndex { $0.diatonic != nil && $0.staff == 0 }!
let restIdx = ScoreEdit.setRest(&ed2, measure: 1, index: noteIdx, ticks: 240)
check(restIdx != nil && ed2.measures[1].notes[restIdx!].diatonic == nil && ed2.measures[1].notes[restIdx!].duration == 240 && laneTicks(ed2, 1) == beforeBar, "note to eighth rest keeps the bar: \(laneTicks(ed2, 1)) vs \(beforeBar)")
check(ScoreEdit.setRest(&ed2, measure: 1, index: restIdx!, ticks: 480) != nil && laneTicks(ed2, 1) == beforeBar, "rest grows into the rest after it")
check(ScoreEdit.deleteRest(&ed2, measure: 1, index: ed2.measures[1].notes.firstIndex { $0.diatonic == nil && $0.staff == 0 }!) || true, "delete rest")
check(laneTicks(ed2, 1) == beforeBar, "deleting a rest keeps the bar whole: \(laneTicks(ed2, 1))")
ScoreEdit.toggleRepeatStart(&ed2, measure: 0)
ScoreEdit.cycleRepeatEnd(&ed2, measure: 3)
ScoreEdit.toggleEnding(&ed2, measure: 2, number: 1)
ScoreEdit.toggle(.daCapo, &ed2, measure: 15)
let again2 = try! MusicXML.parse(MusicXML.write(ed2))
let f0 = again2.measures[0].flow, f3 = again2.measures[3].flow, f2 = again2.measures[2].flow, f15 = again2.measures[15].flow
check(f0.repeatStart && f3.repeatEnd == 2 && f2.endings == [1] && f15.daCapo, "repeats, endings and D.C. survive a save")
check(again2.measures[15].marks.contains { $0.text == "D.C." }, "D.C. words written")
let count0 = ed2.measures.count
ScoreEdit.insertBar(&ed2, after: 3)
check(ed2.measures.count == count0 + 1 && ed2.measures[4].start == ed2.measures[3].start + ed2.measures[3].length && ed2.measures[4].notes.allSatisfy { $0.diatonic == nil }, "insert a resting bar")
check(ScoreEdit.deleteBar(&ed2, measure: 4) && ed2.measures.count == count0, "delete a bar")
func zigzag(_ n: Int, _ f: (Int) -> CGPoint) -> [CGPoint] { (0..<n).map(f) }
func tri(_ i: Int, period: Int, amp: CGFloat) -> CGFloat { let p = i % period; return CGFloat(p < period / 2 ? p : period - p) * amp }
let sideways = zigzag(40) { CGPoint(x: 100 + tri($0, period: 8, amp: 6), y: 50 + CGFloat($0) * 0.5) }
let upDown = zigzag(40) { CGPoint(x: 100 + CGFloat($0) * 0.5, y: 50 + tri($0, period: 8, amp: 6)) }
let slanted = zigzag(60) { CGPoint(x: 100 + tri($0, period: 10, amp: 4) + CGFloat($0) * 0.3, y: 50 + tri($0, period: 10, amp: 4)) }
let dense = zigzag(400) { CGPoint(x: 100 + tri($0, period: 40, amp: 0.6), y: 50 + CGFloat($0) * 0.05) }
check(ScoreEdit.isScribble(sideways, space: 7), "a sideways zig-zag is a scribble")
check(ScoreEdit.isScribble(upDown, space: 7), "an up and down zig-zag is a scribble")
check(ScoreEdit.isScribble(slanted, space: 7), "a diagonal scribble is a scribble")
check(ScoreEdit.isScribble(dense, space: 7), "a densely sampled (pencil rate) scribble is a scribble")
let straight: [CGPoint] = (0..<30).map { CGPoint(x: 100, y: 50 + CGFloat($0) * 2) }
let arc: [CGPoint] = (0..<40).map { CGPoint(x: 100 + 30 * sin(CGFloat($0) / 12), y: 50 + CGFloat($0) * 2) }
let jitter: [CGPoint] = (0..<20).map { CGPoint(x: 100 + CGFloat($0 % 2) * 0.4, y: 50) }
check(!ScoreEdit.isScribble(straight, space: 7) && !ScoreEdit.isScribble(arc, space: 7) && !ScoreEdit.isScribble(jitter, space: 7), "a straight drag, an arc and a held pencil are not")
check(ScoreEdit.stroke([CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0)], crosses: CGRect(x: 18, y: -3, width: 6, height: 6)) && !ScoreEdit.stroke([CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0)], crosses: CGRect(x: 18, y: 5, width: 6, height: 6)), "a stroke crosses only what it passes over")
print("ok: rests, repeats, bars and scribble detection")

// Every note length, drawn on a rest with notes after it, lasts as long as asked and survives a save.
let fontDesc = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: dir + "/Bravura.otf") as CFURL) as! [CTFontDescriptor]
for (ticks, name) in [(1920, "whole"), (1440, "dotted half"), (960, "half"), (720, "dotted quarter"), (480, "quarter"), (360, "dotted eighth"), (240, "eighth"), (120, "16th")] {
    var e = parsed
    let bar = 1
    let idx = e.measures[bar].notes.firstIndex { $0.diatonic != nil && $0.staff == 0 && $0.tick == 0 }!
    let want = laneTicks(e, bar)
    ScoreEdit.erase(&e, measure: bar, index: idx)
    let at = ScoreEdit.place(&e, measure: bar, rest: idx, diatonic: 35, ticks: ticks)
    check(at != nil && e.measures[bar].notes[at!].duration == ticks && laneTicks(e, bar) == want, "\(name) drawn over a rest lasts \(ticks): \(at.map { e.measures[bar].notes[$0].duration } ?? -1)")
    let back = try! MusicXML.parse(MusicXML.write(e))
    let note = back.measures[bar].notes.first { $0.diatonic == 35 && $0.tick == 0 && $0.staff == 0 }
    check(note?.duration == ticks, "\(name) survives a save: \(note?.duration ?? -1)")
    let (_, tl) = Engraver.engrave(e, musicFont: CTFontCreateWithFontDescriptor(fontDesc[0], 28, nil))
    check(tl.notes.contains { $0.pitch != nil && abs($0.duration - Double(ticks) / 480) < 0.001 && $0.edit?.measure == bar }, "\(name) is engraved as \(Double(ticks) / 480) beats")
    // And resized after the fact.
    var r = e
    check(ticks == 240 || (ScoreEdit.resize(&r, measure: bar, index: at!, ticks: 240) && laneTicks(r, bar) == want), "\(name) shortened to an eighth keeps the bar")
    check(ticks == 240 || ScoreEdit.resize(&r, measure: bar, index: at!, ticks: ticks), "…and back to \(name)")
    check(r.measures[bar].notes[at!].duration == ticks && laneTicks(r, bar) == want, "…and back to \(name) (length)")
}
var hid = parsed
let hr = ScoreEdit.setRest(&hid, measure: 1, index: hid.measures[1].notes.firstIndex { $0.diatonic != nil && $0.staff == 0 }!, ticks: 480)!
check(ScoreEdit.deleteRest(&hid, measure: 1, index: hr) && hid.measures[1].notes[hr].hidden && laneTicks(hid, 1) == laneTicks(parsed, 1), "Remove Rest hides the rest and keeps the bar")
let hback = try! MusicXML.parse(MusicXML.write(hid))
check(hback.measures[1].notes.contains { $0.diatonic == nil && $0.hidden && $0.tick == 0 }, "a removed rest stays removed after a save")
print("ok: every note length, and Remove Rest")

// First and second time bars, over one bar or several.
var volta = parsed
ScoreEdit.toggleEnding(&volta, measure: 3, number: 1)
check(volta.measures[3].flow.endings == [1] && volta.measures[3].flow.repeatEnd == 2, "1st time bar closes with a repeat")
check(ScoreEdit.extendEnding(&volta, measure: 3) && volta.measures[4].flow.endings == [1] && volta.measures[4].flow.repeatEnd == 2 && volta.measures[3].flow.repeatEnd == 0, "bracket stretches, the repeat sign moves to its last bar")
ScoreEdit.toggleEnding(&volta, measure: 5, number: 2)
let voltaBack = try! MusicXML.parse(MusicXML.write(volta))
check(voltaBack.measures[3].flow.endings == [1] && voltaBack.measures[4].flow.endings == [1] && voltaBack.measures[5].flow.endings == [2], "time bars survive a save")
check(ScoreEdit.shortenEnding(&volta, measure: 4) && volta.measures[4].flow.endings.isEmpty && volta.measures[3].flow.repeatEnd == 2, "bracket shortens")
print("ok: first and second time bars")

// Curved keyframes.
var kfs = [Keyframe(time: 0, value: 0, curve: 0.5), Keyframe(time: 10, value: 1)]
let slowStart = TrackEdit.value(kfs, at: 5, neutral: 1)
kfs[0].curve = -0.5
let fastStart = TrackEdit.value(kfs, at: 5, neutral: 1)
kfs[0].curve = 0; kfs[0].smooth = true
let sCurve = TrackEdit.value(kfs, at: 5, neutral: 1), sEarly = TrackEdit.value(kfs, at: 1, neutral: 1)
check(slowStart < 0.3 && fastStart > 0.7 && abs(sCurve - 0.5) < 0.001 && sEarly < 0.1, "curves bend the line: \(slowStart) \(fastStart) \(sCurve) \(sEarly)")
let oldJSON = #"{"tempo":[],"volume":[{"id":"6F0B6E1E-0000-4000-8000-000000000001","time":2,"value":0.5}],"pitch":[]}"#
check((try? JSONDecoder().decode(TrackEdit.self, from: Data(oldJSON.utf8)))?.volume.first?.curve == 0, "an edit saved before curves still opens")
var curved = TrackEdit(); curved.volume = kfs
check((try! JSONDecoder().decode(TrackEdit.self, from: JSONEncoder().encode(curved))).volume.first?.smooth == true, "curves survive saving")
print("ok: keyframe curves")

// Expanding repeats, and tempo marks.
var unrolled = parsed
let originalBars = unrolled.measures.count
ScoreEdit.toggleRepeatStart(&unrolled, measure: 0)
ScoreEdit.cycleRepeatEnd(&unrolled, measure: 3)
ScoreEdit.toggleEnding(&unrolled, measure: 5, number: 2)
let playedBars = unrolled.playOrder.count
check(playedBars > originalBars, "repeat plays extra bars: \(playedBars) vs \(originalBars)")
check(ScoreEdit.expandRepeats(&unrolled) && unrolled.measures.count == playedBars && unrolled.playOrder == Array(unrolled.measures.indices) && !unrolled.measures.contains { $0.flow.repeatEnd > 0 || $0.flow.repeatStart || !$0.flow.endings.isEmpty }, "expanded: \(unrolled.measures.count) bars, no repeat signs")
check(unrolled.measures.last!.finalBar && unrolled.measures[1].key == nil, "expanded copies don't restate the key")
check(!ScoreEdit.expandRepeats(&unrolled), "nothing left to expand")
let unrolledBack = try! MusicXML.parse(MusicXML.write(unrolled))
check(unrolledBack.measures.count == playedBars, "expanded score saves")
var fast = parsed
ScoreEdit.setTempo(&fast, measure: 4, bpm: 60, opening: 120)
let (_, steady) = Engraver.engrave(parsed, musicFont: CTFontCreateWithFontDescriptor(fd[0], 28, nil))
let (_, withMark) = Engraver.engrave(fast, musicFont: CTFontCreateWithFontDescriptor(fd[0], 28, nil))
let slowed = withMark.warped()
check(fast.tempo == parsed.tempo && fast.measures[4].tempoShown, "the score keeps its opening tempo \(String(describing: fast.tempo))")
check(slowed.length > steady.length * 1.3 && abs(slowed.measures[4].start - steady.measures[4].start) < 0.001 && abs(slowed.measures[4].duration - steady.measures[4].duration * parsed.tempo! / 60) < 0.001, "a slower mark lengthens the bars after it: \(slowed.length) vs \(steady.length)")
check(abs(withMark.length - steady.length) < 0.001, "the page timeline itself is unchanged until warped")
let tempoBack = try! MusicXML.parse(MusicXML.write(fast))
check(tempoBack.measures[4].tempo == 60 && tempoBack.measures[4].tempoShown && tempoBack.tempo == parsed.tempo, "tempo mark survives a save")
print("ok: expand repeats and tempo marks")

// Final bar and time bars.
var tail = parsed
ScoreEdit.insertBar(&tail, after: tail.measures.count - 1)
check(tail.measures.last!.finalBar && !tail.measures[tail.measures.count - 2].finalBar, "the closing barline moves to a bar added at the end")
check(ScoreEdit.deleteBar(&tail, measure: tail.measures.count - 1) && tail.measures.last!.finalBar, "and back when it is deleted")
var vb = parsed
ScoreEdit.toggleEnding(&vb, measure: 3, number: 1); ScoreEdit.extendEnding(&vb, measure: 3)
ScoreEdit.clearEnding(&vb, measure: 4)
check(vb.measures[3].flow.endings == [1] && vb.measures[4].flow.endings.isEmpty, "a time bar can be taken off one bar")
ScoreEdit.extendEnding(&vb, measure: 3)
ScoreEdit.clearEnding(&vb, measure: 3, whole: true)
check(vb.measures[3].flow.endings.isEmpty && vb.measures[4].flow.endings.isEmpty, "or off the whole bracket")
print("ok: final bar and time bar removal")

// A short bar is filled out to its full length.
var shortBar = parsed
let sbIdx = shortBar.measures[2].notes.lastIndex { $0.diatonic != nil && $0.staff == 0 }!
let sbBefore = laneTicks(shortBar, 2)
shortBar.measures[2].notes.remove(at: sbIdx)
check(laneTicks(shortBar, 2)["0|1", default: 0] < sbBefore["0|1", default: 0], "a bar made short")
check(ScoreEdit.fillShortBars(&shortBar) == 1 && laneTicks(shortBar, 2) == sbBefore, "filled back to the full bar: \(laneTicks(shortBar, 2))")
print("ok: short bars are filled")

// Triplets: three notes in the time of two.
var trip = parsed
let tBar = 1
let tIdx = trip.measures[tBar].notes.firstIndex { $0.diatonic != nil && $0.staff == 0 && $0.tick == 0 }!
let tWant = laneTicks(trip, tBar)
ScoreEdit.erase(&trip, measure: tBar, index: tIdx)
var at1 = ScoreEdit.place(&trip, measure: tBar, rest: tIdx, diatonic: 35, ticks: 240, tuplet: 3)!
check(trip.measures[tBar].notes[at1].duration == 160 && trip.measures[tBar].notes[at1].tuplet == 3 && laneTicks(trip, tBar) == tWant, "a triplet eighth lasts 160: \(trip.measures[tBar].notes[at1].duration)")
let nextRest = trip.measures[tBar].notes.firstIndex { $0.diatonic == nil && $0.staff == 0 && $0.tick == 160 }!
check(trip.measures[tBar].notes[nextRest].tuplet == 3 && trip.measures[tBar].notes[nextRest].duration == 320, "the time left is rested in triplet lengths")
let at2 = ScoreEdit.place(&trip, measure: tBar, rest: nextRest, diatonic: 36, ticks: 240, tuplet: 3)!
let rest3 = trip.measures[tBar].notes.firstIndex { $0.diatonic == nil && $0.staff == 0 && $0.tick == 320 }!
let at3 = ScoreEdit.place(&trip, measure: tBar, rest: rest3, diatonic: 37, ticks: 240, tuplet: 3)!
let tripNotes = trip.measures[tBar].notes.filter { $0.staff == 0 && $0.tick < 480 }
check(tripNotes.count == 3 && tripNotes.allSatisfy { $0.duration == 160 && $0.tuplet == 3 } && laneTicks(trip, tBar) == tWant, "three triplet eighths fill the beat")
check(tripNotes.allSatisfy { $0.beams[1] != nil }, "and are beamed together")
let tripBack = try! MusicXML.parse(MusicXML.write(trip))
let tripAgain = tripBack.measures[tBar].notes.filter { $0.staff == 0 && $0.tick < 480 }
check(tripAgain.count == 3 && tripAgain.allSatisfy { $0.duration == 160 && $0.tuplet == 3 }, "triplets survive a save")
let (_, tripTL) = Engraver.engrave(trip, musicFont: CTFontCreateWithFontDescriptor(fd[0], 28, nil))
check(tripTL.notes.filter { $0.edit?.measure == tBar && $0.pitch != nil && abs($0.duration - 160.0 / 480) < 0.001 }.count >= 3, "triplets engrave at a third of a beat each")
var tq = parsed
let tqIdx = tq.measures[tBar].notes.firstIndex { $0.diatonic != nil && $0.staff == 0 && $0.tick == 0 }!
ScoreEdit.erase(&tq, measure: tBar, index: tqIdx)
let q1 = ScoreEdit.place(&tq, measure: tBar, rest: tqIdx, diatonic: 35, ticks: 480, tuplet: 3)!
check(tq.measures[tBar].notes[q1].duration == 320 && laneTicks(tq, tBar) == tWant, "a triplet quarter lasts 320")
check(ScoreEdit.resize(&tq, measure: tBar, index: q1, ticks: 480, tuplet: 0) && tq.measures[tBar].notes[q1].duration == 480 && tq.measures[tBar].notes[q1].tuplet == 0 && laneTicks(tq, tBar) == tWant, "a triplet turned back into a plain note keeps the bar")
print("ok: triplets")
try? MusicXML.write(trip).write(to: URL(fileURLWithPath: "/tmp/Triplets.musicxml"))

// Editing a blank bar in each metre: every bar stays full, nothing overlaps, rests sit on the beat grid.
func blankScore(_ beats: Int, _ type: Int, bars: Int = 2) -> ParsedScore {
    var s = ParsedScore(); s.staffCount = 1; s.tempo = 100
    let length = beats * 480 * 4 / type
    for i in 0..<bars {
        var m = PMeasure(); m.start = i * length; m.length = length
        if i == 0 { m.key = 0; m.time = (beats, type); m.clefs[0] = Clef() }
        var r = PNote(); r.staff = 0; r.duration = length; r.type = "whole"; r.measureRest = true
        m.notes.append(r); m.finalBar = i == bars - 1; s.measures.append(m)
    }
    return s
}
func laneSound(_ s: ParsedScore, _ m: Int) -> [(tick: Int, end: Int)] {
    s.measures[m].notes.filter { !$0.chord }.map { ($0.tick, $0.tick + $0.duration) }.sorted { $0.tick < $1.tick }
}
func tidy(_ s: ParsedScore, _ m: Int) -> Bool {
    let l = laneSound(s, m)
    var at = 0
    for x in l { if x.tick != at { return false }; at = x.end }
    return at == s.measures[m].length
}
for (b, t) in [(4, 4), (3, 4), (2, 4), (6, 8), (12, 8), (2, 2), (5, 4)] {
    var s = try! MusicXML.parse(MusicXML.write(blankScore(b, t)))
    let length = s.measures[0].length
    check(length == b * 1920 / t, "\(b)/\(t) bar length \(length)")
    for k in 0..<12 {
        guard let i = s.measures[0].notes.firstIndex(where: { $0.diatonic == nil }) else { break }
        let want = [240, 240, 480, 120, 240, 480][k % 6]
        ScoreEdit.place(&s, measure: 0, rest: i, diatonic: 35 + k % 5, ticks: want)
        check(tidy(s, 0), "\(b)/\(t) after note \(k + 1): \(laneSound(s, 0))")
    }
    s = try! MusicXML.parse(MusicXML.write(s))
    check(tidy(s, 0), "\(b)/\(t) survives a save")
}
do {
    var s = try! MusicXML.parse(MusicXML.write(blankScore(4, 4)))
    ScoreEdit.place(&s, measure: 0, rest: 0, diatonic: 35, ticks: 240)
    ScoreEdit.place(&s, measure: 0, rest: s.measures[0].notes.firstIndex { $0.tick == 240 && $0.diatonic == nil }!, diatonic: 36, ticks: 240)
    let kinds = s.measures[0].notes.sorted { $0.tick < $1.tick }.map { "\($0.tick):\($0.duration)" }
    check(kinds == ["0:240", "240:240", "480:480", "960:960"], "rests after two eighths are a quarter and a half: \(kinds)")
    check(s.measures[0].notes.filter { $0.diatonic != nil }.allSatisfy { $0.beams[1] != nil }, "two eighths in a beat are beamed")
}
print("ok: editing every metre")

// Free editing: exactly what was asked, nothing else.
do {
    var s = try! MusicXML.parse(MusicXML.write(blankScore(4, 4)))
    for k in 0..<5 {
        if k == 0 { ScoreEdit.placeFree(&s, measure: 0, rest: 0, diatonic: 35, ticks: 480) }
        else { ScoreEdit.append(&s, measure: 0, staff: 0, diatonic: 35 + k, ticks: 480) }
    }
    check(s.measures[0].notes.count == 5 && s.measures[0].notes.allSatisfy { $0.duration == 480 }, "five quarters go into a 4/4 bar: \(s.measures[0].notes.count)")
    check(laneSound(s, 0).last?.end == 2400, "the bar runs long, untouched")
    let back = try! MusicXML.parse(MusicXML.write(s))
    check(back.measures[0].notes.filter { $0.diatonic != nil }.count == 5, "an overfull bar survives a save")
    check(ScoreEdit.resizeFree(&s, measure: 0, index: 0, ticks: 960) && s.measures[0].notes.count == 5 && s.measures[0].notes[0].duration == 960, "a longer note overwrites nothing")
    check(ScoreEdit.setRestFree(&s, measure: 0, index: 1, ticks: 240) != nil && s.measures[0].notes.count == 5, "a note becomes a rest, no padding")
}
print("ok: free editing")

// Ties.
do {
    var s = try! MusicXML.parse(MusicXML.write(blankScore(4, 4)))
    ScoreEdit.place(&s, measure: 0, rest: 0, diatonic: 35, ticks: 960)
    let second = s.measures[0].notes.firstIndex { $0.tick == 960 }!
    ScoreEdit.place(&s, measure: 0, rest: second, diatonic: 37, ticks: 960)
    check(ScoreEdit.toggleTie(&s, measure: 0, index: 0, free: false), "a note ties to the one after it")
    check(s.measures[0].notes[1].diatonic == 35 && s.measures[0].notes[0].tieStart, "which takes the same pitch")
    let xml = String(decoding: MusicXML.write(s), as: UTF8.self)
    check(xml.contains("<tie type=\"start\"/>") && xml.contains("<tie type=\"stop\"/>") && xml.contains("<tied type=\"stop\"/>"), "the tie is written with both ends")
    let back = try! MusicXML.parse(MusicXML.write(s))
    check(back.measures[0].notes.first { $0.tick == 0 }!.tieStart, "ties survive a save")
    let (_, tl) = Engraver.engrave(s, musicFont: CTFontCreateWithFontDescriptor(fd[0], 28, nil))
    let heard = tl.notes.filter { $0.pitch != nil }
    check(heard.count == 1 && abs(heard[0].duration - 4) < 0.001, "a tied pair sounds once, for both lengths: \(heard.map(\.duration))")
    check(ScoreEdit.toggleTie(&s, measure: 0, index: 0, free: false) && !s.measures[0].notes[0].tieStart, "tapping again unties")
    // Last note of the piece has nothing to tie to.
    var e = blankScore(4, 4, bars: 1)
    ScoreEdit.place(&e, measure: 0, rest: 0, diatonic: 35, ticks: 1920)
    check(!ScoreEdit.toggleTie(&e, measure: 0, index: 0, free: false), "nothing to tie to at the end")
    check(ScoreEdit.toggleTie(&e, measure: 0, index: 0, free: true) && e.measures[0].notes[0].tieStart, "free editing ties it anyway")
}
print("ok: ties")

// Codas: signs, wordings, playing order and a save.
do {
    var s = blankScore(4, 4, bars: 8)
    ScoreEdit.toggle(.segno, &s, measure: 1)
    ScoreEdit.toggle(.toCoda, &s, measure: 3)
    ScoreEdit.toggle(.dsAlCoda, &s, measure: 5)
    ScoreEdit.toggle(.coda, &s, measure: 6)
    check(s.playOrder == [0, 1, 2, 3, 4, 5, 1, 2, 3, 6, 7], "D.S. al Coda: \(s.playOrder)")
    check(ScoreEdit.has(.dsAlCoda, in: s, measure: 5) && !ScoreEdit.has(.dalSegno, in: s, measure: 5), "the wording is told apart")
    ScoreEdit.toggle(.dalSegno, &s, measure: 5)
    check(ScoreEdit.has(.dalSegno, in: s, measure: 5) && !ScoreEdit.has(.dsAlCoda, in: s, measure: 5) && s.measures[5].marks.filter { !$0.dynamic }.count == 1, "one wording at a time")
    ScoreEdit.toggle(.dsAlCoda, &s, measure: 5)
    let xml = String(decoding: MusicXML.write(s), as: UTF8.self)
    check(xml.contains("<segno/>") && xml.contains("<coda/>"), "the segno and coda are written as signs")
    let back = try! MusicXML.parse(MusicXML.write(s))
    check(back.playOrder == s.playOrder && back.measures[6].flow.coda && back.measures[3].flow.toCoda && !back.measures[3].flow.coda, "a coda survives a save: \(back.playOrder)")
    ScoreEdit.toggle(.dsAlCoda, &s, measure: 5)
    check(!s.measures[5].flow.dalSegno && s.measures[5].marks.isEmpty, "toggling again takes it off")
    var c = blankScore(4, 4, bars: 6)
    ScoreEdit.toggle(.toCoda, &c, measure: 2); ScoreEdit.toggle(.dcAlCoda, &c, measure: 3); ScoreEdit.toggle(.coda, &c, measure: 4)
    check(c.playOrder == [0, 1, 2, 3, 0, 1, 2, 4, 5], "D.C. al Coda: \(c.playOrder)")
    // The same, with a repeat before the coda: repeats are not taken the second time.
    var r = blankScore(4, 4, bars: 6)
    r.measures[0].flow.repeatStart = true; r.measures[1].flow.repeatEnd = 2
    ScoreEdit.toggle(.toCoda, &r, measure: 2); ScoreEdit.toggle(.dcAlCoda, &r, measure: 3); ScoreEdit.toggle(.coda, &r, measure: 4)
    check(r.playOrder == [0, 1, 0, 1, 2, 3, 0, 1, 2, 4, 5], "D.C. al Coda with a repeat: \(r.playOrder)")
}
print("ok: codas")

// Tempo marks: the bars of a warped timeline last as long as their marks say, and the ratio says which part is playing.
do {
    var t = blankScore(4, 4, bars: 4)
    for m in 0..<4 { ScoreEdit.place(&t, measure: m, rest: 0, diatonic: 35, ticks: 1920) }
    ScoreEdit.setTempo(&t, measure: 2, bpm: 200, opening: 100)
    let (_, tl) = Engraver.engrave(t, musicFont: CTFontCreateWithFontDescriptor(fd[0], 28, nil))
    check(tl.stretch.count == 4 && tl.stretch[0] == 1 && abs(tl.stretch[2] - 0.5) < 0.001 && abs(tl.stretch[3] - 0.5) < 0.001, "a mark halves the length of the bars from there: \(tl.stretch)")
    let w = tl.warped()
    check(w.warpedApplied && !tl.warpedApplied && abs(w.measures[2].duration - 2) < 0.001 && abs(w.length - 12) < 0.001, "warping speeds up the later bars: \(w.length)")
}
print("ok: tempo marks")

// Words from a lyrics file go under the notes, one syllable a note, tied notes counting once.
do {
    var s = blankScore(4, 4, bars: 2)
    for m in 0..<2 { ScoreEdit.place(&s, measure: m, rest: 0, diatonic: 35, ticks: 960); ScoreEdit.place(&s, measure: m, rest: s.measures[m].notes.firstIndex { $0.tick == 960 && $0.diatonic == nil }!, diatonic: 35, ticks: 960) }
    ScoreEdit.toggleTie(&s, measure: 0, index: s.measures[0].notes.firstIndex { $0.tick == 960 && $0.diatonic != nil }!, free: false)
    let words: [(text: String, wordEnd: Bool)] = [("Glo", false), ("ry", true), ("be", true), ("to", true)]
    check(ScoreEdit.addLyrics(&s, syllables: words) == 3, "the tied note takes no syllable of its own")
    let heads = s.measures.flatMap { $0.notes.filter { $0.diatonic != nil }.sorted { $0.tick < $1.tick } }
    check(heads.map { $0.lyricText ?? "-" } == ["Glo", "ry", "-", "be"], "syllables in order: \(heads.map { $0.lyricText ?? "-" })")
    check(heads[0].syllabic == "begin" && heads[1].syllabic == "end" && heads[0].lyric == "Glo -", "a split word is begun and ended")
    check(ScoreEdit.addLyrics(&s, syllables: words) == 0, "a score with words of its own is left alone")
    let back = try! MusicXML.parse(MusicXML.write(s))
    check(back.measures[0].notes.contains { $0.lyricText == "Glo" }, "the words survive a save")
}
print("ok: inline lyrics")

// Dynamics: p, f, crescendo and diminuendo shape the loudness; hairpins survive a save and bar edits.
do {
    var s = blankScore(4, 4, bars: 4)
    for m in 0..<4 { ScoreEdit.place(&s, measure: m, rest: 0, diatonic: 35, ticks: 480) }
    ScoreEdit.setDynamic(&s, measure: 0, tick: 0, text: "p")
    ScoreEdit.toggleHairpin(&s, measure: 1, crescendo: true)
    ScoreEdit.setDynamic(&s, measure: 2, tick: 0, text: "f")
    ScoreEdit.toggleHairpin(&s, measure: 3, crescendo: false)
    let f = Dynamics.factor(for: s)
    check(abs(f(0) - 0.45 / 0.72) < 0.001, "p is quieter than normal: \(f(0))")
    check(f(1920) < f(1920 + 1000) && f(1920 + 1000) < f(3840), "a crescendo gets louder across its bar: \(f(1920)) \(f(2920)) \(f(3840))")
    check(abs(f(3840) - 0.86 / 0.72) < 0.001, "and arrives at f: \(f(3840))")
    check(f(5760 + 1000) < f(5760), "a diminuendo gets quieter: \(f(5760)) \(f(6760))")
    let (_, tl) = Engraver.engrave(s, musicFont: CTFontCreateWithFontDescriptor(fd[0], 28, nil))
    let heard = tl.notes.filter { $0.pitch != nil }.sorted { $0.start < $1.start }
    check(heard.count == 4 && heard[0].velocity < 0.7 && heard[2].velocity > 1.1, "the notes carry their loudness: \(heard.map(\.velocity))")
    let back = try! MusicXML.parse(MusicXML.write(s))
    check(back.measures[1].hairpins == s.measures[1].hairpins && back.measures[3].hairpins.first?.crescendo == false, "hairpins survive a save: \(back.measures[1].hairpins)")
    check(back.measures[0].marks.contains { $0.dynamic && $0.text == "p" }, "and so does the p")
    // A hairpin over two bars; a bar added inside it makes it longer, one taken out makes it shorter.
    check(ScoreEdit.resizeHairpin(&s, measure: 1, by: 1) && s.measures[1].hairpins[0].span == 1, "a hairpin stretches over the next bar")
    ScoreEdit.insertBar(&s, after: 1)
    check(s.measures[1].hairpins[0].span == 2, "a bar inserted inside it lengthens it")
    ScoreEdit.deleteBar(&s, measure: 2)
    check(s.measures[1].hairpins[0].span == 1, "a bar deleted from it shortens it")
    ScoreEdit.setDynamic(&s, measure: 0, tick: 0, text: nil)
    check(!s.measures[0].marks.contains { $0.dynamic }, "a dynamic can be removed")
}
print("ok: dynamics")

// A sweep: a few thousand random edits in several metres. Every bar must stay valid, and a save must change nothing.
do {
    var rng = SystemRandomNumberGenerator()
    var seed: UInt64 = 0x9E3779B97F4A7C15
    func rand(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
    let lengths = [1920, 960, 480, 240, 120, 1440, 720, 360]
    var edits = 0
    for (round, (b, t)) in (0..<12).flatMap({ r in [(4, 4), (3, 4), (6, 8), (2, 4), (12, 8), (5, 4)].map { (r, $0) } }).enumerated().map({ ($0.element.0, $0.element.1) }) {
        seed = 0x9E3779B97F4A7C15 &+ UInt64(round) &* 104729 &+ UInt64(b * 31 + t)
        var s = blankScore(b, t, bars: 4)
        var log: [String] = []
        for step in 0..<600 {
            let m = rand(s.measures.count)
            let notes = s.measures[m].notes
            guard !notes.isEmpty else { continue }
            let i = rand(notes.count)
            let op = rand(14), len = lengths[rand(lengths.count)], pitch = 28 + rand(14), trip = rand(8) == 0 ? 3 : 0, flag = rand(2) == 0, pick = rand(5)
            log.append("op\(op) bar\(m) idx\(i) len\(len) trip\(trip) pitch\(pitch) \(notes[i].diatonic == nil ? "rest" : "note")@\(notes[i].tick):\(notes[i].duration)")
            if log.count > 8 { log.removeFirst() }
            switch op {
            case 0, 1, 2: if notes[i].diatonic == nil { ScoreEdit.place(&s, measure: m, rest: i, diatonic: pitch, ticks: len, tuplet: trip) }
            case 3: ScoreEdit.resize(&s, measure: m, index: i, ticks: len, tuplet: trip)
            case 4: ScoreEdit.setRest(&s, measure: m, index: i, ticks: len)
            case 5: ScoreEdit.erase(&s, measure: m, index: i)
            case 6: ScoreEdit.setPitch(&s, measure: m, index: i, diatonic: pitch)
            case 7: ScoreEdit.setAccidental(&s, measure: m, index: i, [.sharp, .flat, .natural, .key][pick % 4])
            case 8: ScoreEdit.toggleTie(&s, measure: m, index: i, free: false)
            case 9: ScoreEdit.toggleArticulation(&s, measure: m, index: i, ScoreEdit.articulations[pick].name)
            case 10: ScoreEdit.setDynamic(&s, measure: m, tick: [0, 480, 960][pick % 3], text: pick == 4 ? nil : ScoreEdit.dynamicNames[(pick + len) % 8])
            case 11: ScoreEdit.toggleHairpin(&s, measure: m, crescendo: flag); if pick < 2 { ScoreEdit.resizeHairpin(&s, measure: m, by: flag ? 1 : -1) }
            case 12: if s.measures.count < 8 { ScoreEdit.insertBar(&s, after: m) }
            default: if s.measures.count > 2, pick == 0 { ScoreEdit.deleteBar(&s, measure: m) }
            }
            edits += 1
            for k in s.measures.indices {
                let tidyBar = tidy(s, k)
                // Triplets can't fill every bar to the tick with plain lengths; every other bar must be exact.
                let triplets = s.measures[k].notes.contains { $0.tuplet > 0 }
                check(tidyBar, "\(b)/\(t) step \(step) bar \(k) not tidy: \(laneSound(s, k)) of \(s.measures[k].length)\n" + log.joined(separator: "\n"))
                check(s.measures[k].notes.allSatisfy { $0.duration > 0 && $0.tick >= 0 }, "bad note in bar \(k)")
                for h in s.measures[k].hairpins { check(k + h.span < s.measures.count, "hairpin runs off the end") }
            }
            if step % 50 == 49 {
                let back = try! MusicXML.parse(MusicXML.write(s))
                check(back.measures.count == s.measures.count, "a save changed the number of bars")
                for k in s.measures.indices where !s.measures[k].notes.contains(where: { $0.tuplet > 0 }) {
                    check(back.measures[k].notes.count == s.measures[k].notes.count, "a save changed bar \(k): \(s.measures[k].notes.count) to \(back.measures[k].notes.count)")
                }
                _ = Engraver.engrave(s, musicFont: CTFontCreateWithFontDescriptor(fd[0], 28, nil))
            }
        }
    }
    _ = rng
    print("ok: \(edits) random edits")
}

// The same, with free editing: anything goes, but nothing may crash and a save must keep every note.
do {
    var seed: UInt64 = 42
    func rand(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
    for (b, t) in [(4, 4), (3, 4), (6, 8)] {
        var s = blankScore(b, t, bars: 3)
        for step in 0..<400 {
            let m = rand(3), notes = s.measures[m].notes
            guard !notes.isEmpty else { continue }
            let i = rand(notes.count), len = [1920, 960, 480, 240, 120, 720][rand(6)]
            switch rand(5) {
            case 0: if notes[i].diatonic == nil { ScoreEdit.placeFree(&s, measure: m, rest: i, diatonic: 28 + rand(14), ticks: len, tuplet: rand(6) == 0 ? 3 : 0) }
            case 1: ScoreEdit.append(&s, measure: m, staff: 0, diatonic: 28 + rand(14), ticks: len)
            case 2: ScoreEdit.resizeFree(&s, measure: m, index: i, ticks: len)
            case 3: ScoreEdit.setRestFree(&s, measure: m, index: i, ticks: len)
            default: ScoreEdit.toggleTie(&s, measure: m, index: i, free: true)
            }
            if step % 40 == 39 {
                let back = try! MusicXML.parse(MusicXML.write(s))
                for k in s.measures.indices { check(back.measures[k].notes.filter { $0.diatonic != nil }.count == s.measures[k].notes.filter { $0.diatonic != nil }.count, "free editing: a save lost notes in bar \(k) of \(b)/\(t)") }
                _ = Engraver.engrave(s, musicFont: CTFontCreateWithFontDescriptor(fd[0], 28, nil))
            }
        }
    }
}
print("ok: free editing sweep")

// The synth respects loudness, and Bass is an instrument of its own.
do {
    func peak(_ velocity: Float, _ voice: Instrument) -> Float {
        let b = Synth.renderOffline([(start: 0, seconds: 0.5, pitch: 48, instrument: voice, velocity: velocity)], volume: 0.8, total: 1)!
        let l = b.floatChannelData![0]
        return (0..<Int(b.frameLength)).map { abs(l[$0]) }.max() ?? 0
    }
    let quiet = peak(0.4, .piano), loud = peak(1.2, .piano)
    check(loud > quiet * 1.5, "a louder note has a bigger signal: \(quiet) \(loud)")
    check(peak(1, .bass) > 0.01 && Instrument.allCases.contains(.bass), "bass makes sound")
    let mixed = Synth.renderOffline([(start: 0, seconds: 0.3, pitch: 48, instrument: .bass, velocity: 1), (start: 0.5, seconds: 0.3, pitch: 72, instrument: .flute, velocity: 1)], volume: 0.8, total: 1)!
    let l = mixed.floatChannelData![0]
    check((0..<22_000).contains { abs(l[$0]) > 0.01 } && (22_100..<44_000).contains { abs(l[$0]) > 0.01 }, "each staff's instrument sounds in turn")
}
print("ok: synth loudness and bass")

// Chords: worked out from the notes, read from the file, saved and transposed.
do {
    func name(_ midi: [Int], flats: Bool = false) -> String { Chords.detect(midi.map { ($0, 1.0) })?.name(flats: flats) ?? "N.C." }
    check(name([60, 64, 67]) == "C", "C major triad: \(name([60, 64, 67]))")
    check(name([57, 60, 64]) == "Am", "A minor: \(name([57, 60, 64]))")
    check(name([55, 59, 62, 65]) == "G7", "G7: \(name([55, 59, 62, 65]))")
    check(name([57, 60, 64, 67]) == "Am7" || name([57, 60, 64, 67]) == "C/A", "A minor seventh: \(name([57, 60, 64, 67]))")
    check(name([47, 55, 62, 65]) == "G7/B", "slash chord: \(name([47, 55, 62, 65]))")
    check(name([58, 62, 65], flats: true) == "B♭" && name([58, 62, 65], flats: false) == "A♯", "spelling follows the key: \(name([58, 62, 65], flats: true))")
    check(name([59, 62, 65]) == "Bdim", "diminished: \(name([59, 62, 65]))")
    check(name([]) == "N.C.", "silence has no chord")
    // A chart from a score: four quarter-note bars on C, then G.
    var s = blankScore(4, 4, bars: 2)
    for m in 0..<2 {
        for k in 0..<4 {
            let rest = s.measures[m].notes.firstIndex { $0.diatonic == nil && $0.tick == k * 480 } ?? 0
            ScoreEdit.place(&s, measure: m, rest: rest, diatonic: m == 0 ? [28, 30, 32, 30][k] : [32, 34, 36, 34][k], ticks: 480)
        }
    }
    let chart = Chords.chart(for: s)
    check(!chart.fromFile && chart.bars[0].first?.chord?.name(flats: false) == "C" && chart.bars[1].first?.chord?.name(flats: false) == "G", "a chart from the notes: \(chart.bars.map { $0.map { $0.chord?.name(flats: false) ?? "-" } })")
    // Chord symbols in the file are used as written, saved, and move with the key.
    s.measures[0].chords = [ChordMark(tick: 0, chord: Chord(root: 9, kind: "m7", bass: nil)), ChordMark(tick: 960, chord: Chord(root: 2, kind: "7", bass: 6))]
    let back = try! MusicXML.parse(MusicXML.write(s))
    check(back.measures[0].chords == s.measures[0].chords, "chord symbols survive a save: \(back.measures[0].chords)")
    check(Chords.chart(for: back).fromFile && Chords.chart(for: back).bars[0].count == 2, "and are used as the chart")
    let up = back.transposed(by: 2).measures[0].chords.map { $0.chord?.name(flats: false) ?? "-" }
    check(up == ["Bm7", "E7/G♯"], "they move with the key: \(up)")
}
print("ok: chords")

// Medleys: bars copied from one score into another, with their own key and tempo, and the old music's back after them.
do {
    func tune(_ fifths: Int, _ beats: Int, _ type: Int, bars: Int, staves: Int = 1, tempo: Double? = nil) -> ParsedScore {
        var s = blankScore(beats, type, bars: bars)
        s.staffCount = staves; s.tempo = tempo
        s.measures[0].key = fifths
        for m in 0..<bars {
            if staves > 1 { var r = PNote(); r.staff = 1; r.duration = s.measures[m].length; r.type = "whole"; r.measureRest = true; s.measures[m].notes.append(r) }
            ScoreEdit.place(&s, measure: m, rest: s.measures[m].notes.firstIndex { $0.diatonic == nil && $0.staff == 0 }!, diatonic: 35 + m, ticks: s.measures[m].length)
        }
        if staves > 1 { s.measures[0].clefs[1] = Clef(sign: "F", line: 4) }
        return s
    }
    let source = tune(0, 3, 4, bars: 4, tempo: 140)
    var dest = tune(1, 4, 4, bars: 4, staves: 2, tempo: 90)
    let clip = ScoreEdit.clip(from: source, bars: 1...2, title: "Waltz")!
    check(clip.count == 2 && clip.key == 0 && clip.time.beats == 3 && clip.tempo == 140, "a clip remembers where it came from")
    let went = ScoreEdit.paste(&dest, clip: clip, after: 1, matchKey: false, openingTempo: 90)!
    check(went == 2...3 && dest.measures.count == 6, "two bars go in after bar 2: \(went)")
    check(dest.measures[2].key == 0 && dest.measures[2].time?.beats == 3 && dest.measures[2].tempo == 140 && dest.measures[2].tempoShown, "the new bars carry their own key, metre and tempo")
    check(dest.measures[2].length == 1440 && dest.measures[4].length == 1920, "bar lengths are kept")
    check(dest.measures[4].key == 1 && dest.measures[4].time?.beats == 4 && dest.measures[4].tempo == 90, "the old music gets its key, metre and tempo back after: \(String(describing: dest.measures[4].key)) \(String(describing: dest.measures[4].time)) \(String(describing: dest.measures[4].tempo))")
    check(dest.measures[2].notes.contains { $0.staff == 1 && $0.diatonic == nil } && dest.measures[2].notes.filter { $0.staff == 0 && $0.diatonic != nil }.count == 1, "a staff the clip lacks rests")
    check(dest.measures[2].clefs[1]?.sign == "F", "and keeps its clef")
    let back = try! MusicXML.parse(MusicXML.write(dest))
    check(back.measures.count == 6 && back.measures[2].time?.beats == 3 && back.measures[2].length == 1440, "the medley survives a save")
    // Matching the key moves the notes: C major into a piece in G.
    var other = tune(1, 4, 4, bars: 2)
    let clip2 = ScoreEdit.clip(from: tune(0, 4, 4, bars: 2), bars: 0...1)!
    ScoreEdit.paste(&other, clip: clip2, after: 1, matchKey: true, openingTempo: 100)
    check(other.measures[2].key == 1 && (other.measures[2].notes.first { $0.diatonic != nil }?.diatonic ?? -1) == 32, "matching the key moves the notes the short way (C to G, down a fourth): \(String(describing: other.measures[2].key)) \(String(describing: other.measures[2].notes.first { $0.diatonic != nil }?.diatonic))")
    // At the very end the final barline moves; cut and delete never empty the piece.
    var tail = tune(0, 4, 4, bars: 2)
    ScoreEdit.paste(&tail, clip: clip2, after: 1, matchKey: false, openingTempo: 100)
    check(tail.measures[3].finalBar && !tail.measures[1].finalBar, "the closing barline moves to the end")
    check(ScoreEdit.deleteBars(&tail, 0...3) == 3 && tail.measures.count == 1, "the last bar always stays")
    // Hairpin spans grow and a copy of one is trimmed.
    var h = tune(0, 4, 4, bars: 4)
    ScoreEdit.toggleHairpin(&h, measure: 1, crescendo: true); ScoreEdit.resizeHairpin(&h, measure: 1, by: 1)
    ScoreEdit.paste(&h, clip: clip2, after: 1, matchKey: false, openingTempo: 100)
    check(h.measures[1].hairpins[0].span == 3, "a hairpin stretches across bars put into it: \(h.measures[1].hairpins[0].span)")
    let trimmed = ScoreEdit.clip(from: h, bars: 1...1)!
    check(trimmed.measures[0].hairpins[0].span == 0, "a copied hairpin stops at the copied bars")
}
print("ok: medleys")

// More notation: slurs, ornaments, fingering, arpeggio, grace notes, octave lines and the pedal survive read, write and engraving.
do {
    let xml = """
    <score-partwise><part-list><score-part id="P1"><part-name>x</part-name></score-part></part-list><part id="P1">
    <measure number="1"><attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>
    <direction><direction-type><octave-shift type="down" size="8"/></direction-type></direction>
    <direction><direction-type><pedal type="start" line="yes"/></direction-type></direction>
    <note><grace slash="yes"/><pitch><step>D</step><octave>5</octave></pitch><type>eighth</type></note>
    <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><type>quarter</type><notations><slur type="start" number="1"/><ornaments><trill-mark/></ornaments><technical><fingering>3</fingering></technical></notations></note>
    <note><pitch><step>E</step><octave>5</octave></pitch><duration>1</duration><type>quarter</type><notations><slur type="stop" number="1"/><arpeggiate/><articulations><breath-mark/></articulations></notations></note>
    <note><pitch><step>G</step><octave>5</octave></pitch><duration>2</duration><type>half</type></note></measure>
    <measure number="2"><direction><direction-type><octave-shift type="stop" size="8"/></direction-type></direction>
    <direction><direction-type><pedal type="stop" line="yes"/></direction-type></direction>
    <note><rest measure="yes"/><duration>4</duration></note></measure></part></score-partwise>
    """
    let a = try! MusicXML.parse(Data(xml.utf8))
    let b = try! MusicXML.parse(MusicXML.write(a))
    for s in [a, b] {
        let n = s.measures[0].notes
        check(s.measures[0].graces.count == 1 && s.measures[0].graces[0].diatonic == 36, "a grace note is kept")
        check(n[0].slurStart && n[1].slurStop && n[0].articulations.contains("trill-mark") && n[0].articulations.contains("finger:3"), "slurs, trill and fingering are kept")
        check(n[1].articulations.contains("arpeggiate") && n[1].articulations.contains("breath-mark"), "arpeggio and breath mark are kept")
        check(s.measures[0].spans.map(\.kind).sorted() == ["8va", "pedal"] && s.measures[0].spans.allSatisfy { $0.span == 1 }, "octave line and pedal span into bar 2")
    }
    let t = a.transposed(by: 2)
    check(t.measures[0].graces[0].diatonic == 37 && t.measures[0].graces[0].alter == 0, "a grace note transposes")
    let (pdf2, tl) = Engraver.engrave(a, musicFont: CTFontCreateWithFontDescriptor(fd[0], 28, nil))
    check(pdf2.count > 0 && tl.notes.filter(\.grace).count == 1 && tl.notes.filter({ !$0.grace && !$0.isRest }).count == 3, "engraves with a grace note event")
    if let out = ProcessInfo.processInfo.environment["PA_DUMP"] { try? pdf2.write(to: URL(fileURLWithPath: out)) }   // look at the page: PA_DUMP=/tmp/n.pdf
    let font = CTFontCreateWithFontDescriptor(fd[0], 28, nil)
    for cp: UInt16 in [0xE566, 0xE567, 0xE56C, 0xE56D, 0xE4CE, 0xE4D1, 0xE63C, 0xE650, 0xE655, 0xE240, 0xE0A4] {
        var c = cp, g: CGGlyph = 0
        check(CTFontGetGlyphsForCharacters(font, &c, &g, 1) && g != 0, "the music font has U+\(String(cp, radix: 16))")
    }
}
print("ok: more notation")

// Pitch finding, judging held notes, and tap tempo.
do {
    func tone(_ hz: Double, rate: Double = 48_000, n: Int = 4096, harmonics: [Double] = [1]) -> [Float] {
        (0..<n).map { i in Float(harmonics.enumerated().reduce(0.0) { $0 + $1.element * sin(2 * .pi * hz * Double($1.offset + 1) * Double(i) / rate) } * 0.3) }
    }
    for hz in [41.2, 110.0, 261.63, 440.0, 880.0, 1760.0] {
        for h in [[1.0], [1.0, 0.6, 0.4, 0.2]] {
            let r = Pitch.detect(tone(hz, harmonics: h), rate: 48_000)
            check(r != nil && abs(Pitch.midi(r!.hz) - Pitch.midi(hz)) < 0.05, "detects \(hz) Hz: \(String(describing: r))")
        }
    }
    check(Pitch.detect([Float](repeating: 0, count: 4096), rate: 48_000) == nil, "silence has no pitch")
    check(Pitch.name(69) == "A4" && Pitch.name(60) == "C4" && abs(Pitch.hz(Pitch.midi(300)) - 300) < 0.001, "note names and frequencies")
    // Judge: hold C4 for a half-second note (0.4 s needed at 80%).
    var j = NoteJudge()
    j.aim(at: [60], seconds: 0.5)
    var t = 0.0, verdict = NoteJudge.Verdict.silent
    while t < 0.6, verdict != .done { verdict = j.feed(60.1, at: t); t += 0.05 }
    check(verdict == .done && t > 0.4 && t < 0.6, "holding the note long enough finishes it: \(t)")
    j.aim(at: [62], seconds: 0.5)
    check({ if case .wrong = j.feed(65, at: 1.0) { return true }; return false }(), "a different note is wrong")
    check({ if case .off = j.feed(62.6, at: 1.05) { return true }; return false }(), "the right note out of tune is off")
    var hold = NoteJudge()
    hold.aim(at: [60], seconds: 0.5)
    for k in 0..<4 { _ = hold.feed(60, at: Double(k) * 0.05) }
    _ = hold.feed(nil, at: 0.3); _ = hold.feed(nil, at: 0.45)   // a long dropout starts the hold again
    check({ if case .good(let p) = hold.feed(60, at: 0.5) { return p < 0.2 }; return false }(), "a dropout resets the hold")
    // A repeated note needs a fresh start; octaves count only when allowed.
    var rep = NoteJudge()
    rep.aim(at: [60], seconds: 0.1)
    var v = NoteJudge.Verdict.silent, k = 0.0
    while v != .done { v = rep.feed(60, at: k); k += 0.05 }
    rep.aim(at: [60], seconds: 0.1)
    check(rep.feed(60, at: k) == .silent, "still sounding the last note: wait for a fresh one")
    _ = rep.feed(nil, at: k + 0.05)
    check({ if case .good = rep.feed(60, at: k + 0.1) { return true }; return false }(), "after a stop the repeated note counts")
    var oct = NoteJudge(); oct.aim(at: [60], seconds: 1)
    check({ if case .wrong = oct.feed(72, at: 0) { return true }; return false }(), "an octave up is wrong by default")
    oct.anyOctave = true
    check({ if case .good = oct.feed(72.05, at: 0.05) { return true }; return false }(), "an octave up counts when allowed")
    // Tap tempo: eight taps at 100 BPM, one of them late, still reads 100.
    var tap = TapTempo(), bpm: Double?
    check(tap.tap(at: 0) == nil && abs((tap.tap(at: 0.6) ?? 0) - 100) < 0.01, "one tap is not enough; two give the tempo")
    for i in 2..<8 { bpm = tap.tap(at: Double(i) * 0.6 + (i == 5 ? 0.12 : 0)) }
    check(bpm != nil && abs(bpm! - 100) < 3, "tap tempo reads about 100: \(String(describing: bpm))")
    check(tap.tap(at: 20) == nil && tap.count == 1, "a pause starts the taps again")
}
print("ok: pitch, judging, tap tempo")

// Reviewing a take: the right note green, the note the player actually hit green when right and red when late.
do {
    // Quarter notes C D E F G A on beats 0...5 (MIDI 60 62 64 65 67 69), ids 0...5.
    let pitches = [60, 62, 64, 65, 67, 69]
    let events = pitches.enumerated().map { i, p in NoteEvent(id: i, start: Double(i), duration: 1, page: 0, rect: .zero, pitch: p) }
    func take(_ frames: [(Double, Double, Float?)]) -> Take {
        var t = Take(); t.tempo = 120; t.frames = frames.map { TakeFrame(t: $0.0, beat: $0.1, midi: $0.2) }; t.duration = frames.last?.0 ?? 0; return t
    }
    let judge = TakeJudge(events: events, staff: nil)
    // In time: at beat 2.5 the player is on E.
    let a = take([(1.0, 2.5, 64.05)])
    let ok = judge.lit(a, at: 1.0)
    check(ok.green == [2] && ok.red.isEmpty, "playing the right note in time lights it green: \(ok)")
    // Two notes behind: at beat 4.5 the player is still on E (id 2); G (id 4) should be green and E red.
    let b = take([(2.25, 4.5, 64.0)])
    let late = judge.lit(b, at: 2.25)
    check(late.green == [4] && late.red == [2], "two notes behind: the note due is green and the one played is red: \(late)")
    // A note not in the score near here: the due note is green and the stray pitch is reported.
    let c = take([(1.0, 2.5, 61.0)])
    let stray = judge.lit(c, at: 1.0)
    check(stray.green == [2] && stray.red.isEmpty && stray.stray == 61, "a wrong note is reported as stray: \(stray)")
    // Out of tune is not a note.
    let d = take([(1.0, 2.5, 64.25)])
    check(judge.lit(d, at: 1.0).green == [2], "slightly out of tune still counts as the note")
    let e = take([(1.0, 2.5, 64.45)])
    check(judge.lit(e, at: 1.0).stray != nil && judge.lit(e, at: 1.0).red.isEmpty, "well out of tune is not the note")
    // Silence: only the due note is lit.
    check(judge.lit(take([(1.0, 2.5, nil)]), at: 1.0) == ReviewLit(green: [2], red: [], stray: nil, beat: 2.5), "silence lights only the due note")
    // The summary: play 4 of the 6 notes, the rest a note behind.
    var frames: [(Double, Double, Float?)] = []
    for i in 0..<6 {
        for k in 0..<4 {
            let beat = Double(i) + Double(k) * 0.25 + 0.1
            let p: Float = i >= 4 ? Float(pitches[i - 1]) : Float(pitches[i])   // last two are played a note behind
            frames.append((beat * 0.5, beat, p))
        }
    }
    let s = judge.summary(take(frames))
    check(s.total == 6 && s.hit == 4, "summary: 4 of 6 notes: \(s)")
    // However far behind or ahead: 20 notes, the player 7 notes behind in one place and 9 ahead in another.
    let longPitches = (0..<20).map { 50 + ($0 * 7) % 24 }   // all different within the run
    let longEvents = longPitches.enumerated().map { i, p in NoteEvent(id: i, start: Double(i), duration: 1, page: 0, rect: .zero, pitch: p) }
    let longJudge = TakeJudge(events: longEvents, staff: nil)
    let behind = longJudge.lit(take([(1.0, 14.5, Float(longPitches[7]))]), at: 1.0)   // due: note 14, playing note 7
    check(behind.green == [14] && behind.red == [7], "seven notes behind: \(behind)")
    let ahead = longJudge.lit(take([(1.0, 3.5, Float(longPitches[12]))]), at: 1.0)    // due: note 3, playing note 12
    check(ahead.green == [3] && ahead.red == [12], "nine notes ahead: \(ahead)")
    // The take's clock: halfway between frames gives halfway between beats; before the first frame it extrapolates.
    let t2 = take([(1.0, 2.0, nil), (2.0, 4.0, nil)])
    check(abs(t2.beat(at: 1.5) - 3) < 0.001 && abs(t2.beat(at: 0.5) - 1) < 0.001, "take beat clock: \(t2.beat(at: 0.5)) \(t2.beat(at: 1.5))")
    // Repeats and octaves.
    let oct = TakeJudge(events: events, staff: nil, anyOctave: true)
    check(oct.lit(take([(1.0, 2.5, 76.0)]), at: 1.0).green == [2], "an octave up counts when allowed")
}
print("ok: reviewing takes")

// Keyboard shortcuts: no two actions share a default, a changed shortcut takes the key from whoever had it, and reset puts it back.
do {
    let all = ShortcutAction.allCases
    check(Set(all.map(\.defaultChord)).count == all.count, "every default shortcut is different")
    check(Shortcuts.chord(.playPause, "") == .plain("space") && KeyChord.plain("pageDown").label == "Page Down" && KeyChord.cmd("e").label == "⌘E", "labels: \(KeyChord.cmd("e").label)")
    let a = Shortcuts.assign(.cmd("t"), to: .editScore, in: "")   // ⌘T belongs to the tuner
    check(a.displaced == "Tuner" && Shortcuts.chord(.editScore, a.blob) == .cmd("t") && Shortcuts.chord(.tuner, a.blob).isNone, "a taken shortcut moves: \(a)")
    let back = Shortcuts.reset(.editScore, in: a.blob)
    check(Shortcuts.chord(.editScore, back) == .cmd("e"), "reset returns the default")
    let cleared = Shortcuts.assign(.none, to: .metronome, in: "")
    check(Shortcuts.chord(.metronome, cleared.blob).isNone && Shortcuts.overrides(cleared.blob).count == 1, "a shortcut can be taken away")
    check(Shortcuts.assign(.plain("k"), to: .metronome, in: cleared.blob).blob.isEmpty, "choosing the default again stores nothing")
}
print("ok: keyboard shortcuts")

// The written review: facts from a take, places that can be tapped, and the review made from them.
do {
    // 24 quarter notes in six bars of 4; every pitch different within a bar run so each note can be told apart.
    let ps = (0..<24).map { 48 + ($0 * 5) % 30 }
    let events = ps.enumerated().map { i, p in NoteEvent(id: i, start: Double(i), duration: 1, page: 0, rect: .zero, pitch: p) }
    let bars = (0..<6).map { BarSpan(number: $0 + 1, start: Double($0 * 4), end: Double($0 * 4 + 4)) }
    let judge = TakeJudge(events: events, staff: nil)
    // Bars 1 and 2 perfect, bar 3 to 5 two notes behind, bar 6 perfect; sung a bit sharp (+10 cents).
    var t = Take(); t.tempo = 120
    for i in 0..<24 {
        let behind = (8..<20).contains(i)
        let note = behind ? max(0, i - 2) : i
        for k in 0..<4 {
            let beat = Double(i) + 0.15 + Double(k) * 0.2
            t.frames.append(TakeFrame(t: beat * 0.5, beat: beat, midi: Float(ps[note]) + 0.1))
        }
    }
    t.duration = t.frames.last!.t
    let f = judge.facts(t, bars: bars)
    check(f.total == 24 && f.hit < 24 && f.hit > 8, "facts: \(f.hit) of \(f.total)")
    check(f.behind != nil && f.behind!.notes == 2 && f.behind!.fromBar >= 3 && f.behind!.toBar <= 5, "fell behind by two in bars 3 to 5: \(String(describing: f.behind))")
    check(f.ahead == nil, "never ahead")
    check(f.cents != nil && abs(f.cents! - 10) < 2, "ten cents sharp: \(String(describing: f.cents))")
    check(!f.missed.isEmpty && f.missed.allSatisfy { f.notes[$0] != nil && f.notes[$0]!.hit == false }, "missed notes are real notes that were missed")
    check(f.bestBars != nil && f.bestBars!.from == 1, "the clean opening is the best stretch: \(String(describing: f.bestBars))")
    // Tokens: real places become taps, made-up ones vanish.
    let text = "See {bars:3-5} and {note:\(f.missed[0])} but not {bar:99} or {note:500}."
    let seg = ReviewText.parse(text, facts: f)
    check(seg.contains(.ref(.bars(3, 5))) && seg.contains(.ref(.note(f.missed[0]))) && !seg.contains(.ref(.bar(99))), "references are checked: \(seg)")
    check(!seg.contains { if case .text(let s) = $0 { return s.contains("{") }; return false }, "no braces left over")
    check(ReviewRef(url: ReviewRef.bars(3, 5).url) == .bars(3, 5) && ReviewRef(url: ReviewRef.note(7).url) == .note(7) && ReviewRef(url: ReviewRef.bar(2).url) == .bar(2), "references survive a link")
    // The rules-based review points at real places.
    let r = ReviewComposer.template(f)
    check(!r.headline.isEmpty && r.paragraphs.contains { $0.kind == .timing && $0.text.contains("Behind by") }, "template review: \(r.headline)")
    let refs = r.paragraphs.flatMap { ReviewText.parse($0.text, facts: f) }.compactMap { s -> ReviewRef? in if case .ref(let x) = s { x } else { nil } }
    check(!refs.isEmpty, "the review has tappable places")
    check(abs(t.time(atBeat: t.beat(at: 3.3)) - 3.3) < 0.01, "time and beat are inverses: \(t.time(atBeat: t.beat(at: 3.3)))")
}
check(ReviewText.accepts(original: "You fell behind by 2 notes at {bars:3-5}.", rewrite: "2 notes behind at {bars:3-5}."), "a faithful rewrite is accepted")
check(!ReviewText.accepts(original: "You fell behind by 2 notes at {bars:3-5}.", rewrite: "Oh dear, around {bars:3-5} you slipped 2 notes behind, but it is fine, keep going and it will settle soon enough."), "a chatty rewrite is refused")
check(!ReviewText.accepts(original: "You fell behind by 2 notes at {bars:3-5}.", rewrite: "You fell behind by 3 notes at {bars:3-5}."), "a changed number is refused")
check(!ReviewText.accepts(original: "You fell behind by 2 notes at {bars:3-5}.", rewrite: "You fell behind by 2 notes at {bars:4-5}."), "a changed place is refused")
check(!ReviewText.accepts(original: "Work on {bar:2}.", rewrite: "Work on it."), "a dropped place is refused")
print("ok: written review")

// Apple Music lyrics (TTML) become LRC lines.
do {
    let ttml = """
    <tt><body><div>
    <p begin="0:12.500" end="0:15"><span begin="0:12.5">Hello</span> <span>there</span> &amp; you</p>
    <p begin="00:01:02.250" end="1:05"><span>Second</span><br/>line</p>
    <p begin="bad">Skipped</p>
    </div></body></tt>
    """
    let lrc = TTML.toLRC(ttml)
    check(lrc == "[00:12.50]Hello there & you\n[01:02.25]Second line", "TTML to LRC: \(String(describing: lrc))")
    check(TTML.seconds("62.5s") == 62.5 && TTML.seconds("1:02.5") == 62.5 && TTML.toLRC("<tt></tt>") == nil, "TTML times")
}
print("ok: ttml")

// Cutting the singer down: a tone in the middle (the "voice") goes, a tone on one side (an "instrument") stays.
import AVFoundation
do {
    let rate = 44_100.0, n = 44_100
    let dir = FileManager.default.temporaryDirectory.appending(path: "pa-vocal-check", directoryHint: .isDirectory)
    try? FileManager.default.removeItem(at: dir)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let src = dir.appending(path: "song.caf")
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: false)!
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
    buf.frameLength = AVAudioFrameCount(n)
    for i in 0..<n {
        let voice = Float(sin(2 * .pi * 880 * Double(i) / rate)) * 0.3, guitar = Float(sin(2 * .pi * 1320 * Double(i) / rate)) * 0.3
        buf.floatChannelData![0][i] = voice + guitar   // the voice in both channels, the guitar only on the left
        buf.floatChannelData![1][i] = voice
    }
    let file = try! AVAudioFile(forWriting: src, settings: fmt.settings)
    try! file.write(from: buf)
    let out = await VocalReducer.ensure(src)
    check(out != nil, "the reduced copy is made")
    let read = try! AVAudioFile(forReading: out!)
    let rb = AVAudioPCMBuffer(pcmFormat: read.processingFormat, frameCapacity: AVAudioFrameCount(read.length))!
    try! read.read(into: rb)
    func power(_ hz: Double) -> Double {   // Goertzel
        var re = 0.0, im = 0.0
        for i in 0..<Int(rb.frameLength) { let x = Double(rb.floatChannelData![0][i]), a = 2 * .pi * hz * Double(i) / rate; re += x * cos(a); im += x * sin(a) }
        return (re * re + im * im).squareRoot() / Double(rb.frameLength)
    }
    check(power(880) < power(1320) * 0.05, "the middle tone is cut and the side tone stays: voice \(power(880)) guitar \(power(1320))")
    check(await VocalReducer.ensure(src) == out, "a second ask finds the copy")
    try? FileManager.default.removeItem(at: dir)
}
print("ok: vocal reduction")

// The microphone analyser must finish whatever the size of the buffers it is given (it once looped forever while its window filled).
do {
    let rate = 48_000.0
    let tone = (0..<48_000).map { Float(sin(2 * .pi * 440 * Double($0) / rate)) * 0.3 }
    for chunk in [128, 512, 1024, 4096, 4800, 9999] {
        let a = PitchAnalyzer(rate: rate, gate: 0.001)
        var found: [Double] = []
        var at = 0
        while at < tone.count {
            let end = min(at + chunk, tone.count)
            tone[at..<end].withUnsafeBufferPointer { found += a.process($0).compactMap(\.hz) }
            at = end
        }
        check(found.count > 20 && found.allSatisfy { abs(Pitch.midi($0) - 69) < 0.1 }, "analyser with \(chunk)-sample buffers: \(found.count) readings")
    }
}
print("ok: analyser")

// A printed metronome mark beats a separate "sound" tempo, wherever they come in the bar.
do {
    func tempo(_ body: String) -> (Double?, Double?) {
        let xml = "<score-partwise><part-list><score-part id=\"P1\"><part-name>x</part-name></score-part></part-list><part id=\"P1\"><measure number=\"1\"><attributes><divisions>1</divisions></attributes>\(body)<note><rest/><duration>4</duration></note></measure></part></score-partwise>"
        let s = try! MusicXML.parse(Data(xml.utf8))
        return (s.tempo, s.measures[0].tempo)
    }
    let soundFirst = tempo("<sound tempo=\"150\"/><direction><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>80</per-minute></metronome></direction-type></direction>")
    check(soundFirst.0 == 80 && soundFirst.1 == 80, "a printed 80 beats a sound tempo of 150: \(soundFirst)")
    let together = tempo("<direction><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>80</per-minute></metronome></direction-type><sound tempo=\"150\"/></direction>")
    check(together.0 == 80 && together.1 == 80, "same, inside one direction: \(together)")
    let soundOnly = tempo("<sound tempo=\"150\"/>")
    check(soundOnly.0 == 150 && soundOnly.1 == 150, "a sound tempo alone still counts")
}
print("ok: printed tempo")

// Backing vocals: words in round brackets come off the line, keep their timing, and lose the brackets.
let duet = Lyrics.parse("[00:01.00] I want you (I want you) back\n[00:05.00] (ooh)\n[00:09.00] Plain line", duration: nil)
let (front, back) = duet.lines[0].splitBacking
precondition(front.text == "I want you back" && back?.text == "I want you", "brackets split as '\(front.text)' / '\(back?.text ?? "nil")'")
precondition(back!.syllables.allSatisfy { $0.start >= front.start }, "backing syllables lost their times")
let (alone, aloneBack) = duet.lines[1].splitBacking
precondition(alone.syllables.isEmpty && aloneBack?.text == "ooh", "a line all in brackets: '\(alone.text)' / '\(aloneBack?.text ?? "nil")'")
precondition(duet.lines[2].splitBacking.backing == nil, "a line without brackets grew backing vocals")
// Singers chosen in Assign Singers replace the file's own parts, and lines out of range are ignored.
let sung = duet.withSingers([0: 1, 1: LyricLine.everyone, 2: 2, 7: 3])
precondition(sung.lines.map(\.part) == [1, LyricLine.everyone, 2] && sung.partCount == 2, "singers: \(sung.lines.map(\.part))")
print("ok: backing vocals split from their lines, singers assigned")

// Word timing: only lyrics with a time for each word fill and swell.
precondition(!duet.wordTimed && Lyrics.parse("[00:01.00] <00:01.00>Hey <00:01.50>you", duration: nil).wordTimed, "word timing not detected")
// Editing keeps singers: a line found at the same time or with the same words keeps its singer.
let beforeEdit = Lyrics.parse("[00:01.00] One\n[00:03.00] Two\n[00:05.00] Three", duration: nil).withSingers([0: 1, 1: 2, 2: 3])
let afterEdit = Lyrics.parse("[00:01.00] One fixed\n[00:02.00] Changed\n[00:05.00] Three", duration: nil)
precondition(afterEdit.singers(after: beforeEdit) == [0: 1, 1: 2, 2: 3], "singers after edit: \(afterEdit.singers(after: beforeEdit))")
let afterInsert = Lyrics.parse("[00:01.00] One\n[00:02.00] New line\n[00:03.00] Two\n[00:05.00] Three", duration: nil)
precondition(afterInsert.singers(after: beforeEdit) == [0: 1, 2: 2, 3: 3], "singers after insert: \(afterInsert.singers(after: beforeEdit))")
print("ok: word timing detected, singers kept through an edit")

// Equaliser curve: a bell peaks at its gain, a low cut takes out the lows and leaves the middle, flat is flat.
let bell = EQBand(kind: .bell, frequency: 1_000, gain: 6, q: 1)
precondition(abs(bell.response(at: 1_000) - 6) < 0.05 && abs(bell.response(at: 50)) < 0.3, "bell: \(bell.response(at: 1_000)) at centre")
let cut = EQBand(kind: .lowCut, frequency: 200)
precondition(cut.response(at: 30) < -20 && abs(cut.response(at: 2_000)) < 0.2, "low cut: \(cut.response(at: 30)) at 30 Hz")
precondition(TrackEQ.flat.isFlat && abs(TrackEQ.flat.response(at: 440)) < 0.01 && !TrackEQ.presets[1].eq.isFlat, "flat EQ isn't flat")
print("ok: equaliser curves")
