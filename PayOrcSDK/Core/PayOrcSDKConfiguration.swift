import Foundation
import UIKit

// MARK: - PayOrcConfiguration

/// Configuration for the PayOrc iOS SDK.
///
/// Create one instance and pass it to ``PayOrcSDK/initialize(configuration:)``
/// once at app launch. All properties beyond `merchantKey`, `merchantSecret`,
/// and `environment` are optional and carry sensible defaults.
public struct PayOrcConfiguration {

    // MARK: Required

    /// Your PayOrc merchant key (provided in the PayOrc dashboard).
    public let merchantKey: String

    /// Your PayOrc merchant secret (provided in the PayOrc dashboard).
    public let merchantSecret: String

    /// The deployment environment (`sandbox` or `production`).
    public let environment: PayOrcEnvironment

    // MARK: Checkout Customization

    /// When `true` (default), the SDK automatically fetches checkout customization
    /// from the PayOrc API immediately after ``PayOrcSDK/initialize(configuration:)``
    /// is called — mirroring the Flutter SDK's `fetchCheckoutCustomizationOnInit`.
    public let fetchCheckoutCustomizationOnInit: Bool

    /// Currency code sent with the automatic checkout customization request.
    /// Defaults to `"AED"`. Pass the merchant's primary currency here.
    public let checkoutCustomizationCurrency: String

    /// Amount sent with the automatic checkout customization request.
    /// Defaults to `1`. Used to derive payment-method availability.
    public let checkoutCustomizationAmount: Decimal

    // MARK: Optional — Tabby

    /// Tabby API key. When set, Tabby Buy Now Pay Later becomes available.
    public let tabbyApiKey: String?

    /// Tabby merchant code (e.g. `"ae"` for UAE, `"sa"` for KSA).
    /// Required when ``tabbyApiKey`` is set.
    public let tabbyMerchantCode: String

    // MARK: Optional — Device / App Metadata

    /// Override for the `X-App-ID` header. Defaults to the bundle identifier.
    public let appId: String?

    /// Override for the `X-App-Version` header. Defaults to the bundle short version.
    public let appVersion: String?

    /// Override for the `X-Device-Id` header. Defaults to `UIDevice.current.identifierForVendor`.
    public let deviceId: String?

    /// Override for the `X-Device-OS` header. Defaults to `"iOS"`.
    public let deviceOS: String?

    /// Override for the `X-Device-Model` header.
    /// Defaults to `UIDevice.current.model` (e.g. `"iPhone"`).
    public let deviceModel: String?

    /// Override for the `X-DEVICE-BRAND` header. Defaults to `"Apple"`.
    public let deviceBrand: String?

    /// Optional `X-Browser-Token` header value.
    public let browserToken: String?

    // MARK: Initializer

    public init(
        merchantKey: String,
        merchantSecret: String,
        environment: PayOrcEnvironment = .sandbox,
        fetchCheckoutCustomizationOnInit: Bool = true,
        checkoutCustomizationCurrency: String = "AED",
        checkoutCustomizationAmount: Decimal = 1,
        tabbyApiKey: String? = nil,
        tabbyMerchantCode: String = "ae",
        appId: String? = nil,
        appVersion: String? = nil,
        deviceId: String? = nil,
        deviceOS: String? = nil,
        deviceModel: String? = nil,
        deviceBrand: String? = nil,
        browserToken: String? = nil
    ) {
        self.merchantKey = merchantKey
        self.merchantSecret = merchantSecret
        self.environment = environment
        self.fetchCheckoutCustomizationOnInit = fetchCheckoutCustomizationOnInit
        self.checkoutCustomizationCurrency = checkoutCustomizationCurrency
        self.checkoutCustomizationAmount = checkoutCustomizationAmount
        self.tabbyApiKey = tabbyApiKey
        self.tabbyMerchantCode = tabbyMerchantCode
        self.appId = appId
        self.appVersion = appVersion
        self.deviceId = deviceId
        self.deviceOS = deviceOS
        self.deviceModel = deviceModel
        self.deviceBrand = deviceBrand
        self.browserToken = browserToken
    }
}

// MARK: - Resolved Header Values

extension PayOrcConfiguration {

    /// Resolved `X-App-ID` — falls back to the host bundle identifier.
    var resolvedAppId: String {
        appId ?? Bundle.main.bundleIdentifier ?? "payorc-ios-sdk"
    }

    /// Resolved `X-App-Version` — falls back to `CFBundleShortVersionString`.
    var resolvedAppVersion: String {
        appVersion
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "1.0"
    }

    /// Resolved `X-Device-Id` — falls back to `identifierForVendor` UUID string.
    var resolvedDeviceId: String {
        deviceId
            ?? UIDevice.current.identifierForVendor?.uuidString
            ?? UUID().uuidString
    }

    /// Resolved `X-Device-OS` — always `"iOS"` unless explicitly overridden.
    var resolvedDeviceOS: String {
        deviceOS ?? "iOS"
    }

    /// Resolved `X-Device-Model` — falls back to `UIDevice.current.model`.
    var resolvedDeviceModel: String {
        deviceModel ?? UIDevice.current.model
    }

    /// Resolved `X-DEVICE-BRAND` — defaults to `"Apple"` on iOS to match Flutter and Postman samples.
    var resolvedDeviceBrand: String {
        deviceBrand ?? "Apple"
    }

    /// Resolved `X-Browser-Token` — falls back to a stable `identifierForVendor` UUID.
    var resolvedBrowserToken: String {
        browserToken
            ?? UIDevice.current.identifierForVendor?.uuidString
            ?? UUID().uuidString
    }
}

// MARK: - Validation

extension PayOrcConfiguration {

    /// Throws ``PayOrcError/invalidConfiguration(_:)`` if required fields are blank.
    func validate() throws {
        let trimmedMerchantKey = merchantKey.trimmingCharacters(in: .whitespaces)
        guard !trimmedMerchantKey.isEmpty else {
            throw PayOrcError.invalidConfiguration("merchantKey must not be empty.")
        }
        guard !merchantSecret.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PayOrcError.invalidConfiguration("merchantSecret must not be empty.")
        }
        if environment == .production && trimmedMerchantKey.lowercased().hasPrefix("test-") {
            throw PayOrcError.invalidConfiguration(
                "Production environment cannot use a test merchant key. Use sandbox for test keys."
            )
        }
    }
}

// MARK: - Equatable

extension PayOrcConfiguration: Equatable {
    public static func == (lhs: PayOrcConfiguration, rhs: PayOrcConfiguration) -> Bool {
        lhs.merchantKey == rhs.merchantKey &&
        lhs.merchantSecret == rhs.merchantSecret &&
        lhs.environment == rhs.environment
    }
}
