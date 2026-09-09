import Foundation

public struct CustomerDetails: Codable, Equatable {
    public let mCustomerId: String
    public let name: String
    public let email: String
    public let mobile: String
    public let code: String

    public init(mCustomerId: String, name: String, email: String, mobile: String, code: String) {
        self.mCustomerId = mCustomerId
        self.name = name
        self.email = email
        self.mobile = mobile
        self.code = code
    }
}

public struct BillingDetails: Codable, Equatable {
    public let addressLine1: String
    public let addressLine2: String
    public let city: String
    public let province: String
    public let country: String
    public let pin: String

    public init(addressLine1: String, addressLine2: String = "", city: String = "", province: String = "", country: String, pin: String = "") {
        self.addressLine1 = addressLine1
        self.addressLine2 = addressLine2
        self.city = city
        self.province = province
        self.country = country
        self.pin = pin
    }
}

public struct ShippingDetails: Codable, Equatable {
    public let shippingName: String
    public let shippingEmail: String
    public let shippingCode: String
    public let shippingMobile: String
    public let addressLine1: String
    public let addressLine2: String
    public let city: String
    public let province: String
    public let country: String
    public let pin: String
    public let shippingCurrency: String
    public let shippingAmount: String

    public init(shippingName: String = "", shippingEmail: String = "", shippingCode: String = "", shippingMobile: String = "", addressLine1: String = "", addressLine2: String = "", city: String = "", province: String = "", country: String = "", pin: String = "", shippingCurrency: String = "", shippingAmount: String = "") {
        self.shippingName = shippingName
        self.shippingEmail = shippingEmail
        self.shippingCode = shippingCode
        self.shippingMobile = shippingMobile
        self.addressLine1 = addressLine1
        self.addressLine2 = addressLine2
        self.city = city
        self.province = province
        self.country = country
        self.pin = pin
        self.shippingCurrency = shippingCurrency
        self.shippingAmount = shippingAmount
    }
}

public struct OrderDetails: Codable, Equatable {
    public let mOrderId: String
    public let amount: String
    public let convenienceFee: String
    public let quantity: String
    public let currency: String
    public let description: String

    public init(mOrderId: String = "", amount: String, convenienceFee: String = "", quantity: String = "", currency: String, description: String = "") {
        self.mOrderId = mOrderId
        self.amount = amount
        self.convenienceFee = convenienceFee
        self.quantity = quantity
        self.currency = currency
        self.description = description
    }
}

public struct Urls: Codable, Equatable {
    public let webhookUrl: String

    public init(webhookUrl: String) {
        self.webhookUrl = webhookUrl
    }
}

public struct PaymentRequest: Codable, Equatable {
    public let paymentToken: String?
    public let orderDetails: [OrderDetails]
    public let customerDetails: CustomerDetails
    public let billingDetails: BillingDetails
    public let shippingDetails: ShippingDetails
    public let urls: Urls?
    public let parameters: [[String: String]]
    public let customData: [[String: String]]

    public init(paymentToken: String? = nil, orderDetails: [OrderDetails], customerDetails: CustomerDetails, billingDetails: BillingDetails, shippingDetails: ShippingDetails = ShippingDetails(), urls: Urls? = nil, parameters: [[String: String]] = [], customData: [[String: String]] = []) {
        self.paymentToken = paymentToken
        self.orderDetails = orderDetails
        self.customerDetails = customerDetails
        self.billingDetails = billingDetails
        self.shippingDetails = shippingDetails
        self.urls = urls
        self.parameters = parameters
        self.customData = customData
    }

