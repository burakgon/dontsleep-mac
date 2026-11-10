import AppKit
import Sparkle

/// Updates over the air, with Sparkle.
///
/// Once a day the app asks GitHub for the appcast of the latest release. A newer version is
/// downloaded, checked against the update key and the code signature, and installed in the
/// background; the app then restarts itself the next time that disturbs nobody. Sparkle
/// sleeps between checks: it costs one timer that fires once a day.
final class Updater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    /// Whether this is a bad moment to restart: the Mac is being kept awake, or the menu is open.
    var isBusy: () -> Bool = { false }

    /// Called right before the app restarts to finish an update.
    var willRelaunch: () -> Void = {}

    /// Whether an update was found that the person has not looked at yet. The menu offers it.
    private(set) var hasUpdateWaitingForAttention = false

    private var controller: SPUStandardUpdaterController?
    private var installPendingUpdate: (() -> Void)?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    /// Whether updates are looked for, downloaded and installed without asking.
    var updatesAutomatically: Bool {
        get {
            guard let updater = controller?.updater else { return false }
            return updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates
        }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            controller?.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    /// Looks for an update now and says what it found.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Restarts into an update that is downloaded and ready, unless that would interrupt something.
    func installPendingUpdateIfIdle() {
        guard let installPendingUpdate, !isBusy() else { return }
        installPendingUpdate()
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        // A menu bar app is rarely quit, so "on quit" could be weeks away. Take the first
        // quiet moment instead. Sparkle still installs on quit if none comes.
        installPendingUpdate = immediateInstallHandler
        DispatchQueue.main.async { [weak self] in self?.installPendingUpdateIfIdle() }
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        willRelaunch()
    }

    // MARK: - SPUStandardUserDriverDelegate

    // An app without windows should not throw an alert in front of whatever the person is
    // doing. Updates found by the daily check are offered in the menu instead.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        hasUpdateWaitingForAttention = !handleShowingUpdate
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        hasUpdateWaitingForAttention = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        hasUpdateWaitingForAttention = false
    }
}
