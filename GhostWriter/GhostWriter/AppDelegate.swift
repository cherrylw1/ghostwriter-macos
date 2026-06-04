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
        var events: [CGEvent] = []
        
        // 1. First select the partial word fragment already typed using CGEvent with shift+left arrows
        let fragmentLength = fragment.count
        if fragmentLength > 0 {
            for _ in 0..<fragmentLength {
                if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 123, keyDown: true) {
                    keyDown.flags = .maskShift
                    keyDown.setIntegerValueField(.eventSourceUserData, value: 999)
                    events.append(keyDown)
                }
                if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 123, keyDown: false) {
                    keyUp.flags = .maskShift
                    keyUp.setIntegerValueField(.eventSourceUserData, value: 999)
                    events.append(keyUp)
                }
            }
        }
        
        // 2. Then simulate typing the FULL prediction word character by character using CGEventKeyboardSetUnicodeString
        let utf16Chars = Array(word.utf16)
        for char in utf16Chars {
            var unichar = char
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                keyDown.setIntegerValueField(.eventSourceUserData, value: 999)
                events.append(keyDown)
            }
            if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                keyUp.setIntegerValueField(.eventSourceUserData, value: 999)
                events.append(keyUp)
            }
        }
        
        // 3. Then simulate a space character
        var spaceChar: UInt16 = 32
        if let spaceDown = CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: true) {
            spaceDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &spaceChar)
            spaceDown.setIntegerValueField(.eventSourceUserData, value: 999)
            events.append(spaceDown)
        }
        if let spaceUp = CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: false) {
            spaceUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &spaceChar)
            spaceUp.setIntegerValueField(.eventSourceUserData, value: 999)
            events.append(spaceUp)
        }
        
        if events.isEmpty {
            completion()
            return
        }
        
        // Post events with a 10ms delay between each event
        for (index, event) in events.enumerated() {
            let delay = index * 10
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
                event.post(tap: .cgSessionEventTap)
                if index == events.count - 1 {
                    // Settle time for last key event to process before executing callback
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
                        completion()
                    }
                }
            }
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
