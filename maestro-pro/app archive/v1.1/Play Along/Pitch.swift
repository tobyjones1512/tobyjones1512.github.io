import Accelerate
import Foundation

// Pitch maths with no audio or UI in it: finding the note in a sound (YIN), judging whether it is the note the score
// wants held for long enough, and working a tempo out from taps. Checked in Checks/main.swift.

nonisolated enum Pitch {
    static let names = ["C", "D♭", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

    /// MIDI note number (fractional) of a frequency; `a4` is the tuning of the A above middle C.
    static func midi(_ hz: Double, a4: Double = 440) -> Double { 69 + 12 * log2(hz / a4) }
    static func hz(_ midi: Double, a4: Double = 440) -> Double { a4 * pow(2, (midi - 69) / 12) }
    static func name(_ midi: Int) -> String { names[midi.mod(12)] + String(midi.floorDiv(12) - 1) }
    static func letter(_ midi: Int) -> String { names[midi.mod(12)] }

    /// The fundamental of a short stretch of sound (YIN: de Cheveigné and Kawahara, 2002), or nil when it isn't clearly pitched.
    /// `clarity` is 0...1. The stretch must be longer than a period of `minHz` plus 512 samples.
    static func detect(_ x: [Float], rate: Double, minHz: Double = 40, maxHz: Double = 2000) -> (hz: Double, clarity: Double)? {
        let tauMax = Int(rate / minHz) + 1, tauMin = max(2, Int(rate / maxHz))
        let w = x.count - tauMax
        guard w >= 512, tauMax > tauMin + 2 else { return nil }
        var d = [Float](repeating: 0, count: tauMax)
        var diff = [Float](repeating: 0, count: w)
        x.withUnsafeBufferPointer { p in
            for tau in 1..<tauMax {
                vDSP_vsub(p.baseAddress! + tau, 1, p.baseAddress!, 1, &diff, 1, vDSP_Length(w))
                var s: Float = 0
                vDSP_svesq(diff, 1, &s, vDSP_Length(w))
                d[tau] = s
            }
        }
        // Cumulative mean normalised difference: a dip near 0 marks a period.
        var running: Float = 0
        d[0] = 1
        for tau in 1..<tauMax { running += d[tau]; d[tau] = running > 0 ? d[tau] * Float(tau) / running : 1 }
        var found = -1, tau = tauMin
        while tau < tauMax - 1 {
            if d[tau] < 0.15 {
                while tau + 1 < tauMax - 1, d[tau + 1] < d[tau] { tau += 1 }
                found = tau
                break
            }
            tau += 1
        }
        if found < 0 {
            guard let m = (tauMin..<tauMax - 1).min(by: { d[$0] < d[$1] }), d[m] < 0.3 else { return nil }
            found = m
        }
        let a = d[found - 1], b = d[found], c = d[found + 1]
        let denom = a - 2 * b + c
        let t = Double(found) + (denom != 0 ? Double(0.5 * (a - c) / denom) : 0)
        guard t > 0 else { return nil }
        return (rate / t, Double(max(0, 1 - b)))
    }
}

/// Decides whether what is being played is the note asked for: right pitch (within the tolerance), held long enough.
nonisolated struct NoteJudge {
    enum Verdict: Equatable {
        case silent                    // nothing playing, or still sounding the previous note
        case good(progress: Double)    // right note and in tune, so many tenths of the way through the hold
        case off(cents: Double)        // the right note, too sharp (+) or flat (-)
        case wrong(heard: Double)      // a different note (MIDI, fractional)
        case done
    }

    /// How far from the note counts as in tune, in semitones.
    var tolerance = 0.3
    /// Count the note in any octave (for voices and instruments that can't reach it).
    var anyOctave = false
    /// How much of the written length has to be held.
    var holdFraction = 0.8

    private(set) var pitches: [Int] = []
    private(set) var required = 0.3
    private(set) var held = 0.0
    private var gap = 0.0, armed = true, last: Double?
    private var previous: [Int] = []
    private(set) var goodTime = 0.0, badTime = 0.0, deviationSum = 0.0, deviationCount = 0

    /// How well the notes went: time spent right and in tune against time spent playing something else.
    var accuracy: Double { goodTime + badTime > 0 ? goodTime / (goodTime + badTime) : 1 }
    /// The average distance from the note when it was right, in cents.
    var averageCents: Double { deviationCount > 0 ? deviationSum / Double(deviationCount) * 100 : 0 }

    /// Ask for a new note (any of `pitches`, as a chord allows), to be held for `seconds`.
    mutating func aim(at pitches: [Int], seconds: Double) {
        previous = self.pitches
        self.pitches = pitches
        required = max(0.15, seconds * holdFraction)
        held = 0; gap = 0; last = nil
        armed = previous.isEmpty
    }

    mutating func resetScore() { goodTime = 0; badTime = 0; deviationSum = 0; deviationCount = 0 }

    func offset(_ midi: Double, from p: Int) -> Double {
        var d = midi - Double(p)
        if anyOctave { d -= 12 * (d / 12).rounded() }
        return d
    }

    /// The signed distance, in semitones, from the closest of the wanted notes.
    func nearest(_ midi: Double) -> Double? { pitches.map { offset(midi, from: $0) }.min { abs($0) < abs($1) } }

    mutating func feed(_ midi: Double?, at time: Double) -> Verdict {
        let dt = min(0.2, last.map { max(0, time - $0) } ?? 0)
        last = time
        guard !pitches.isEmpty else { return .silent }
        guard let midi else {
            gap += dt
            if gap > 0.2 { held = 0 }
            armed = true
            return .silent
        }
        // A repeated note needs a fresh start: the last one has to stop (or move away) before this one counts.
        if !armed, previous.allSatisfy({ abs(offset(midi, from: $0)) > tolerance }) { armed = true }
        guard armed, let d = nearest(midi) else { return .silent }
        if abs(d) <= tolerance {
            held += dt; gap = 0
            goodTime += dt; deviationSum += abs(d); deviationCount += 1
            return held >= required ? .done : .good(progress: held / required)
        }
        badTime += dt; gap += dt
        if gap > 0.2 { held = 0 }
        return abs(d) < 1 ? .off(cents: d * 100) : .wrong(heard: midi)
    }
}

/// Works a tempo out from taps in time with the beat.
nonisolated struct TapTempo {
    private(set) var times: [Double] = []
    var count: Int { times.count }

    /// Records a tap; the tempo (beats a minute) from the second tap, steadier with each one. A pause of more than 2.5 s starts again.
    mutating func tap(at t: Double) -> Double? {
        if let last = times.last, t - last > 2.5 { times = [] }
        times = Array((times + [t]).suffix(9))
        guard times.count >= 2 else { return nil }
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
        let med = gaps.sorted()[gaps.count / 2]
        let steady = gaps.filter { abs($0 - med) < med * 0.35 }   // one stumble doesn't move the answer
        return 60 / (steady.reduce(0, +) / Double(steady.count))
    }

    mutating func reset() { times = [] }
}

/// Cuts the incoming sound into overlapping stretches and finds the pitch of each.
nonisolated final class PitchAnalyzer: @unchecked Sendable {
    private var window: [Float] = []
    private var sinceLast = 0
    private let rate: Double, gate: Float
    private let size = 4096, hop = 1024

    init(rate: Double, gate: Float) { self.rate = rate; self.gate = gate }

    /// Pitches found in the new samples; `age` is how long ago (seconds) the stretch ended, so frames get honest times.
    func process(_ samples: UnsafeBufferPointer<Float>) -> [(hz: Double?, level: Double, age: Double)] {
        var out: [(hz: Double?, level: Double, age: Double)] = []
        var idx = 0
        while idx < samples.count {
            let take = min(hop - sinceLast, samples.count - idx)
            window.append(contentsOf: samples[idx..<idx + take])
            idx += take; sinceLast += take
            if window.count > size { window.removeFirst(window.count - size) }
            // A full hop of new sound has arrived. (This count restarts even while the window is still filling; if it didn't, the next
            // slice would be zero long and this loop would never end, which froze the audio thread and took the app down with it.)
            guard sinceLast >= hop else { continue }
            sinceLast = 0
            guard window.count == size else { continue }
            var rms: Float = 0
            for v in window.suffix(2048) { rms += v * v }
            rms = (rms / 2048).squareRoot()
            let hit = rms >= gate ? Pitch.detect(window, rate: rate) : nil
            out.append((hit.flatMap { $0.clarity >= 0.75 ? $0.hz : nil }, Double(min(1, Double(rms).squareRoot() * 3)), Double(samples.count - idx) / rate))
        }
        return out
    }
}
