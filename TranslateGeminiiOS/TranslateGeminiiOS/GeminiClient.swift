import Foundation

struct GeminiClient {
    let apiKey: String
    let model: String

    func translateToRussian(_ text: String) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw NSError(domain: "Translator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bad URL"])
        }

        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": "Translate the following text from English or Hebrew to Russian. Return only the translation.\\n\\n\(text)"]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            if
                let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                let error = json["error"] as? [String: Any],
                let message = error["message"] as? String
            {
                throw NSError(domain: "Translator", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
            }
            let body = String(data: responseData, encoding: .utf8) ?? ""
            throw NSError(domain: "Translator", code: 2, userInfo: [NSLocalizedDescriptionKey: "API error: \(body)"])
        }

        let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        let text = parts?.first?["text"] as? String
        return text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
