import Observation
import SwiftUI

/// Writes (and keeps) the review of a take.
@Observable final class WrittenReviewModel {
    enum State { case writing, ready(WrittenReview) }
    private(set) var state = State.writing
    private(set) var facts = ReviewFacts()
    private(set) var note: String?
    /// Apple Intelligence is still rewording the paragraphs.
    private(set) var improving = false
    @ObservationIgnored private var take: Take?
    @ObservationIgnored private var title = ""
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var task: Task<Void, Never>?

    private struct Cached: Codable { var signature: String; var review: WrittenReview }

    func load(take: Take, facts: ReviewFacts, title: String, folder: URL) {
        self.take = take; self.title = title; self.folder = folder; self.facts = facts
        task?.cancel()
        let sig = "\(facts.hit)/\(facts.total)/\(facts.bars.count)"
        let url = folder.appending(path: "\(take.id.uuidString).review.json")
        if let c = try? JSONDecoder().decode(Cached.self, from: Data(contentsOf: url)), c.signature == sig {
            state = .ready(c.review); note = nil; return
        }
        write(signature: sig, url: url)
    }

    /// Asks for a fresh review (the model words it differently each time).
    func regenerate() {
        guard let take, let folder else { return }
        task?.cancel()
        write(signature: "\(facts.hit)/\(facts.total)/\(facts.bars.count)", url: folder.appending(path: "\(take.id.uuidString).review.json"))
    }

    /// The review is worked out by rules at once, so it can be read straight away; then Apple Intelligence rewords it in a
    /// teacher's own words, one paragraph at a time, and anything that changes a number or a place is thrown away.
    private func write(signature: String, url: URL) {
        let facts = facts, base = ReviewComposer.template(facts)
        state = .ready(base)
        note = ReviewAI.availability.reason
        improving = ReviewAI.availability.available
        task = Task {
            var review = base
            if improving {
                for i in base.paragraphs.indices {
                    guard !Task.isCancelled else { return }
                    if let r = await ReviewAI.rewrite(base.paragraphs[i].text, kind: base.paragraphs[i].kind) {
                        review.paragraphs[i].text = r; review.byAI = true
                        state = .ready(review)
                    }
                }
                if review.byAI { review.headline = await ReviewAI.headline(facts, fallback: base.headline); state = .ready(review) }
            }
            guard !Task.isCancelled else { return }
            improving = false
            try? JSONEncoder().encode(Cached(signature: signature, review: review)).write(to: url)
        }
    }
}

/// The written review: a score, a strip of bars to tap, and short paragraphs whose places are tappable.
struct WrittenReviewView: View {
    let model: WrittenReviewModel
    let reviewer: ReviewSession
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    barStrip
                    switch model.state {
                    case .writing:
                        HStack(spacing: 10) { ProgressView(); Text("Writing your review…").foregroundStyle(.secondary) }.padding(.vertical, 8)
                    case .ready(let review):
                        ForEach(Array(review.paragraphs.enumerated()), id: \.offset) { _, p in paragraph(p) }
                        if model.improving {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Apple Intelligence is putting it in its own words…").font(.caption).foregroundStyle(.secondary) }
                        } else if let note = model.note {
                            Label(note, systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                        } else if review.byAI {
                            Label("Written by Apple Intelligence on this device", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .environment(\.openURL, OpenURLAction { url in
                guard let ref = ReviewRef(url: url) else { return .systemAction }
                reviewer.focus(ref, facts: model.facts)
                return .handled
            })
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { model.regenerate() } label: { Label("Write Again", systemImage: "arrow.clockwise") } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        let f = model.facts
        let headline: String = { if case .ready(let r) = model.state { ReviewText.parse(r.headline, facts: f).map { if case .text(let t) = $0 { t } else { "" } }.joined() } else { title } }()
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.secondary.opacity(0.25), lineWidth: 8)
                Circle().trim(from: 0, to: f.accuracy).stroke(color(f.accuracy), style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(Int((f.accuracy * 100).rounded()))%").font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
            }
            .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 6) {
                Text(headline).font(.custom("Baskerville-Bold", size: 24, relativeTo: .title2))
                HStack(spacing: 14) {
                    stat("\u{E1D5}", "\(f.hit) of \(f.total) notes", bravura: true)
                    if let c = f.cents { stat(c >= 0 ? "\u{E262}" : "\u{E260}", abs(c) < 8 ? "in tune" : "\(Int(abs(c).rounded()))¢ \(c > 0 ? "sharp" : "flat")", bravura: true) }
                    if let r = f.behind { stat("\u{E4E5}", "behind by \(r.notes)", bravura: true) } else if let r = f.ahead { stat("\u{E4E5}", "ahead by \(r.notes)", bravura: true) }
                }
                .font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func stat(_ glyph: String, _ text: String, bravura: Bool) -> some View {
        HStack(spacing: 4) {
            Text(glyph).font(.custom("Bravura", size: 17)).foregroundStyle(Theme.accent)
            Text(text).foregroundStyle(.secondary)
        }
    }

    /// Every bar as a small block, coloured by how it went; tap one to see it in the music.
    private var barStrip: some View {
        let numbers = Array(Set(model.facts.bars.map(\.number))).sorted()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) { Text("\u{E030}").font(.custom("Bravura", size: 18)); Text("Bar by bar").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 4)], spacing: 4) {
                ForEach(numbers, id: \.self) { n in
                    let a = model.facts.barAccuracy[n]
                    Button { reviewer.focus(.bar(n), facts: model.facts) } label: {
                        Text("\(n)").font(.caption2.weight(.bold)).monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .foregroundStyle(a == nil ? Color.secondary : Color.white)
                            .background(a.map { color($0) } ?? Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(reviewer.focusRef == .bar(n) ? Color.primary : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bar \(n), \(a.map { "\(Int($0 * 100)) percent" } ?? "no notes")")
                }
            }
        }
    }

    private func paragraph(_ p: WrittenReview.Para) -> some View {
        let (symbol, tint): (String, Color) = switch p.kind {
        case .strength: ("star.fill", .green)
        case .timing: ("metronome.fill", .orange)
        case .pitch: ("tuningfork", .blue)
        case .trouble: ("exclamationmark.triangle.fill", .red)
        case .tip: ("lightbulb.fill", .yellow)
        }
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(attributed(p.text)).font(.body).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The paragraph with each place as a tappable chip: a bit of notation, then where it is.
    private func attributed(_ text: String) -> AttributedString {
        var out = AttributedString()
        for seg in ReviewText.parse(text, facts: model.facts) {
            switch seg {
            case .text(let t): out += AttributedString(t)
            case .ref(let r):
                // A bit of notation (a note, or a barline) and where it is, as one link.
                let mark: String
                if case .note = r { mark = "\u{2669}" } else { mark = "\u{1D100}" }
                var chip = AttributedString("\u{2060}" + mark + "\u{00A0}" + model.facts.label(r))
                chip.font = .body.weight(.semibold)
                chip.link = r.url
                chip.foregroundColor = Color(red: 0.08, green: 0.38, blue: 0.95)
                chip.underlineStyle = .single
                out += chip
            }
        }
        return out
    }

    private func color(_ a: Double) -> Color { a >= 0.85 ? .green : a >= 0.5 ? .orange : .red }
}
