import UIKit
import CryptoKit

// MARK: - RequestSigner

/// Generates HTTP headers for PayOrc service-sdk requests.
///
/// Header set matches gateway expectations (Postman-compatible):
/// `merchant-key`, `merchant-secret`, `Content-Type`,
/// `X-SDK-Name`, `X-SDK-Version`, `X-App-ID`, `X-App-Version`, `X-Device-Id`,
/// `X-Device-OS`, `X-Device-Model`, `X-DEVICE-BRAND`, `X-Browser-Token`,
/// `X-IP`, `X-IP-COUNTRY`, `Cookie` (if available).
public struct RequestSigner {

    // MARK: Constants (must match Postman/gateway expectations)

    private static let sdkName    = "payorc-sdk"
    private static let sdkVersion = "1.0.0"

    // MARK: Public API

    /// Builds the HTTP headers for PayOrc requests with HMAC-SHA256 signature.
    ///
    /// Signature algorithm:
    /// ```
    /// HMAC-SHA256(key: merchantSecret, data: merchantKey + timestamp + rawBodyJSON)
    /// ```
    /// Result is lowercased hex — identical to Flutter's `Hmac(sha256, …).convert(…).toString()`.
    ///
    /// - Parameters:
    ///   - body:          Raw JSON body data that will be sent with the request.
    ///   - configuration: The active SDK configuration (keys + device info).
    /// - Returns: A `[String: String]` header dictionary ready to be applied to a `URLRequest`.
    /// - Throws: ``PayOrcError/invalidConfiguration(_:)`` if the configuration fails validation.
    public static func signedHeaders(
        for body: Data,
        configuration: PayOrcConfiguration
    ) throws -> [String: String] {
        try configuration.validate()

        let merchantKey    = configuration.merchantKey.trimmingCharacters(in: .whitespaces)
        let merchantSecret = configuration.merchantSecret.trimmingCharacters(in: .whitespaces)
        let timestamp      = String(Int(Date().timeIntervalSince1970))

        // Must use the exact UTF-8 string that will be sent on the wire
        let bodyString     = String(data: body, encoding: .utf8) ?? "{}"

        // Signature: HMAC-SHA256(merchantSecret, merchantKey + timestamp + bodyJson) — lowercased hex
        let signatureInput = merchantKey + timestamp + bodyString
        let symmetricKey   = SymmetricKey(data: Data(merchantSecret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(signatureInput.utf8),
            using: symmetricKey
        )
        let signatureHex = Data(mac).map { String(format: "%02x", $0) }.joined()

        #if DEBUG
        debugPrint("[PayOrc] ═══════ SIGNATURE GENERATION ═══════")
        debugPrint("  Environment: \(configuration.environment.rawValue)")
        debugPrint("  Merchant Key: \(merchantKey)")
        debugPrint("  Merchant Secret: \(merchantSecret) [length: \(merchantSecret.count)]")
        debugPrint("  Timestamp: \(timestamp)")
        debugPrint("  ")
        debugPrint("  Body Bytes: \(body.count)")
        debugPrint("  Body String (compact): \(bodyString)")
        debugPrint("  ")
        
        // Verify body is compact
        if bodyString.contains(": ") {
            debugPrint("  ⚠️  WARNING: Body contains space after colon (not compact)")
        }
        if bodyString.contains("\n") {
            debugPrint("  ⚠️  WARNING: Body contains newlines (not compact)")
        }
        
        debugPrint("  Signature Input: \(signatureInput)")
        debugPrint("  Signature Hex: \(signatureHex)")
        debugPrint("  Headers being set: merchant-key, merchant-secret, X-Timestamp, X-Signature, X-SDK-Name, X-SDK-Version, X-App-ID, X-App-Version, X-Device-Id, X-Device-OS, X-Device-Model, X-DEVICE-BRAND, X-Browser-Token, X-IP, X-IP-COUNTRY")
        debugPrint("[PayOrc] ═══════════════════════════════════")
        #endif

        let headers: [String: String] = [
            // Auth
            "merchant-key":    merchantKey,
            "merchant-secret": merchantSecret,

            // Content
            "Content-Type":    "application/json",
            "Accept":          "application/json",

            // Signing
            "X-Timestamp":     timestamp,
            "X-Signature":     signatureHex,

            // SDK identity (matches Flutter SDK values exactly)
            "X-SDK-Name":      sdkName,
            "X-SDK-Version":   sdkVersion,

            // App metadata
            "X-App-ID":        configuration.resolvedAppId,
            "X-App-Version":   configuration.resolvedAppVersion,

            // Device metadata
            "X-Device-Id":     configuration.resolvedDeviceId,
            "X-Device-OS":     configuration.resolvedDeviceOS,
            "X-Device-Model":  configuration.resolvedDeviceModel,
            "X-DEVICE-BRAND":  configuration.resolvedDeviceBrand,
            "X-Browser-Token": configuration.resolvedBrowserToken,

            // Geo headers (required by gateway — E0021 without these)
            "X-IP":            GeoContext.effectiveIP,
            "X-IP-COUNTRY":    GeoContext.effectiveCountry,
        ]
        
        #if DEBUG
        debugPrint("[PayOrc] Headers being set on request:")
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            debugPrint("   \(name): \(value)")
        }
        #endif
        
        return headers
    }

    /// Returns headers for a GET-style or empty-body request.
    public static func signedHeaders(
        configuration: PayOrcConfiguration
    ) throws -> [String: String] {
        try signedHeaders(for: Data("{}".utf8), configuration: configuration)
    }
}
