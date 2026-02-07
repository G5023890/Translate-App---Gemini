import SwiftUI
import UIKit

@MainActor
final class TranslatorViewModel: ObservableObject {
    @Published var sourceText: String = ""
    @Published var translatedText: String = ""
    @Published var apiKey: String = ""
    @Published var isTranslating = false
    @Published var errorMessage: String?

    init() {
        apiKey = KeychainService.load(account: "GeminiAPIKey") ?? ""
    }

    func saveApiKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = KeychainService.save(trimmed, account: "GeminiAPIKey")
    }

    func pasteFromClipboard() {
        sourceText = UIPasteboard.general.string ?? ""
    }

    func copyTranslation() {
        UIPasteboard.general.string = translatedText
    }

    func translate() async {
        errorMessage = nil
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = "Введите или вставьте текст для перевода."
            return
        }

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorMessage = "Добавьте Gemini API ключ в настройках."
            return
        }

        isTranslating = true
        defer { isTranslating = false }

        do {
            let client = GeminiClient(apiKey: key, model: "gemini-2.5-flash")
            let result = try await client.translateToRussian(text)
            translatedText = result.isEmpty ? "Пустой ответ от модели." : result
        } catch {
            errorMessage = "Ошибка перевода: \(error.localizedDescription)"
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = TranslatorViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextEditor(text: $vm.sourceText)
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3)))

                HStack {
                    Button("Вставить") {
                        vm.pasteFromClipboard()
                    }
                    .buttonStyle(.bordered)

                    Button("Перевести") {
                        Task { await vm.translate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isTranslating)

                    if vm.isTranslating {
                        ProgressView()
                            .padding(.leading, 4)
                    }
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Перевод")
                        .font(.headline)
                    ScrollView {
                        Text(vm.translatedText.isEmpty ? "Здесь появится перевод" : vm.translatedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(minHeight: 160)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button("Скопировать перевод") {
                    vm.copyTranslation()
                }
                .buttonStyle(.bordered)
                .disabled(vm.translatedText.isEmpty)
            }
            .padding()
            .navigationTitle("Translate Gemini")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Настройки") {
                        SettingsView(vm: vm)
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var vm: TranslatorViewModel

    var body: some View {
        Form {
            Section("Gemini") {
                SecureField("API ключ", text: $vm.apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Text("Модель: gemini-2.5-flash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Сохранить") {
                    vm.saveApiKey()
                }
            }
        }
        .navigationTitle("Настройки")
    }
}

