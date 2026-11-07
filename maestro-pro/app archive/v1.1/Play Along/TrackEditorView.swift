import SwiftUI

/// The backing track as a waveform with keyframe lanes beneath it: tap a lane to add a keyframe, drag one to move it.
/// Speed, level and pitch follow the lines as the track plays, so changes can be heard straight away.
struct TrackEditorView: View {
    let item: ScoreItem
    let transport: Transport
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var edit = TrackEdit()
    @State private var wave: Waveform?
    @State private var zoom = 1.0
    @State private var selected: Selection?
    @State private var undo: [TrackEdit] = []
    @State private var redo: [TrackEdit] = []
    @State private var drag: Drag?

    struct Selection: Equatable { var lane: Lane; var id: UUID }
    struct Drag { var lane: Lane; var id: UUID?; var before: TrackEdit; var moved = false }

    private var duration: Double { max(wave?.duration ?? transport.trackLength ?? 1, 0.1) }
    @State private var laneHeight: CGFloat = 112

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: true) {
                        let width = max(geo.size.width - 40, 300) * zoom
                        VStack(spacing: 14) {
                            waveformView(width: width)
                            ForEach(Lane.allCases) { lane in laneView(lane, width: width) }
                        }
                        .frame(width: width)
                        .overlay(alignment: .topLeading) { Playhead(transport: transport, duration: duration, width: width) }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    controls
                        .padding(.horizontal, 14).padding(.bottom, 10)
                }
                // The three lanes share what the waveform and controls leave.
                .onChange(of: geo.size.height, initial: true) { _, h in
                    let spare: CGFloat = h - 140 - 90 - 70 - 48
                    laneHeight = max(100, min(230, spare / 3))
                }
            }
            .background(StageBackground())
            .navigationTitle("Edit Backing Track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button("Reset All Lanes", systemImage: "arrow.counterclockwise", role: .destructive) { change { $0 = TrackEdit() }; selected = nil }
                    } label: { Label("More", systemImage: "ellipsis.circle") }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { stepHistory(undo: true) } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(undo.isEmpty)
                    Button { stepHistory(undo: false) } label: { Label("Redo", systemImage: "arrow.uturn.forward") }.disabled(redo.isEmpty)
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .task {
            edit = library.trackEdit(item)
            if let url = library.trackURL(item) {
                let w = await Task.detached(priority: .userInitiated) { Waveform.load(url, bins: 1400) }.value
                withAnimation(.smooth) { wave = w }
            }
        }
        .onDisappear { transport.pause() }
        #if DEBUG
        .task {
            guard CommandLine.arguments.contains("-trackeditortest") else { return }
            try? await Task.sleep(for: .seconds(2))
            fade(in: true); slowEnd()
            change { $0.pitch = [Keyframe(time: 0, value: 0), Keyframe(time: 10, value: 2)] }
            transport.seek(toTrackTime: 5)
            transport.play()
            try? await Task.sleep(for: .seconds(1.5))
            let saved = library.trackEdit(item)
            try? "volume \(edit.volume.count) tempo \(edit.tempo.count) pitch \(edit.pitch.count); saved \(saved.volume.count)/\(saved.tempo.count)/\(saved.pitch.count); playing \(transport.isPlaying) at \(transport.trackTime ?? -1); duration \(duration)".write(toFile: "/tmp/track-test.txt", atomically: true, encoding: .utf8)
            transport.pause()
        }
        #endif
    }

    // MARK: Waveform

    private func waveformView(width: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black)
            Canvas { ctx, size in
                if let wave {
                    let bw = size.width / CGFloat(wave.peaks.count)
                    for (i, p) in wave.peaks.enumerated() {
                        let h = max(1, CGFloat(p) * (size.height - 24))
                        ctx.fill(Path(CGRect(x: CGFloat(i) * bw, y: (size.height - h) / 2, width: max(1, bw - 0.5), height: h)), with: .color(Theme.accent.opacity(0.85)))
                    }
                }
                // Barlines, so the lanes can be lined up with the music.
                let bars = transport.timeline.measures.enumerated().compactMap { i, m -> (Int, Double)? in
                    let t = transport.trackTime(forBeat: m.start)
                    return t >= 0 && t <= duration ? (m.bar + 1, t) : nil
                }
                let every = max(1, Int((40 / max(1, width / CGFloat(max(bars.count, 1)))).rounded(.up)))
                for (n, (bar, t)) in bars.enumerated() {
                    let x = CGFloat(t / duration) * size.width
                    ctx.fill(Path(CGRect(x: x, y: 0, width: 0.7, height: size.height)), with: .color(.white.opacity(0.16)))
                    if n % every == 0 { ctx.draw(Text("\(bar)").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6)), at: CGPoint(x: x + 8, y: 8)) }
                }
            }
            if wave == nil { ProgressView() }
        }
        .frame(height: 140)
        .overlay(DisplayGlass(radius: 10))
        .recessed(radius: 10)
        .contentShape(.rect)
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in transport.seek(toTrackTime: Double(max(0, min(width, v.location.x)) / width) * duration) })
        .accessibilityLabel("Backing track waveform")
        .accessibilityHint("Drag to move the playhead.")
    }

    // MARK: Lanes

    private func laneView(_ lane: Lane, width: CGFloat) -> some View {
        let frames = edit[lane]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(lane.rawValue, systemImage: lane.symbol).font(.subheadline.weight(.semibold))
                Spacer()
                if let s = selected, s.lane == lane, let k = frames.first(where: { $0.id == s.id }) {
                    Text("\(String(format: "%.2f", k.time)) s · \(lane.label(k.value))").font(.caption.monospacedDigit()).foregroundStyle(Theme.accent)
                } else if frames.isEmpty {
                    Text("Tap to add keyframes").font(.caption).foregroundStyle(.secondary)
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.05))
                Canvas { ctx, size in drawLane(&ctx, size: size, lane: lane, frames: frames) }
            }
            .recessed(radius: 10)
            .frame(height: laneHeight)
            .contentShape(.rect)
            .gesture(laneGesture(lane, width: width))
            .accessibilityElement()
            .accessibilityLabel("\(lane.rawValue) keyframes, \(frames.count)")
            .accessibilityHint("Tap to add a keyframe. Drag a keyframe to move it.")
        }
    }

    private func y(_ v: Double, _ lane: Lane, _ h: CGFloat) -> CGFloat {
        let r = lane.range
        return h - 12 - CGFloat((v - r.lowerBound) / (r.upperBound - r.lowerBound)) * (h - 24)
    }

    private func value(atY py: CGFloat, _ lane: Lane, _ h: CGFloat) -> Double {
        let r = lane.range
        let f = Double((h - 12 - py) / (h - 24))
        var v = r.lowerBound + max(0, min(1, f)) * (r.upperBound - r.lowerBound)
        // Settle on tidy numbers; hold near the neutral value so it's easy to return to.
        let step: Double = lane == .tempo ? 0.05 : lane == .volume ? 0.02 : 0.25
        v = (v / step).rounded() * step
        if abs(v - lane.neutral) < step * 1.6 { v = lane.neutral }
        return max(r.lowerBound, min(r.upperBound, v))
    }

    private func drawLane(_ ctx: inout GraphicsContext, size: CGSize, lane: Lane, frames: [Keyframe]) {
        // Gridlines at the neutral value and the ends.
        for v in [lane.range.lowerBound, lane.neutral, lane.range.upperBound] {
            var line = Path(); line.move(to: CGPoint(x: 0, y: y(v, lane, size.height))); line.addLine(to: CGPoint(x: size.width, y: y(v, lane, size.height)))
            ctx.stroke(line, with: .color(.white.opacity(v == lane.neutral ? 0.22 : 0.08)), style: StrokeStyle(lineWidth: 1, dash: v == lane.neutral ? [4, 4] : []))
            ctx.draw(Text(lane.label(v)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)), at: CGPoint(x: size.width - 24, y: y(v, lane, size.height) - 7))
        }
        // The curve, flat out to both edges.
        var path = Path()
        let first = frames.first?.value ?? lane.neutral
        path.move(to: CGPoint(x: 0, y: y(first, lane, size.height)))
        for (n, k) in frames.enumerated() {
            // A curved segment is drawn as a run of short lines.
            if n > 0, frames[n - 1].curve != 0 || frames[n - 1].smooth {
                let a = frames[n - 1]
                for s in 1..<24 {
                    let t = a.time + (k.time - a.time) * Double(s) / 24
                    path.addLine(to: CGPoint(x: CGFloat(t / duration) * size.width, y: y(TrackEdit.value(frames, at: t, neutral: lane.neutral), lane, size.height)))
                }
            }
            path.addLine(to: CGPoint(x: CGFloat(k.time / duration) * size.width, y: y(k.value, lane, size.height)))
        }
        path.addLine(to: CGPoint(x: size.width, y: y(frames.last?.value ?? lane.neutral, lane, size.height)))
        ctx.stroke(path, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        var fill = path
        fill.addLine(to: CGPoint(x: size.width, y: size.height)); fill.addLine(to: CGPoint(x: 0, y: size.height)); fill.closeSubpath()
        ctx.fill(fill, with: .color(Theme.accent.opacity(0.1)))
        for k in frames {
            let c = CGPoint(x: CGFloat(k.time / duration) * size.width, y: y(k.value, lane, size.height))
            let on = selected == Selection(lane: lane, id: k.id)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - (on ? 9 : 7), y: c.y - (on ? 9 : 7), width: on ? 18 : 14, height: on ? 18 : 14)), with: .color(on ? .white : Theme.accent))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)), with: .color(.black.opacity(0.4)), lineWidth: 1)
        }
    }

    private func laneGesture(_ lane: Lane, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { v in
            let h = laneHeight
            if drag == nil {
                // What's under the finger or pencil: a keyframe to move, or empty lane to add to on release.
                let hit = edit[lane].min { hypot(xPos($0, width) - v.startLocation.x, y($0.value, lane, h) - v.startLocation.y) < hypot(xPos($1, width) - v.startLocation.x, y($1.value, lane, h) - v.startLocation.y) }
                    .flatMap { hypot(xPos($0, width) - v.startLocation.x, y($0.value, lane, h) - v.startLocation.y) < 26 ? $0 : nil }
                drag = Drag(lane: lane, id: hit?.id, before: edit)
                selected = hit.map { Selection(lane: lane, id: $0.id) }
            }
            guard var d = drag, let id = d.id else { return }
            if hypot(v.translation.width, v.translation.height) > 3 { d.moved = true; drag = d }
            let t = Double(max(0, min(width, v.location.x)) / width) * duration
            apply { e in
                var frames = e[lane]
                guard let i = frames.firstIndex(where: { $0.id == id }) else { return }
                frames[i].time = (t * 100).rounded() / 100
                frames[i].value = value(atY: v.location.y, lane, h)
                e[lane] = frames
            }
        }
        .onEnded { v in
            defer { drag = nil }
            guard let d = drag else { return }
            if d.id != nil {
                if d.moved { push(d.before) }
                return
            }
            guard hypot(v.translation.width, v.translation.height) < 6 else { return }
            // A tap on empty lane adds a keyframe there.
            let t = (Double(max(0, min(width, v.location.x)) / width) * duration * 100).rounded() / 100
            let k = Keyframe(time: t, value: value(atY: v.location.y, lane, laneHeight))
            push(d.before)
            apply { $0[lane] = $0[lane] + [k] }
            selected = Selection(lane: lane, id: k.id)
        }
    }

    private func xPos(_ k: Keyframe, _ width: CGFloat) -> CGFloat { CGFloat(k.time / duration) * width }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 14) {
            Button { transport.toggle() } label: {
                Image(systemName: transport.isPlaying ? "pause.fill" : "play.fill").frame(width: 28)
            }
            .keyTint(transport.isPlaying ? Theme.accent : nil)
            .accessibilityLabel(transport.isPlaying ? "Pause" : "Play")
            Divider().frame(height: 24)
            Button("Add at Playhead", systemImage: "plus.circle") { addAtPlayhead() }
                .help("Add a keyframe to the selected lane at the playhead")
            Button("Delete", systemImage: "trash", role: .destructive) { deleteSelected() }.disabled(selected == nil)
            Menu {
                Button("Fade In (4 s)", systemImage: "speaker.wave.1") { fade(in: true) }
                Button("Fade Out (4 s)", systemImage: "speaker.slash") { fade(in: false) }
                Button("Slow the Last 8 s", systemImage: "tortoise") { slowEnd() }
            } label: { Label("Presets", systemImage: "wand.and.stars") }
            if let k = selectedFrame {
                Divider().frame(height: 24)
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").foregroundStyle(.secondary)
                Slider(value: Binding { k.smooth ? 0 : k.curve } set: { v in setCurve(push: false) { $0.curve = (v * 20).rounded() / 20; $0.smooth = false } }, in: -1...1) { if $0 { push(edit) } }
                    .frame(width: 120)
                    .accessibilityLabel("Curve to the next keyframe")
                Button("S-Curve") { setCurve(push: true) { $0.smooth = true; $0.curve = 0 } }.lit(k.smooth)
                Button("Straight") { setCurve(push: true) { $0.smooth = false; $0.curve = 0 } }.disabled(k.curve == 0 && !k.smooth)
            }
            Spacer()
            Button { zoom = max(1, zoom / 1.5) } label: { Image(systemName: "minus.magnifyingglass") }.accessibilityLabel("Zoom out")
            Text(String(format: "%.1f×", zoom)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 34)
            Button { zoom = min(16, zoom * 1.5) } label: { Image(systemName: "plus.magnifyingglass") }.accessibilityLabel("Zoom in")
        }
        .buttonStyle(KeyStyle())
        .padding(12)
        .metalPlate(radius: 16)
        .environment(\.colorScheme, .dark)
    }

    private var selectedFrame: Keyframe? {
        guard let s = selected else { return nil }
        return edit[s.lane].first { $0.id == s.id }
    }

    /// Bends the line from the selected keyframe to the next one.
    private func setCurve(push undoable: Bool, _ f: (inout Keyframe) -> Void) {
        guard let s = selected else { return }
        if undoable { push(edit) }
        apply { e in
            var frames = e[s.lane]
            if let i = frames.firstIndex(where: { $0.id == s.id }) { f(&frames[i]) }
            e[s.lane] = frames
        }
    }

    /// The lane to act on: the selected keyframe's, or volume.
    private var activeLane: Lane { selected?.lane ?? .volume }

    private func addAtPlayhead() {
        let t = ((transport.trackTime ?? 0) * 100).rounded() / 100
        let lane = activeLane
        let k = Keyframe(time: max(0, min(duration, t)), value: edit.value(lane, at: t))
        push(edit)
        apply { $0[lane] = $0[lane] + [k] }
        selected = Selection(lane: lane, id: k.id)
    }

    private func deleteSelected() {
        guard let s = selected else { return }
        push(edit)
        apply { $0[s.lane] = $0[s.lane].filter { $0.id != s.id } }
        selected = nil
    }

    private func fade(in fadeIn: Bool) {
        change { e in
            let len = min(4, duration / 2)
            let frames = fadeIn
                ? [Keyframe(time: 0, value: 0), Keyframe(time: len, value: 1)]
                : [Keyframe(time: duration - len, value: 1), Keyframe(time: duration, value: 0)]
            e.volume = e.volume.filter { fadeIn ? $0.time > len : $0.time < duration - len } + frames
        }
    }

    private func slowEnd() {
        change { e in
            let from = max(0, duration - 8)
            e.tempo = e.tempo.filter { $0.time < from } + [Keyframe(time: from, value: 1), Keyframe(time: duration - 0.5, value: 0.6)]
        }
    }

    // MARK: History

    private func apply(_ f: (inout TrackEdit) -> Void) {
        f(&edit)
        transport.automation = edit
        library.saveTrackEdit(edit, for: item)
    }

    /// One undoable step.
    private func change(_ f: (inout TrackEdit) -> Void) {
        push(edit)
        apply(f)
    }

    private func push(_ before: TrackEdit) {
        guard undo.last != before else { return }
        undo.append(before)
        if undo.count > 100 { undo.removeFirst() }
        redo = []
    }

    private func stepHistory(undo isUndo: Bool) {
        guard let previous = isUndo ? undo.popLast() : redo.popLast() else { return }
        if isUndo { redo.append(edit) } else { undo.append(edit) }
        selected = nil
        apply { $0 = previous }
    }
}

/// A line across the waveform and lanes at the recording's current position.
private struct Playhead: View {
    let transport: Transport
    let duration: Double
    let width: CGFloat

    var body: some View {
        let t = transport.trackTime ?? 0
        Rectangle()
            .fill(.white)
            .frame(width: 1.5)
            .shadow(color: .white.opacity(0.6), radius: 3)
            .offset(x: CGFloat(max(0, min(duration, t)) / duration) * width)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
