import AppKit

let app = NSApplication.shared
let delegate = ServerDelegate()
app.delegate = delegate
app.run()