    /// Builds the card-payment JSON body in Flutter's exact insertion-order, with no
    /// forward-slash escaping — byte-for-byte matching Dart's `jsonEncode(toJson(card))`.
    ///
    /// Mirrors `PaymentRequest.toJson(CardData card)` in payment_request.dart.
    public func payloadData(for card: CardData) throws -> Data {
        guard let order = orderDetails.first else {
            throw PayOrcError.invalidConfiguration("Order details are required.")
        }

        let s = OrderedJSON.string   // shorthand
        let o = OrderedJSON.object

        // customer_details — Flutter insertion order: m_customer_id, name, email, mobile, code
        let customerJson = o([
            ("m_customer_id", s(customerDetails.mCustomerId)),
            ("name",          s(customerDetails.name)),
            ("email",         s(card.email ?? customerDetails.email)),
            ("mobile",        s(card.mobile ?? customerDetails.mobile)),
            ("code",          s(card.countryCode ?? customerDetails.code)),
        ])

        // billing_details — Flutter insertion order: address_line1…pin
        let billingJson = o([
            ("address_line1", s(billingDetails.addressLine1)),
            ("address_line2", s(billingDetails.addressLine2)),
            ("city",          s(billingDetails.city)),
            ("province",      s(billingDetails.province)),
            ("country",       s(billingDetails.country)),
            ("pin",           s(billingDetails.pin)),
        ])

        // order_details — Flutter insertion order: m_order_id, amount, currency, convenience_fee, description
        let conv = order.convenienceFee.trimmingCharacters(in: .whitespaces)
        let orderJson = o([
            ("m_order_id",      s(order.mOrderId)),
            ("amount",          s(order.amount)),
            ("currency",        s(order.currency)),
            ("convenience_fee", s(conv)),
            ("description",     s(order.description)),
        ])

        // card_details — mirrors Flutter's _cardDetailsJson(...), which omits any
        // field that's empty (e.g. saved-card/token retries with no PAN or expiry)
        // rather than sending an empty string.
        // Flutter normalises 2-digit year: yearRaw.length == 2 ? '20$yearRaw' : yearRaw
        let month = card.expiryMonth.trimmingCharacters(in: .whitespaces)
        let rawYear = card.expiryYear.trimmingCharacters(in: .whitespaces)
        let normalizedYear = rawYear.count == 2 ? "20\(rawYear)" : rawYear
        let expiry: String
        if month.isEmpty && normalizedYear.isEmpty {
            expiry = ""
        } else if month.isEmpty {
            expiry = normalizedYear
        } else if normalizedYear.isEmpty {
            expiry = month
        } else {
            expiry = "\(month)/\(normalizedYear)"
        }
        let pan = (card.cardNumber ?? "").replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespaces)
        let cvv = card.cvv.trimmingCharacters(in: .whitespaces)
        let holder = card.cardholderName.trimmingCharacters(in: .whitespaces)
        let resolvedToken = ((card.paymentToken ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            ? (paymentToken ?? "") : (card.paymentToken ?? "")).trimmingCharacters(in: .whitespaces)
        var cardPairs: [(key: String, value: String)] = []
        if !holder.isEmpty { cardPairs.append(("card_holder_name", s(holder))) }
        if !pan.isEmpty { cardPairs.append(("card_number", s(pan))) }
        if !cvv.isEmpty { cardPairs.append(("cvv", s(cvv))) }
        if !expiry.isEmpty { cardPairs.append(("expiry", s(expiry))) }
        if !resolvedToken.isEmpty { cardPairs.append(("payment_token", s(resolvedToken))) }
        let cardJson = o(cardPairs)

        // data object — Flutter insertion order:
        // action, class, capture_method, type,
        // customer_details, billing_details, order_details, card_details,
        // [shipping_details], [urls], parameters, custom_data
        var dataPairs: [(key: String, value: String)] = [
            ("action",           s("AUTH")),
            ("class",            s("ECOM")),
            ("capture_method",   s("MANUAL")),
            ("type",             s("CARD")),
            ("customer_details", customerJson),
            ("billing_details",  billingJson),
            ("order_details",    orderJson),
            ("card_details",     cardJson),
        ]

        // shipping_details — mirrors Flutter: `if (_shippingDetailsJson().isNotEmpty)`
        let sd = shippingDetails
        let hasShipping = [sd.shippingName, sd.shippingEmail, sd.shippingCode, sd.shippingMobile,
                           sd.addressLine1, sd.addressLine2, sd.city, sd.province,
                           sd.country, sd.pin, sd.shippingCurrency, sd.shippingAmount
                          ].contains(where: { !$0.isEmpty })
        if hasShipping {
            let shippingJson = o([
                ("shipping_name",     s(sd.shippingName)),
                ("shipping_email",    s(sd.shippingEmail)),
                ("shipping_code",     s(sd.shippingCode)),
                ("shipping_mobile",   s(sd.shippingMobile)),
                ("address_line1",     s(sd.addressLine1)),
                ("address_line2",     s(sd.addressLine2)),
                ("city",              s(sd.city)),
                ("province",          s(sd.province)),
                ("country",           s(sd.country)),
                ("pin",               s(sd.pin)),
                ("shipping_currency", s(sd.shippingCurrency)),
                ("shipping_amount",   s(sd.shippingAmount)),
            ])
            dataPairs.append(("shipping_details", shippingJson))
        }

        // urls — mirrors Flutter: `if (urls != null && urls!.webhookUrl.trim().isNotEmpty)`
        if let webhookUrl = urls?.webhookUrl.trimmingCharacters(in: .whitespaces), !webhookUrl.isEmpty {
            dataPairs.append(("urls", o([("webhook_url", s(webhookUrl))])))
        }

        dataPairs.append(("parameters",  OrderedJSON.array(parameters)))
        dataPairs.append(("custom_data", OrderedJSON.array(customData)))

        let jsonString = o([("data", o(dataPairs))])

        guard let data = jsonString.data(using: .utf8) else {
            throw PayOrcError.invalidConfiguration("Could not encode payment payload as UTF-8.")
        }
        return data
    }

