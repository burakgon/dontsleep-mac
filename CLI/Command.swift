import DontSleepKit
import Foundation

/// The `dontsleep` command: a thin client of the app in the menu bar.
///
/// The app holds the power assertion, because macOS ties an assertion to the life of the
/// process that took it. This command only tells the app what to do, over a socket, and
/// starts the app first when it has to.
@main
enum Command {
    static func main() {
        let invocation: Invocation
        do {
            invocation = try CommandLineInterface.parse(Array(CommandLine.arguments.dropFirst()))
        } catch {
            fail("\(error.message)\nRun \"dontsleep --help\" to see what it understands.", code: 64)
        }

        switch invocation.operation {
        case .help:
            print(CommandLineInterface.usage)
        case .version:
            print(version ?? "unknown")
        case .send(let request):
            // The app belongs to the person at the Mac. As root this command would look in
            // root's home, find nothing, and start a second copy there.
            guard getuid() != 0 else { fail("run dontsleep as yourself, without sudo: it controls the app in your menu bar") }
            let status = perform(request)
            print(invocation.json ? CommandLineInterface.json(status) : CommandLineInterface.describe(status))
        }
    }

    /// Carries out a request and returns the state it leaves behind.
    private static func perform(_ request: Request) -> Status {
        do {
            return try answer(to: request)
        } catch {
            guard error == .notRunning else { fail(error.reason) }
            switch request.action {
            case .on, .toggle:
                return startAppAndPerform(request)
            case .displaySleep:
                // No need to start the app for this: it reads the setting when it starts.
                if let allow = request.allowDisplaySleep { StoredSettings.allowsDisplaySleep = allow }
                return offline
            case .off, .status, .quit:
                return offline
            }
        }
    }

    private static func answer(to request: Request) throws(ControlClient.Failure) -> Status {
        let response = try ControlClient.send(request)
        if let error = response.error { fail(error) }
        guard let status = response.status else { fail("DontSleep gave an empty answer") }
        return status
    }

    private static func startAppAndPerform(_ request: Request) -> Status {
        guard startApp() else {
            fail("could not start DontSleep. Is the app installed? Open it once from the Applications folder.")
        }
        // The app listens a moment after it starts. The first launch after an update can
        // take longer, while macOS checks the new copy.
        let deadline = Date(timeIntervalSinceNow: 20)
        while Date() < deadline {
            do {
                return try answer(to: request)
            } catch {
                guard error == .notRunning else { fail(error.reason) }
                usleep(50_000)
            }
        }
        fail("DontSleep was started but does not answer")
    }

    private static func startApp() -> Bool {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // -g keeps the app from taking the focus, and --background tells it nobody is
        // looking, so it does not point out its menu bar icon.
        let target = appBundle.map { [$0.path] } ?? ["-b", ControlSocket.appIdentifier]
        open.arguments = ["-g"] + target + ["--args", "--background"]
        open.standardOutput = FileHandle.nullDevice
        open.standardError = FileHandle.nullDevice
        do { try open.run() } catch { return false }
        open.waitUntilExit()
        return open.terminationStatus == 0
    }

    /// The state to report while the app is not running.
    private static var offline: Status {
        Status(running: false, active: false, displaySleepAllowed: StoredSettings.allowsDisplaySleep, version: version)
    }

    /// The app this command is part of: it lives at DontSleep.app/Contents/Helpers/dontsleep,
    /// and is usually run through a symbolic link on the PATH.
    private static let appBundle: URL? = {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0, let resolved = realpath(buffer, nil) else { return nil }
        defer { free(resolved) }
        let executable = URL(fileURLWithFileSystemRepresentation: resolved, isDirectory: false, relativeTo: nil)
        let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return bundle.pathExtension == "app" ? bundle : nil
    }()

    private static let version: String? = {
        guard let appBundle, let info = NSDictionary(contentsOf: appBundle.appending(path: "Contents/Info.plist")) else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }()

    private static func fail(_ message: String, code: Int32 = 1) -> Never {
        FileHandle.standardError.write(Data("dontsleep: \(message)\n".utf8))
        exit(code)
    }
}
