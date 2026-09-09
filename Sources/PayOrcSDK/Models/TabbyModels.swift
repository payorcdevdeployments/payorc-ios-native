import Foundation

public enum TabbySessionStatus: String, Decodable {
    case created
    case rejected
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = TabbySessionStatus(rawValue: rawValue) ?? .unknown
    }
}

public struct TabbyInitData: Equatable {
    public let orderId: String
    public let merchantCode: String
    public let password: String
    public let extraKey: String?
    public let mode: String?

    public init(
        orderId: String,
        merchantCode: String,
        password: String,
        extraKey: String? = nil,
        mode: String? = nil
    ) {
        self.orderId = orderId
        self.merchantCode = merchantCode
        self.password = password
        self.extraKey = extraKey
        self.mode = mode
    }

    public static func fromResponseData(_ data: [String: AnyCodable]?) -> TabbyInitData? {
        guard let data = data else { return nil }

        func stringValue(for keys: String...) -> String? {
            for key in keys {
                if let value = data[key]?.value {
                    if let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return string
                    }
                    if let int = value as? Int {
                        return String(int)
                    }
                    if let num = value as? NSNumber {
                        return num.stringValue
                    }
                }
            }
            return nil
        }

        guard let orderId = stringValue(for: "order_id", "orderId") else {
            return nil
        }
        guard let merchantCode = stringValue(for: "merchant_code", "merchantCode") else {
            return nil
        }
        guard let password = stringValue(for: "password") else {
            return nil
        }

        let extraKey = stringValue(for: "extra_key", "extraKey")
        let mode = stringValue(for: "mode")

        return TabbyInitData(
            orderId: orderId,
            merchantCode: merchantCode,
            password: password,
            extraKey: extraKey,
            mode: mode
        )
    }
}

public struct TabbySession {
    public let status: TabbySessionStatus
    public let sessionId: String
    public let paymentId: String
    public let webUrl: String?
    public let rejectionReason: String?

    public init(
        status: TabbySessionStatus,
        sessionId: String,
        paymentId: String,
        webUrl: String?,
        rejectionReason: String? = nil
    ) {
        self.status = status
        self.sessionId = sessionId
        self.paymentId = paymentId
        self.webUrl = webUrl
        self.rejectionReason = rejectionReason
    }
}

private struct TabbyCheckoutSessionResponse: Decodable {
    let id: String
    let status: TabbySessionStatus?
    let payment: TabbyPaymentReference?
    let configuration: TabbyCheckoutConfiguration?
}

private struct TabbyPaymentReference: Decodable {
    let id: String
}

private struct TabbyCheckoutConfiguration: Decodable {
    let availableProducts: TabbySessionAvailableProducts?
    let products: TabbyProducts?
}

private struct TabbyProducts: Decodable {
    let installments: TabbyInstallmentsProduct?
}

private struct TabbyInstallmentsProduct: Decodable {
    let rejectionReason: String?
}

public struct TabbySessionAvailableProducts: Decodable {
    public let installments: TabbyProduct?
}

public struct TabbyProduct: Decodable {
    public let type: String?
    public let webUrl: String
}

public extension PaymentRequest {
    func tabbySessionPayload(
        merchantCode: String,
        lang: String = "en"
    ) throws -> [String: Any] {
        guard !orderDetails.isEmpty else {
            throw PayOrcError.invalidConfiguration("Order details are required for Tabby checkout.")
        }

        let now = ISO8601DateFormatter().string(from: Date())

        let buyerPhone: String
        let trimmedCode = customerDetails.code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMobile = customerDetails.mobile.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCode.hasPrefix("+") {
            buyerPhone = "\(trimmedCode)\(trimmedMobile)"
        } else {
            buyerPhone = "+\(trimmedCode)\(trimmedMobile)"
        }

        let buyer: [String: Any] = [
            "email": customerDetails.email,
            "phone": buyerPhone,
            "name": customerDetails.name
        ]

        let buyerHistory: [String: Any] = [
            "loyalty_level": 0,
            "registered_since": now,
            "wishlist_count": 0
        ]

        let shippingAddress: [String: Any]? = {
            guard !shippingDetails.addressLine1.isEmpty ||
                  !shippingDetails.addressLine2.isEmpty ||
                  !shippingDetails.city.isEmpty ||
                  !shippingDetails.province.isEmpty ||
                  !shippingDetails.country.isEmpty ||
                  !shippingDetails.pin.isEmpty else {
                return nil
            }
            return [
                "address": shippingDetails.addressLine1,
                "city": shippingDetails.city,
                "zip": shippingDetails.pin
            ]
        }()

        let items: [[String: Any]] = orderDetails.map { order in
            let item: [String: Any] = [
                "title": order.description,
                "quantity": Int(order.quantity) ?? 1,
                "unit_price": order.amount,
                "category": "general",
                "description": order.description,
                "reference_id": order.mOrderId
            ]
            return item
        }

        let referenceId = orderDetails.first?.mOrderId ?? UUID().uuidString
        var orderPayload: [String: Any] = [
            "reference_id": referenceId,
            "items": items,
        ]

        if !shippingDetails.shippingAmount.isEmpty {
            orderPayload["shipping_amount"] = shippingDetails.shippingAmount
        }

        if !orderDetails.first!.description.isEmpty {
            orderPayload["description"] = orderDetails.first!.description
        }

        let payment: [String: Any] = [
            "amount": orderDetails.first!.amount,
            "currency": orderDetails.first!.currency,
            "buyer": buyer,
            "buyer_history": buyerHistory,
            "shipping_address": shippingAddress as Any,
            "order": orderPayload,
            "order_history": []
        ]

        let payload: [String: Any] = [
            "merchant_code": merchantCode,
            "lang": lang,
            "payment": payment
        ]

        return payload
    }
}

