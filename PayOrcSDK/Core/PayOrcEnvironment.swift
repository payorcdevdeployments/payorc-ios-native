import Foundation

// MARK: - PayOrcEnvironment

/// The deployment environment for the PayOrc SDK.
///
/// This controls which base URLs are used for API calls. Note that checkout
/// customization **always** uses the production host regardless of environment —
/// this mirrors the Flutter SDK's behaviour where the dev-gateway rejects
/// production merchant keys with error `E0021`.
public enum PayOrcEnvironment: String, CaseIterable, Codable, Sendable {
    case sandbox
    case production
}

// MARK: - URL Resolution

extension PayOrcEnvironment {

    // MARK: Base URLs

    /// Production base URL (scheme + host + path prefix).
    static let productionBaseURL = "https://gateway.payorc.com/service-sdk/api/v1"

    /// Sandbox base URL.
    ///
    /// The PayOrc integration currently uses the same gateway host for both
    /// sandbox and production environments.
    static let sandboxBaseURL    = productionBaseURL

    /// The base URL for payment / add-card / customer-cards calls.
    public var baseURL: String {
        switch self {
        case .sandbox:    return Self.sandboxBaseURL
        case .production: return Self.productionBaseURL
        }
    }

    // MARK: Endpoint URLs

    /// POST `sdk/payment`
    public var paymentURL: String {
        "\(baseURL)/sdk/payment"
    }

    /// POST `sdk/wallet/payment`
    public var walletPaymentURL: String {
        "\(baseURL)/sdk/wallet/payment"
    }

    /// POST `sdk/add-card`
    public var addCardURL: String {
        "\(baseURL)/sdk/add-card"
    }

    /// POST `sdk/customer/cards`
    public var customerCardsURL: String {
        "\(baseURL)/sdk/customer/cards"
    }

    /// POST `sdk/tabby/init`
    public var tabbyInitURL: String {
        "\(baseURL)/sdk/tabby/init"
    }

    /// POST `sdk/tabby/confirm`
    public var tabbyConfirmURL: String {
        "\(baseURL)/sdk/tabby/confirm"
    }

    /// POST `sdk/checkout/customization`
    ///
    /// This **always** uses the production host, regardless of the current environment.
    /// The dev-gateway rejects production merchant keys, so customization must be
    /// fetched from the production service even during sandbox testing.
    public var checkoutCustomizationURL: String {
        "\(Self.productionBaseURL)/sdk/checkout/customization"
    }

    // MARK: Convenience

    /// Human-readable label for logging / display.
    public var displayName: String {
        switch self {
        case .sandbox:    return "Sandbox"
        case .production: return "Production"
        }
    }
}
