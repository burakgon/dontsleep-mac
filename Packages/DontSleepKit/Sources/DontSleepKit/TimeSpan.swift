import Foundation

/// Lengths of time as people type them on a command line: `90s`, `45m`, `2h`, `1h30m`, `1.5h`, `2d`.
public enum TimeSpan {
    /// The longest session the command line accepts.
    public static let longest: TimeInterval = 366 * 86400

    /// The seconds in `text`, or nil when it is not a length of time. A number needs a unit:
    /// `30` alone could as well mean seconds as minutes.
    public static func parse(_ text: String) -> TimeInterval? {
        var total = 0.0
        var number = ""
        var parts = 0
        for character in text.lowercased() {
            switch character {
            case "0"..."9", ".":
                number.append(character)
            case "s", "m", "h", "d":
                guard let value = Double(number), value.isFinite else { return nil }
                let unit: Double = switch character {
                case "s": 1
                case "m": 60
                case "h": 3600
                default: 86400
                }
                total += value * unit
                number = ""
                parts += 1
            default:
                return nil
            }
        }
        guard number.isEmpty, parts > 0, total >= 1, total <= longest else { return nil }
        return total.rounded()
    }

    /// A short description of a number of seconds: `2h 5m`, `45m`, `30s`.
    public static func describe(_ seconds: TimeInterval) -> String {
        var rest = max(0, Int(seconds.rounded()))
        var parts: [String] = []
        for (unit, size) in [("d", 86400), ("h", 3600), ("m", 60), ("s", 1)] {
            let count = rest / size
            rest %= size
            if count > 0 { parts.append("\(count)\(unit)") }
        }
        // Two units are precise enough: 1d 4h, 2h 5m, 3m 20s.
        return parts.isEmpty ? "0s" : parts.prefix(2).joined(separator: " ")
    }
}
