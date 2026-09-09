import Foundation

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private func decodeIfPresent<T: Decodable>(
    _ type: T.Type,
    from container: KeyedDecodingContainer<AnyCodingKey>,
    keys: [String]
) throws -> T? {
    for key in keys {
        guard let codingKey = AnyCodingKey(stringValue: key) else { continue }
        if let value = try container.decodeIfPresent(T.self, forKey: codingKey) {
            return value
        }
    }
    return nil
}

// MARK: - CheckoutCustomizationResponse
//
// Full mirror of the Flutter SDK's `checkout_customization_response.dart`.
// JSON keys follow snake_case; decoded via `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`.

/// Top-level response from `POST .../sdk/checkout/customization`.
///
/// Wraps the inner ``CheckoutCustomizationData`` alongside standard API metadata.
public struct CheckoutCustomizationResponse: Decodable {

    public let data:    CheckoutCustomizationData?
    public let message: String?
    public let status:  String?
    public let code:    String?

    /// `true` when `code == "00"` or `status` is `"success"`.
    public var isSuccess: Bool {
        if let code, code == "00" { return true }
        if let status, status.lowercased() == "success" { return true }
        return false
    }
}

// MARK: - CheckoutCustomizationData

/// Payload returned by the checkout customization endpoint.
///
/// Contains available payment methods, merchant branding/UI details,
/// company details, and logo URLs.
public struct CheckoutCustomizationData: Decodable {

    /// Ordered list of payment methods enabled for this merchant.
    public let availableMethods:          [AvailablePaymentMethod]

    /// URL of the PayOrc-hosted SDK logo.
    public let payorcLogo:                String?

    /// Merchant-specific UI customization values.
    public let merchantDetails:           MerchantDetails?

    /// Whether the billing section should be shown on the new-card form.
    public let showNewCardBillingSection: Bool?

    /// Company branding assets.
    public let companyDetails:            CompanyDetails?

    // MARK: CodingKeys — handle snake_case field name variants

    enum CodingKeys: String, CodingKey {
        case availableMethods          = "available_methods"
        case payorcLogo                = "sdk_payorc_logo"
        case merchantDetails           = "merchant_details"
        case showNewCardBillingSection  = "show_new_card_billing_section"
        case companyDetails            = "company_details"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        availableMethods = (try? decodeIfPresent([AvailablePaymentMethod].self, from: c, keys: ["available_methods", "availableMethods"])) ?? []
        payorcLogo = try? decodeIfPresent(String.self, from: c, keys: ["sdk_payorc_logo", "sdkPayorcLogo"])
        merchantDetails = try? decodeIfPresent(MerchantDetails.self, from: c, keys: ["merchant_details", "merchantDetails"])
        showNewCardBillingSection = try? decodeIfPresent(Bool.self, from: c, keys: ["show_new_card_billing_section", "showNewCardBillingSection"])
        companyDetails = try? decodeIfPresent(CompanyDetails.self, from: c, keys: ["company_details", "companyDetails"])
    }
}

// MARK: - AvailablePaymentMethod

/// A single payment method entry from `available_methods`.
///
/// Mirrors Flutter's `AvailablePaymentMethod`.
public struct AvailablePaymentMethod: Decodable {

    /// Method type identifier (e.g. `"card"`, `"apple_pay"`, `"tabby"`).
    public let type:             String

    /// Display order (lower = higher priority).
    public let sequence:         Int

    /// `1` = visible to the user, `0` = hidden.
    public let show:             Int

    /// Supported card schemes for card-type methods (e.g. `["visa", "mastercard"]`).
    public let schemes:          [String]

    /// Payment service provider identifier.
    public let psp:              String

    /// Merchant-facing identifier for this method (Apple Pay merchant identifier, etc.)
    public let identifier:       String

    /// Merchant ID provided by the PSP.
    public let merchantId:       String

    /// Gateway merchant ID (Google Pay).
    public let gatewayMerchantId: String

    /// Public key for client-side encryption (where applicable).
    public let publicKey:        String

