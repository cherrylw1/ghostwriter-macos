import Cocoa
import ApplicationServices

class ContextHarvester {
    static let shared = ContextHarvester()
    
    private var lastActiveAppBundleId: String?
    private var typingTimer: Timer?
    private var keyboardMonitor: Any?
    
    private init() {}
    
    func start() {
        setupActiveAppObserver()
        setupKeyboardObserver()
    }
    
    private func setupActiveAppObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppActivation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // Log current active app on start
        if let currentApp = NSWorkspace.shared.frontmostApplication {
            logActiveApp(currentApp)
        }
    }
    
    @objc private func handleAppActivation(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            logActiveApp(app)
            
            // Re-attempt keyboard monitor setup in case permission was granted
            setupKeyboardObserver()
        }
    }
    
    private func logActiveApp(_ app: NSRunningApplication) {
        let bundleId = app.bundleIdentifier ?? "Unknown"
        let name = app.localizedName ?? "Unknown"
        
        if bundleId != lastActiveAppBundleId {
            lastActiveAppBundleId = bundleId
            print("📱 Active App Changed: \(name) [\(bundleId)]")
        }
    }
    
    private func setupKeyboardObserver() {
        guard keyboardMonitor == nil else { return }
        
        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.resetTypingTimer()
        }
    }
    
    private func resetTypingTimer() {
        // Run on the main queue to ensure thread safety with timers and UI element reads
        DispatchQueue.main.async { [weak self] in
            self?.typingTimer?.invalidate()
            self?.typingTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                self?.harvestContext()
            }
        }
    }
    
    private func harvestContext() {
        let activeAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        let (prefix, suffix) = getSurroundingText()
        
        print("✍️ Typing paused (300ms) in: \(activeAppName)")
        print("  - Prefix: \(prefix)")
        print("  - Suffix: \(suffix)")
    }
    
    private func getSurroundingText() -> (prefix: String, suffix: String) {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementObj: AnyObject?
        
        let error = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElementObj)
        guard error == .success, let focusedElement = focusedElementObj else {
            return ("", "")
        }
        
        let element = focusedElement as! AXUIElement
        
        // Get value
        var valueObj: AnyObject?
        let valueError = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueObj)
        guard valueError == .success, let fullText = valueObj as? String else {
            return ("", "")
        }
        
        // Get selection range
        var selectedRangeValue: AnyObject?
        let rangeError = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)
        
        let utf16Count = fullText.utf16.count
        var cursorPosition = utf16Count
        
        if rangeError == .success, let selectedRangeVal = selectedRangeValue {
            var range = CFRange()
            if AXValueGetValue(selectedRangeVal as! AXValue, .cfRange, &range) {
                cursorPosition = range.location
            }
        }
        
        let safeCursor = min(utf16Count, max(0, cursorPosition))
        let prefixStart = max(0, safeCursor - 500)
        let prefixEnd = safeCursor
        let suffixStart = safeCursor
        let suffixEnd = min(utf16Count, safeCursor + 200)
        
        let prefixNSRange = NSRange(location: prefixStart, length: prefixEnd - prefixStart)
        let suffixNSRange = NSRange(location: suffixStart, length: suffixEnd - suffixStart)
        
        let prefix = Range(prefixNSRange, in: fullText).map { String(fullText[$0]) } ?? ""
        let suffix = Range(suffixNSRange, in: fullText).map { String(fullText[$0]) } ?? ""
        
        return (prefix, suffix)
    }
}
