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
                    
                    // Partial word awareness: compare last word fragment in prefix with current word
                    let fragment = getLastWordFragment(from: prefix)
                    var textToInject = word
                    if !fragment.isEmpty && word.lowercased().hasPrefix(fragment.lowercased()) {
                        textToInject = String(word.dropFirst(fragment.count))
                    }
                    
                    let completionToInject = textToInject + " "
                    insertText(completionToInject)
                    
                    // Save this word acceptance to StyleDB
                    StyleDB.shared.saveCompletion(appName: appName, prefix: prefix, acceptedText: word)
                    print("✅ Accepted word: [\(word)] (injected: [\(completionToInject)])")
                    
                    GhostOverlay.shared.currentWordIndex += 1
                    
                    if GhostOverlay.shared.currentWordIndex >= words.count {
                        print("✅ All words accepted")
                        isOverlayVisible = false
                        GhostOverlay.shared.hide()
                        clearPrediction()
                    } else {
                        GhostOverlay.shared.updateOverlayTextAndPosition()
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
    }
    
    private func insertText(_ text: String) {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementObj: AnyObject?
        let error = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElementObj)
        guard error == .success, let focusedElement = focusedElementObj else {
            simulateKeyboardTyping(text)
            return
        }
        
        let element = focusedElement as! AXUIElement
        
        // 1. Read current kAXValueAttribute
        var valueObj: AnyObject?
        let valueError = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueObj)
        
        // 2. Read current kAXSelectedTextRangeAttribute
        var selectedRangeValue: AnyObject?
        let rangeError = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)
        
        guard valueError == .success, let fullText = valueObj as? String,
              rangeError == .success, let rangeVal = selectedRangeValue else {
            simulateKeyboardTyping(text)
            return
        }
        
        var range = CFRange()
        guard AXValueGetValue(rangeVal as! AXValue, .cfRange, &range) else {
            simulateKeyboardTyping(text)
            return
        }
        
        // 3. Insert prediction text at cursor position by replacing the selected range
        let nsFullText = fullText as NSString
        let prefix = nsFullText.substring(to: range.location)
        let suffix = nsFullText.substring(from: range.location + range.length)
        let newFullText = prefix + text + suffix
        
        // 4. Update kAXValueAttribute with the new complete string
        let setStatus = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newFullText as CFTypeRef)
        
        if setStatus == .success {
            // 5. Move cursor to the end of the inserted text
            let newCursorLocation = range.location + text.count
            var newRange = CFRange(location: newCursorLocation, length: 0)
            if let newRangeValue = AXValueCreate(.cfRange, &newRange) {
                _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, newRangeValue)
            }
        } else {
            simulateKeyboardTyping(text)
        }
    }
    
    private func simulateKeyboardTyping(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let utf16Chars = Array(text.utf16)
        
        for char in utf16Chars {
            var unichar = char
            
            // Post Key Down
            let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            keyDownEvent?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
            keyDownEvent?.post(tap: .cgSessionEventTap)
            
            // Post Key Up
            let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            keyUpEvent?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
            keyUpEvent?.post(tap: .cgSessionEventTap)
        }
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
