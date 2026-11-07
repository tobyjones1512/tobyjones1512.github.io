import SwiftUI

/// Posts feedback to the Fider board. Tags are assigned by slug and must already exist on the board:
/// "maestro-pro", "bug-report", "feature-suggestion", "other".
struct FeedbackView: View {
    private enum Kind: String, CaseIterable, Identifiable {
        case bug = "Bug Report"
        case feature = "Feature Suggestion"
        case other = "Something Else"

        var id: String { rawValue }

        var tagSlug: String {
            switch self {
            case .bug: "bug-report"
            case .feature: "feature-suggestion"
            case .other: "other"
            }
        }
    }

    private static let baseURL = "https://thecaffeinemediacompany.fider.io"
    // ponytail: key ships in the binary, so anyone can extract it; move to a proxy if abused.
    private static let apiKey = "riepFInpHYZUgxnVc33cbsKFon6NWzHkhBZa8O1n3PR8v0hiKg4L8Zhe3gjKofyZ"

    @Environment(\.dismiss) private var dismiss
    @State private var kind = Kind.bug
    @State private var title = ""
    @State private var details = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var didSend = false

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    // Fider requires 10–100 characters.
    private var canSend: Bool { (10...100).contains(trimmedTitle.count) && !isSending }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(Kind.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                }
                Section {
                    TextField("Title", text: $title)
                    TextField("Description", text: $details, axis: .vertical)
                        .lineLimit(5...12)
                } footer: {
                    Text("Title must be 10–100 characters. Your feedback is posted publicly at [thecaffeinemediacompany.fider.io](https://thecaffeinemediacompany.fider.io).")
                }
                Section {
                    Link(destination: URL(string: Self.baseURL)!) {
                        Label("See Other Users' Feedback", systemImage: "list.bullet.bubble")
                    }
                }
            }
            .navigationTitle("Provide Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Send") { Task { await send() } }.disabled(!canSend)
                    }
                }
            }
            .alert("Couldn't send feedback", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Thanks for your feedback!", isPresented: $didSend) {
                Button("OK") { dismiss() }
            }
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            let created = try await request("/api/v1/posts", body: ["title": trimmedTitle, "description": details])
            guard let number = (try? JSONSerialization.jsonObject(with: created) as? [String: Any])?["number"] as? Int else {
                throw URLError(.cannotParseResponse)
            }
            // Post exists at this point; a tagging failure shouldn't report the whole send as failed.
            for slug in ["maestro-pro", kind.tagSlug] {
                _ = try? await request("/api/v1/posts/\(number)/tags/\(slug)", body: nil)
            }
            didSend = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func request(_ path: String, body: [String: String]?) async throws -> Data {
        var req = URLRequest(url: URL(string: Self.baseURL + path)!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(Self.apiKey)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["errors"] as? [[String: Any]]
            throw NSError(domain: "Fider", code: 0, userInfo: [
                NSLocalizedDescriptionKey: message?.first?["message"] as? String ?? "Server error."
            ])
        }
        return data
    }
}
