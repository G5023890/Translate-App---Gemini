import Cocoa
import Carbon.HIToolbox
import Security
import ServiceManagement
import ApplicationServices

final class TranslationWindowController: NSWindowController, NSWindowDelegate {
    private let textView: NSTextView
    private var keyMonitor: Any?

    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 640, height: 360)
        let style: NSWindow.StyleMask = [.titled, .closable, .resizable]
        let window = NSWindow(contentRect: contentRect, styleMask: style, backing: .buffered, defer: false)
        window.title = "Перевод"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let scrollView = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.string = ""
        textView.textContainerInset = NSSize(width: 12, height: 12)

        scrollView.documentView = textView
        window.contentView = scrollView

        self.textView = textView
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func show(message: String) {
        textView.string = message
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if keyMonitor != nil { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isEsc = event.keyCode == UInt16(kVK_Escape)
            let isCmdW = event.keyCode == UInt16(kVK_ANSI_W) && event.modifierFlags.contains(.command)
            if isEsc || isCmdW {
                self?.window?.orderOut(nil)
                return nil
            }
            return event
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}

enum KeychainService {
    private static let service = "TranslateGemini"

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
        } else {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
    }
}

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
                        ["text": "Translate the following text from English or Hebrew to Russian. Return only the translation.\n\n\(text)"]
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyRef: EventHotKeyRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x47524D4E), id: 1) // "GRMN"
    private let windowController = TranslationWindowController()
    private var statusItem: NSStatusItem!
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        requestAccessibilityIfNeeded()
        requestInputMonitoringIfNeeded()
        registerHotKey()
    }

    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, userData in
            guard let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if hk.id == delegate.hotKeyID.id {
                DispatchQueue.main.async {
                    delegate.handleHotKey()
                }
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), nil)

        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_L), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func handleHotKey() {
        captureSelectionAndTranslate()
    }

    private func captureSelectionAndTranslate() {
        let hasAX = AXIsProcessTrusted()
        let hasInput = CGPreflightListenEventAccess()
        if !hasAX || !hasInput {
            let axStatus = hasAX ? "OK" : "нет доступа"
            let inputStatus = hasInput ? "OK" : "нет доступа"
            windowController.show(message: "Нет прав.\nAccessibility: \(axStatus)\nInput Monitoring: \(inputStatus)\nОткройте Настройки и включите доступ.")
            return
        }
        if let axText = readSelectedTextViaAccessibility(),
           !axText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            translate(text: axText)
            return
        }
        let initialClipboard = NSPasteboard.general.string(forType: .string) ?? ""
        readSelectionViaCopy { selectedText in
            if selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let currentClipboard = NSPasteboard.general.string(forType: .string) ?? ""
                if !currentClipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   currentClipboard != initialClipboard {
                    self.windowController.show(message: "Не удалось получить выделение, использую буфер…")
                    self.translate(text: currentClipboard)
                    return
                }
                self.promptTranslateClipboardFallback()
                return
            }
            self.translate(text: selectedText)
        }
    }
}

extension AppDelegate {
    private func translate(text: String) {
        Task {
            do {
                self.windowController.show(message: "Перевожу…")
                let apiKey = KeychainService.load(account: "GeminiAPIKey") ?? ""
                if apiKey.isEmpty {
                    self.windowController.show(message: "Не найден ключ Gemini.\nОткройте Настройки и добавьте ключ.")
                    return
                }
                let client = GeminiClient(apiKey: apiKey, model: "gemini-2.5-flash")
                let translation = try await client.translateToRussian(text)
                self.windowController.show(message: translation.isEmpty ? "Пустой ответ от модели." : translation)
            } catch {
                self.windowController.show(message: "Ошибка перевода: \(error.localizedDescription)")
            }
        }
    }

