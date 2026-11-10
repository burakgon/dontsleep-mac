import AppKit
import DontSleepKit

/// The icon in the menu bar and the menu under it: the whole interface of the app.
///
/// It is an ordinary menu of ordinary items, which macOS draws, highlights, reads aloud and
/// lets the keyboard navigate without any help from the app. Nothing here runs unless
/// something happens: the menu is brought up to date when it is about to open and the icon
/// when the state changes. There is no timer and no polling.
final class MenuBarItem: NSObject, NSMenuDelegate {
    private static let durations: [(title: String, seconds: TimeInterval)] = [
        ("15 Minutes", 15 * 60), ("30 Minutes", 30 * 60), ("1 Hour", 3600),
        ("2 Hours", 2 * 3600), ("4 Hours", 4 * 3600), ("8 Hours", 8 * 3600),
    ]

    private let keepAwake: KeepAwake
    private let updater: Updater
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let durationsMenu = NSMenu()
    private let settingsMenu = NSMenu()
    private let iconMenu = NSMenu()
    private let updateItem = NSMenuItem(title: "Update Available…", action: #selector(checkForUpdates), keyEquivalent: "")
    private let keepAwakeItem = NSMenuItem(title: "Keep Awake", action: #selector(toggleKeepAwake), keyEquivalent: "")
    private let displaySleepItem = NSMenuItem(title: "Allow Display Sleep", action: #selector(toggleDisplaySleep), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
    private let automaticUpdatesItem = NSMenuItem(title: "Update Automatically", action: #selector(toggleAutomaticUpdates), keyEquivalent: "")
    private let commandLineToolItem = NSMenuItem(title: "Command Line Tool", action: #selector(toggleCommandLineTool), keyEquivalent: "")
    private var clickMonitor: Any?

    private(set) var isMenuOpen = false
    var onMenuClose: (() -> Void)?

    /// The look of the icon in the menu bar. Remembered when changed.
    var iconStyle = IconStyle.chosen {
        didSet {
            IconStyle.chosen = iconStyle
            refresh()
        }
    }

    init(keepAwake: KeepAwake, updater: Updater) {
        self.keepAwake = keepAwake
        self.updater = updater
        super.init()
        buildMenus()
        statusItem.autosaveName = "DontSleep"
        statusItem.menu = menu
        watchForQuickToggle()
        refresh()
    }

    /// Shows the menu as if the icon had been clicked.
    @objc func showMenu() {
        guard !isMenuOpen else { return }
        statusItem.button?.performClick(nil)
    }

    /// Brings the icon and the menu in line with the state.
    func refresh() {
        let isActive = keepAwake.isActive
        show(iconStyle, isActive: isActive)
        statusItem.button?.toolTip = isActive
            ? "Your Mac is being kept awake. Right-click to turn off."
            : "Your Mac sleeps as usual. Right-click to keep it awake."

        keepAwakeItem.state = isActive ? .on : .off
        keepAwakeItem.subtitle = keepAwake.endsAt.map { end in
            // The time is enough for today and tonight. Further out it needs the date.
            let soon = end.timeIntervalSinceNow < 20 * 3600
            return "Until \(end.formatted(date: soon ? .omitted : .numeric, time: .shortened))"
        }
        displaySleepItem.state = keepAwake.allowsDisplaySleep ? .on : .off
        for item in durationsMenu.items {
            item.state = isActive && keepAwake.duration == item.representedObject as? TimeInterval ? .on : .off
        }
    }

    // MARK: - Menus

    private func buildMenus() {
        menu.delegate = self
        menu.autoenablesItems = false
        updateItem.isHidden = true
        durationsMenu.autoenablesItems = false
        for duration in Self.durations {
            let item = NSMenuItem(title: duration.title, action: #selector(keepAwakeForDuration), keyEquivalent: "")
            item.representedObject = duration.seconds
            durationsMenu.addItem(item)
        }
        iconMenu.delegate = self
        iconMenu.autoenablesItems = false
        for style in IconStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(chooseIcon), keyEquivalent: "")
            item.representedObject = style.rawValue
            item.image = style.image(isActive: true)
            // macOS 27 hides the images of menu items unless they are the point, as here.
            if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
            iconMenu.addItem(item)
        }
        settingsMenu.delegate = self
        settingsMenu.autoenablesItems = false
        settingsMenu.items = [
            submenuItem("Menu Bar Icon", iconMenu), .separator(),
            loginItem, automaticUpdatesItem, commandLineToolItem, .separator(),
            NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: ""),
            NSMenuItem(title: "About DontSleep", action: #selector(showAbout), keyEquivalent: ""),
        ]
        menu.items = [
            updateItem,
            keepAwakeItem, submenuItem("Keep Awake For", durationsMenu), .separator(),
            displaySleepItem, .separator(),
            submenuItem("Settings", settingsMenu),
            NSMenuItem(title: "Quit DontSleep", action: #selector(NSApplication.terminate), keyEquivalent: "q"),
        ]
        // Everything but Quit, which the app itself answers, is handled here.
        for item in menu.items + durationsMenu.items + settingsMenu.items + iconMenu.items where item.action != #selector(NSApplication.terminate) {
            item.target = self
        }
    }

    private func submenuItem(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === iconMenu {
            // Whatever was being tried on gives way to what is chosen.
            refresh()
        }
        guard menu === self.menu else { return }
        isMenuOpen = false
        onMenuClose?()
    }

    /// Pointing at a look in the Menu Bar Icon menu tries it on in the menu bar itself.
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard menu === iconMenu else { return }
        let style = (item?.representedObject as? String).flatMap(IconStyle.init) ?? iconStyle
        show(style, isActive: keepAwake.isActive)
    }

    /// Puts a look in the menu bar: filled in while on, outlined and dimmed while off.
    private func show(_ style: IconStyle, isActive: Bool) {
        statusItem.button?.image = style.image(isActive: isActive)
        statusItem.button?.appearsDisabled = !isActive
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === self.menu {
            // "Until 14:30" may have turned into the date, and an update may be waiting.
            refresh()
            updateItem.isHidden = !updater.hasUpdateWaitingForAttention
        } else if menu === settingsMenu {
            // These are looked up only when the submenu opens: they ask the system.
            loginItem.state = LoginItem.isEnabled ? .on : .off
            automaticUpdatesItem.state = updater.updatesAutomatically ? .on : .off
            commandLineToolItem.state = CommandLineTool.installedLink != nil ? .on : .off
        } else if menu === iconMenu {
            for item in iconMenu.items {
                item.state = item.representedObject as? String == iconStyle.rawValue ? .on : .off
            }
        }
    }

    // MARK: - Keeping awake

    private func setActive(_ active: Bool, for duration: TimeInterval? = nil) {
        guard active else { return keepAwake.stop() }
        do {
            try keepAwake.start(for: duration)
        } catch {
            Alert.show("DontSleep couldn’t keep your Mac awake", error.description)
        }
    }

    @objc private func toggleKeepAwake() {
        setActive(!keepAwake.isActive)
    }

    @objc private func keepAwakeForDuration(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        // Choosing the duration that is running turns it off again, like any checked item.
        if keepAwake.isActive, keepAwake.duration == seconds {
            keepAwake.stop()
        } else {
            setActive(true, for: seconds)
        }
    }

    @objc private func toggleDisplaySleep() {
        keepAwake.allowsDisplaySleep.toggle()
    }

    /// A right-click, or a click with Option or Control held, turns DontSleep on or off
    /// without opening the menu. Ordinary clicks never reach this code: the system shows
    /// the menu for them.
    private func watchForQuickToggle() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window === statusItem.button?.window else { return event }
            let isQuick = event.type == .rightMouseDown || !event.modifierFlags.isDisjoint(with: [.option, .control])
            guard isQuick else { return event }
            setActive(!keepAwake.isActive)
            return nil
        }
    }

    // MARK: - Settings

    @objc private func chooseIcon(_ sender: NSMenuItem) {
        guard let style = (sender.representedObject as? String).flatMap(IconStyle.init) else { return }
        iconStyle = style
    }

    @objc private func toggleOpenAtLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            Alert.show("DontSleep couldn’t change its login item", error.localizedDescription,
                       button: "Open Login Items Settings") { LoginItem.openSystemSettings() }
        }
    }

    @objc private func toggleAutomaticUpdates() {
        updater.updatesAutomatically.toggle()
    }

    @objc private func toggleCommandLineTool() {
        do {
            if CommandLineTool.installedLink != nil {
                try CommandLineTool.uninstall()
            } else {
                let link = try CommandLineTool.install()
                Alert.show("The dontsleep command is ready",
                           "It is installed at \(link.path). Try it in Terminal:\n\ndontsleep on --for 2h\ndontsleep status\ndontsleep --help")
            }
        } catch let error as CommandLineTool.Failure {
            switch error {
            case .noWritableFolder(let command):
                Alert.show("Installing the dontsleep command needs your password",
                           "None of the usual folders for commands can be written without it. Run this in Terminal instead:\n\n\(command)",
                           button: "Copy Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
            case .occupied(let path):
                Alert.show("Something else is already installed at \(path)",
                           "DontSleep left it alone. Remove or rename it, then try again.")
            }
        } catch {
            Alert.show("DontSleep couldn’t install the dontsleep command", error.localizedDescription)
        }
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func showAbout() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString(string: "Keeps your Mac awake.\n", attributes: attributes)
        var link = attributes
        link[.link] = URL(string: "https://github.com/burakgon/dontsleep-mac")
        credits.append(NSAttributedString(string: "github.com/burakgon/dontsleep-mac", attributes: link))

        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}

/// An alert from an app without windows: it has to step forward first.
enum Alert {
    static func show(_ message: String, _ detail: String, button: String? = nil, action: (() -> Void)? = nil) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        if let button {
            alert.addButton(withTitle: button)
            alert.addButton(withTitle: "Cancel")
        }
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn, button != nil {
            action?()
        }
    }
}

#if DEBUG
extension MenuBarItem {
    /// The parts of the interface that DebugDriver reaches for.
    var debugHandles: (button: NSStatusBarButton?, menu: NSMenu) {
        (statusItem.button, menu)
    }
}
#endif
