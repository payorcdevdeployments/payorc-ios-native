import Foundation

// MARK: - WalletPaymentResult

/// A decoded wallet (Apple Pay) payment token — the Swift equivalent of Flutter's
/// `WalletPaymentResult`.
///
/// `paymentData` is the JSON object obtained by parsing `PKPaymentToken.paymentData`
/// as UTF-8 JSON (keys: `version`, `data`, `signature`, `header`) — this is the same
/// shape Flutter's `Token.toJson()` round-trips back out to the wire.
public struct WalletPaymentResult {
    public let paymentData: [String: Any]
    public let paymentMethodDisplayName: String
    public let paymentMethodNetwork: String
    public let paymentMethodType: Int
    public let transactionIdentifier: String

    public init(
        paymentData: [String: Any],
        paymentMethodDisplayName: String,
        paymentMethodNetwork: String,
        paymentMethodType: Int,
        transactionIdentifier: String
    ) {
        self.paymentData = paymentData
        self.paymentMethodDisplayName = paymentMethodDisplayName
        self.paymentMethodNetwork = paymentMethodNetwork
        self.paymentMethodType = paymentMethodType
        self.transactionIdentifier = transactionIdentifier
    }
}

// MARK: - WalletPaymentRequest

/// Builds the `POST sdk/wallet/payment` body for wallet (Apple Pay) payments —
/// mirrors Flutter's `WalletPaymentRequest.toJson(request:wallet:walletType:)`.
public enum WalletPaymentRequest {

    public static func json(
        request: PaymentRequest,
        wallet: WalletPaymentResult,
        walletType: String = "APPLE_PAY"
    ) throws -> [String: Any] {
        guard let order = request.orderDetails.first else {
            throw PayOrcError.invalidConfiguration("Order details are required.")
        }

        let customerDetailsPayload: [String: String] = [
            "m_customer_id": request.customerDetails.mCustomerId,
            "name": request.customerDetails.name,
            "email": request.customerDetails.email,
            "mobile": request.customerDetails.mobile,
            "code": request.customerDetails.code
        ]

        let billingDetailsPayload: [String: String] = [
            "address_line1": request.billingDetails.addressLine1,
            "address_line2": request.billingDetails.addressLine2,
            "city": request.billingDetails.city,
            "province": request.billingDetails.province,
            "country": request.billingDetails.country,
            "pin": request.billingDetails.pin
        ]

        let convenienceFee = order.convenienceFee.trimmingCharacters(in: .whitespaces)
        let orderDetailsPayload: [String: String] = [
            "m_order_id": order.mOrderId,
            "amount": order.amount,
            "currency": order.currency,
            "convenience_fee": convenienceFee,
            "description": order.description
        ]

        let tokenPayload: [String: Any] = [
            "paymentData": wallet.paymentData,
            "paymentMethod": [
                "displayName": wallet.paymentMethodDisplayName,
                "network": wallet.paymentMethodNetwork,
                "type": wallet.paymentMethodType
            ],
            "transactionIdentifier": wallet.transactionIdentifier
        ]

        var dataPayload: [String: Any] = [
            "action": "AUTH",
            "class": "ECOM",
            "capture_method": "MANUAL",
            "type": walletType,
            "customer_details": customerDetailsPayload,
            "billing_details": billingDetailsPayload,
            "order_details": orderDetailsPayload,
            "token": tokenPayload,
            "parameters": request.parameters,
            "custom_data": request.customData
        ]

        let shippingPayload: [String: String] = [
            "shipping_name": request.shippingDetails.shippingName,
            "shipping_email": request.shippingDetails.shippingEmail,
            "shipping_code": request.shippingDetails.shippingCode,
            "shipping_mobile": request.shippingDetails.shippingMobile,
            "address_line1": request.shippingDetails.addressLine1,
            "address_line2": request.shippingDetails.addressLine2,
            "city": request.shippingDetails.city,
            "province": request.shippingDetails.province,
            "country": request.shippingDetails.country,
            "pin": request.shippingDetails.pin,
            "shipping_currency": request.shippingDetails.shippingCurrency,
            "shipping_amount": request.shippingDetails.shippingAmount
        ]
        if shippingPayload.values.contains(where: { !$0.isEmpty }) {
            dataPayload["shipping_details"] = shippingPayload
        }

        if let urls = request.urls, !urls.webhookUrl.trimmingCharacters(in: .whitespaces).isEmpty {
            dataPayload["urls"] = ["webhook_url": urls.webhookUrl]
        }

        return ["data": dataPayload]
    }
}
