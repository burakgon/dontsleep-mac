import Foundation
import Testing
@testable import DontSleepKit

/// These tests take real power assertions and ask macOS which ones the process holds, so
/// they run one at a time.
@Suite(.serialized)
@MainActor
struct KeepAwakeTests {
    private func held(_ type: String) -> Int {
        PowerAssertion.heldByThisProcess().count { $0 == type }
    }

    private let system = "PreventUserIdleSystemSleep"
    private let display = "PreventUserIdleDisplaySleep"

    @Test func assertionIsHeldAndReleased() throws {
        let before = held(display)
        let assertion = PowerAssertion(name: "DontSleep tests")
        #expect(assertion.scope == nil)

        try assertion.hold(.display)
        #expect(assertion.scope == .display)
        #expect(held(display) == before + 1)

        // Holding the same scope twice does not stack assertions.
        try assertion.hold(.display)
        #expect(held(display) == before + 1)

        assertion.release()
        #expect(assertion.scope == nil)
        #expect(held(display) == before)
    }

    @Test func assertionIsReleasedWhenForgotten() throws {
        let before = held(system)
        do {
            let assertion = PowerAssertion(name: "DontSleep tests")
            try assertion.hold(.system)
            #expect(held(system) == before + 1)
        }
        #expect(held(system) == before)
    }

    @Test func startKeepsTheDisplayOnUnlessItMaySleep() throws {
        let systemBefore = held(system), displayBefore = held(display)
        let keepAwake = KeepAwake(allowsDisplaySleep: false, reason: "DontSleep tests")
        #expect(!keepAwake.isActive)
        #expect(held(display) == displayBefore)

        try keepAwake.start()
        #expect(keepAwake.isActive)
        #expect(keepAwake.endsAt == nil)
        #expect(held(display) == displayBefore + 1)
        #expect(held(system) == systemBefore)

        // Changing the setting swaps the assertion of a running session.
        keepAwake.allowsDisplaySleep = true
        #expect(keepAwake.isActive)
        #expect(held(display) == displayBefore)
        #expect(held(system) == systemBefore + 1)

        keepAwake.stop()
        #expect(!keepAwake.isActive)
        #expect(held(display) == displayBefore)
        #expect(held(system) == systemBefore)
    }

    @Test func changingTheSettingWhileOffHoldsNothing() {
        let systemBefore = held(system), displayBefore = held(display)
        let keepAwake = KeepAwake(allowsDisplaySleep: false, reason: "DontSleep tests")
        keepAwake.allowsDisplaySleep = true
        #expect(!keepAwake.isActive)
        #expect(held(system) == systemBefore)
        #expect(held(display) == displayBefore)
    }

    @Test func timedSessionEndsByItself() async throws {
        let before = held(display)
        let keepAwake = KeepAwake(reason: "DontSleep tests")
        var changes = 0
        keepAwake.onChange = { changes += 1 }

        try keepAwake.start(for: 0.3)
        #expect(keepAwake.isActive)
        #expect(keepAwake.duration == 0.3)
        #expect(changes == 1)
        let end = try #require(keepAwake.endsAt)
        #expect(abs(end.timeIntervalSinceNow - 0.3) < 0.1)

        try await Task.sleep(for: .milliseconds(900))
        #expect(!keepAwake.isActive)
        #expect(keepAwake.endsAt == nil)
        #expect(keepAwake.duration == nil)
        #expect(changes == 2)
        #expect(held(display) == before)
    }

    @Test func startingAgainReplacesTheSession() async throws {
        let before = held(display)
        let keepAwake = KeepAwake(reason: "DontSleep tests")
        try keepAwake.start(for: 0.3)
        // Until further notice now: the timer of the first session must not end this one.
        try keepAwake.start()
        #expect(keepAwake.endsAt == nil)
        #expect(held(display) == before + 1)

        try await Task.sleep(for: .milliseconds(700))
        #expect(keepAwake.isActive)
        keepAwake.stop()
        #expect(held(display) == before)
    }

    @Test func resumeIgnoresAMomentThatHasPassed() throws {
        let keepAwake = KeepAwake(reason: "DontSleep tests")
        try keepAwake.resume(until: Date(timeIntervalSinceNow: -5))
        #expect(!keepAwake.isActive)

        let end = Date(timeIntervalSinceNow: 60)
        try keepAwake.resume(until: end)
        #expect(keepAwake.isActive)
        #expect(keepAwake.endsAt == end)
        keepAwake.stop()

        try keepAwake.resume(until: nil)
        #expect(keepAwake.isActive)
        #expect(keepAwake.endsAt == nil)
        keepAwake.stop()
    }

    @Test func requestsDriveTheSession() throws {
        let keepAwake = KeepAwake(reason: "DontSleep tests")

        try keepAwake.perform(Request(.on, duration: 3600, allowDisplaySleep: true))
        #expect(keepAwake.isActive)
        #expect(keepAwake.allowsDisplaySleep)
        var status = keepAwake.status(version: "1.2.3")
        #expect(status.running && status.active && status.displaySleepAllowed)
        #expect(status.version == "1.2.3")
        #expect(status.until == keepAwake.endsAt)
        #expect((3598...3600).contains(try #require(status.remainingSeconds)))

        try keepAwake.perform(Request(.toggle))
        #expect(!keepAwake.isActive)
        status = keepAwake.status(version: nil)
        #expect(status.running && !status.active)
        #expect(status.until == nil && status.remainingSeconds == nil)
        // The setting outlives the session.
        #expect(status.displaySleepAllowed)

        try keepAwake.perform(Request(.toggle))
        #expect(keepAwake.isActive)
        #expect(keepAwake.endsAt == nil)

        try keepAwake.perform(Request(.displaySleep, allowDisplaySleep: false))
        #expect(keepAwake.isActive)
        #expect(!keepAwake.allowsDisplaySleep)

        // Asking for the state changes nothing.
        try keepAwake.perform(Request(.status, allowDisplaySleep: true))
        #expect(!keepAwake.allowsDisplaySleep)

        try keepAwake.perform(Request(.off))
        #expect(!keepAwake.isActive)
    }
}
