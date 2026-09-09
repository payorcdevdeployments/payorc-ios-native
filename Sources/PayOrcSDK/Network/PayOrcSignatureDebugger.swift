import Foundation

// MARK: - PayOrc Signature Debugger

/// Diagnostic utility for debugging E0021 signature failures.
///
/// Use this to:
/// 1. Verify your credentials are set correctly
/// 2. Test signature generation locally
/// 3. Compare iOS vs Flutter signature formats
/// 4. Generate test payloads for manual curl testing
struct PayOrcSignatureDebugger {

    // MARK: - Test Payload Generator

    /// Generates a minimal test payment payload for signature debugging.
    static func testPaymentPayload() -> [String: Any] {
        return [
            "data": [
                "action": "AUTH",
                "type": "CARD",
                "class": "ECOM",
                "capture_method": "MANUAL",
                "card_details": [
                    "card_number": "4111111111111111",
                    "expiry": "08/29",
                    "cvv": "123",
                    "card_holder_name": "Test User",
                    "payment_token": ""
                ],
                "billing_details": [
                    "address_line1": "Test Address",
                    "address_line2": "",
                    "city": "Dubai",
                    "province": "",
                    "country": "AE",
                    "pin": ""
                ],
                "customer_details": [
                    "m_customer_id": "test-cust-123",
                    "name": "Test Customer",
                    "email": "test@example.com",
                    "mobile": "971500000000",
                    "code": "971"
                ],
                "order_details": [
                    "m_order_id": "test-order-123",
                    "amount": "10.00",
                    "currency": "AED",
                    "description": "Test Payment",
                    "convenience_fee": ""
                ]
            ]
        ]
    }

    /// Generates a minimal test checkout customization payload.
    static func testCheckoutPayload() -> [String: Any] {
        return [
            "data": [
                "currency": "AED",
                "amount": 100
            ]
        ]
    }

    // MARK: - Signature Verification

    /// Manually computes a test signature to compare with SDK output.
    ///
    /// Usage:
    /// ```swift
    /// let payload = PayOrcSignatureDebugger.testPaymentPayload()
    /// let bodyJson = try! CompactJSONEncoder.encodeCompactString(payload)
    /// let sig = PayOrcSignatureDebugger.computeSignature(
    ///     merchantKey: "test-KEY",
    ///     merchantSecret: "test-SECRET",
    ///     timestamp: "1234567890",
    ///     bodyJson: bodyJson
    /// )
    /// print("Test signature: \(sig)")
    /// ```
    static func computeSignature(
        merchantKey: String,
        merchantSecret: String,
        timestamp: String,
        bodyJson: String
    ) -> String {
        let signatureInput = merchantKey + timestamp + bodyJson
        
        let symmetricKey = CryptoKit.SymmetricKey(data: Data(merchantSecret.utf8))
        let mac = CryptoKit.HMAC<CryptoKit.SHA256>.authenticationCode(
            for: Data(signatureInput.utf8),
            using: symmetricKey
        )
        
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Curl Command Generator

    /// Generates a ready-to-use curl command for testing.
    ///
    /// Usage:
    /// ```swift
    /// let command = PayOrcSignatureDebugger.curlCommand(
    ///     merchantKey: "test-KEY",
    ///     merchantSecret: "test-SECRET",
    ///     signature: "abc123...",
    ///     timestamp: "1234567890",
    ///     payload: testPaymentPayload(),
    ///     url: "https://gateway.payorc.com/service-sdk/api/v1/sdk/payment"
    /// )
    /// print(command)
    /// // Copy and paste into terminal
    /// ```
    static func curlCommand(
        merchantKey: String,
        merchantSecret: String,
        signature: String,
        timestamp: String,
        payload: [String: Any],
        url: String
    ) throws -> String {
        let bodyJson = try CompactJSONEncoder.encodeCompactString(payload)
        
        var curl = "curl -X POST '\(url)' \\\n"
        curl += "  -H 'merchant-key: \(merchantKey)' \\\n"
        curl += "  -H 'merchant-secret: \(merchantSecret)' \\\n"
        curl += "  -H 'Content-Type: application/json' \\\n"
        curl += "  -H 'X-Timestamp: \(timestamp)' \\\n"
        curl += "  -H 'X-Signature: \(signature)' \\\n"
        curl += "  -H 'X-SDK-Name: payorc-sdk' \\\n"
        curl += "  -H 'X-SDK-Version: 1.0.0' \\\n"
        curl += "  -H 'X-App-ID: payorc.IosPayorcDemoApp' \\\n"
        curl += "  -H 'X-App-Version: 1.0' \\\n"
        curl += "  -H 'X-Device-Os: iOS' \\\n"
        curl += "  -H 'X-Device-Model: iPhone' \\\n"
        curl += "  -H 'X-DEVICE-BRAND: Apple' \\\n"
        curl += "  -H 'X-IP: 127.0.0.1' \\\n"
        curl += "  -H 'X-IP-COUNTRY: ZZ' \\\n"
        curl += "  -H 'Accept: application/json' \\\n"
        curl += "  --data-raw '\(bodyJson)'"
        
        return curl
    }

    // MARK: - Diagnostic Report

    /// Prints a comprehensive debugging report.
    static func printDiagnosticReport(
        merchantKey: String,
        merchantSecret: String,
        timestamp: String,
        payload: [String: Any]
    ) throws {
        print("╔══════════════════════════════════════════════════════╗")
        print("║    PayOrc iOS Signature Debugger Report              ║")
        print("╚══════════════════════════════════════════════════════╝")
        print()
        print("🔑 Credentials:")
        print("   Merchant Key: \(merchantKey)")
        print("   Merchant Secret: \(merchantSecret) [length: \(merchantSecret.count)]")
        print()
        print("⏰ Timestamp: \(timestamp)")
        print()
        
        let bodyJson = try CompactJSONEncoder.encodeCompactString(payload)
        print("📦 Payload (compact JSON):")
        print("   \(bodyJson)")
        print("   Byte count: \(bodyJson.utf8.count)")
        print()
        
        let signature = computeSignature(
            merchantKey: merchantKey,
            merchantSecret: merchantSecret,
            timestamp: timestamp,
            bodyJson: bodyJson
        )
        print("✍️  Computed Signature:")
        print("   \(signature)")
        print()
        
        print("🔗 Use this for testing:")
        print("   X-Timestamp: \(timestamp)")
        print("   X-Signature: \(signature)")
        print()
    }
}

// Import CryptoKit at module level
import CryptoKit
