import Accelerate
import AVFoundation

/// Tempo and key of a recording, so the score can be matched to its backing track.
/// Tempo: onset strength (spectral flux) autocorrelated over many beats, which pins the beat to a
/// hundredth of a BPM on a steady track. Key: the track's pitch-class profile against Krumhansl's
/// major and minor key profiles.
/// ponytail: one tempo for the whole track; a recording that speeds up or slows down gets its average.
nonisolated struct TrackAnalysis: Sendable {
    var bpm: Double
    var tonic: Int      // pitch class, 0 = C
    var minor: Bool

    /// The key signature of the detected key, in fifths (relative major and minor share one).
    var fifths: Int { ParsedScore.transposedKey(0, by: minor ? (tonic + 3) % 12 : tonic) }
    var keyName: String { ParsedScore.keyName(fifths, minor: minor) }

    /// The track's tempo as the score counts it: the beat-level reading, halved or doubled toward `near`.
    func tempo(near current: Double) -> Double {
        [bpm / 2, bpm, bpm * 2].min { abs(log($0 / current)) < abs(log($1 / current)) }!
    }

    /// Semitones that move a score in `scoreFifths` to the track's key signature (−5…6, the shorter way).
    func transposition(fromFifths scoreFifths: Int) -> Int {
        let n = (7 * (fifths - scoreFifths)).mod(12)   // 7 is its own inverse mod 12: fifths → semitones
        return n > 6 ? n - 12 : n
    }

    static func load(_ url: URL) -> TrackAnalysis? {
        guard let file = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buf)) != nil, let data = buf.floatChannelData else { return nil }
        let n = Int(buf.frameLength), channels = Int(buf.format.channelCount)
        var mono = [Float](UnsafeBufferPointer(start: data[0], count: n))
        for c in 1..<max(1, channels) { vDSP.add(mono, UnsafeBufferPointer(start: data[c], count: n), result: &mono) }
        return analyse(mono, rate: file.processingFormat.sampleRate)
    }

    static func analyse(_ x: [Float], rate: Double) -> TrackAnalysis? {
        let size = 4096, hop = 512, half = size / 2
        guard x.count > size * 8, let fft = vDSP.FFT(log2n: 12, radix: .radix2, ofType: DSPSplitComplex.self) else { return nil }
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        // Pitch class of each FFT bin in the range where a 4096-point FFT still separates semitones.
        let pcOfBin: [Int?] = (0..<half).map { (k: Int) -> Int? in
            let f = Double(k) * rate / Double(size)
            guard f >= 180, f <= 2500 else { return nil }
            let midi: Double = 12 * log2(f / 440) + 69
            return Int(midi.rounded()).mod(12)
        }
        var flux: [Float] = [], chroma = [Double](repeating: 0, count: 12)
        var prev = [Float](repeating: 0, count: half)
        var re = [Float](repeating: 0, count: half), im = re, mags = re
        for start in stride(from: 0, to: x.count - size, by: hop) {
            let frame = vDSP.multiply(x[start..<start + size], window)
            re.withUnsafeMutableBufferPointer { r in im.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                frame.withUnsafeBufferPointer { $0.withMemoryRebound(to: DSPComplex.self) { vDSP_ctoz($0.baseAddress!, 2, &split, 1, vDSP_Length(half)) } }
                fft.forward(input: split, output: &split)
                vDSP.absolute(split, result: &mags)
            } }
            let logm = mags.map { log1p($0) }
            flux.append(zip(logm, prev).reduce(0) { $0 + max(0, $1.0 - $1.1) })
            prev = logm
            for k in 0..<half { if let pc = pcOfBin[k] { chroma[pc] += Double(mags[k]) } }
        }
        guard let bpm = tempo(flux, framesPerSecond: rate / Double(hop)) else { return nil }
        let (tonic, minor) = key(chroma)
        return TrackAnalysis(bpm: bpm, tonic: tonic, minor: minor)
    }

    /// Beats per minute from an onset-strength envelope.
    static func tempo(_ flux: [Float], framesPerSecond fr: Double) -> Double? {
        // Onsets stand out from a half-second running mean; only rises count.
        let w = max(1, Int(fr / 2)), n = flux.count
        var sums = [Float](repeating: 0, count: n + 1)
        for i in 0..<n { sums[i + 1] = sums[i] + flux[i] }
        let env: [Float] = (0..<n).map { i in
            let a = max(0, i - w), b = min(n, i + w + 1)
            return max(0, flux[i] - (sums[b] - sums[a]) / Float(b - a))
        }
        let maxLag = min(n - 1, Int(60 * fr / 50 * 32))   // 32 beats at the slowest tempo considered
        guard maxLag > Int(60 * fr / 50) * 4 else { return nil }
        let ac: [Double] = (0...maxLag).map { lag in
            Double(vDSP.dot(env[0..<(n - lag)], env[lag..<n])) / Double(n - lag)
        }
        func at(_ l: Double) -> Double {
            let i = Int(l), t = l - Double(i)
            return i + 1 > maxLag ? 0 : ac[i] * (1 - t) + ac[i + 1] * t
        }
        // Coarse: the beat whose first few multiples line up best, gently favouring moderate tempos.
        func score(_ bpm: Double, beats: Int) -> Double {
            let p = 60 * fr / bpm
            return (1...beats).reduce(0) { $0 + ($1 * Int(p) < maxLag ? at(Double($1) * p) : 0) }
        }
        let coarse = stride(from: 50.0, through: 220, by: 0.25).max { a, b in
            let prior = { (x: Double) in exp(-0.5 * pow(log2(x / 110), 2)) }
            return score(a, beats: 8) * prior(a) < score(b, beats: 8) * prior(b)
        }!
        // Fine: the far multiples are sharp, so they set the exact value.
        return stride(from: coarse * 0.985, through: coarse * 1.015, by: 0.005).max { score($0, beats: 32) < score($1, beats: 32) }
            .map { ($0 * 100).rounded() / 100 }
    }

    /// Tonic and mode whose Krumhansl–Kessler profile correlates best with the pitch-class profile.
    static func key(_ chroma: [Double]) -> (tonic: Int, minor: Bool) {
        let major = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        let minor = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
        func r(_ a: [Double], _ b: [Double]) -> Double {
            let ma = a.reduce(0, +) / 12, mb = b.reduce(0, +) / 12
            let num = zip(a, b).reduce(0) { $0 + ($1.0 - ma) * ($1.1 - mb) }
            let den = sqrt(a.reduce(0) { $0 + ($1 - ma) * ($1 - ma) } * b.reduce(0) { $0 + ($1 - mb) * ($1 - mb) })
            return den > 0 ? num / den : 0
        }
        var best = (score: -2.0, tonic: 0, minor: false)
        for t in 0..<12 {
            let rotated = (0..<12).map { chroma[(t + $0) % 12] }
            for (profile, isMinor) in [(major, false), (minor, true)] {
                let s = r(rotated, profile)
                if s > best.score { best = (s, t, isMinor) }
            }
        }
        return (best.tonic, best.minor)
    }
}
