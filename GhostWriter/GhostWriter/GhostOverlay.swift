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
        self.level = .statusBar
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Configure text field to display autocomplete ghost text
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.textColor = NSColor.lightGray
        let systemFont = NSFont.systemFont(ofSize: 13)
        textField.font = NSFontManager.shared.convert(systemFont, toHaveTrait: .italicFontMask)
        textField.frame = contentView!.bounds
        textField.autoresizingMask = [.width, .height]
        
        contentView!.addSubview(textField)
    }
    
    func show(text: String, at cursorRect: CGRect) {
        self.textField.stringValue = text
        
        // Adjust coordinates:
        // AXUIElement's selected bounds are in screen coordinates where Y=0 is at the top.
        // NSWindow setFrameOrigin uses screen coordinates where Y=0 is at the bottom.
        if let mainScreen = NSScreen.main {
            let screenHeight = mainScreen.frame.height
            
            // Position overlay immediately to the right of the active text cursor
            let targetX = cursorRect.origin.x + cursorRect.width
            let targetY = screenHeight - cursorRect.origin.y - cursorRect.height
            
            self.setFrameOrigin(CGPoint(x: targetX, y: targetY))
            self.orderFront(nil)
        }
    }
    
    func hide() {
        self.orderOut(nil)
    }
}
