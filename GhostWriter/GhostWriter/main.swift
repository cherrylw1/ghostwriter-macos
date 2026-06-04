import Cocoa

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate

// Start the Cocoa application event loop
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
