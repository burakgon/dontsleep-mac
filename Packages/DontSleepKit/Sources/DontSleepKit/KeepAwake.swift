import Foundation

/// Keeps the Mac awake, until further notice or until a moment in time.
///
/// This is the whole state of DontSleep. The menu bar item and the `dontsleep` command both
/// drive it, and both read it back.
@MainActor
public final class KeepAwake {
    /// Whether the Mac is being kept awake right now.
    public private(set) var isActive = false

    /// When the Mac may sleep again, or nil while it is kept awake until further notice.
    public private(set) var endsAt: Date?

    /// The length the current session was started with, if it was started with one.
    public private(set) var duration: TimeInterval?

    /// Whether the display may sleep while the Mac is kept awake. Takes effect at once.
    public var allowsDisplaySleep: Bool {
        didSet {
            guard allowsDisplaySleep != oldValue else { return }
            if isActive { try? assertion.hold(scope) }
            onChange?()
        }
    }

    /// Called after any of the above changed.
    public var onChange: (() -> Void)?

    private let assertion: PowerAssertion
    private var timer: DispatchSourceTimer?

    public init(allowsDisplaySleep: Bool = false, reason: String = "DontSleep is keeping this Mac awake") {
        self.allowsDisplaySleep = allowsDisplaySleep
        assertion = PowerAssertion(name: reason)
    }

    private var scope: WakeScope { allowsDisplaySleep ? .system : .display }

    /// Keeps the Mac awake for `duration` seconds, or until `stop()` when it is nil.
    /// Starting again while active replaces the running session.
    public func start(for duration: TimeInterval? = nil) throws(PowerAssertion.Failure) {
        try start(until: duration.map { Date(timeIntervalSinceNow: $0) })
        self.duration = duration
        onChange?()
    }

    /// Keeps the Mac awake until `end`, or until `stop()` when it is nil.
    public func resume(until end: Date?) throws(PowerAssertion.Failure) {
        if let end, end <= Date() { return }
        try start(until: end)
        onChange?()
    }

    public func stop() {
        guard isActive else { return }
        timer?.cancel()
        timer = nil
        assertion.release()
        isActive = false
        endsAt = nil
        duration = nil
        onChange?()
    }

    private func start(until end: Date?) throws(PowerAssertion.Failure) {
        try assertion.hold(scope)
        timer?.cancel()
        timer = nil
        isActive = true
        endsAt = end
        duration = nil
        if let end { schedule(end) }
    }

    /// One timer that fires once. It follows the wall clock, so a session that ends at 14:30
    /// ends at 14:30 even if the Mac was put to sleep by hand for part of it.
    private func schedule(_ end: Date) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(wallDeadline: .now() + max(0, end.timeIntervalSinceNow), leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.expire() }
        }
        timer.resume()
        self.timer = timer
    }

    private func expire() {
        guard let endsAt, endsAt.timeIntervalSinceNow < 1 else { return }
        stop()
    }
}
