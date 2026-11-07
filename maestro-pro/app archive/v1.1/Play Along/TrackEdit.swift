import Foundation

// Edits to a backing track, kept beside it as keyframe lanes. They change how the recording plays, never the file.

nonisolated struct Keyframe: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Seconds into the recording.
    var time: Double
    var value: Double
    /// How the line leaves this keyframe for the next: 0 is straight, above 0 starts slowly and finishes quickly,
    /// below 0 starts quickly and settles. `smooth` eases both ends (an S).
    var curve = 0.0
    var smooth = false

    init(time: Double, value: Double, curve: Double = 0, smooth: Bool = false) {
        self.time = time; self.value = value; self.curve = curve; self.smooth = smooth
    }

    // Files saved before curves existed have neither field.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        time = try c.decode(Double.self, forKey: .time)
        value = try c.decode(Double.self, forKey: .value)
        curve = try c.decodeIfPresent(Double.self, forKey: .curve) ?? 0
        smooth = try c.decodeIfPresent(Bool.self, forKey: .smooth) ?? false
    }

    /// Where along the way (0…1) the line has got to when the time is `f` of the way between keyframes.
    func shaped(_ f: Double) -> Double {
        let f = max(0, min(1, f))
        if smooth { return f * f * (3 - 2 * f) }
        if curve > 0 { return pow(f, 1 + 3 * curve) }
        if curve < 0 { return 1 - pow(1 - f, 1 - 3 * curve) }
        return f
    }
}

nonisolated enum Lane: String, CaseIterable, Identifiable {
    case tempo = "Tempo", volume = "Volume", pitch = "Pitch"
    var id: String { rawValue }

    var range: ClosedRange<Double> {
        switch self {
        case .tempo: 0.5...2.0
        case .volume: 0...1
        case .pitch: -12...12
        }
    }
    var neutral: Double { switch self { case .tempo: 1; case .volume: 1; case .pitch: 0 } }
    var symbol: String { switch self { case .tempo: "gauge.with.dots.needle.33percent"; case .volume: "speaker.wave.2"; case .pitch: "tuningfork" } }

    func label(_ v: Double) -> String {
        switch self {
        case .tempo: "\(Int((v * 100).rounded()))%"
        case .volume: v <= 0.005 ? "Off" : "\(Int((v * 100).rounded()))%"
        case .pitch: v == 0 ? "0" : String(format: "%+.1f st", v)
        }
    }
}

nonisolated struct TrackEdit: Codable, Equatable {
    /// Playback speed as a multiple of the recording's, where it plays.
    var tempo: [Keyframe] = []
    /// Level, 0 (silent) to 1 (as recorded).
    var volume: [Keyframe] = []
    /// Semitones up or down.
    var pitch: [Keyframe] = []

    var isEmpty: Bool { tempo.isEmpty && volume.isEmpty && pitch.isEmpty }

    subscript(lane: Lane) -> [Keyframe] {
        get { switch lane { case .tempo: tempo; case .volume: volume; case .pitch: pitch } }
        set {
            let sorted = newValue.sorted { $0.time < $1.time }
            switch lane { case .tempo: tempo = sorted; case .volume: volume = sorted; case .pitch: pitch = sorted }
        }
    }

    /// The lane's value at a time: straight or curved lines between keyframes, held flat before the first and after the last.
    static func value(_ frames: [Keyframe], at t: Double, neutral: Double) -> Double {
        guard let first = frames.first, let last = frames.last else { return neutral }
        if t <= first.time { return first.value }
        if t >= last.time { return last.value }
        var lo = 0, hi = frames.count - 1
        while hi - lo > 1 { let mid = (lo + hi) / 2; if frames[mid].time <= t { lo = mid } else { hi = mid } }
        let a = frames[lo], b = frames[hi]
        let f = (t - a.time) / max(b.time - a.time, 0.0001)
        return a.value + (b.value - a.value) * a.shaped(f)
    }

    func value(_ lane: Lane, at t: Double) -> Double { Self.value(self[lane], at: t, neutral: lane.neutral) }
}
