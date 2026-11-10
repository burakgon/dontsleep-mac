import Foundation
import IOKit.pwr_mgt

/// What stays awake while a power assertion is held.
public enum WakeScope: Sendable, Equatable {
    /// The Mac stays awake. The display may still dim and sleep.
    case system
    /// The display stays on, and with it the Mac.
    case display

    var assertionType: String {
        switch self {
        case .system: "PreventUserIdleSystemSleep"
        case .display: "PreventUserIdleDisplaySleep"
        }
    }
}

/// A power management assertion. While one is held, macOS does not put the Mac to sleep for
/// lack of user activity. Closing the lid, the Apple menu and an empty battery still do.
///
/// Holding an assertion costs nothing: there is no timer and nothing to poll. macOS drops
/// the assertion by itself when the process ends, however it ends.
public final class PowerAssertion {
    public struct Failure: Error, CustomStringConvertible, Equatable {
        public let code: IOReturn

        public var description: String {
            "macOS refused the power assertion (0x\(String(UInt32(bitPattern: code), radix: 16)))"
        }
    }

    /// What is being kept awake, or nil while nothing is held.
    public private(set) var scope: WakeScope?

    private var id: IOPMAssertionID = 0
    private let name: String

    /// - Parameter name: Shown by `pmset -g assertions` and Activity Monitor as the reason.
    public init(name: String) {
        self.name = name
    }

    deinit {
        if scope != nil { IOPMAssertionRelease(id) }
    }

    /// Holds an assertion for `scope`. Changing scope takes the new assertion before it
    /// gives up the old one, so the Mac is never left uncovered in between.
    public func hold(_ scope: WakeScope) throws(Failure) {
        guard scope != self.scope else { return }
        var new: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            scope.assertionType as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), name as CFString, &new)
        guard result == kIOReturnSuccess else { throw Failure(code: result) }
        release()
        id = new
        self.scope = scope
    }

    public func release() {
        guard scope != nil else { return }
        IOPMAssertionRelease(id)
        id = 0
        scope = nil
    }

    /// The types of the assertions this process holds, as macOS itself reports them.
    static func heldByThisProcess() -> [String] {
        var copied: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&copied) == kIOReturnSuccess,
              let all = copied?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        return (all[NSNumber(value: getpid())] ?? []).compactMap { $0["AssertType"] as? String }
    }
}
