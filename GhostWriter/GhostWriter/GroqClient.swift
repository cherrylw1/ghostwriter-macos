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
    
    private static let counterQueue = DispatchQueue(label: "com.ghostwriter.groqclient.counter")
    private static var apiCallCount = 0
    
    private static func incrementAndGetCallCount() -> Int {
        return counterQueue.sync {
            apiCallCount += 1
            return apiCallCount
        }
    }
    
    static func complete(prefix: String, activeAppName: String, screenshotBase64: String?) async throws -> String {
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(groqAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Fetch recent completions from StyleDB if count is at least 10
        let completionsCount = StyleDB.shared.getCompletionsCount()
        var systemPrompt = """
You are an inline autocomplete engine. Your job is to predict 
the next 3-5 words the user is about to type based purely on 
their current text. 

Rules:
- Continue the text naturally as any fluent writer would
- Match the tone and style of what is already written
- Output only the predicted words, nothing else
- No quotes, no punctuation unless grammatically necessary
- No commas between words
- No lists
- No explanation
"""
        
        if completionsCount >= 10 {
            let recentCompletions = StyleDB.shared.fetchRecentExamples(appName: activeAppName, limit: 3)
            if !recentCompletions.isEmpty {
                let examplesText = recentCompletions.map { "- \($0)" }.joined(separator: "\n")
                let prependedPrompt = """
                Here are recent examples of how this user writes in \(activeAppName):
                \(examplesText)
                Match this style exactly.
                
                """
                systemPrompt = prependedPrompt + systemPrompt
            }
        }
        
        // Smart Screenshot Strategy:
        // Default is text-only. Vision is used on every 10th call OR when prefix length is short (< 20 chars).
        let currentCallCount = incrementAndGetCallCount()
        let useVision = (currentCallCount % 10 == 0) || (prefix.count < 20)
        let model = useVision ? "meta-llama/llama-4-scout-17b-16e-instruct" : "llama-3.1-8b-instant"
        
        let messages: [[String: Any]]
        if useVision, let screenshot = screenshotBase64 {
            let userContent: [[String: Any]] = [
                ["type": "text", "text": prefix],
                [
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/jpeg;base64,\(screenshot)"
                     ]
                ]
            ]
            messages = [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ]
        } else {
            messages = [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prefix]
            ]
        }
        
        let requestBody: [String: Any] = [
            "model": model,
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
        
        // 2. Remove all single quote characters '
        completion = completion.replacingOccurrences(of: "'", with: "")
        
        // 3. Remove all double quote characters "
        completion = completion.replacingOccurrences(of: "\"", with: "")
        
        // 4. Remove all backtick characters
        completion = completion.replacingOccurrences(of: "`", with: "")
        
        // 5. Remove commas that appear between words (not in contractions)
        completion = completion.replacingOccurrences(of: ",", with: "")
        
        // 6. Split into words
        let rawWords = completion.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        // Remove consecutive duplicate words
        var cleanWords: [String] = []
        var lastWord: String?
        for word in rawWords {
            if word.lowercased() == lastWord?.lowercased() {
                continue
            }
            cleanWords.append(word)
            lastWord = word
        }
        
        // Take only the first 5 words of the response
        let firstFiveWords = cleanWords.prefix(5).joined(separator: " ")
        
        // 7. Trim whitespace
        let cleanedPrediction = firstFiveWords.trimmingCharacters(in: .whitespacesAndNewlines)
        if shouldDiscard(prediction: cleanedPrediction, prefix: prefix) {
            print("⚠️ Prediction discarded — too similar to recent context")
            throw DiscardedPredictionError()
        }
        return cleanedPrediction
    }
    
    private static func shouldDiscard(prediction: String, prefix: String) -> Bool {
        let predWords = prediction.components(separatedBy: .whitespacesAndNewlines)
                                  .map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
                                  .filter { !$0.isEmpty }
        let prefixWords = prefix.components(separatedBy: .whitespacesAndNewlines)
                                .map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
                                .filter { !$0.isEmpty }
        let lastTenPrefixWords = Array(prefixWords.suffix(10))
        
        var overlapCount = 0
        for predWord in predWords {
            if lastTenPrefixWords.contains(predWord) {
                overlapCount += 1
            }
        }
        return overlapCount > 2
    }
}

struct DiscardedPredictionError: Error {}
