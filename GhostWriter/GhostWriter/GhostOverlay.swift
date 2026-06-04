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
    
    var words: [String] = []
    var currentWordIndex: Int = 0
    
    func show(text: String, at cursorRect: CGRect?) {
        DispatchQueue.main.async {
            self.words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            self.currentWordIndex = 0
            
            // Part 1 - Always display the FULL first word of the prediction
            let (prefixText, _) = ContextHarvester.shared.getSurroundingText()
            let fragment = self.getLastWordFragment(from: prefixText)
            if !fragment.isEmpty, let firstWord = self.words.first {
                if !firstWord.lowercased().hasPrefix(fragment.lowercased()) {
                    let fullFirstWord = fragment + firstWord
                    self.words[0] = fullFirstWord
                }
            }
            
            let remainingWords = self.words[self.currentWordIndex...]
            self.textField.stringValue = remainingWords.joined(separator: " ")
            self.alphaValue = 1.0
            
            self.positionOverlay(at: cursorRect)
            self.orderFrontRegardless()
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
    
    func positionOverlay(at cursorRect: CGRect?) {
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
        print("🪟 Overlay shown at coordinates: [\(targetX), \(targetY)]")
    }
    
    func updateOverlayTextAndPosition() {
        DispatchQueue.main.async {
            guard self.currentWordIndex < self.words.count else {
                self.hide()
                return
            }
            
            let remainingWords = self.words[self.currentWordIndex...]
            self.textField.stringValue = remainingWords.joined(separator: " ")
            
            let cursorRect = ContextHarvester.shared.getFocusedElementCursorRect()
            self.positionOverlay(at: cursorRect)
        }
    }
    
    func hide() {
        DispatchQueue.main.async {
            self.alphaValue = 0.0
            self.orderOut(nil)
            self.words = []
            self.currentWordIndex = 0
        }
    }
}
