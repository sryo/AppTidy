import Cocoa

// Explicit entry point to ensure AppDelegate is connected properly
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
