import Foundation

struct ExplicationContext {
    let bookTitle: String
    let author: String?
    let chapterTitle: String
    let surroundingText: String
}

enum ClaudeServiceError: Error, LocalizedError {
    case missingAPIKey
    case networkError(Error)
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Claude API key not configured"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from Claude API"
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}

actor ClaudeService {
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let model = "claude-opus-4-5-20251101"

    private var apiKey: String? {
        // Try to read from environment or UserDefaults
        ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
            ?? UserDefaults.standard.string(forKey: "anthropicAPIKey")
    }

    func explicate(
        selectedText: String,
        context: ExplicationContext
    ) async throws -> String {
        guard let apiKey = apiKey else {
            throw ClaudeServiceError.missingAPIKey
        }

        let prompt = buildExplicationPrompt(selectedText: selectedText, context: context)

        let request = try buildRequest(apiKey: apiKey, prompt: prompt)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeServiceError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorBody = String(data: data, encoding: .utf8) {
                throw ClaudeServiceError.apiError(errorBody)
            }
            throw ClaudeServiceError.apiError("HTTP \(httpResponse.statusCode)")
        }

        return try parseResponse(data)
    }

    private func buildExplicationPrompt(selectedText: String, context: ExplicationContext) -> String {
        var prompt = """
        You are generating margin notes for a book reader. Notes appear inline and can start discussion threads.

        Book: \(context.bookTitle)
        """

        if let author = context.author {
            prompt += "\nAuthor: \(author)"
        }

        prompt += """

        Chapter: \(context.chapterTitle)

        Context:
        ---
        \(context.surroundingText)
        ---

        Highlighted passage:
        "\(selectedText)"

        Write a margin note. This is marginalia, not an essay—2-4 sentences, one pointed observation or question.

        Draw from what's relevant:
        - Literal vs. figurative meaning, symbolic layers
        - Literary devices, formal techniques, prosody
        - Philological notes: etymology, translation issues, textual variants
        - Historical, philosophical, or theological context
        - Connection to the work's broader argument or structure
        - Intertextual allusions or echoes

        But distill to the single most interesting thing. Be terse and substantive. Skip surface-level observations. Assume literary familiarity.

        For biblical texts: engage as scholarship (historical-critical, literary), not devotionally.
        For poetry: form often is the observation.
        For philosophy/theology: name the tradition or debate being invoked.

        Think: what would you actually scribble in a margin? Sometimes that's "cf. Romans 9" or "echoes Hyperion" or "watch the verb tense shift." Not everything needs unpacking—just marking.
        """

        return prompt
    }

    private func buildRequest(apiKey: String, prompt: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw ClaudeServiceError.invalidResponse
        }
        return text
    }

    func setAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "anthropicAPIKey")
    }

    var isConfigured: Bool {
        apiKey != nil && !apiKey!.isEmpty
    }
}