    /// Builds the Tabby-init JSON body in Flutter's exact insertion-order.
    /// Mirrors `PaymentRequest.toTabbyInitJson()` in payment_request.dart.
    public func tabbyInitPayload() throws -> [String: Any] {
        guard let order = orderDetails.first else {
            throw PayOrcError.invalidConfiguration("Order details are required for Tabby init.")
        }

        let convenienceFee = order.convenienceFee.trimmingCharacters(in: .whitespaces)
        var orderDetailsPayload: [String: Any] = [
            "m_order_id": order.mOrderId,
            "amount": order.amount,
            "currency": order.currency,
            "convenience_fee": convenienceFee,
            "description": order.description
        ]
        if !order.quantity.trimmingCharacters(in: .whitespaces).isEmpty {
            orderDetailsPayload["quantity"] = order.quantity
        }

        var dataPayload: [String: Any] = [
            "action": "AUTH",
            "class": "ECOM",
            "capture_method": "MANUAL",
            "type": "TABBY",
            "customer_details": [
                "m_customer_id": customerDetails.mCustomerId,
                "name": customerDetails.name,
                "email": customerDetails.email,
                "mobile": customerDetails.mobile,
                "code": customerDetails.code
            ],
            "billing_details": [
                "address_line1": billingDetails.addressLine1,
                "address_line2": billingDetails.addressLine2,
                "city": billingDetails.city,
                "province": billingDetails.province,
                "country": billingDetails.country,
                "pin": billingDetails.pin
            ],
            "order_details": orderDetailsPayload,
            "parameters": parameters,
            "custom_data": customData
        ]

        if !shippingDetails.addressLine1.isEmpty ||
            !shippingDetails.addressLine2.isEmpty ||
            !shippingDetails.city.isEmpty ||
            !shippingDetails.province.isEmpty ||
            !shippingDetails.country.isEmpty ||
            !shippingDetails.pin.isEmpty {
            dataPayload["shipping_details"] = [
                "shipping_name": shippingDetails.shippingName,
                "shipping_email": shippingDetails.shippingEmail,
                "shipping_code": shippingDetails.shippingCode,
                "shipping_mobile": shippingDetails.shippingMobile,
                "address_line1": shippingDetails.addressLine1,
                "address_line2": shippingDetails.addressLine2,
                "city": shippingDetails.city,
                "province": shippingDetails.province,
                "country": shippingDetails.country,
                "pin": shippingDetails.pin,
                "shipping_currency": shippingDetails.shippingCurrency,
                "shipping_amount": shippingDetails.shippingAmount
            ]
        }

        if let urls = urls, !urls.webhookUrl.trimmingCharacters(in: .whitespaces).isEmpty {
            dataPayload["urls"] = ["webhook_url": urls.webhookUrl.trimmingCharacters(in: .whitespaces)]
        }

        return ["data": dataPayload]
    }

