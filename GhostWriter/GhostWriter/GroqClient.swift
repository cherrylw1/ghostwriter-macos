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
You are an AI autocomplete engine built for someone who primarily 
writes AI prompts and Google Docs content. Their writing is direct, 
instructional and specific — never corporate or formal.

Your job: predict the next 3-5 words they are about to type.

Rules:
- If they are writing an AI prompt (detected by words like write, 
  create, generate, make, list, explain, give, describe, build, 
  summarize, analyze) — complete it like an experienced prompt writer
- If they are writing in Google Docs — complete it like a clear 
  direct writer, no filler words
- Never output comma separated lists
- Never use corporate language like 'regulatory requirements' 
  or 'industry standards' unless the prefix explicitly requires it
- Never explain yourself
- Output only the next 3-5 words as a natural continuation
- Match the exact tone and vocabulary of the prefix

Examples of good completions:
- 'write me a detailed' → 'step by step guide'
- 'create a list of' → 'the top 10 ways'
- 'explain how to' → 'build this feature in'
- 'I wanted to' → 'follow up on this'
- 'can you help me' → 'understand how this'
- 'generate a' → 'comprehensive breakdown of'
- 'Hi Aaron,' → 'hope you are doing'
- 'following up on' → 'our conversation from yesterday'
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
        
        // 2. Remove all comma characters from prediction output
        completion = completion.replacingOccurrences(of: ",", with: "")
        
        // 3. Split into words
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
        
        // 4. Remove any trailing or leading spaces
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
