import Foundation

// MARK: - PayOrcError

/// Comprehensive typed error taxonomy for the PayOrc iOS SDK.
///
/// Errors are grouped by category so callers can handle classes of failures
/// without exhaustive switching. Use ``localizedDescription`` for display-ready messages.
public enum PayOrcError: Error {

    // MARK: Configuration Errors

    /// SDK `initialize(configuration:)` has not been called yet.
    case sdkNotInitialized

    /// The supplied configuration is invalid (e.g. empty merchant key).
    case invalidConfiguration(String)

    // MARK: Validation Errors

    /// Card number is missing or fails Luhn check.
    case invalidCardNumber

    /// Expiry month/year is missing, in the past, or malformed.
    case invalidExpiryDate

    /// CVV is missing or wrong length for the card scheme.
    case invalidCVV

    /// Email address is missing or malformed.
    case invalidEmail

    /// Mobile number is missing or malformed.
    case invalidMobile

    /// Generic field-level validation failure with the field name and a display message.
    case validation(field: String, message: String)

    // MARK: Network Errors

    /// Device has no active internet connection.
    case noInternetConnection

    /// Request timed out before receiving a response.
    case timeout

    /// Server returned a non-2xx HTTP status code.
    case serverError(statusCode: Int, message: String?)

    /// Server returned 401 / 403 — credentials are invalid or expired.
    case unauthorized

    /// Low-level transport or Alamofire error wrapping the underlying cause.
    case requestFailed(underlying: Error)

    // MARK: API Business-Logic Errors

    /// The API responded with a non-success business code.
    /// `code` is the raw API code (e.g. `"E0021"`), `message` is display text.
    case apiFailure(code: String, message: String)

    /// Checkout customization endpoint failed or returned no data.
    case checkoutCustomizationFailed(String)

    /// Payment API returned a business-level failure.
    case paymentFailed(code: String, message: String)

    // MARK: Parsing / Decoding Errors

    /// JSON could not be decoded into the expected model.
    case decodingFailed(String)

    /// Response shape was completely unexpected.
    case unexpectedResponse

    // MARK: Platform Errors

    /// Requested feature is not available on this platform/OS version.
    case unsupported(feature: String)
}

// MARK: - LocalizedError

extension PayOrcError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sdkNotInitialized:
            return "PayOrc SDK is not initialized. Call PayOrc.initialize(configuration:) first."
        case .invalidConfiguration(let reason):
            return "PayOrc SDK configuration is invalid: \(reason)"

        case .invalidCardNumber:
            return "Enter a valid card number."
        case .invalidExpiryDate:
            return "Enter a valid expiry date."
        case .invalidCVV:
            return "Enter a valid CVV."
        case .invalidEmail:
            return "Enter a valid email address."
        case .invalidMobile:
            return "Enter a valid mobile number."
        case .validation(let field, let message):
            return "\(field): \(message)"

        case .noInternetConnection:
            return "No internet connection. Please check your network and try again."
        case .timeout:
            return "The request timed out. Please try again."
        case .serverError(let statusCode, let message):
            let base = "Server error (\(statusCode))."
            return message.map { "\(base) \($0)" } ?? base
        case .unauthorized:
            return "Authentication failed. Please check your merchant credentials."
        case .requestFailed(let underlying):
            return underlying.localizedDescription

        case .apiFailure(_, let message):
            return message
        case .checkoutCustomizationFailed(let reason):
            return "Checkout customization failed: \(reason)"
        case .paymentFailed(_, let message):
            return message

        case .decodingFailed(let detail):
            return "Could not parse server response. \(detail)"
        case .unexpectedResponse:
            return "Received an unexpected response from the server."

        case .unsupported(let feature):
            return "\(feature) is not supported on this platform."
        }
    }
}

// MARK: - Equatable

extension PayOrcError: Equatable {
    public static func == (lhs: PayOrcError, rhs: PayOrcError) -> Bool {
        switch (lhs, rhs) {
        case (.sdkNotInitialized, .sdkNotInitialized),
             (.invalidCardNumber, .invalidCardNumber),
             (.invalidExpiryDate, .invalidExpiryDate),
             (.invalidCVV, .invalidCVV),
             (.invalidEmail, .invalidEmail),
             (.invalidMobile, .invalidMobile),
             (.noInternetConnection, .noInternetConnection),
             (.timeout, .timeout),
             (.unauthorized, .unauthorized),
             (.unexpectedResponse, .unexpectedResponse):
            return true
        case (.invalidConfiguration(let a), .invalidConfiguration(let b)):
            return a == b
        case (.validation(let af, let am), .validation(let bf, let bm)):
            return af == bf && am == bm
        case (.serverError(let ac, let am), .serverError(let bc, let bm)):
            return ac == bc && am == bm
        case (.apiFailure(let ac, let am), .apiFailure(let bc, let bm)):
            return ac == bc && am == bm
        case (.checkoutCustomizationFailed(let a), .checkoutCustomizationFailed(let b)):
            return a == b
        case (.paymentFailed(let ac, let am), .paymentFailed(let bc, let bm)):
            return ac == bc && am == bm
        case (.decodingFailed(let a), .decodingFailed(let b)):
            return a == b
        case (.unsupported(let a), .unsupported(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Helpers

extension PayOrcError {
    /// Returns `true` when this is a validation-category error.
    public var isValidationError: Bool {
        switch self {
        case .invalidCardNumber, .invalidExpiryDate, .invalidCVV,
             .invalidEmail, .invalidMobile, .validation:
            return true
        default:
            return false
        }
    }

    /// Returns `true` when this is a network-category error.
    public var isNetworkError: Bool {
        switch self {
        case .noInternetConnection, .timeout, .serverError, .unauthorized, .requestFailed:
            return true
        default:
            return false
        }
    }

    /// Returns `true` when this is retryable (transient network issue).
    public var isRetryable: Bool {
        switch self {
        case .noInternetConnection, .timeout:
            return true
        case .serverError(let code, _):
            return code >= 500
        default:
            return false
        }
    }
}