    /// Builds the JSON body bytes for `POST sdk/add-card` — tokenises/verifies `card`
    /// without charging it. Mirrors `AddCardRequest.fromModels` in
    /// add_card_request.dart.
    ///
    /// Built with ``OrderedJSON`` (byte-exact Flutter insertion order, no `\/`
    /// escaping) rather than a `[String: Any]` dictionary — same reasoning as
    /// ``payloadData(for:)``: `sdk/add-card` shares `sdk/payment`'s order-sensitive
    /// signature validation, so `JSONSerialization`'s `.sortedKeys` output (used for
    /// the SDK's other dict-bodied endpoints) fails with `E0021 Invalid request
    /// signature`.
    public func addCardPayloadData(for card: CardData) throws -> Data {
        let s = OrderedJSON.string
        let o = OrderedJSON.object

        let order = orderDetails.first

        let customerJson = o([
            ("m_customer_id", s(customerDetails.mCustomerId)),
            ("name",          s(customerDetails.name)),
            ("email",         s(card.email ?? customerDetails.email)),
            ("mobile",        s(card.mobile ?? customerDetails.mobile)),
            ("code",          s((card.countryCode ?? customerDetails.code)
                                    .replacingOccurrences(of: "+", with: "")
                                    .trimmingCharacters(in: .whitespaces))),
        ])

        let billingJson = o([
            ("address_line1", s(billingDetails.addressLine1)),
            ("address_line2", s(billingDetails.addressLine2)),
            ("city",          s(billingDetails.city)),
            ("province",      s(billingDetails.province)),
            ("country",       s(billingDetails.country)),
            ("pin",           s(billingDetails.pin)),
        ])

        let orderJson = o([
            ("m_order_id",      s(order?.mOrderId ?? "")),
            ("currency",        s(order?.currency ?? "")),
            ("description",     s(order?.description ?? "")),
            ("amount",          s(order?.amount ?? "")),
            ("convenience_fee", s("")),
        ])

        let rawYear = card.expiryYear.trimmingCharacters(in: .whitespaces)
        let expiryYear = rawYear.count == 2 ? "20\(rawYear)" : rawYear
        let expiry = "\(card.expiryMonth.trimmingCharacters(in: .whitespaces))/\(expiryYear)"
        let pan = (card.cardNumber ?? "").replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespaces)
        let cardJson = o([
            ("payment_token",    s(card.paymentToken ?? "")),
            ("card_holder_name", s(card.cardholderName)),
            ("card_number",      s(pan)),
            ("cvv",              s(card.cvv)),
            ("expiry",           s(expiry)),
        ])

        let sd = shippingDetails
        let shippingJson = o([
            ("shipping_name",     s(sd.shippingName)),
            ("shipping_email",    s(sd.shippingEmail)),
            ("shipping_code",     s(sd.shippingCode)),
            ("shipping_mobile",   s(sd.shippingMobile)),
            ("address_line1",     s(sd.addressLine1)),
            ("address_line2",     s(sd.addressLine2)),
            ("city",              s(sd.city)),
            ("province",          s(sd.province)),
            ("country",           s(sd.country)),
            ("pin",               s(sd.pin)),
            ("shipping_currency", s(sd.shippingCurrency)),
            ("shipping_amount",   s(sd.shippingAmount)),
        ])

        var dataPairs: [(key: String, value: String)] = [
            ("action",           s("AUTH_REVERSAL")),
            ("class",            s("ECOM")),
            ("capture_method",   s("MANUAL")),
            ("type",             s("CARD")),
            ("customer_details", customerJson),
            ("billing_details",  billingJson),
            ("order_details",    orderJson),
            ("card_details",     cardJson),
            ("shipping_details", shippingJson),
        ]

        if let webhookUrl = urls?.webhookUrl.trimmingCharacters(in: .whitespaces), !webhookUrl.isEmpty {
            dataPairs.append(("urls", o([("webhook_url", s(webhookUrl))])))
        }

        dataPairs.append(("parameters",  OrderedJSON.array(parameters)))
        dataPairs.append(("custom_data", OrderedJSON.array(customData)))

        let jsonString = o([("data", o(dataPairs))])

        guard let data = jsonString.data(using: .utf8) else {
            throw PayOrcError.invalidConfiguration("Could not encode add-card payload as UTF-8.")
        }
        return data
    }
}

public struct CardData: Codable, Equatable {
    public let cardNumber: String?
    public let cardholderName: String
    public let expiryMonth: String
    public let expiryYear: String
    public let cvv: String
    public let email: String?
    public let countryCode: String?
    public let mobile: String?
    public let paymentToken: String?

    /// Card scheme (e.g. "VISA", "MASTERCARD") as returned by `sdk/customer/cards`.
    /// Populated for saved cards, where `cardNumber` holds only the last 4 digits.
    public let cardNetwork: String?