    /// Merchant code (Tabby, etc.)
    public let merchantCode:     String

    // MARK: Helpers

    /// `true` when this method should be shown to the user.
    public var isVisible: Bool { show == 1 }

    enum CodingKeys: String, CodingKey {
        case type, sequence, show, schemes, psp, identifier
        case merchantId       = "merchant_id"
        case gatewayMerchantId = "gateway_merchant_id"
        case publicKey        = "public_key"
        case merchantCode     = "merchant_code"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        type = (try? decodeIfPresent(String.self, from: c, keys: ["type"])) ?? ""
        sequence = (try? decodeIfPresent(Int.self, from: c, keys: ["sequence"])) ?? 0
        show = Self.decodeTruthyInt(from: c, keys: ["show"])
        schemes = (try? decodeIfPresent([String].self, from: c, keys: ["schemes"])) ?? []
        psp = (try? decodeIfPresent(String.self, from: c, keys: ["psp"])) ?? ""
        identifier = (try? decodeIfPresent(String.self, from: c, keys: ["identifier"])) ?? ""
        merchantId = (try? decodeIfPresent(String.self, from: c, keys: ["merchant_id", "merchantId"])) ?? ""
        gatewayMerchantId = (try? decodeIfPresent(String.self, from: c, keys: ["gateway_merchant_id", "gatewayMerchantId"])) ?? ""
        publicKey = (try? decodeIfPresent(String.self, from: c, keys: ["public_key", "publicKey"])) ?? ""
        merchantCode = (try? decodeIfPresent(String.self, from: c, keys: ["merchant_code", "merchantCode"])) ?? ""
    }

    /// Mirrors Flutter's `_asTruthyInt`: accepts Bool, Int, or string "1"/"true"/"yes".
    private static func decodeTruthyInt(
        from container: KeyedDecodingContainer<AnyCodingKey>,
        keys: [String]
    ) -> Int {
        for key in keys {
            guard let codingKey = AnyCodingKey(stringValue: key) else { continue }
            if let b = try? container.decode(Bool.self, forKey: codingKey) { return b ? 1 : 0 }
            if let i = try? container.decode(Int.self, forKey: codingKey) { return i }
            if let s = try? container.decode(String.self, forKey: codingKey) {
                let t = s.trimmingCharacters(in: CharacterSet.whitespaces).lowercased()
                if t == "1" || t == "true" || t == "yes" || t == "on" { return 1 }
                return Int(t) ?? 0
            }
        }
        return 0
    }
}

// MARK: - MerchantDetails

/// Merchant branding and UI configuration returned by checkout customization.
///
/// Mirrors Flutter's `MerchantDetails` — all fields are optional because
/// the API may omit any of them.
public struct MerchantDetails: Decodable {

    // MARK: Branding

    public let theme:               String?
    public let icon:                String?
    public let logo:                String?
    public let useLogo:             Int?
    public let weAcceptImage:       String?
    public let cobrandingLogo:      String?
    public let cobrandingLogoFilename: String?
    public let cobrandingLogoVisible:  Int?
    public let useLogoInsteadIcon:  Int?
    public let merchantName:        String?
    public let companyName:         String?

    // MARK: Colors

    /// Hex color string for the brand color (e.g. `"#1A73E8"`).
    public let brandColor:          String?

    /// Hex color string for primary action buttons.
    public let buttonColor:         String?

    /// Hex color string for accent / highlight elements.
    public let accentColor:         String?

    /// Hex color for borders/outlines.
    public let borderColor:         String?

    /// Hex color for primary text.
    public let textPrimary:         String?

    /// Hex color for secondary/subtitle text.
    public let textSecondary:       String?

    /// Raw integer encoding a color (used for auto-select tint in some PSPs).
    public let autoselectColor:     Int?

    // MARK: Typography

    /// Custom font name (e.g. `"Poppins-Regular"`).
    public let fontName:            String?
    public let brandingLanguage:    String?

    // MARK: Form / Layout

    /// Input border style — `"outline"` or `"underline"`.
    public let fieldBorder:         String?

