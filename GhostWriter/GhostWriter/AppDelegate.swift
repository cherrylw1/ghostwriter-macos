import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate? {
        return NSApplication.shared.delegate as? AppDelegate
    }
    
    var currentPrediction: String?
    var currentPrefix: String?
    var currentAppName: String?
    
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
        guard GhostOverlay.shared.isVisible else {
            return false
        }
        
        if keyCode == 48 { // Tab key
            if let prediction = currentPrediction,
               let prefix = currentPrefix,
               let appName = currentAppName {
                
                // Inject prediction text via AXUIElement
                insertText(prediction)
                
                // Save to StyleDB
                StyleDB.shared.saveCompletion(appName: appName, prefix: prefix, acceptedText: prediction)
                
                print("✅ Accepted: [\(prediction)]")
                print("💾 Saved to style DB")
            }
            
            GhostOverlay.shared.hide()
            clearPrediction()
            return true // Suppress Tab key
        } else if keyCode == 53 { // Escape key
            print("❌ Rejected")
            GhostOverlay.shared.hide()
            clearPrediction()
            return true // Suppress Escape key
        } else {
            // Any other key: dismiss suggestion, log what was typed, and pass key event
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
    
    private func clearPrediction() {
        currentPrediction = nil
        currentPrefix = nil
        currentAppName = nil
    }
    
    private func insertText(_ text: String) {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementObj: AnyObject?
        let error = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElementObj)
        guard error == .success, let focusedElement = focusedElementObj else { return }
        
        // Inject the text using kAXSelectedTextAttribute (replaces selection or inserts at cursor)
        AXUIElementSetAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
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
