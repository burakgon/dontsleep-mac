import Foundation

/// What a `dontsleep` command line asks for.
public struct Invocation: Equatable, Sendable {
    public enum Operation: Equatable, Sendable {
        case send(Request)
        case help
        case version
    }

    public var operation: Operation
    /// Print the resulting state as JSON rather than as a sentence.
    public var json: Bool

    public init(_ operation: Operation, json: Bool = false) {
        self.operation = operation
        self.json = json
    }
}

public struct UsageError: Error, Equatable {
    public let message: String
}

/// The grammar of the `dontsleep` command and the text it prints. Kept apart from the
/// command itself so that it can be tested.
public enum CommandLineInterface {
    public static let usage = """
        dontsleep keeps your Mac awake. It controls the DontSleep app in the menu bar.

        USAGE
          dontsleep on [--for <time>] [--display-sleep | --no-display-sleep]
          dontsleep off
          dontsleep toggle [--for <time>] [--display-sleep | --no-display-sleep]
          dontsleep status
          dontsleep display-sleep <on|off>
          dontsleep quit

        COMMANDS
          on               Keep the Mac awake. Starts DontSleep if it is not running.
          off              Let the Mac sleep again.
          toggle           Turn on when off, and off when on.
          status           Show whether the Mac is being kept awake.
          display-sleep    on: the display may sleep while the Mac stays awake.
                           off: the display stays on as well. The choice is remembered.
          quit             Quit DontSleep.

        OPTIONS
          --for <time>          Turn off by itself after this long: 45m, 2h, 1h30m, 90s, 1d.
                                "dontsleep on 2h" is the same as "dontsleep on --for 2h".
          --display-sleep       Like "display-sleep on".
          --no-display-sleep    Like "display-sleep off".
          --json                Print the resulting state as JSON. Works with every command.
          -h, --help            Show this help.
          -v, --version         Show the version.

        EXAMPLES
          dontsleep on                            Stay awake until "dontsleep off".
          dontsleep on --for 2h --display-sleep   Stay awake for a long job, screen off.
          dontsleep status --json                 {"active":true,"until":"2026-11-10T14:30:00Z",...}

        Every command prints the state it leaves behind and exits with 0 when it succeeded.
        """

    public static func parse(_ arguments: [String]) throws(UsageError) -> Invocation {
        var json = false
        var duration: TimeInterval?
        var allowDisplaySleep: Bool?
        var words: [String] = []

        var index = 0
        func value(of option: String) throws(UsageError) -> String {
            index += 1
            guard index < arguments.count else { throw UsageError(message: "\(option) needs a value, for example \(option) 2h") }
            return arguments[index]
        }
        func time(_ text: String) throws(UsageError) -> TimeInterval {
            guard let seconds = TimeSpan.parse(text) else {
                throw UsageError(message: "\"\(text)\" is not a length of time. Use a number and a unit, for example 45m, 2h or 1h30m.")
            }
            return seconds
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "-h", "--help", "help":
                return Invocation(.help)
            case "-v", "--version", "version":
                return Invocation(.version)
            case "--json":
                json = true
            case "--for", "-t":
                duration = try time(try value(of: argument))
            case "--display-sleep":
                allowDisplaySleep = true
            case "--no-display-sleep":
                allowDisplaySleep = false
            default:
                if argument.hasPrefix("--for=") {
                    duration = try time(String(argument.dropFirst("--for=".count)))
                } else if argument.hasPrefix("-") && argument.count > 1 {
                    throw UsageError(message: "unknown option \(argument)")
                } else {
                    words.append(argument)
                }
            }
            index += 1
        }

        guard let command = words.first else { return Invocation(.help) }
        var rest = Array(words.dropFirst())
        let request: Request
        switch command {
        case "on", "toggle":
            if duration == nil, let word = rest.first {
                duration = try time(word)
                rest.removeFirst()
            }
            request = Request(command == "on" ? .on : .toggle, duration: duration, allowDisplaySleep: allowDisplaySleep)
        case "off", "status", "quit":
            guard duration == nil, allowDisplaySleep == nil else {
                throw UsageError(message: "\"\(command)\" takes no options besides --json")
            }
            request = Request(command == "off" ? .off : command == "status" ? .status : .quit)
        case "display-sleep":
            guard duration == nil, allowDisplaySleep == nil else {
                throw UsageError(message: "\"display-sleep\" takes on or off, and no options besides --json")
            }
            switch rest.first {
            case "on", "allow", "yes": request = Request(.displaySleep, allowDisplaySleep: true)
            case "off", "prevent", "no": request = Request(.displaySleep, allowDisplaySleep: false)
            default: throw UsageError(message: "\"display-sleep\" needs on or off")
            }
            rest.removeFirst()
        default:
            throw UsageError(message: "unknown command \"\(command)\"")
        }
        if let extra = rest.first { throw UsageError(message: "unexpected argument \"\(extra)\"") }
        return Invocation(.send(request), json: json)
    }

    /// The state in a sentence, for people.
    public static func describe(_ status: Status, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        guard status.running else { return "off (DontSleep is not running)" }
        guard status.active else { return "off" }
        var text = "on"
        if let until = status.until {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            // The date as well once the time alone would be ambiguous.
            formatter.dateFormat = until.timeIntervalSince(now) < 86400 ? "HH:mm" : "yyyy-MM-dd HH:mm"
            text += " until \(formatter.string(from: until)) (\(TimeSpan.describe(until.timeIntervalSince(now))) left)"
        }
        return text + (status.displaySleepAllowed ? ", display may sleep" : ", display stays on")
    }

    /// The state as one line of JSON, for scripts and agents.
    public static func json(_ status: Status) -> String {
        (try? ControlCoding.encode(status)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
