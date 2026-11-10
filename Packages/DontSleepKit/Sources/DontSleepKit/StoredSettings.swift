import Foundation

/// The one setting DontSleep remembers, kept in the app's preferences. The `dontsleep`
/// command reads and writes the same preferences, so it can report and change the setting
/// while the app is not running.
public enum StoredSettings {
    private static let allowDisplaySleepKey = "AllowDisplaySleep"
    private static let domain = ControlSocket.appIdentifier

    /// Whether the display may sleep while the Mac is kept awake. Off unless chosen.
    public static var allowsDisplaySleep: Bool {
        get {
            CFPreferencesAppSynchronize(domain as CFString)
            return CFPreferencesGetAppBooleanValue(allowDisplaySleepKey as CFString, domain as CFString, nil)
        }
        set {
            CFPreferencesSetAppValue(allowDisplaySleepKey as CFString, newValue as CFBoolean, domain as CFString)
            CFPreferencesAppSynchronize(domain as CFString)
        }
    }
}