    private func requestAccessibilityIfNeeded() {
        let options: [CFString: Any] = ["AXTrustedCheckOptionPrompt" as CFString: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !trusted {
            showPermissionsAlert(
                title: "Нужен доступ к Accessibility",
                message: "Чтобы считывать выделенный текст, включите доступ в «Конфиденциальность и безопасность → Универсальный доступ».",
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        }
    }

    private func requestInputMonitoringIfNeeded() {
        if CGPreflightListenEventAccess() {
            return
        }
        _ = CGRequestListenEventAccess()
        showPermissionsAlert(
            title: "Нужен доступ к Monitoring ввода",
            message: "Чтобы работать с сочетаниями и копированием выделения, включите доступ в «Конфиденциальность и безопасность → Monitoring ввода».",
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )
    }

    private func showPermissionsAlert(title: String, message: String, settingsURL: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "Открыть настройки")
            alert.addButton(withTitle: "Позже")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn, let url = URL(string: settingsURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func promptTranslateClipboardFallback() {
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            windowController.show(message: "Не удалось получить выделенный текст.\nПопробуйте еще раз или используйте «Перевести буфер» в меню.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Использовать буфер обмена?"
        alert.informativeText = "Выделение не найдено. Перевести текущий текст из буфера обмена?"
        alert.addButton(withTitle: "Перевести")
        alert.addButton(withTitle: "Отмена")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            windowController.show(message: "Перевожу…")
            translate(text: text)
        } else {
            windowController.show(message: "Отменено.")
        }
    }

    private func readSelectionViaCopy(completion: @escaping (String) -> Void) {
        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let clone = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    clone.setData(data, forType: type)
                }
            }
            return clone
        } ?? []
        let initialChangeCount = pasteboard.changeCount

        func sendCopyShortcut() {
            let src = CGEventSource(stateID: .combinedSessionState)
            let cDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
            let cUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
            cDown?.flags = .maskCommand
            cUp?.flags = .maskCommand
            cDown?.post(tap: .cgAnnotatedSessionEventTap)
            cUp?.post(tap: .cgAnnotatedSessionEventTap)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            sendCopyShortcut()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                sendCopyShortcut()
            }

            self.readSelectionWithRetry(pasteboard: pasteboard, initialChangeCount: initialChangeCount, attempts: 18) { selectedText in
                pasteboard.clearContents()
                if !previousItems.isEmpty {
                    _ = pasteboard.writeObjects(previousItems)
                }
                completion(selectedText)
            }
        }
    }

    private func readSelectionWithRetry(
        pasteboard: NSPasteboard,
        initialChangeCount: Int,
        attempts: Int,
        completion: @escaping (String) -> Void
    ) {
        let current = pasteboard.string(forType: .string) ?? ""
        if pasteboard.changeCount != initialChangeCount, !current.isEmpty {
            completion(current)
            return
        }
        if attempts <= 0 {
            completion("")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.readSelectionWithRetry(
                pasteboard: pasteboard,
                initialChangeCount: initialChangeCount,
                attempts: attempts - 1,
                completion: completion
            )
        }
    }
}

extension AppDelegate {
    private func readSelectedTextViaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()

        if let focusedElement = copyAXElementAttribute(systemWide, attribute: kAXFocusedUIElementAttribute as String) {
            if let text = extractSelectedText(from: focusedElement) {
                return text
            }
            if let text = searchSelectedText(in: focusedElement, maxNodes: 250) {
                return text
            }
        }

        if let focusedWindow = copyAXElementAttribute(systemWide, attribute: kAXFocusedWindowAttribute as String) {
            if let text = searchSelectedText(in: focusedWindow, maxNodes: 250) {
                return text
            }
        }

