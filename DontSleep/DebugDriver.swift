#if DEBUG
import AppKit

/// Stands in for a hand on the mouse and keyboard in debug builds, so that the interface can
/// be tested and photographed from a script. It reads one command per line from the named
/// pipe in the DONTSLEEP_DEBUG_PIPE environment variable:
///
///     menu | close                     open or close the menu
///     click | rightclick | optionclick click the icon in the menu bar
///     key down|up|left|right|return|space|escape
///     icon lightBulb|coffeeCup|...     wear another look in the menu bar
///     stage | unstage                  cover the screen with a plain backdrop, for pictures
///     dismiss                          close the welcome, as its Done button would
///     frame                            print where the icon is on screen
///
/// Release builds do not contain any of this.
final class DebugDriver {
    private let menuBarItem: MenuBarItem
    private var source: DispatchSourceRead?
    private var backdrop: NSWindow?

    init?(menuBarItem: MenuBarItem) {
        guard let path = ProcessInfo.processInfo.environment["DONTSLEEP_DEBUG_PIPE"] else { return nil }
        // Opened for writing as well, so that the pipe stays open between writers.
        let descriptor = open(path, O_RDWR | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        self.menuBarItem = menuBarItem

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .global())
        // Runs on a background queue, so it must not inherit this type's place on the main actor.
        source.setEventHandler { @Sendable [weak self] in
            var buffer = [UInt8](repeating: 0, count: 1024)
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { return }
            for line in String(decoding: buffer[..<count], as: UTF8.self).split(separator: "\n") {
                let command = String(line)
                // Through the run loop, so that commands arrive while the menu is open.
                MainRunLoop.async { self?.run(command) }
            }
        }
        source.resume()
        self.source = source
    }

    private func run(_ command: String) {
        let words = command.split(separator: " ").map(String.init)
        let handles = menuBarItem.debugHandles
        switch words.first {
        case "menu":
            menuBarItem.showMenu()
        case "close":
            handles.menu.cancelTracking()
        case "click":
            click(handles.button, type: .leftMouseDown, flags: [])
        case "rightclick":
            click(handles.button, type: .rightMouseDown, flags: [])
        case "optionclick":
            click(handles.button, type: .leftMouseDown, flags: .option)
        case "key":
            key(words.last ?? "")
        case "icon":
            if let style = words.last.flatMap(IconStyle.init) { menuBarItem.iconStyle = style }
        case "dismiss":
            NSApp.abortModal()
        case "stage":
            stage()
        case "unstage":
            backdrop?.orderOut(nil)
            backdrop = nil
        case "frame":
            let icon = handles.button?.window?.frame ?? .zero
            print("icon \(Int(icon.minX)) \(Int(icon.minY)) \(Int(icon.width)) \(Int(icon.height))")
            fflush(stdout)
        default:
            print("unknown debug command: \(command)")
            fflush(stdout)
        }
    }

    /// Covers the screen, menu bar included, with a plain backdrop that shows nothing but
    /// this app's icon where it really is. The menu still opens above it, so a picture of
    /// the menu has nothing of the desktop or of other apps in it.
    private func stage() {
        guard backdrop == nil, let button = menuBarItem.debugHandles.button,
              let item = button.window, let screen = item.screen else { return }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        let view = StageView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.item = item.frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        view.icon = button.image
        window.contentView = view
        window.orderFrontRegardless()
        backdrop = window
    }

    /// Posts a press and release in the middle of `view`, as the window server would.
    private func click(_ view: NSView?, type down: NSEvent.EventType, flags: NSEvent.ModifierFlags) {
        guard let view, let window = view.window else { return }
        let location = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        let up: NSEvent.EventType = down == .rightMouseDown ? .rightMouseUp : .leftMouseUp
        for type in [down, up] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
    }

    private func key(_ name: String) {
        let keys: [String: (code: UInt16, characters: String)] = [
            "down": (125, "\u{F701}"), "up": (126, "\u{F700}"), "left": (123, "\u{F702}"), "right": (124, "\u{F703}"),
            "return": (36, "\r"), "space": (49, " "), "escape": (53, "\u{1B}"),
        ]
        guard let key = keys[name] else { return }
        let window = NSApp.keyWindow?.windowNumber ?? 0
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window, context: nil, characters: key.characters,
                charactersIgnoringModifiers: key.characters, isARepeat: false, keyCode: key.code) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
    }
}

/// The backdrop of `stage`: a night sky, and a menu bar with one icon in it.
private final class StageView: NSView {
    var item = NSRect.zero
    var icon: NSImage?

    override func draw(_ dirtyRect: NSRect) {
        let night = NSColor(displayP3Red: 0.05, green: 0.05, blue: 0.16, alpha: 1)
        night.setFill()
        bounds.fill()
        let sky = NSRect(x: 0, y: bounds.maxY - 420, width: bounds.width, height: 420)
        NSGradient(starting: night, ending: NSColor(displayP3Red: 0.27, green: 0.23, blue: 0.62, alpha: 1))?.draw(in: sky, angle: 90)

        // The icon is highlighted, the way the menu bar shows the item whose menu is open.
        let highlight = NSRect(x: item.minX + 2, y: item.midY - 12, width: item.width - 4, height: 24)
        NSColor(white: 1, alpha: 0.16).setFill()
        NSBezierPath(roundedRect: highlight, xRadius: 7, yRadius: 7).fill()
        guard let icon = icon?.withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) ?? icon else { return }
        let white = NSImage(size: icon.size, flipped: false) { rect in
            icon.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let alignment = icon.alignmentRect
        white.draw(at: NSPoint(x: item.midX - alignment.midX, y: item.midY - alignment.midY), from: .zero, operation: .sourceOver, fraction: 1)
    }
}
#endif
