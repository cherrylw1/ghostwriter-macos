import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate? {
        return NSApplication.shared.delegate as? AppDelegate
    }
    
    var currentPrediction: String?
    var currentPrefix: String?
    var currentAppName: String?
    var isOverlayVisible = false
    var isInGracePeriod = false
    
    private var eventTap: CFRunLoopSource?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        checkAccessibility()
        ContextHarvester.shared.start()
        setupEventTap()
    }
    
    func setupEventTap() {
        guard eventTap == nil else { return }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            guard type == .keyDown else {
                return Unmanaged.passRetained(event)
            }
            
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            
            guard let refcon = refcon else {
                return Unmanaged.passRetained(event)
            }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
            
            if delegate.handleKeyEvent(event: event, keyCode: keyCode) {
                return nil // Suppress event
            }
            
            return Unmanaged.passRetained(event)
        }
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return
        }
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.eventTap = runLoopSource
        print("✅ Event tap established")
    }
    
    func handleKeyEvent(event: CGEvent, keyCode: Int64) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == 999 {
            return false // Let our simulated events pass through
        }
        
        if isInGracePeriod {
            return false // During grace period, all keys pass silently
        }
        
        guard isOverlayVisible else {
            return false
        }
        
        if keyCode == 48 { // Tab key
            if let appName = currentAppName {
                let (prefix, _) = ContextHarvester.shared.getSurroundingText()
                let words = GhostOverlay.shared.words
                let index = GhostOverlay.shared.currentWordIndex
                
                if index < words.count {
                    let word = words[index]
                    let fragment = getLastWordFragment(from: prefix)
                    
                    // Inject word via simulated keyboard typing with 10ms delays
                    injectWordViaKeyboard(word: word, fragment: fragment) {
                        // This completion runs after the keystroke simulation finishes typing the word + space
                        StyleDB.shared.saveCompletion(appName: appName, prefix: prefix, acceptedText: word)
                        print("✅ Accepted word: [\(word)]")
                        
                        // Add a 500ms cooldown after any Tab word acceptance
                        ContextHarvester.shared.isCoolingDown = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                            ContextHarvester.shared.isCoolingDown = false
                        }
                        
                        GhostOverlay.shared.currentWordIndex += 1
                        
                        if GhostOverlay.shared.currentWordIndex >= words.count {
                            print("✅ All words accepted")
                            self.isOverlayVisible = false
                            GhostOverlay.shared.hide()
                            self.clearPrediction()
                        } else {
                            GhostOverlay.shared.updateOverlayTextAndPosition()
                        }
                    }
                } else {
                    isOverlayVisible = false
                    GhostOverlay.shared.hide()
                    clearPrediction()
                }
            } else {
                isOverlayVisible = false
                GhostOverlay.shared.hide()
                clearPrediction()
            }
            return true // Suppress Tab key
        } else if keyCode == 53 { // Escape key
            isOverlayVisible = false
            print("❌ Rejected")
            
            GhostOverlay.shared.hide()
            clearPrediction()
            return true // Suppress Escape key
        } else {
            // Any other key: dismiss suggestion, log what was typed, and pass key event
            isOverlayVisible = false
            var typed = ""
            if let nsEvent = NSEvent(cgEvent: event) {
                typed = nsEvent.characters ?? ""
            }
            print("❌ Rejected (typed: '\(typed)')")
            
            GhostOverlay.shared.hide()
            clearPrediction()
            return false // Let the key event pass through to target application
        }
    }
    
    private func getLastWordFragment(from prefix: String) -> String {
        if prefix.isEmpty { return "" }
        if let lastChar = prefix.last, lastChar.isWhitespace {
            return ""
        }
        let components = prefix.components(separatedBy: .whitespacesAndNewlines)
        return components.last ?? ""
    }
    
    private func clearPrediction() {
        currentPrediction = nil
        currentPrefix = nil
        currentAppName = nil
        isOverlayVisible = false
        
        isInGracePeriod = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) { [weak self] in
            self?.isInGracePeriod = false
        }
    }
    
    private func injectWordViaKeyboard(word: String, fragment: String, completion: @escaping () -> Void) {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // 1. Store current clipboard contents to restore later
        let pasteboard = NSPasteboard.general
        var clipboardBackup: [NSPasteboardItem] = []
        if let items = pasteboard.pasteboardItems {
            for item in items {
                let backupItem = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        backupItem.setData(data, forType: type)
                    }
                }
                clipboardBackup.append(backupItem)
            }
        }
        
        // 2. Set NSPasteboard.general string to the word + space
        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(word + " ", forType: .string)
        
        // Helper to simulate Cmd+V paste (keycode 9 with .maskCommand flag)
        func performPaste() {
            guard let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) else {
                completion()
                return
            }
            cmdVDown.flags = .maskCommand
            cmdVDown.setIntegerValueField(.eventSourceUserData, value: 999)
            
            guard let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
                completion()
                return
            }
            cmdVUp.flags = .maskCommand
            cmdVUp.setIntegerValueField(.eventSourceUserData, value: 999)
            
            cmdVDown.post(tap: .cgSessionEventTap)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
                cmdVUp.post(tap: .cgSessionEventTap)
                
                // After 50ms restore original clipboard contents
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
                    pasteboard.clearContents()
                    if !clipboardBackup.isEmpty {
                        pasteboard.writeObjects(clipboardBackup)
                    }
                    completion()
                }
            }
        }
        
        let hasOverlap = !fragment.isEmpty && word.lowercased().hasPrefix(fragment.lowercased())
        
        if hasOverlap {
            let fragmentLength = fragment.count
            deleteFragment(count: fragmentLength) {
                performPaste()
            }
        } else {
            performPaste()
        }
    }
    
    private func deleteFragment(count: Int, completion: @escaping () -> Void) {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        func backspace(remaining: Int) {
            guard remaining > 0 else {
                completion()
                return
            }
            
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true) {
                keyDown.setIntegerValueField(.eventSourceUserData, value: 999)
                keyDown.post(tap: .cgSessionEventTap)
            }
            
            if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false) {
                keyUp.setIntegerValueField(.eventSourceUserData, value: 999)
                keyUp.post(tap: .cgSessionEventTap)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) {
                backspace(remaining: remaining - 1)
            }
        }
        
        backspace(remaining: count)
    }
    
    private func checkAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if isTrusted {
            print("✅ Accessibility access granted")
        } else {
            print("⚠️ Accessibility access DENIED — go to System Settings > Privacy & Security > Accessibility and enable GhostWriter")
        }
    }
}