        return nil
    }

    private func copyAXAnyAttribute(_ element: AXUIElement, attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if err == .success, let unwrapped = value {
            return (unwrapped as AnyObject)
        }
        return nil
    }

    private func extractSelectedText(from element: AXUIElement) -> String? {
        if let selected = copyAXAnyAttribute(element, attribute: kAXSelectedTextAttribute as String) as? String {
            let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        let value = copyAXAnyAttribute(element, attribute: kAXValueAttribute as String) as? String
        let rangeRef = copyAXAnyAttribute(element, attribute: kAXSelectedTextRangeAttribute as String)
        if let valueString = value, let axRange = rangeRef {
            var cfRange = CFRange()
            if AXValueGetValue(axRange as! AXValue, .cfRange, &cfRange) {
                if cfRange.location != kCFNotFound, cfRange.length > 0, valueString.count >= cfRange.location {
                    let start = valueString.index(valueString.startIndex, offsetBy: max(0, cfRange.location))
                    let end = valueString.index(start, offsetBy: min(cfRange.length, valueString.count - cfRange.location))
                    return String(valueString[start..<end])
                }
            }
        }

        if let axRange = rangeRef {
            var attributed: CFTypeRef?
            let paramErr = AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXAttributedStringForRangeParameterizedAttribute as CFString,
                axRange,
                &attributed
            )
            if paramErr == .success, let attr = attributed as? NSAttributedString {
                let str = attr.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !str.isEmpty {
                    return str
                }
            }
        }

        return nil
    }

    private func searchSelectedText(in root: AXUIElement, maxNodes: Int) -> String? {
        var queue: [AXUIElement] = [root]
        var visited = 0
        while !queue.isEmpty, visited < maxNodes {
            let element = queue.removeFirst()
            visited += 1
            if let text = extractSelectedText(from: element) {
                return text
            }
            if let children = copyAXAnyAttribute(element, attribute: kAXChildrenAttribute as String) as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }
        return nil
    }

    private func copyAXElementAttribute(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let unwrapped = value else { return nil }
        if CFGetTypeID(unwrapped) == AXUIElementGetTypeID() {
            return (unwrapped as! AXUIElement)
        }
        return nil
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    private let geminiKeyField = NSSecureTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Запускать при входе в систему", target: nil, action: nil)
    private let saveButton = NSButton(title: "Сохранить", target: nil, action: nil)
    private var keyMonitor: Any?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 210),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройки"
        window.center()
        window.isReleasedWhenClosed = false

        let content = NSView(frame: window.contentView?.bounds ?? .zero)
        content.autoresizingMask = [.width, .height]

        let geminiKeyLabel = NSTextField(labelWithString: "Gemini API ключ")
        let modelLabel = NSTextField(labelWithString: "Модель: gemini-2.5-flash")
        let hotkeyLabel = NSTextField(labelWithString: "Горячая клавиша: Shift+Command+L")

        [geminiKeyLabel].forEach { $0.font = NSFont.systemFont(ofSize: 13, weight: .semibold) }
        modelLabel.textColor = .secondaryLabelColor
        hotkeyLabel.textColor = .secondaryLabelColor

        geminiKeyField.placeholderString = "AIza..."

        geminiKeyLabel.frame = NSRect(x: 20, y: 150, width: 200, height: 18)
        geminiKeyField.frame = NSRect(x: 20, y: 125, width: 480, height: 24)

        modelLabel.frame = NSRect(x: 20, y: 95, width: 300, height: 18)
        hotkeyLabel.frame = NSRect(x: 20, y: 70, width: 300, height: 18)

        statusLabel.frame = NSRect(x: 20, y: 40, width: 280, height: 22)
        statusLabel.textColor = .secondaryLabelColor

        launchAtLoginCheckbox.frame = NSRect(x: 300, y: 36, width: 220, height: 24)
        saveButton.frame = NSRect(x: 420, y: 6, width: 80, height: 28)

        content.addSubview(geminiKeyLabel)
        content.addSubview(geminiKeyField)
        content.addSubview(modelLabel)
        content.addSubview(hotkeyLabel)
        content.addSubview(statusLabel)
        content.addSubview(launchAtLoginCheckbox)
        content.addSubview(saveButton)
        window.contentView = content

        super.init(window: window)
        window.delegate = self

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin)
        saveButton.target = self
        saveButton.action = #selector(saveNow)
        geminiKeyField.delegate = self

        loadValues()
    }

    required init?(coder: NSCoder) { nil }

    private func loadValues() {
        if let key = KeychainService.load(account: "GeminiAPIKey") {
            geminiKeyField.stringValue = key
        }
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func saveValues() {
        _ = KeychainService.save(geminiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), account: "GeminiAPIKey")
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        saveValues()
    }

    @objc private func saveNow() {
        saveValues()
        statusLabel.stringValue = "Сохранено"
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            statusLabel.stringValue = "Ошибка автозапуска: \(error.localizedDescription)"
            launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if keyMonitor != nil { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isEsc = event.keyCode == UInt16(kVK_Escape)
            let isCmdW = event.keyCode == UInt16(kVK_ANSI_W) && event.modifierFlags.contains(.command)
            if isEsc || isCmdW {
                self?.window?.orderOut(nil)
                return nil
            }
            return event
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}

extension AppDelegate {
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⇢Я"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Перевести выделение", action: #selector(translateFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Перевести буфер", action: #selector(translateClipboard), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Выход", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func translateFromMenu() {
        handleHotKey()
    }
    
    @objc private func translateClipboard() {
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            windowController.show(message: "Буфер пуст.\nСкопируйте текст (Command+C) и попробуйте снова.")
            return
        }
        windowController.show(message: "Перевожу…")
        translate(text: text)
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