    /// App bar / navigation style — `"nativeIos"` or `"nativeAndroid"`.
    public let appStyle:            String?

    // MARK: Field Visibility Flags

    public let amountVisible:          Int?
    public let shippingAddressVisible: Int?
    public let locationVisible:        Int?
    public let mobileVisible:          Int?
    public let convenienceVisible:     Int?
    public let shippingFeeVisible:     Int?
    public let emailVisible:           Int?
    public let nameVisible:            Int?
    public let remarkVisible:          Int?
    public let remarkLabel:            String?
    public let shippingVisible:        Int?

    // MARK: Card Schemes

    /// List of supported card scheme strings (e.g. `["visa", "mastercard", "amex"]`).
    public let supportedCardSchemes: [String]

    // MARK: Misc

    public let sdkOptions:  [String: AnyCodable]?
    public let tcLink:      String?

    // MARK: CodingKeys

    enum CodingKeys: String, CodingKey {
        case theme, icon, logo, borderColor, fontName
        case useLogo               = "use_logo"
        case weAcceptImage         = "we_accept_image"
        case cobrandingLogo        = "cobranding_logo"
        case cobrandingLogoFilename = "cobranding_logo_filename"
        case cobrandingLogoVisible  = "cobranding_logo_visible"
        case useLogoInsteadIcon    = "use_logo_instead_icon"
        case merchantName          = "merchant_name"
        case companyName           = "company_name"
        case brandColor            = "brand_color"
        case buttonColor           = "button_color"
        case accentColor           = "accent_color"
        case textPrimary           = "text_primary"
        case textSecondary         = "text_secondary"
        case autoselectColor       = "autoselect_color"
        case brandingLanguage      = "branding_language"
        case fieldBorder           = "field_border"
        case appStyle              = "app_style"
        case amountVisible         = "amount_visible"
        case shippingAddressVisible = "shipping_address_visible"
        case locationVisible       = "location_visible"
        case mobileVisible         = "mobile_visible"
        case convenienceVisible    = "convenience_visible"
        case shippingFeeVisible    = "shipping_fee_visible"
        case emailVisible          = "email_visible"
        case nameVisible           = "name_visible"
        case remarkVisible         = "remark_visible"
        case remarkLabel           = "remark_label"
        case shippingVisible       = "shipping_visible"
        case supportedCardSchemes  = "supported_card_schemes"
        case sdkOptions            = "sdk_options"
        case tcLink                = "tc_link"
    }

    // MARK: Convenience Helpers

    /// `true` when the field border should be rendered as an outline box.
    public var isOutlineBorder: Bool {
        fieldBorder?.lowercased() == "outline"
    }

    /// `true` when a native-iOS style app bar / navigation should be used.
    public var useNativeIosAppBar: Bool {
        appStyle?.lowercased() == "nativeios"
    }
}

// MARK: - CompanyDetails

/// Company-level branding assets returned by checkout customization.
///
/// Mirrors Flutter's `CompanyDetails`.
public struct CompanyDetails: Decodable {

    public let favIcon:          String?
    public let logo:             String?
    public let letterHead:       String?
    public let footerBanner:     String?
    public let title:            String?
    public let termsAndCondition: String?

    enum CodingKeys: String, CodingKey {
        case logo, title
        case favIcon          = "fav_icon"
        case letterHead       = "letter_head"
        case footerBanner     = "footer_banner"
        case termsAndCondition = "terms_and_condition"
    }
}

// MARK: - PaymentMethodType

/// Strongly-typed payment method identifiers.
public enum PaymentMethodType: String {
    case card      = "card"
    case applePay  = "apple_pay"
    case googlePay = "google_pay"
    case tabby     = "tabby"
    case samsungPay = "samsung_pay"
    case unknown
}

extension AvailablePaymentMethod {
    /// Typed representation of ``type``.
    public var paymentMethodType: PaymentMethodType {
        PaymentMethodType(rawValue: type.lowercased()) ?? .unknown
    }
}
