import Cocoa

class GhostOverlay: NSPanel {
    static let shared = GhostOverlay()
    private let textField = NSTextField()
    
    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        
        // Window level set to floating + 1 to appear above Chrome windows
        self.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Configure text field: gray, clear background, plain system 13pt font, borderless
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.textColor = NSColor.gray
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.frame = contentView!.bounds
        textField.autoresizingMask = [.width, .height]
        
        contentView!.addSubview(textField)
    }
    
    func show(text: String, at cursorRect: CGRect?) {
        DispatchQueue.main.async {
            self.textField.stringValue = text
            self.alphaValue = 1.0
            
            let targetX: CGFloat
            let targetY: CGFloat
            
            if let rect = cursorRect, let mainScreen = NSScreen.main {
                let screenHeight = mainScreen.frame.height
                // Position immediately to the right of the cursor bounds
                targetX = rect.origin.x + rect.width
                targetY = screenHeight - rect.origin.y - rect.height
            } else {
                // Fallback: 20px below and 0px right of the mouse cursor coordinates
                let mouseLoc = NSEvent.mouseLocation
                targetX = mouseLoc.x
                targetY = mouseLoc.y - 20
            }
            
            self.setFrameOrigin(CGPoint(x: targetX, y: targetY))
            self.orderFrontRegardless()
            print("🪟 Overlay shown at coordinates: [\(targetX), \(targetY)]")
        }
    }
    
    func hide() {
        DispatchQueue.main.async {
            self.alphaValue = 0.0
            self.orderOut(nil)
        }
    }
}
