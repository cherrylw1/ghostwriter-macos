import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        checkAccessibility()
        ContextHarvester.shared.start()
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
