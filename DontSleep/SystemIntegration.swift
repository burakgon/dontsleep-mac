import AppKit
import ServiceManagement

/// Opening the app when the person logs in. macOS keeps the list, under System Settings >
/// General > Login Items, so there is nothing to store and no helper to install.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Puts the `dontsleep` command on the PATH, as a symbolic link to the copy inside the app.
/// The link keeps pointing at the current version when the app updates itself.
enum CommandLineTool {
    enum Failure: Error {
        /// None of the folders can be written without a password. Carries the command that does it by hand.
        case noWritableFolder(command: String)
        /// A file that is not a link stands where the link would go.
        case occupied(path: String)
    }

    static let name = "dontsleep"

    /// The command inside the app.
    static var bundled: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/\(name)")
    }

    /// Folders that are on the PATH of a shell, in order of preference. The first exists on
    /// most Macs, the second belongs to Homebrew on Apple silicon, and the third is the
    /// per-user folder that many command line installers use.
    private static var folders: [URL] {
        [URL(filePath: "/usr/local/bin"), URL(filePath: "/opt/homebrew/bin"),
         FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin")]
    }

    /// The link that points at this copy of the app, if the command is installed.
    static var installedLink: URL? {
        folders.map { $0.appending(path: name) }.first { link in
            (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == bundled.path
        }
    }

    @discardableResult
    static func install() throws -> URL {
        let files = FileManager.default
        guard let folder = folders.first(where: { files.isWritableFile(atPath: $0.path) }) else {
            let folder = folders[0].path
            throw Failure.noWritableFolder(
                command: "sudo mkdir -p \(folder) && sudo ln -sf '\(bundled.path)' \(folder)/\(name)")
        }
        let link = folder.appending(path: name)
        if (try? files.destinationOfSymbolicLink(atPath: link.path)) != nil {
            // A link, maybe to a copy of the app that has since moved: replace it.
            try files.removeItem(at: link)
        } else if files.fileExists(atPath: link.path) {
            throw Failure.occupied(path: link.path)
        }
        try files.createSymbolicLink(at: link, withDestinationURL: bundled)
        return link
    }

    static func uninstall() throws {
        while let link = installedLink {
            try FileManager.default.removeItem(at: link)
        }
    }
}
