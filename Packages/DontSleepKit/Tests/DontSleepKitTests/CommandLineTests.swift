import Foundation
import Testing
@testable import DontSleepKit

struct TimeSpanTests {
    @Test(arguments: [
        ("90s", 90.0), ("45m", 2700), ("2h", 7200), ("1h30m", 5400), ("1.5h", 5400),
        ("2d", 172_800), ("1H", 3600), ("1d2h3m4s", 93_784), ("0.5m", 30),
    ] as [(String, Double)])
    func parses(_ text: String, _ seconds: Double) {
        #expect(TimeSpan.parse(text) == seconds)
    }

    @Test(arguments: ["", "30", "h", "2x", "abc", "1h30", "-5m", "0s", "0.2s", "1..5h", "500d", "2 h", "1e3s"])
    func refuses(_ text: String) {
        #expect(TimeSpan.parse(text) == nil)
    }

    @Test(arguments: [
        (0.0, "0s"), (59, "59s"), (60, "1m"), (200, "3m 20s"), (3600, "1h"), (7199, "1h 59m"),
        (7500, "2h 5m"), (86400, "1d"), (100_800, "1d 4h"), (-3, "0s"),
    ] as [(Double, String)])
    func describes(_ seconds: Double, _ text: String) {
        #expect(TimeSpan.describe(seconds) == text)
    }
}

struct CommandLineTests {
    private func request(_ arguments: String...) throws -> Request {
        guard case .send(let request) = try CommandLineInterface.parse(arguments).operation else {
            Issue.record("\(arguments) did not parse to a request")
            return Request(.status)
        }
        return request
    }

    @Test func commands() throws {
        #expect(try request("on") == Request(.on))
        #expect(try request("off") == Request(.off))
        #expect(try request("toggle") == Request(.toggle))
        #expect(try request("status") == Request(.status))
        #expect(try request("quit") == Request(.quit))
        #expect(try request("display-sleep", "on") == Request(.displaySleep, allowDisplaySleep: true))
        #expect(try request("display-sleep", "off") == Request(.displaySleep, allowDisplaySleep: false))
    }

    @Test func durations() throws {
        #expect(try request("on", "--for", "2h") == Request(.on, duration: 7200))
        #expect(try request("on", "--for=45m") == Request(.on, duration: 2700))
        #expect(try request("on", "-t", "90s") == Request(.on, duration: 90))
        #expect(try request("on", "1h30m") == Request(.on, duration: 5400))
        #expect(try request("--for", "2h", "on") == Request(.on, duration: 7200))
        #expect(try request("toggle", "30m") == Request(.toggle, duration: 1800))
    }

    @Test func displayOptions() throws {
        #expect(try request("on", "--display-sleep") == Request(.on, allowDisplaySleep: true))
        #expect(try request("on", "--no-display-sleep") == Request(.on, allowDisplaySleep: false))
        #expect(try request("on", "--for", "2h", "--display-sleep") == Request(.on, duration: 7200, allowDisplaySleep: true))
        #expect(try request("toggle", "--display-sleep") == Request(.toggle, allowDisplaySleep: true))
    }

    @Test func jsonHelpAndVersion() throws {
        #expect(try CommandLineInterface.parse(["status", "--json"]) == Invocation(.send(Request(.status)), json: true))
        #expect(try CommandLineInterface.parse(["--json", "on"]) == Invocation(.send(Request(.on)), json: true))
        #expect(try CommandLineInterface.parse(["status"]).json == false)
        #expect(try CommandLineInterface.parse([]) == Invocation(.help))
        for help in ["-h", "--help", "help"] {
            #expect(try CommandLineInterface.parse([help]) == Invocation(.help))
        }
        for version in ["-v", "--version", "version"] {
            #expect(try CommandLineInterface.parse([version]) == Invocation(.version))
        }
    }

    @Test(arguments: [
        ["sleep"], ["on", "--for"], ["on", "--for", "soon"], ["on", "30"], ["on", "2h", "3h"],
        ["off", "--for", "2h"], ["status", "--display-sleep"], ["display-sleep"], ["display-sleep", "maybe"],
        ["on", "--loud"], ["off", "now"], ["display-sleep", "on", "--for", "1h"],
    ])
    func mistakes(_ arguments: [String]) {
        #expect(throws: UsageError.self) {
            try CommandLineInterface.parse(arguments)
        }
    }

    @Test func everyCommandInTheHelpParses() throws {
        // The usage text is the documentation agents read: what it shows must work.
        let lines = CommandLineInterface.usage.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let examples = lines.filter { $0.hasPrefix("dontsleep ") && !$0.contains("<") && !$0.contains("[") && !$0.hasPrefix("dontsleep keeps") }
        #expect(examples.count >= 6)
        for example in examples {
            // Drop the explanation that follows the command after a run of spaces.
            let command = example.components(separatedBy: "  ").first ?? example
            let arguments = command.split(separator: " ").dropFirst().map(String.init)
            #expect(throws: Never.self, "\(command)") {
                try CommandLineInterface.parse(arguments)
            }
        }
    }

    @Test func sentences() {
        let utc = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)    // 2027-01-15 08:00:00 UTC
        func describe(_ status: Status) -> String {
            CommandLineInterface.describe(status, now: now, timeZone: utc)
        }

        #expect(describe(Status(running: false, active: false, displaySleepAllowed: false)) == "off (DontSleep is not running)")
        #expect(describe(Status(running: true, active: false, displaySleepAllowed: true)) == "off")
        #expect(describe(Status(running: true, active: true, displaySleepAllowed: false)) == "on, display stays on")
        #expect(describe(Status(running: true, active: true, displaySleepAllowed: true)) == "on, display may sleep")
        #expect(describe(Status(running: true, active: true, until: now.addingTimeInterval(7199), displaySleepAllowed: true))
            == "on until 09:59 (1h 59m left), display may sleep")
        #expect(describe(Status(running: true, active: true, until: now.addingTimeInterval(3 * 86400), displaySleepAllowed: false))
            == "on until 2027-01-18 08:00 (3d left), display stays on")
    }

    @Test func jsonAlwaysHasTheSameKeys() throws {
        let off = CommandLineInterface.json(Status(running: false, active: false, displaySleepAllowed: false))
        #expect(off == #"{"active":false,"displaySleepAllowed":false,"remainingSeconds":null,"running":false,"until":null,"version":null}"#)

        let status = Status(running: true, active: true, until: Date(timeIntervalSince1970: 1_800_000_000),
                            remainingSeconds: 7199, displaySleepAllowed: true, version: "1.0.0")
        let on = CommandLineInterface.json(status)
        #expect(on == #"{"active":true,"displaySleepAllowed":true,"remainingSeconds":7199,"running":true,"until":"2027-01-15T08:00:00Z","version":"1.0.0"}"#)
        #expect(!on.contains("\n"))

        // What is printed can be read back.
        #expect(try ControlCoding.decode(Status.self, from: Data(on.utf8)) == status)
        #expect(try ControlCoding.decode(Status.self, from: Data(off.utf8)).until == nil)
    }
}
