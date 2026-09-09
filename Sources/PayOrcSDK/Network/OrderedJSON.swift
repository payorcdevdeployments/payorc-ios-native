import Foundation

// MARK: - Ordered JSON Builder
//
// JSONSerialization on Swift [String: Any] dictionaries does NOT guarantee key ordering.
// Even with .sortedKeys, alphabetical ordering differs from Flutter's insertion-order output.
// The PayOrc gateway validates HMAC-SHA256 over the raw body bytes it receives, but it
// normalises the JSON exactly as Dart's jsonEncode does (insertion-order keys, no \/ escaping).
//
// This builder produces JSON strings byte-for-byte identical to Flutter's jsonEncode output
// by writing keys in the same insertion order as Flutter's toJson / toTabbyInitJson methods.

struct OrderedJSON {

    // MARK: - Primitives

    static func string(_ s: String) -> String {
        // Escape characters required by JSON spec.
        // Crucially, do NOT escape '/' — Dart's jsonEncode never does, and the gateway expects it.
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if ch.value < 0x20 {
                    out += String(format: "\\u%04x", ch.value)
                } else {
                    out += String(ch)
                }
            }
        }
        out += "\""
        return out
    }

    static func array(_ items: [[String: String]]) -> String {
        if items.isEmpty { return "[]" }
        let inner = items.map { dict -> String in
            let pairs = dict.map { k, v in "\(string(k)):\(string(v))" }.joined(separator: ",")
            return "{\(pairs)}"
        }.joined(separator: ",")
        return "[\(inner)]"
    }

    // MARK: - Ordered object builder

    /// Builds a compact JSON object from an ordered list of (key, rawValue) pairs.
    /// rawValue must already be a valid JSON fragment (string, number, array, or nested object).
    static func object(_ pairs: [(key: String, value: String)]) -> String {
        let inner = pairs.map { "\(string($0.key)):\($0.value)" }.joined(separator: ",")
        return "{\(inner)}"
    }
}
