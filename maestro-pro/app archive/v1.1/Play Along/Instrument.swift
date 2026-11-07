import CoreAudio
import AVFoundation
import Foundation
import os

// A small additive synthesiser, so the score can be played back on a chosen instrument with no sample
// files to ship. Each instrument is a harmonic recipe and an envelope.
// ponytail: no stereo spread, no reverb. Loudness follows the printed dynamics (a velocity per note) and each staff can
// have its own voice (Bass, Piano…). Add a
// convolution reverb if it needs to sound less synthetic.

nonisolated enum Instrument: String, CaseIterable, Identifiable {
    case off = "Off", piano = "Piano / Keyboard", organ = "Organ", guitar = "Acoustic Guitar", bass = "Bass"
    case flute = "Flute", clarinet = "Clarinet", altoSax = "Alto Saxophone", tenorSax = "Tenor Saxophone", trumpet = "Trumpet"

    var id: String { rawValue }

    struct Voicing {
        var harmonics: [Float]
        var attack: Float = 0.01
        var decay: Float?          // pluck/strike: seconds to fall by 1/e; nil = held at full level
        var release: Float = 0.12
        var vibrato: Float = 0     // fraction of pitch
    }

    var voicing: Voicing {
        switch self {
        case .off, .piano: Voicing(harmonics: [1, 0.55, 0.38, 0.22, 0.13, 0.08, 0.05, 0.03], attack: 0.004, decay: 1.8, release: 0.25)
        case .organ: Voicing(harmonics: [1, 1, 0.8, 0.6, 0.4, 0.3, 0.2, 0.15], attack: 0.012, release: 0.07)
        case .guitar: Voicing(harmonics: [1, 0.6, 0.3, 0.15, 0.1, 0.05], attack: 0.002, decay: 1.0, release: 0.15)
        case .bass: Voicing(harmonics: [1, 0.75, 0.4, 0.22, 0.12, 0.06], attack: 0.008, decay: 1.2, release: 0.22)
        case .flute: Voicing(harmonics: [1, 0.25, 0.08, 0.03], attack: 0.06, release: 0.1, vibrato: 0.005)
        case .clarinet: Voicing(harmonics: [1, 0, 0.5, 0, 0.3, 0, 0.2, 0, 0.1], attack: 0.04, release: 0.08)
        case .altoSax: Voicing(harmonics: [1, 0.85, 0.6, 0.5, 0.35, 0.25, 0.15, 0.1], attack: 0.03, release: 0.09, vibrato: 0.004)
        case .tenorSax: Voicing(harmonics: [1, 0.9, 0.55, 0.4, 0.25, 0.15, 0.1, 0.05], attack: 0.035, release: 0.1, vibrato: 0.004)
        case .trumpet: Voicing(harmonics: [1, 0.9, 0.8, 0.7, 0.55, 0.4, 0.3, 0.2, 0.1], attack: 0.04, release: 0.08)
        }
    }
}

/// How the player's own instrument is pitched: written music sounds this many semitones lower.
nonisolated enum InstrumentKey: String, CaseIterable, Identifiable {
    case concert = "Concert", bFlat = "B♭", eFlat = "E♭", tenor = "B♭ Tenor"

    var id: String { rawValue }
    /// Semitones the music is written above where it sounds.
    var offset: Int { switch self { case .concert: 0; case .bFlat: 2; case .eFlat: 9; case .tenor: 14 } }
    var label: String {
        switch self {
        case .concert: "Concert (C)"
        case .bFlat: "B♭ (clarinet, trumpet)"
        case .eFlat: "E♭ (alto sax)"
        case .tenor: "B♭ (tenor sax)"
        }
    }
}

