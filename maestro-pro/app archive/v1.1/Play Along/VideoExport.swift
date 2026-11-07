import AVFoundation
import CoreGraphics
import CoreText
import PencilKit
import UIKit

// Exports the score as a landscape MP4: the system being played, big, with the chosen highlights (notes, bar,
// moving line) and any pencil annotations, plus the backing track and the instrument if one is chosen.
// ponytail: plays at normal speed (practice speed isn't applied), and shows the current system plus the next
// if it fits. Add a "two systems" or full-page layout if asked.

nonisolated struct VideoOptions {
    var title: String
    var dark: Bool
    var notes: Bool, bar: Bool, line: Bool
    var tint: CGColor, ink: CGColor, paper: CGColor, stage: CGColor
    var tempo: Double
    var track: URL?, trackOffset: Double, trackSemitones: Int
    var instrument: Instrument, staffInstruments: [Instrument?] = [], soundingShift: Int, volume: Float
    var drawings: [Int: PKDrawing]
}

nonisolated enum VideoExport {
    static let size = CGSize(width: 1920, height: 1080), fps = 30.0, margin: CGFloat = 80

    enum Failure: LocalizedError {
        case nothing, writer(String)
        var errorDescription: String? {
            switch self { case .nothing: "There’s nothing to export yet."; case .writer(let m): "The video couldn’t be written. \(m)" }
        }
    }

    static func export(pages: [CGPDFPage], timeline: Timeline, start: Double, options o: VideoOptions, progress: @Sendable (Double) -> Void) async throws -> URL {
        Analytics.track("export_video")
        guard !timeline.measures.isEmpty, !timeline.systems.isEmpty else { throw Failure.nothing }
        let seconds = (timeline.length - start) * 60 / o.tempo + 1
        let dir = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let videoURL = dir.appending(path: "video.mp4"), audioURL = dir.appending(path: "audio.m4a")
        try await renderVideo(pages: pages, timeline: timeline, start: start, seconds: seconds, options: o, to: videoURL, progress: progress)
        let hasAudio = try renderAudio(timeline: timeline, start: start, seconds: seconds, options: o, to: audioURL)
        let name = o.title.replacingOccurrences(of: "/", with: "-")
        let final = dir.appending(path: "\(name.isEmpty ? "Maestro Pro" : name).mp4")
        guard hasAudio else { try FileManager.default.moveItem(at: videoURL, to: final); return final }
        // Join picture and sound.
        let comp = AVMutableComposition()
        let v = AVURLAsset(url: videoURL), a = AVURLAsset(url: audioURL)
        if let vt = try await v.loadTracks(withMediaType: .video).first, let ct = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try ct.insertTimeRange(CMTimeRange(start: .zero, duration: try await v.load(.duration)), of: vt, at: .zero)
        }
        if let at = try await a.loadTracks(withMediaType: .audio).first, let ct = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let d = min(try await a.load(.duration), try await v.load(.duration))
            try ct.insertTimeRange(CMTimeRange(start: .zero, duration: d), of: at, at: .zero)
        }
        guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else { throw Failure.writer("No exporter.") }
        do { try await session.export(to: final, as: .mp4) } catch { throw Failure.writer(error.localizedDescription) }
        return final
    }

    // MARK: Picture

    private final class Strips {
        let pages: [CGPDFPage], timeline: Timeline, o: VideoOptions, scale: CGFloat
        var paper: [Int: CGImage] = [:], ink: [Int: CGImage] = [:], pageInk: [Int: CGImage] = [:]
        init(pages: [CGPDFPage], timeline: Timeline, o: VideoOptions) {
            self.pages = pages; self.timeline = timeline; self.o = o
            let widest = timeline.systems.map(\.rect.width).max() ?? 500
            scale = min(4.5, (VideoExport.size.width - 2 * VideoExport.margin) / widest)
        }

        func rect(_ i: Int) -> CGRect { timeline.systems[i].rect }
        func height(_ i: Int) -> CGFloat { rect(i).height * scale }

        func paperImage(_ i: Int) -> CGImage? {
            if let c = paper[i] { return c }
            let sys = timeline.systems[i], page = pages[sys.page]
            let w = Int(sys.rect.width * scale), h = Int(sys.rect.height * scale)
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
            ctx.setFillColor(o.dark ? CGColor(gray: 1, alpha: 1) : o.paper)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: -sys.rect.minX * scale, y: -sys.rect.minY * scale)
            page.draw(in: ctx, size: CGSize(width: page.size.width * scale, height: page.size.height * scale))
            if o.dark {   // white music on black paper, like the app
                ctx.setBlendMode(.difference)
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                ctx.fill(CGRect(x: -10_000, y: -10_000, width: 40_000, height: 40_000))
            }
            let img = ctx.makeImage()
            paper[i] = img
            return img
        }

        /// Where the system has ink (bright), for tinting the sounding notes.
        func inkImage(_ i: Int) -> CGImage? {
            if let c = ink[i] { return c }
            let sys = timeline.systems[i], page = pages[sys.page]
            if pageInk[sys.page] == nil { pageInk[sys.page] = inkMask(page, pixelWidth: Int(page.size.width * scale)) }   // ink bright, like a luminance mask
            let crop = pageInk[sys.page]?.cropping(to: CGRect(x: sys.rect.minX * scale, y: sys.rect.minY * scale, width: sys.rect.width * scale, height: sys.rect.height * scale))
            ink[i] = crop
            return crop
        }

        func trim(keeping keep: Set<Int>) {
            for k in paper.keys where !keep.contains(k) { paper[k] = nil; ink[k] = nil }
        }
    }

    private static func renderVideo(pages: [CGPDFPage], timeline: Timeline, start: Double, seconds: Double, options o: VideoOptions, to url: URL, progress: @Sendable (Double) -> Void) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        guard writer.startWriting() else { throw Failure.writer(writer.error?.localizedDescription ?? "") }
        writer.startSession(atSourceTime: .zero)
        let strips = Strips(pages: pages, timeline: timeline, o: o)
        let frames = Int(seconds * fps)
        for f in 0..<frames {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(4)) }
            guard let pool = adaptor.pixelBufferPool else { throw Failure.writer("No buffer pool.") }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard let pb else { throw Failure.writer("Out of memory.") }
            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                draw(frame: ctx, beat: start + Double(f) / fps * o.tempo / 60, timeline: timeline, strips: strips, o: o)
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps)))
            if f % 15 == 0 { progress(Double(f) / Double(frames) * 0.8) }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw Failure.writer(writer.error?.localizedDescription ?? "") }
    }

    private static func draw(frame ctx: CGContext, beat: Double, timeline t: Timeline, strips: Strips, o: VideoOptions) {
        let W = size.width, H = size.height, s = strips.scale
        ctx.setFillColor(o.stage)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.translateBy(x: 0, y: H)   // from here, y runs down
        ctx.scaleBy(x: 1, y: -1)
        let mi = t.measureIndex(at: max(0, beat)) ?? 0
        let m = t.measures[mi]
        let cur = m.system
        // The playing system, with the next below it when both fit.
        var shown = [cur]
        if cur + 1 < t.systems.count, strips.height(cur) + strips.height(cur + 1) + 60 <= H - 2 * margin { shown.append(cur + 1) }
        let total = shown.map(strips.height).reduce(0, +) + CGFloat(shown.count - 1) * 60
        var y = (H - total) / 2
        strips.trim(keeping: Set(shown))
        for i in shown {
            let sys = t.systems[i], x = (W - sys.rect.width * s) / 2, h = strips.height(i)
            let r = CGRect(x: x, y: y, width: sys.rect.width * s, height: h)
            defer { y += h + 60 }
            guard let paper = strips.paperImage(i) else { continue }
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil))
            ctx.clip()
            image(ctx, paper, in: r)
            if i == cur {
                if o.bar {
                    ctx.setFillColor(o.tint.copy(alpha: o.dark ? 0.2 : 0.16)!)
                    ctx.fill(CGRect(x: x + (m.x0 - sys.rect.minX) * s, y: y, width: (m.x1 - m.x0) * s, height: h))
                }
                if o.notes, let ink = strips.inkImage(i) {
                    for n in t.notes where !n.isRest && n.page == sys.page && beat >= n.start && beat < n.end && n.rect.intersects(sys.rect) {
                        for part in [n.rect.insetBy(dx: n.rect.width * 0.12, dy: n.rect.height * 0.16)] + (n.stem.map { [$0] } ?? []) {
                            let box = CGRect(x: x + (part.minX - sys.rect.minX) * s, y: y + (part.minY - sys.rect.minY) * s, width: part.width * s, height: part.height * s)
                            ctx.saveGState()
                            ctx.clip(to: box)
                            clip(ctx, mask: ink, in: r)
                            ctx.setFillColor(o.dark ? o.tint : o.ink)
                            ctx.fill(box)
                            ctx.restoreGState()
                        }
                    }
                }
            }
            // Pencil annotations.
            if let d = o.drawings[sys.page], !d.strokes.isEmpty {
                let img = d.image(from: sys.rect, scale: s)
                if let cg = img.cgImage { image(ctx, cg, in: r) }
            }
            ctx.restoreGState()
            if i == cur, o.line {
                let px = x + (m.x(at: beat) - sys.rect.minX) * s
                ctx.setFillColor(o.tint)
                ctx.fill(CGRect(x: px - 2, y: y, width: 4, height: h))
                ctx.setShadow(offset: .zero, blur: 12, color: o.tint)
                ctx.fill(CGRect(x: px - 1.5, y: y, width: 3, height: h))
                ctx.setShadow(offset: .zero, blur: 0)
            }
        }
        // Bar counter and title.
        let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 34, nil)
        label("\(o.title)", font, at: CGPoint(x: margin, y: 30), ctx: ctx, color: CGColor(gray: 1, alpha: 0.6))
        label("Bar \(m.bar + 1)", font, at: CGPoint(x: W - margin - 130, y: 30), ctx: ctx, color: o.tint)
    }

    /// Draws an image into a top-left-origin context.
    private static func image(_ ctx: CGContext, _ img: CGImage, in r: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
        ctx.restoreGState()
    }

    private static func clip(_ ctx: CGContext, mask: CGImage, in r: CGRect) {
        // clip(to:mask:) is bottom-left origin; flip around the rect.
        ctx.translateBy(x: 0, y: r.minY + r.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.clip(to: r, mask: mask)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: 0, y: -(r.minY + r.maxY))
    }

    private static func label(_ text: String, _ font: CTFont, at p: CGPoint, ctx: CGContext, color: CGColor) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): color]))
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: p.x, y: p.y + 30)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: Sound

    /// The backing track and instrument mixed to a file. False if there's nothing to hear.
    private static func renderAudio(timeline: Timeline, start: Double, seconds: Double, options o: VideoOptions, to url: URL) throws -> Bool {
        let rate = 44_100.0, total = AVAudioFramePosition(seconds * rate)
        let trackFile = o.track.flatMap { try? AVAudioFile(forReading: $0) }
        let events = timeline.notes.compactMap { n -> (start: Double, seconds: Double, pitch: Int, instrument: Instrument, velocity: Float)? in
            let voice = (n.staff < o.staffInstruments.count ? o.staffInstruments[n.staff] : nil) ?? o.instrument
            guard let pitch = n.pitch, voice != .off else { return nil }
            return ((n.sounds - start) * 60 / o.tempo, n.duration * 60 / o.tempo, pitch - o.soundingShift, voice, Float(n.velocity))
        }
        let synth = events.isEmpty ? nil : Synth.renderOffline(events, volume: o.volume, total: seconds)
        guard trackFile != nil || synth != nil else { return false }

        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        var players: [AVAudioPlayerNode] = []
        if let file = trackFile {
            let player = AVAudioPlayerNode(), pitch = AVAudioUnitTimePitch()
            pitch.pitch = Float(o.trackSemitones * 100)
            engine.attach(player); engine.attach(pitch)
            engine.connect(player, to: pitch, format: file.processingFormat)
            engine.connect(pitch, to: engine.mainMixerNode, format: file.processingFormat)
            let fileRate = file.processingFormat.sampleRate
            if o.trackOffset >= 0 {
                let from = AVAudioFramePosition(o.trackOffset * fileRate)
                if from < file.length { player.scheduleSegment(file, startingFrame: from, frameCount: AVAudioFrameCount(file.length - from), at: nil) }
            } else {
                player.scheduleFile(file, at: AVAudioTime(sampleTime: AVAudioFramePosition(-o.trackOffset * rate), atRate: rate))
            }
            players.append(player)
        }
        if let synth {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: synth.format)
            player.scheduleBuffer(synth, at: nil)
            players.append(player)
        }
        try engine.start()
        players.forEach { $0.play() }
        let out = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000],
                                  commonFormat: .pcmFormatFloat32, interleaved: false)
        let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
        while engine.manualRenderingSampleTime < total {
            let n = AVAudioFrameCount(min(4096, total - engine.manualRenderingSampleTime))
            guard try engine.renderOffline(n, to: buf) != .error else { break }
            try out.write(from: buf)
        }
        engine.stop()
        return true
    }
}
