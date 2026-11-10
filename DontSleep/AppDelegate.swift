import AppKit
import DontSleepKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

    private let keepAwake = KeepAwake(allowsDisplaySleep: StoredSettings.allowsDisplaySleep)
    private var updater: Updater?
    private var menuBarItem: MenuBarItem?
    private var server: ControlServer?
    #if DEBUG
    private var debugDriver: DebugDriver?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One copy is enough: a second would put a second icon in the menu bar and take
        // the socket away from the first.
        let identifier = Bundle.main.bundleIdentifier ?? ControlSocket.appIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter { $0 != .current }
        guard others.isEmpty else { exit(0) }

        // Pick up where the app left off if it restarted itself to finish an update.
        if let session = SessionHandover.take() {
            try? keepAwake.resume(until: session.end)
        }

        let updater = Updater()
        let menuBarItem = MenuBarItem(keepAwake: keepAwake, updater: updater)
        self.updater = updater
        self.menuBarItem = menuBarItem

        // An update waits for a moment when restarting disturbs nobody.
        updater.isBusy = { [keepAwake, weak self] in
            keepAwake.isActive || self?.menuBarItem?.isMenuOpen == true || self?.welcome != nil
        }
        updater.willRelaunch = { [keepAwake] in
            if keepAwake.isActive {
                SessionHandover.save(end: keepAwake.endsAt, allowsDisplaySleep: keepAwake.allowsDisplaySleep)
            }
        }
        menuBarItem.onMenuClose = { [weak updater] in updater?.installPendingUpdateIfIdle() }
        keepAwake.onChange = { [weak self] in self?.stateChanged() }

        listenForCommands()
        #if DEBUG
        debugDriver = DebugDriver(menuBarItem: menuBarItem)
        #endif

        // The app has no window, so the first time it is opened it says where it lives and
        // lets the person pick its icon. Not when the dontsleep command started it: then
        // nobody is looking, and the welcome waits until the app is opened by hand.
        if !hasWelcomed, !CommandLine.arguments.contains("--background") {
            perform(#selector(showMenuOrWelcome), with: nil, afterDelay: 0.3)
        }
    }

    /// Opening the app again while it runs has nothing to bring to the front but the menu.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showMenuOrWelcome()
        return false
    }

    private var hasWelcomed: Bool {
        get { UserDefaults.standard.bool(forKey: "HasWelcomed") }
        set { UserDefaults.standard.set(newValue, forKey: "HasWelcomed") }
    }

    /// The welcome, while it is on screen.
    private var welcome: Welcome?

    @objc private func showMenuOrWelcome() {
        guard let menuBarItem, welcome == nil else { return }
        guard !hasWelcomed else { return menuBarItem.showMenu() }
        let welcome = Welcome(menuBarItem: menuBarItem)
        self.welcome = welcome
        welcome.run()
        self.welcome = nil
        hasWelcomed = true
        startAfresh()
    }

    /// Ends this copy of the app and starts a new one in its place.
    ///
    /// To draw the welcome, AppKit loads everything a window needs and keeps it for as long
    /// as the app runs: more than twice the memory the app uses otherwise. The welcome is
    /// shown once in the life of the app, so the copy that showed it steps aside for one
    /// that never loaded any of it. The icon is back in the menu bar a moment later.
    private func startAfresh() {
        // An update that arrived during the welcome restarts the app as well, into the new version.
        if updater?.installPendingUpdateIfIdle() == true { return }
        if keepAwake.isActive {
            SessionHandover.save(end: keepAwake.endsAt, allowsDisplaySleep: keepAwake.allowsDisplaySleep)
        }
        // A shell waits for this copy to be gone, since two copies cannot run side by side,
        // and then opens the app again without bringing it to the front.
        let successor = Process()
        successor.executableURL = URL(fileURLWithPath: "/bin/sh")
        successor.arguments = [
            "-c",
            "while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open -g \"$0\" --args --background",
            Bundle.main.bundlePath,
        ]
        guard (try? successor.run()) != nil else { return }
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    private func stateChanged() {
        if StoredSettings.allowsDisplaySleep != keepAwake.allowsDisplaySleep {
            StoredSettings.allowsDisplaySleep = keepAwake.allowsDisplaySleep
        }
        menuBarItem?.refresh()
        updater?.installPendingUpdateIfIdle()
    }

    // MARK: - The dontsleep command

    private func listenForCommands() {
        let server = ControlServer { [weak self] request in
            // Requests arrive on a background queue; the state lives on the main thread.
            MainRunLoop.sync {
                self?.respond(to: request) ?? Response(error: "DontSleep is quitting")
            }
        }
        do {
            try server.start()
            self.server = server
        } catch {
            // The app still works from the menu bar; only the command cannot reach it.
            NSLog("DontSleep: the dontsleep command is unavailable: \(error)")
        }
    }

    private func respond(to request: Request) -> Response {
        do {
            try keepAwake.perform(request)
        } catch {
            return Response(status: keepAwake.status(version: Self.version), error: error.description)
        }
        if request.action == .quit {
            // After the answer is on its way.
            NSApp.perform(#selector(NSApplication.terminate), with: nil, afterDelay: 0.2, inModes: [.common])
        }
        return Response(status: keepAwake.status(version: Self.version))
    }
}

/// Carries a running session across the restart that finishes an update.
enum SessionHandover {
    private static let key = "SessionHandover"

    static func save(end: Date?, allowsDisplaySleep: Bool) {
        var record: [String: Any] = ["savedAt": Date()]
        if let end { record["end"] = end }
        UserDefaults.standard.set(record, forKey: key)

        // The assertion ends with this process, a moment before the new copy takes its
        // own. The system's caffeinate covers that gap and then goes away by itself.
        let bridge = Process()
        bridge.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        bridge.arguments = [allowsDisplaySleep ? "-i" : "-d", "-t", "60"]
        try? bridge.run()
    }

    struct Session {
        /// When it ends, or nil for a session without an end.
        let end: Date?
    }

    /// The session to continue, if the app was restarted moments ago in the middle of one.
    static func take() -> Session? {
        guard let record = UserDefaults.standard.dictionary(forKey: key) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        guard let savedAt = record["savedAt"] as? Date, abs(savedAt.timeIntervalSinceNow) < 300 else { return nil }
        return Session(end: record["end"] as? Date)
    }
}
