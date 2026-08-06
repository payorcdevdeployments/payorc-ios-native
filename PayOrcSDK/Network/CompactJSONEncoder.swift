import Foundation

// MARK: - CompactJSONEncoder

/// Produces deterministic, compact JSON exactly matching JavaScript's JSON.stringify output.
///
/// Critical for PayOrc request signing, which requires byte-for-byte matching of:
/// - JSON key ordering (alphabetical)
/// - Number formatting (no decimals on whole numbers)
/// - No whitespace (compact form)
///
/// This ensures the signed body matches what the gateway validates.
struct CompactJSONEncoder {

    // MARK: - Encoding

    /// Encodes a dictionary to compact JSON bytes suitable for signing.
    ///
    /// - Parameters:
    ///   - dictionary: The data to encode. Key order is preserved to match JavaScript's
    ///     `JSON.stringify` output for deterministic signing.
    /// - Returns: UTF-8 bytes of compact JSON
    /// - Throws: Encoding errors if data cannot be serialized
    static func encodeCompact(_ dictionary: [String: Any]) throws -> Data {
        // .sortedKeys ensures alphabetical key ordering — critical for HMAC signing
        // because the gateway hashes a specific byte sequence. Without sorted keys,
        // Swift dictionaries produce non-deterministic ordering across runs,
        // causing the signed body to differ from the sent body.
        // Flutter's jsonEncode also produces sorted keys via Dart's LinkedHashMap
        // which preserves insertion order — but the gateway validates sorted-key JSON.
        let data = try JSONSerialization.data(
            withJSONObject: dictionary,
            options: [.sortedKeys]
        )
        return data
    }

    /// Encodes and returns the compact JSON as a string for inspection.
    ///
    /// Useful for debugging and verification.
    ///
    /// - Parameters:
    ///   - dictionary: The data to encode
    /// - Returns: Compact JSON string
    /// - Throws: Encoding errors
    static func encodeCompactString(_ dictionary: [String: Any]) throws -> String {
        let data = try encodeCompact(dictionary)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Validates that a JSON string is compact (no spaces after colons/commas).
    ///
    /// Returns false if formatting whitespace is detected.
    ///
    /// - Parameters:
    ///   - jsonString: The JSON string to validate
    /// - Returns: true if compact, false if formatted
    static func isCompact(_ jsonString: String) -> Bool {
        // Check for common formatting patterns
        return !jsonString.contains(": ") &&  // Space after colon
               !jsonString.contains(": \n") && // Space after colon with newline
               !jsonString.contains("\n")      // Any newlines
    }
}

// MARK: - JSON Normalization (matching Flutter SDK behavior)

/// Normalizes values for JavaScript JSON.stringify compatibility.
///
/// Key behaviors:
/// - Whole doubles (e.g., 1.0) become ints (1)
/// - Nested dictionaries and arrays are recursively normalized
/// - Null and boolean values pass through
struct JSNormalizer {

    /// Recursively normalizes a value to match JavaScript JSON.stringify output.
    static func normalize(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return dict.mapValues { normalize($0) }
        }
        
        if let array = value as? [Any] {
            return array.map { normalize($0) }
        }
        
        if let double = value as? Double {
            // If whole number, return as Int
            if double.truncatingRemainder(dividingBy: 1) == 0 && !double.isNaN && double.isFinite {
                return Int(double)
            }
            return double
        }
        
        if let decimal = value as? Decimal {
            let doubleValue = NSDecimalNumber(decimal: decimal).doubleValue
            if doubleValue.truncatingRemainder(dividingBy: 1) == 0 && !doubleValue.isNaN && doubleValue.isFinite {
                return Int(doubleValue)
            }
            return doubleValue
        }
        
        return value
    }
}
