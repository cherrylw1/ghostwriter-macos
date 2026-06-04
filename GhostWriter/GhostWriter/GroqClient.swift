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
    
    static func complete(prefix: String, activeAppName: String, screenshotBase64: String?) async throws -> String {
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(groqAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Fetch recent completions from StyleDB
        let recentCompletions = StyleDB.shared.fetchRecentExamples(appName: activeAppName, limit: 3)
        var systemPrompt = "You are an inline autocomplete engine. Predict only the next 5 words that complete the user's text. Return only the predicted words, no punctuation at the end, no explanation, nothing else."
        
        if !recentCompletions.isEmpty {
            let examplesText = recentCompletions.map { "- \($0)" }.joined(separator: "\n")
            let prependedPrompt = """
            Here are recent examples of how this user writes in \(activeAppName):
            \(examplesText)
            Match this style exactly.
            
            """
            systemPrompt = prependedPrompt + systemPrompt
        }
        
        var userContent: [[String: Any]] = [
            ["type": "text", "text": prefix]
        ]
        
        if let screenshot = screenshotBase64 {
            let imageObject: [String: Any] = [
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(screenshot)"
                ]
            ]
            userContent.append(imageObject)
        }
        
        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userContent]
        ]
        
        let requestBody: [String: Any] = [
            "model": "meta-llama/llama-4-scout-17b-16e-instruct",
            "messages": messages,
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
        guard var completion = decoded.choices.first?.message.content else {
            throw NSError(domain: "GroqClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Empty completion response"])
        }
        
        // Response Cleanup:
        // 1. Strip all newlines
        completion = completion.replacingOccurrences(of: "\n", with: " ")
        completion = completion.replacingOccurrences(of: "\r", with: " ")
        
        // 2. Take only the first 5 words of the response
        let words = completion.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let firstFiveWords = words.prefix(5).joined(separator: " ")
        
        // 3. Trim whitespace
        return firstFiveWords.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
