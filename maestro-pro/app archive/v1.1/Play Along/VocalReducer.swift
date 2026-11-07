import AVFoundation
import Accelerate

/// Cuts the singer down in a stereo recording: a voice is usually the same in both channels, so playing the difference
/// between the channels removes it (and anything else in the middle). A little of the bass is added back, since the
/// bass and kick are in the middle too. The result is mono.
/// ponytail: this is the old phase-cancelling trick, so it leaves some reverb and takes the middle instruments with it;
/// it can't separate a voice from a mono recording. A stem-separation model would do better but isn't built in.
nonisolated enum VocalReducer {
    /// The name of the copy made from a recording file.
    static func derivedName(_ file: String) -> String { (file as NSString).deletingPathExtension + ".novocals.caf" }

    /// Makes the copy (once). Returns its URL, or nil when the recording isn't stereo or can't be read.
    static func ensure(_ source: URL) async -> URL? {
        let dest = source.deletingLastPathComponent().appending(path: derivedName(source.lastPathComponent))
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        return await Task.detached(priority: .utility) { make(from: source, to: dest) ? dest : nil }.value
    }

    private static func make(from source: URL, to dest: URL) -> Bool {
        guard let input = try? AVAudioFile(forReading: source), input.processingFormat.channelCount >= 2 else { return false }
        let format = input.processingFormat, rate = format.sampleRate
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let temp = dest.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: temp)
        guard let output = try? AVAudioFile(forWriting: temp, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536) else { return false }
        let a = Float(1 - exp(-2 * Double.pi * 140 / rate))   // one-pole low-pass at 140 Hz for the bass
        var bass: Float = 0, bass2: Float = 0   // two poles, so little of the voice's own range gets back in
        while input.framePosition < input.length {
            do { try input.read(into: buffer, frameCount: 65_536) } catch { return false }
            let n = Int(buffer.frameLength)
            guard n > 0, let l = buffer.floatChannelData?[0], let r = buffer.floatChannelData?[1] else { break }
            for i in 0..<n {
                let side = (l[i] - r[i]) * 0.5, mid = (l[i] + r[i]) * 0.5
                bass += a * (mid - bass)
                bass2 += a * (bass - bass2)
                let out = max(-1, min(1, side * 1.5 + bass2))
                l[i] = out; r[i] = out
            }
            do { try output.write(from: buffer) } catch { return false }
        }
        try? FileManager.default.removeItem(at: dest)
        return (try? FileManager.default.moveItem(at: temp, to: dest)) != nil
    }
}
