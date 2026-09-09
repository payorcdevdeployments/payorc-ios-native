import PassKit

// MARK: - ApplePayConfiguration

/// Apple Pay parameters resolved from checkout customization — the Swift
/// equivalent of Flutter's `buildApplePayConfigurationJson(...)`.
public struct ApplePayConfiguration {
    public let merchantIdentifier:   String
    public let displayName:          String
    public let supportedNetworks:    [PKPaymentNetwork]
    public let merchantCapabilities: PKMerchantCapability
    public let countryCode:          String
    public let currencyCode:         String
}

extension ApplePayConfiguration {

    /// Resolves Apple Pay configuration from checkout customization.
    ///
    /// Looks for the `available_methods` entry whose `type` normalizes to
    /// `APPLE_PAY`, is visible (`show != 0`), and has a non-empty `identifier`
    /// or `merchant_id`. Returns `nil` when Apple Pay isn't configured/visible
    /// for this merchant — mirrors Flutter's `buildApplePayConfigurationJson`.
    public static func resolve(
        customization: CheckoutCustomizationData?,
        currencyCode:  String,
        countryCode:   String = "AE"
    ) -> ApplePayConfiguration? {
        #if DEBUG
        print("[ApplePayConfig] 🔍 Resolving Apple Pay configuration...")
        #endif
        
        guard let customization else {
            #if DEBUG
            print("[ApplePayConfig] ❌ No customization data provided")
            #endif
            return nil
        }

        guard let method = customization.availableMethods.first(where: { method in
            normalize(method.type) == normalize("APPLE_PAY") &&
            method.show != 0 &&
            !(trim(method.identifier).isEmpty && trim(method.merchantId).isEmpty)
        }) else {
            #if DEBUG
            print("[ApplePayConfig] ❌ Apple Pay not found in available methods or is hidden")
            print("[ApplePayConfig]    Available methods: \\(customization.availableMethods.map { $0.type })")
            #endif
            return nil
        }

        let merchantIdentifier = !trim(method.identifier).isEmpty
            ? trim(method.identifier)
            : trim(method.merchantId)

        let md = customization.merchantDetails
        let merchantLabel = trim(md?.merchantName ?? "")
        let companyLabel  = trim(md?.companyName ?? "")
        let displayName = !merchantLabel.isEmpty
            ? merchantLabel
            : (!companyLabel.isEmpty ? companyLabel : "Pay")

        let schemeSources = !method.schemes.isEmpty ? method.schemes : (md?.supportedCardSchemes ?? [])
        let networks = mapSchemesToNetworks(schemeSources)
        let supportedNetworks = !networks.isEmpty ? networks : [.visa, .masterCard, .amex]

        let cc = currencyCode.trimmingCharacters(in: .whitespaces).uppercased()
        let co = countryCode.trimmingCharacters(in: .whitespaces).uppercased()
        
        #if DEBUG
        print("[ApplePayConfig] 📋 Configuration parameters:")
        print("  Currency (input): '\\(currencyCode)' → '\\(cc)'")
        print("  Country (input): '\\(countryCode)' → '\\(co)'")
        print("  Schemes (input): \\(schemeSources)")
        print("  Networks (resolved): \\(supportedNetworks.map { $0.rawValue })")
        #endif
        
        guard !cc.isEmpty, !co.isEmpty else {
            #if DEBUG
            print("[ApplePayConfig] ❌ Currency or country code is empty after trimming")
            #endif
            return nil
        }

        #if DEBUG
        print("[ApplePayConfig] ✅ Configuration resolved successfully")
        #endif
        
        return ApplePayConfiguration(
            merchantIdentifier:   merchantIdentifier,
            displayName:          displayName,
            supportedNetworks:    supportedNetworks,
            merchantCapabilities: [.capability3DS, .capabilityDebit, .capabilityCredit],
            countryCode:          co,
            currencyCode:         cc
        )
    }

    private static func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
    }

    private static func normalize(_ raw: String) -> String {
        raw.uppercased().filter { !" _-".contains($0) }
    }

    private static func mapSchemesToNetworks(_ schemes: [String]) -> [PKPaymentNetwork] {
        var out: [PKPaymentNetwork] = []
        for raw in schemes {
            guard let network = mapOneScheme(normalize(raw)), !out.contains(network) else { continue }
            out.append(network)
        }
        return out
    }

    private static func mapOneScheme(_ normalized: String) -> PKPaymentNetwork? {
        switch normalized {
        case "VISA":                                          return .visa
        case "MASTERCARD", "MASTER", "MC", "EUROCARD":        return .masterCard
        case "AMEX", "AMERICANEXPRESS", "AMERICAN":           return .amex
        case "DISCOVER":                                      return .discover
        case "JCB":                                           return .JCB
        case "MAESTRO", "MAESTROUK":                          return .maestro
        default:                                              return nil
        }
    }
}
