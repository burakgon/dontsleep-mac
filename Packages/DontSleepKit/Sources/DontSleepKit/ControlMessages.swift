import Foundation

/// What the `dontsleep` command asks the app to do.
public struct Request: Codable, Sendable, Equatable {
    public enum Action: String, Codable, Sendable {
        case on, off, toggle, status, quit
        case displaySleep = "display-sleep"
    }

    public var action: Action
    /// For `on` and `toggle`: seconds after which the Mac may sleep again.
    public var duration: TimeInterval?
    /// Whether the display may sleep while the Mac is kept awake. Remembered when given.
    public var allowDisplaySleep: Bool?

    public init(_ action: Action, duration: TimeInterval? = nil, allowDisplaySleep: Bool? = nil) {
        self.action = action
        self.duration = duration
        self.allowDisplaySleep = allowDisplaySleep
    }
}

/// The state of DontSleep, as `dontsleep status --json` prints it.
public struct Status: Codable, Sendable, Equatable {
    /// Whether the app is running at all.
    public var running: Bool
    /// Whether the Mac is being kept awake.
    public var active: Bool
    /// When the Mac may sleep again. Nil when inactive, and when active until further notice.
    public var until: Date?
    /// The seconds left until then.
    public var remainingSeconds: Int?
    /// Whether the display may sleep while the Mac is kept awake.
    public var displaySleepAllowed: Bool
    /// The version of the app.
    public var version: String?

    public init(running: Bool, active: Bool, until: Date? = nil, remainingSeconds: Int? = nil,
                displaySleepAllowed: Bool, version: String? = nil) {
        self.running = running
        self.active = active
        self.until = until
        self.remainingSeconds = remainingSeconds
        self.displaySleepAllowed = displaySleepAllowed
        self.version = version
    }

    /// Writes every key, with null for what is not set, so that the JSON always has the
    /// same shape and a script never has to ask whether a key exists.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(running, forKey: .running)
        try container.encode(active, forKey: .active)
        try container.encode(until, forKey: .until)
        try container.encode(remainingSeconds, forKey: .remainingSeconds)
        try container.encode(displaySleepAllowed, forKey: .displaySleepAllowed)
        try container.encode(version, forKey: .version)
    }
}

/// The app's answer: the state after the request, or why it could not be carried out.
public struct Response: Codable, Sendable, Equatable {
    public var status: Status?
    public var error: String?

    public init(status: Status? = nil, error: String? = nil) {
        self.status = status
        self.error = error
    }
}

extension KeepAwake {
    /// The current state, for the `dontsleep` command.
    public func status(version: String?, now: Date = Date()) -> Status {
        Status(
            running: true,
            active: isActive,
            until: endsAt,
            remainingSeconds: endsAt.map { max(0, Int($0.timeIntervalSince(now).rounded())) },
            displaySleepAllowed: allowsDisplaySleep,
            version: version)
    }

    /// Carries out a request from the `dontsleep` command. `status` and `quit` change nothing here.
    public func perform(_ request: Request) throws(PowerAssertion.Failure) {
        if let allow = request.allowDisplaySleep, request.action != .off, request.action != .status, request.action != .quit {
            allowsDisplaySleep = allow
        }
        switch request.action {
        case .on:
            try start(for: request.duration)
        case .toggle:
            if isActive { stop() } else { try start(for: request.duration) }
        case .off:
            stop()
        case .displaySleep, .status, .quit:
            break
        }
    }
}

/// One line of JSON each way.
public enum ControlCoding {
    public static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
