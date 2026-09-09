import UIKit

// MARK: - APIResponse

/// Generic top-level wrapper returned by all PayOrc service-sdk endpoints.
///
/// ```json
/// { "status": "success", "code": "00", "message": "...", "data": { ... } }
/// ```
///
/// Use ``isSuccess`` to check business-level success before accessing ``data``.
public struct APIResponse<T: Decodable>: Decodable {

    /// Human-readable status string (e.g. `"success"`, `"error"`).
    public let status:  String?

    /// Numeric API result code (e.g. `"00"` for success).
    public let code:    String?

    /// Human-readable message from the server.
    public let message: String?

    /// Decoded payload — `nil` when the API returned no data or an error.
    public let data:    T?

    // MARK: - Success Predicate

    /// `true` when `code == "00"` or `status == "success"` (case-insensitive).
    ///
    /// Mirrors the Flutter SDK's `CheckoutCustomizationResponse.isSuccess` logic.
    public var isSuccess: Bool {
        if let code, code == "00" { return true }
        if let status, status.lowercased() == "success" { return true }
        return false
    }

    // MARK: - Errors

    /// Converts the API response into a ``PayOrcError`` when it indicates failure.
    /// Returns `nil` when the response is successful.
    public func asError() -> PayOrcError? {
        guard !isSuccess else { return nil }
        let c = code    ?? "UNKNOWN"
        let m = message ?? "Unknown error from server."
        return .apiFailure(code: c, message: m)
    }
}

// MARK: - EmptyResponse

/// Decodable type for endpoints that return no meaningful `data` payload.
public struct EmptyResponse: Decodable {}
