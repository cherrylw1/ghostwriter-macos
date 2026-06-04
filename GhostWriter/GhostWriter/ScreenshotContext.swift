import Cocoa
import CoreGraphics

class ScreenshotContext {
    static func captureActiveWindow() async -> String? {
        guard let activeApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let activePID = activeApp.processIdentifier
        
        let options = CGWindowListOption.excludeDesktopElements
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: AnyObject]] else {
            return nil
        }
        
        var activeWindowID: CGWindowID?
        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == activePID else {
                continue
            }
            
            guard let isOnscreen = window[kCGWindowIsOnscreen as String] as? Bool,
                  isOnscreen else {
                continue
            }
            
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0 else {
                continue
            }
            
            if let windowNumber = window[kCGWindowNumber as String] as? CGWindowID {
                activeWindowID = windowNumber
                break
            }
        }
        
        guard let windowID = activeWindowID else { return nil }
        
        guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, .nominalResolution) else {
            return nil
        }
        
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        let properties: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: 0.6]
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: properties) else {
            return nil
        }
        
        return jpegData.base64EncodedString()
    }
}