public enum TabbyEnvironment {
    case production
    case staging

    public var host: String {
        switch self {
        case .production:
            return "https://api.tabby.ai"
        case .staging:
            return "https://api.tabby.dev"
        }
    }
}

public final class TabbyAPI {
    private let apiKey: String
    private let environment: TabbyEnvironment
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(apiKey: String, environment: TabbyEnvironment) {
        self.apiKey = apiKey
        self.environment = environment
        self.session = .shared
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    public func createSession(paymentPayload: [String: Any]) async throws -> TabbySession {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PayOrcError.invalidConfiguration("Tabby API key is required.")
        }

        let urlString = "\(environment.host)/api/v2/checkout"
        guard let url = URL(string: urlString) else {
            throw PayOrcError.invalidConfiguration("Invalid Tabby URL: \(urlString)")
        }

        let bodyData = try JSONSerialization.data(withJSONObject: paymentPayload, options: [])

        #if DEBUG
        if let bodyStr = String(data: bodyData, encoding: .utf8) {
            print("[TabbyAPI] Request body: \(bodyStr)")
        }
        #endif

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // Matches getVersionHeader() in tabby_flutter_inapp_sdk/src/internal/headers.dart
        request.setValue("Flutter/1.10.0", forHTTPHeaderField: "X-SDK-Version")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PayOrcError.unexpectedResponse
        }

        #if DEBUG
        if let rawStr = String(data: data, encoding: .utf8) {
            print("[TabbyAPI] HTTP \(http.statusCode) — Raw response: \(rawStr.prefix(2000))")
        }
        #endif

        if !(200..<300).contains(http.statusCode) {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = body?["message"] as? String
                ?? body?["error"] as? String
                ?? body?["detail"] as? String
                ?? "Tabby API failure (HTTP \(http.statusCode))"
            let code = body?["code"] as? String ?? "\(http.statusCode)"
            #if DEBUG
            print("[TabbyAPI] \(http.statusCode) error body: \(String(data: data, encoding: .utf8) ?? "(empty)")")
            #endif
            throw PayOrcError.apiFailure(code: code, message: message)
        }

        // Parse via JSONSerialization — mirrors how Flutter's CheckoutSession.fromJson works.
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PayOrcError.decodingFailed("Tabby session: could not parse JSON response")
        }

        #if DEBUG
        print("[TabbyAPI] Parsed raw keys: \(Array(raw.keys).sorted())")
        #endif

        let sessionId = raw["id"] as? String ?? ""
        let rawStatus = raw["status"] as? String ?? ""
        // mirrors: SessionStatus.values.firstWhere((e) => e.name == json['status'], orElse: () => SessionStatus.created)
        let status    = TabbySessionStatus(rawValue: rawStatus) ?? .created

        // payment.id — mirrors: Identifiable.fromJson(json['payment'])
        let paymentDict = raw["payment"] as? [String: Any]
        let paymentId   = paymentDict?["id"] as? String ?? ""

        // configuration.available_products.installments — THIS IS AN ARRAY in Tabby's API.
        // mirrors: (json['installments'] as List<dynamic>).map((i) => ProductWebURL.fromJson(i)).toList()
        // We take the first item's web_url, same as Flutter: installmentsPlan = ...installments?.first
        let configuration  = raw["configuration"] as? [String: Any]
        let availableProds = configuration?["available_products"] as? [String: Any]
        let installmentsArr = availableProds?["installments"] as? [[String: Any]]
        let webUrl          = installmentsArr?.first?["web_url"] as? String

        // configuration.products.installments.rejection_reason
        // mirrors: InstallmentsProduct.fromJson(json['installments'])
        let products         = configuration?["products"] as? [String: Any]
        let prodInstallments = products?["installments"] as? [String: Any]
        let rejectionReason  = prodInstallments?["rejection_reason"] as? String

        #if DEBUG
        print("[TabbyAPI] Parsed session: id=\(sessionId) status=\(status) paymentId=\(paymentId) webUrl=\(webUrl ?? "nil") rejectionReason=\(rejectionReason ?? "nil")")
        #endif

        return TabbySession(
            status:          status,
            sessionId:       sessionId,
            paymentId:       paymentId,
            webUrl:          webUrl,
            rejectionReason: rejectionReason
        )
    }
}
