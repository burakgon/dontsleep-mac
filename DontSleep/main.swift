import AppKit

// DontSleep has no windows and no storyboard: the delegate below is the whole app.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
