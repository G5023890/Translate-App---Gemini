import SwiftUI
import Foundation
import Security
import TranslationUIProvider
import ExtensionKit

@main
final class TranslateGeminiProviderExtension: TranslationUIProviderExtension {
    required init() {}

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            MinimalTranslationView(context: context)
        }
    }
}

private struct MinimalTranslationView: View {
    @State private var context: TranslationUIProviderContext
    @State private var apiKey: String
    @State private var translatedText: String = ""
    @State private var isTranslating = false
    @State private var errorMessage: String?

    init(context: TranslationUIProviderContext) {
        _context = State(initialValue: context)
        _apiKey = State(initialValue: ExtensionKeychainService.load(account: "GeminiAPIKey") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Gemini API Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("AIza...", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    Button("Сохранить ключ") {
                        saveAPIKey()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let inputText = context.inputText?.description,
               !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(inputText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Text(translatedText.isEmpty ? "Перевод" : translatedText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Button("Перевести") {
                    Task { await translate() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTranslating)

                if context.allowsReplacement {
                    Button("Заменить") {
                        context.finish(translation: AttributedString(translatedText))
                    }
                    .buttonStyle(.bordered)
                    .disabled(translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if isTranslating {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .task {
            if translatedText.isEmpty {
                await translate()
            }
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = ExtensionKeychainService.save(trimmed, account: "GeminiAPIKey")
    }

    private func translate() async {
        errorMessage = nil
        let text = context.inputText?.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            errorMessage = "Нет текста для перевода."
            return
        }

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorMessage = "Добавьте API ключ."
            return
        }

        isTranslating = true
        defer { isTranslating = false }

        do {
            let client = ExtensionGeminiClient(apiKey: key, model: "gemini-2.5-flash")
            let output = try await client.translateToRussian(text)
            translatedText = output.isEmpty ? "Пустой ответ от модели." : output
        } catch {
            errorMessage = "Ошибка: \(error.localizedDescription)"
        }
    }
}

private enum ExtensionKeychainService {
    private static let service = "TranslateGeminiTranslationProvider"

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            return SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }
}

private struct ExtensionGeminiClient {
    let apiKey: String
    let model: String

    func translateToRussian(_ text: String) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw NSError(domain: "TranslationProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bad URL"])
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

        let body = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            if
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let err = json["error"] as? [String: Any],
                let message = err["message"] as? String
            {
                throw NSError(domain: "TranslationProvider", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
            }
            let fallback = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "TranslationProvider", code: 2, userInfo: [NSLocalizedDescriptionKey: "API error: \(fallback)"])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        let result = parts?.first?["text"] as? String
        return result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
