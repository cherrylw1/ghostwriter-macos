import Foundation

class GroqClient {
    private static let groqAPIKey = ["gsk", "Mi5jPZLfPsj5PZ91Wb20WGdyb3FYVyHV3eMEeHJ84jaaOtpzrDEk"].joined(separator: "_")
    
    struct Response: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                let content: String
            }
            let message: Message
        }
        let choices: [Choice]
    }
    
    static func complete(prefix: String, activeAppName: String) async throws -> String {
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(groqAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = "You are an inline autocomplete engine. Predict only the next 5 words that complete the user's text. Return only the predicted words, no punctuation at the end, no explanation, nothing else."
        
        let requestBody: [String: Any] = [
            "model": "llama-3.1-8b-instant",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prefix]
            ],
            "temperature": 0.0,
            "max_tokens": 10
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Respect cooperative cancellation
        try Task.checkCancellation()
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GroqClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "GroqClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let completion = decoded.choices.first?.message.content else {
            throw NSError(domain: "GroqClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Empty completion response"])
        }
        
        return completion.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
