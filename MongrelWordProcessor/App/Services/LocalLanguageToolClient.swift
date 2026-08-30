import Foundation

struct LanguageToolIssue: Identifiable, Equatable, Sendable {
    let id: String
    let message: String
    let shortMessage: String
    let offset: Int
    let length: Int
    let replacements: [String]
    let ruleID: String
}

enum LanguageToolCheckState: Equatable {
    case idle
    case checking
    case complete(Int)
    case unavailable(String)

    var title: String {
        switch self {
        case .idle: return "Not checked"
        case .checking: return "Checking locally..."
        case .complete(let count): return count == 0 ? "No issues found" : "\(count) suggestions"
        case .unavailable: return "Local server unavailable"
        }
    }
}

enum LocalLanguageToolClient {
    private struct Response: Decodable {
        struct Match: Decodable {
            struct Replacement: Decodable {
                let value: String
            }

            struct Rule: Decodable {
                let id: String
            }

            let message: String
            let shortMessage: String
            let offset: Int
            let length: Int
            let replacements: [Replacement]
            let rule: Rule
        }

        let matches: [Match]
    }

    static let endpoint = URL(string: "http://127.0.0.1:8081/v2/check")!

    static func check(_ text: String) async throws -> [LanguageToolIssue] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "language": "en-US",
            "text": text
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(Response.self, from: data).matches.map { match in
            LanguageToolIssue(
                id: "\(match.rule.id):\(match.offset):\(match.length)",
                message: match.message,
                shortMessage: match.shortMessage,
                offset: match.offset,
                length: match.length,
                replacements: match.replacements.prefix(5).map(\.value),
                ruleID: match.rule.id
            )
        }
    }

    private static func formBody(_ values: [String: String]) -> Data? {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
        let body = values
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return body.data(using: .utf8)
    }
}
