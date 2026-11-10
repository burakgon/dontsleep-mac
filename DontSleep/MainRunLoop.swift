import Foundation

/// Runs work on the main thread by way of its run loop rather than the main dispatch queue.
///
/// The difference shows while a menu is open or an alert is up. Those keep the run loop
/// turning from inside whatever opened them, and the main dispatch queue does not start a
/// second block while it is still inside the first. A block handed to the run loop itself
/// always gets its turn, so the dontsleep command is answered even then.
enum MainRunLoop {
    /// Runs `work` on the main thread and waits for its result. For background threads.
    nonisolated static func sync<Result: Sendable>(_ work: @escaping @MainActor @Sendable () -> Result) -> Result {
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result?
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            result = MainActor.assumeIsolated(work)
            done.signal()
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
        done.wait()
        return result!
    }

    /// Runs `work` on the main thread at its next turn, without waiting for it.
    nonisolated static func async(_ work: @escaping @MainActor @Sendable () -> Void) {
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            MainActor.assumeIsolated(work)
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}