    public init(cardNumber: String? = nil, cardholderName: String, expiryMonth: String, expiryYear: String, cvv: String, email: String? = nil, countryCode: String? = nil, mobile: String? = nil, paymentToken: String? = nil, cardNetwork: String? = nil) {
        self.cardNumber = cardNumber
        self.cardholderName = cardholderName
        self.expiryMonth = expiryMonth
        self.expiryYear = expiryYear
        self.cvv = cvv
        self.email = email
        self.countryCode = countryCode
        self.mobile = mobile
        self.paymentToken = paymentToken
        self.cardNetwork = cardNetwork
    }
}

extension CardData {
    /// Last 4 digits, however `cardNumber` is currently populated (full PAN or,
    /// for saved cards, the last-4-only value already returned by the API).
    public var lastFourDigits: String {
        let digits = (cardNumber ?? "").filter(\.isNumber)
        return digits.count >= 4 ? String(digits.suffix(4)) : digits
    }

    /// Parses one saved-card row from `POST sdk/customer/cards` (`data[]` entries).
    /// Mirrors Flutter's `CardData.fromSDK`.
    public static func fromSDK(_ json: [String: Any]) -> CardData {
        let expiryDate = (json["expiry_date"] as? String) ?? ""
        let parts = expiryDate.split(separator: "/", maxSplits: 1).map(String.init)
        let expiryMonth = parts.first ?? ""
        let expiryYear = (parts.count > 1 && parts[1].count >= 2) ? String(parts[1].suffix(2)) : ""

        return CardData(
            cardNumber: (json["last_4_digit"] as? String) ?? "",
            cardholderName: (json["name"] as? String) ?? "",
            expiryMonth: expiryMonth,
            expiryYear: expiryYear,
            cvv: "",
            paymentToken: (json["payment_token"] as? String) ?? "",
            cardNetwork: (json["card_network"] as? String) ?? ""
        )
    }
}

public struct PaymentResponse: Codable {
    public let status: String
    public let code: String
    public let message: String
    public let data: [String: AnyCodable]?

    public init(status: String, code: String, message: String, data: [String: AnyCodable]? = nil) {
        self.status = status
        self.code = code
        self.message = message
        self.data = data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status  = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? ""
        code    = (try? container.decodeIfPresent(String.self, forKey: .code)) ?? ""
        message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""

        if container.contains(.data) {
            if let dict = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .data) {
                data = dict
            } else {
                data = nil
                #if DEBUG
                print("[PayOrc] PaymentResponse.data was present but not a JSON object — stored as nil.")
                #endif
            }
        } else {
            data = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status,  forKey: .status)
        try container.encode(code,    forKey: .code)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(data, forKey: .data)
    }

    enum CodingKeys: String, CodingKey {
        case status, code, message, data
    }
}

extension PaymentResponse {
    public var redirectUrl: String? {
        if let dict = data {
            return dict["redirect_url"]?.value as? String
        }
        return nil
    }

    public var orderStatus: String? {
        if let dict = data {
            return (dict["status"]?.value as? String) ?? (dict["order_status"]?.value as? String)
        }
        return nil
    }

    public var isAwait3DS: Bool {
        let status = orderStatus?.uppercased() ?? ""
        return status == "AWAIT_3DS" || (redirectUrl?.isEmpty == false)
    }

    public var transactionId: String? {
        if let dict = data {
            return (dict["transaction_id"]?.value as? String) ?? (dict["p_order_id"]?.value as? String)
        }
        return nil
    }

    /// The PayOrc-assigned order id, when present — usually populated even when the
    /// merchant's own `m_order_id` (in the request) was left blank.
    public var pOrderId: String? {
        if let dict = data {
            return dict["p_order_id"]?.value as? String
        }
        return nil
    }

    /// Echoes the merchant's own `m_order_id`, when the response includes it.
    public var mOrderId: String? {
        if let dict = data {
            return dict["m_order_id"]?.value as? String
        }
        return nil
    }
}


public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let object = try? container.decode([String: AnyCodable].self) {
            value = object.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let value as String:
            try container.encode(value)
        case let value as Bool:
            try container.encode(value)
        case let value as Int:
            try container.encode(value)
        case let value as Double:
            try container.encode(value)
        case let value as [Any]:
            try container.encode(value.map { AnyCodable($0) })
        case let value as [String: Any]:
            try container.encode(value.mapValues { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            try container.encodeNil()
        }
    }
}
