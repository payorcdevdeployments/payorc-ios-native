import Foundation

// MARK: - APIEndpoint

/// All PayOrc service-sdk API endpoints.
///
/// Each case encapsulates the HTTP method, full URL, and JSON body parameters.
/// Use ``buildRequest(configuration:)`` to produce a signed ``URLRequest``.
public enum APIEndpoint {

    // MARK: Checkout

    /// `POST sdk/checkout/customization`
    ///
    /// Fetches merchant UI customization (colors, payment methods, branding).
    /// **Always uses the production host** regardless of the active environment —
    /// the dev-gateway rejects production merchant keys.
    case checkoutCustomization(currency: String, amount: Decimal)

    // MARK: Payments

    /// `POST sdk/payment` — Submit a card payment.
    /// Accepts pre-built ordered JSON `Data` (Flutter-compatible byte order, no \/ escaping).
    case payment(bodyData: Data)

    /// `POST sdk/payment` — Submit a card payment from a raw body dictionary (legacy / wallet).
    case paymentDict(body: [String: Any])

    /// `POST sdk/wallet/payment` — Submit an Apple Pay / wallet payment.
    case walletPayment(body: [String: Any])

    /// `POST sdk/add-card` — Tokenise (save) a new card.
    case addCard(body: [String: Any])

    /// `POST sdk/customer/cards` — List saved cards for a customer.
    case customerCards(body: [String: Any])

    // MARK: Tabby

    /// `POST sdk/tabby/init` — Initialise a Tabby BNPL session.
    case tabbyInit(body: [String: Any])

    /// `POST sdk/tabby/confirm` — Confirm a Tabby BNPL payment.
    case tabbyConfirm(body: [String: Any])
}

// MARK: - Properties

extension APIEndpoint {

    /// HTTP method string for the endpoint (all PayOrc endpoints are POST).
    var httpMethod: String { "POST" }

    /// Resolves the full URL string for the given environment.
    func urlString(environment: PayOrcEnvironment) -> String {
        switch self {
        case .checkoutCustomization:
            return environment.checkoutCustomizationURL
        case .payment, .paymentDict:
            return environment.paymentURL
        case .walletPayment:
            return environment.walletPaymentURL
        case .addCard:
            return environment.addCardURL
        case .customerCards:
            return environment.customerCardsURL
        case .tabbyInit:
            return environment.tabbyInitURL
        case .tabbyConfirm:
            return environment.tabbyConfirmURL
        }
    }

    /// JSON body parameters dictionary.
    var parameters: [String: Any] {
        switch self {
        case .checkoutCustomization(let currency, let amount):
            let doubleValue = Double(truncating: amount as NSDecimalNumber)
            let normalizedAmount: Any = doubleValue.truncatingRemainder(dividingBy: 1) == 0
                ? Int(doubleValue)
                : doubleValue
            return [
                "data": [
                    "currency": currency,
                    "amount": normalizedAmount
                ]
            ]
        case .paymentDict(let body),
             .walletPayment(let body),
             .addCard(let body),
             .customerCards(let body),
             .tabbyInit(let body),
             .tabbyConfirm(let body):
            return body
        case .payment:
            // Pre-built Data — bodyData is used directly in buildRequest.
            return [:]
        }
    }

    // MARK: - URLRequest Builder

    /// Builds a fully signed ``URLRequest`` for this endpoint.
    ///
    /// - Parameter configuration: The active SDK configuration (keys + device info).
    /// - Returns: A ready-to-send `URLRequest` with HMAC signature headers.
    /// - Throws: ``PayOrcError`` if the URL is malformed or signing fails.
    func buildRequest(configuration: PayOrcConfiguration) throws -> URLRequest {
        let urlString = urlString(environment: configuration.environment)
        guard let url = URL(string: urlString) else {
            throw PayOrcError.invalidConfiguration("Malformed endpoint URL: \(urlString)")
        }

        let bodyData: Data

        if case .payment(let prebuiltData) = self {
            // Pre-built ordered JSON — use directly, no re-encoding.
            // This preserves Flutter's exact insertion-order key sequence and avoids
            // JSONSerialization's \/ forward-slash escaping, both of which cause 401s.
            bodyData = prebuiltData
        } else {
            // Standard path: normalize parameters and encode via CompactJSONEncoder.
            let normalizedParams = JSNormalizer.normalize(parameters) as? [String: Any] ?? parameters
            bodyData = try CompactJSONEncoder.encodeCompact(normalizedParams)
        }

        let bodyString = String(data: bodyData, encoding: .utf8) ?? "{}"

        #if DEBUG
        let isCompactFormat = CompactJSONEncoder.isCompact(bodyString)
        if !isCompactFormat {
            debugPrint("⚠️  [PayOrc] WARNING: Body JSON is not compact!")
            debugPrint("   Body: \(bodyString)")
        }
        #endif

        var request = URLRequest(url: url)
        request.httpMethod  = httpMethod
        request.httpBody    = bodyData
        request.timeoutInterval = 30

        let headers = try RequestSigner.signedHeaders(for: bodyData, configuration: configuration)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        #if DEBUG
        let missingHeaders = ["merchant-secret", "X-Signature"].filter { request.value(forHTTPHeaderField: $0) == nil }
        if missingHeaders.isEmpty {
            debugPrint("[PayOrc] ✅ Signed headers attached: merchant-secret and X-Signature present")
        } else {
            debugPrint("[PayOrc] ❌ Missing signed headers: \(missingHeaders)")
        }
        debugPrint("[PayOrc] Built request for endpoint=\(self) environment=\(configuration.environment.rawValue) url=\(url.absoluteString)")
        debugPrint("[PayOrc] Request body (compact, used for signature):")
        debugPrint("   \(bodyString)")
        debugPrint("[PayOrc] Body byte count: \(bodyData.count)")
        debugPrint("[PayOrc] Actual httpBody byte count: \(request.httpBody?.count ?? 0)")
        if let actualBody = request.httpBody, actualBody == bodyData {
            debugPrint("[PayOrc] ✅ httpBody matches signed body - GOOD")
        } else {
            debugPrint("[PayOrc] ❌ WARNING: httpBody does NOT match signed body!")
        }
        #endif

        return request
    }
}
