// Check: pitch-shifting (AVAudioUnitTimePitch, as TrackPlayer uses) never changes how long a track plays.
// Run: swiftc Checks/PitchRateCheck.swift -o $CLAUDE_JOB_DIR/tmp/pr && $CLAUDE_JOB_DIR/tmp/pr
import AVFoundation
func run(_ cents: Float, _ rate: Float) -> Double {
    let engine = AVAudioEngine(), node = AVAudioPlayerNode(), tp = AVAudioUnitTimePitch()
    let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    let n = AVAudioFrameCount(44100 * 5)
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!; buf.frameLength = n
    for c in 0..<2 { for i in 0..<Int(n) { buf.floatChannelData![c][i] = sin(Float(i) * 0.05) * 0.5 } }
    engine.attach(node); engine.attach(tp)
    engine.connect(node, to: tp, format: fmt); engine.connect(tp, to: engine.mainMixerNode, format: fmt)
    try! engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 4096)
    tp.pitch = cents; tp.rate = rate
    try! engine.start(); node.scheduleBuffer(buf); node.play()
    let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 4096)!
    var total = 0, lastLoud = 0
    while total < 44100 * 12 {
        _ = try! engine.renderOffline(4096, to: out)
        for i in 0..<Int(out.frameLength) where abs(out.floatChannelData![0][i]) > 0.02 { lastLoud = total + i }
        total += Int(out.frameLength)
    }
    return Double(lastLoud) / 44100
}

let base = run(0, 1)
for c: Float in [500, 1200, -500, -1200] { precondition(abs(run(c, 1) - base) < 0.01, "pitch \(c) changed the speed") }
print("ok")