/// Plays notes on request. Safe to call from the main thread while the audio thread renders.
nonisolated final class Synth: @unchecked Sendable {
    private struct Voice {
        var freq: Float, phase: Float = 0, age = 0, held: Int, amp: Float, v: Instrument.Voicing
    }

    private let engine = AVAudioEngine()
    private let rate: Float = 44_100
    private let voices = OSAllocatedUnfairLock(initialState: [Voice]())
    private var node: AVAudioSourceNode?
    var volume: Float = 0.8

    private func start() {
        if node == nil {
            let format = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 2)!
            let node = AVAudioSourceNode(format: format) { [voices, rate] _, _, frames, list in
                let out = UnsafeMutableAudioBufferListPointer(list)
                for ch in out { memset(ch.mData, 0, Int(ch.mDataByteSize)) }
                let l = out[0].mData!.assumingMemoryBound(to: Float.self), r = out.count > 1 ? out[1].mData!.assumingMemoryBound(to: Float.self) : l
                voices.withLock { Synth.render(&$0, frames: Int(frames), rate: rate, l: l, r: r) }
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            self.node = node
            // Another sound starting (Apple Music) or a change of audio route can stop the engine: start it again.
            NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
                guard let self else { return }
                try? self.engine.start()
            }
        }
        if !engine.isRunning { try? engine.start() }
    }

    func stop() { voices.withLock { $0.removeAll() } }

    /// Starts a note now. `seconds` is how long it is held before its release.
    func play(_ pitch: Int, seconds: Double, as instrument: Instrument, velocity: Float = 1) {
        guard instrument != .off else { return }
        start()
        let voice = Self.voice(pitch, seconds: seconds, instrument: instrument, volume: volume * velocity, rate: rate)
        voices.withLock { list in
            list.append(voice)
            if list.count > 48 { list.removeFirst(list.count - 48) }
        }
    }

    private static func voice(_ pitch: Int, seconds: Double, instrument: Instrument, volume: Float, rate: Float) -> Voice {
        let freq = 440 * powf(2, Float(pitch - 69) / 12)
        var v = instrument.voicing
        v.decay = v.decay.map { $0 * powf(440 / freq, 0.35) }   // high notes die away sooner
        return Voice(freq: freq, held: max(Int(Float(seconds) * rate), 400), amp: volume * 0.22 / v.harmonics.reduce(0, +).squareRoot(), v: v)
    }

    /// The whole score as audio, for exporting a video. `events` are (start second, held seconds, pitch).
    static func renderOffline(_ events: [(start: Double, seconds: Double, pitch: Int, instrument: Instrument, velocity: Float)], volume: Float, total: Double) -> AVAudioPCMBuffer? {
        let rate: Float = 44_100, block = 512, frames = Int(total * Double(rate))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 2)!, frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        let l = buffer.floatChannelData![0], r = buffer.floatChannelData![1]
        memset(l, 0, frames * 4); memset(r, 0, frames * 4)
        let sorted = events.sorted { $0.start < $1.start }
        var voices: [Voice] = [], next = 0, at = 0
        while at < frames {
            let n = min(block, frames - at)
            while next < sorted.count, sorted[next].start * Double(rate) < Double(at + n) {
                let e = sorted[next]
                voices.append(voice(e.pitch, seconds: e.seconds, instrument: e.instrument, volume: volume * e.velocity, rate: rate))
                next += 1
            }
            render(&voices, frames: n, rate: rate, l: l + at, r: r + at)
            at += n
        }
        return buffer
    }

    private static func render(_ voices: inout [Voice], frames: Int, rate: Float, l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>) {
        guard !voices.isEmpty else { return }
        for i in voices.indices {
            let v = voices[i]
            var phase = v.phase, age = v.age
            let attack = max(Int(v.v.attack * rate), 1), release = max(Int(v.v.release * rate), 1)
            for n in 0..<frames {
                let end = v.held + release
                if age >= end { break }
                var env: Float = age < attack ? Float(age) / Float(attack) : 1
                if let d = v.v.decay { env *= expf(-Float(age) / (d * rate)) }
                if age >= v.held { env *= 1 - Float(age - v.held) / Float(release) }
                let vib = v.v.vibrato > 0 ? 1 + v.v.vibrato * sinf(2 * .pi * 5.5 * Float(age) / rate) * min(1, Float(age) / (0.3 * rate)) : 1
                phase += 2 * .pi * v.freq * vib / rate
                if phase > 2 * .pi { phase -= 2 * .pi }
                var s: Float = 0
                for (h, a) in v.v.harmonics.enumerated() where a > 0 && v.freq * Float(h + 1) < rate / 2 { s += a * sinf(Float(h + 1) * phase) }
                s = tanhf(s * env * v.amp * 2) * 0.5
                l[n] += s
                if r != l { r[n] += s }
                age += 1
            }
            voices[i].phase = phase
            voices[i].age = age
        }
        voices.removeAll { $0.age >= $0.held + max(Int($0.v.release * rate), 1) }
    }
}
