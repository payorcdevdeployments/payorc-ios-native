import Foundation

// MARK: - CompactJSONEncoder

/// Produces deterministic, compact JSON matching JavaScript's `JSON.stringify`
/// (and Dart's `jsonEncode`) output.
///
/// Critical for PayOrc request signing: the gateway re-parses the received body
/// and re-serialises it with `JSON.stringify(req.body)` before validating the
/// HMAC, so the bytes we sign must already be in that canonical form:
/// - No whitespace (compact form)
/// - Number formatting (no decimals on whole numbers) — see ``JSNormalizer``
/// - **Forward slashes NOT escaped** (`/`, never `\/`)
///
/// `JSONSerialization` always escapes `/` as `\/` and offers no option to stop it,
/// so ``removingSlashEscapes(_:)`` strips that escaping back out. Without this the
/// signed body differs from the gateway's normalised body wherever a value
/// contains a slash (e.g. `urls.webhook_url`, or base64 `/` in an Apple Pay
/// token), producing `401 E0021 "Invalid request signature"`. This is the same
/// reason `sdk/payment` and `sdk/add-card` build their bodies with ``OrderedJSON``
/// instead of this encoder.
struct CompactJSONEncoder {

    // MARK: - Encoding

    /// Encodes a dictionary to compact JSON bytes suitable for signing.
    ///
    /// - Parameters:
    ///   - dictionary: The data to encode.
    /// - Returns: UTF-8 bytes of compact JSON, with forward slashes left unescaped.
    /// - Throws: Encoding errors if data cannot be serialized
    static func encodeCompact(_ dictionary: [String: Any]) throws -> Data {
        // .sortedKeys keeps output deterministic across runs. Ordering itself does
        // not matter for the signature (the gateway re-serialises in the order it
        // parsed, i.e. the order we send), but the signed bytes and the sent bytes
        // must be identical — which they are, since both come from this call.
        let data = try JSONSerialization.data(
            withJSONObject: dictionary,
            options: [.sortedKeys]
        )
        guard let json = String(data: data, encoding: .utf8) else { return data }
        return Data(removingSlashEscapes(json).utf8)
    }

    /// Removes `\/` escaping from a JSON string produced by `JSONSerialization`,
    /// leaving every other escape sequence (`\"`, `\\`, `\n`, `\uXXXX`, …) intact.
    ///
    /// Walks the string tracking backslash state so `"\\/"` (a literal backslash
    /// followed by a slash) is preserved rather than corrupted.
    static func removingSlashEscapes(_ json: String) -> String {
        var out = String()
        out.reserveCapacity(json.count)
        var pendingBackslash = false
        for ch in json {
            if pendingBackslash {
                if ch == "/" {
                    out.append("/")          // drop the escaping backslash
                } else {
                    out.append("\\")
                    out.append(ch)
                }
                pendingBackslash = false
            } else if ch == "\\" {
                pendingBackslash = true
            } else {
                out.append(ch)
            }
        }
        if pendingBackslash { out.append("\\") }
        return out
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
