import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Writes the review with Apple Intelligence (the on-device model) when it is there; nil otherwise.
enum ReviewAI {
    /// Whether the model can be used now, and if not, why not (for a gentle note under the review).
    static var availability: (available: Bool, reason: String?) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return (true, nil)
            case .unavailable(let why):
                switch why {
                case .appleIntelligenceNotEnabled: return (false, "Turn on Apple Intelligence in Settings for a review written just for you.")
                case .deviceNotEligible: return (false, "This device can’t run Apple Intelligence, so the review is written by the app’s own rules.")
                case .modelNotReady: return (false, "Apple Intelligence is still getting ready, so this review is written by the app’s own rules.")
                @unknown default: return (false, nil)
                }
            }
        }
        #endif
        return (false, "Apple Intelligence needs a newer system, so this review is written by the app’s own rules.")
    }

    static let instructions = """
    You are a concise music teacher. You are given one piece of feedback about a student's recording. Say the same thing more directly, in one short sentence, never longer than the original. No greetings, no exclamation marks, no praise words, no filler, no questions.
    Names in angle brackets, such as <1> or <2>, stand for places in the music. Copy each one exactly as written, once, in the same place in your sentence. Keep every number. Do not add any new facts, places, notes or brackets. Do not use dashes to join clauses.
    """

    /// Swaps each place token for a short numbered name the model can copy without making up tokens of its own.
    private static func hide(_ text: String) -> (text: String, back: [String: String]) {
        var back: [String: String] = [:], out = text
        guard let re = try? NSRegularExpression(pattern: "\\{[^}]*\\}") else { return (text, back) }
        let ns = text as NSString
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: m.range)
            if !back.values.contains(token) { back["<\(back.count + 1)>"] = token }
        }
        for (name, token) in back { out = out.replacingOccurrences(of: token, with: name) }
        return (out, back)
    }

    static func rewrite(_ text: String, kind: WrittenReview.Kind) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            let role: String = switch kind { case .strength: "good playing"; case .timing: "timing"; case .pitch: "tuning"; case .trouble: "trouble spots"; case .tip: "practice" }
            let (hidden, back) = hide(text)
            let session = LanguageModelSession(instructions: instructions)
            guard let r = try? await session.respond(to: "Feedback about the student's \(role):\n\(hidden)").content else { return nil }
            var cleaned = clean(r.trimmingCharacters(in: .whitespacesAndNewlines))
            for (name, token) in back { cleaned = cleaned.replacingOccurrences(of: name, with: token) }
            return ReviewText.accepts(original: text, rewrite: cleaned) && !cleaned.contains("<") ? cleaned : nil
        }
        #endif
        return nil
    }

    static func headline(_ f: ReviewFacts, fallback: String) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            let session = LanguageModelSession(instructions: "You write a plain, factual headline of at most five words for a music student's result. No exclamation marks, no quotation marks, no dashes, no braces.")
            if let r = try? await session.respond(to: "The student played \(f.hit) of \(f.total) notes correctly (\(Int((f.accuracy * 100).rounded())) percent).").content {
                let h = clean(r.trimmingCharacters(in: CharacterSet(charactersIn: " \n\"")))
                if !h.isEmpty, h.count <= 40, !h.contains("{"), !h.contains("!") { return h }
            }
        }
        #endif
        return fallback
    }

    /// The model likes long dashes; the app doesn't use them.
    static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: " \u{2014} ", with: ", ").replacingOccurrences(of: "\u{2014}", with: ", ").replacingOccurrences(of: "  ", with: " ")
    }
}
