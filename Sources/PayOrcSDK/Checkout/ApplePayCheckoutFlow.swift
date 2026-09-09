import UIKit
import PassKit

// MARK: - ApplePayCheckoutFlow

/// Orchestrates the native Apple Pay checkout flow.
///
/// This is the Swift/PassKit equivalent of Flutter's `ApplePayButton` (from the
/// `pay` package) combined with `PaymentOptionsBloc._onSubmitApplePay`.
///
/// ## Flow (mirrors Flutter)
///
/// ```
/// 1. Resolve ApplePayConfiguration  — from checkout customization
/// 2. PKPaymentAuthorizationController — native Apple Pay sheet
/// 3. Decode PKPayment token          — into the wallet JSON shape
/// 4. POST sdk/wallet/payment         — PayOrc back-end (HMAC-signed)
/// 5. onAuthorized / onError          — callback to host app
/// ```
///
/// Do not instantiate directly — call ``PayOrc/showApplePayCheckout(from:request:onAuthorized:onError:)``.
public final class ApplePayCheckoutFlow: NSObject {

    // MARK: - Retained instances
    //
    // PKPaymentAuthorizationController does not strongly retain its delegate,
    // so the flow instance is kept alive here for its lifetime and released
    // once `paymentAuthorizationControllerDidFinish` fires.
    private static var retainedFlows: [ObjectIdentifier: ApplePayCheckoutFlow] = [:]

    private let request:            PaymentRequest
    private let paymentRepository:  PaymentRepository
    private let onAuthorized:       ((PayOrcSDKResult) -> Void)?
    private let onError:            ((PayOrcError) -> Void)?
    private var didReportResult     = false

    private init(
        request:           PaymentRequest,
        paymentRepository: PaymentRepository,
        onAuthorized:      ((PayOrcSDKResult) -> Void)?,
        onError:           ((PayOrcError) -> Void)?
    ) {
        self.request           = request
        self.paymentRepository = paymentRepository
        self.onAuthorized      = onAuthorized
        self.onError           = onError
    }

    // MARK: - Public API

    /// Resolves Apple Pay configuration and presents the native Apple Pay sheet.
    ///
    /// Reports ``PayOrcError/unsupported(feature:)`` via `onError` when Apple Pay
    /// isn't configured for this merchant or isn't available on this device.
    @MainActor
    public static func present(
        request:               PaymentRequest,
        paymentRepository:     PaymentRepository,
        checkoutCustomization: CheckoutCustomizationData?,
        fallbackCurrency:      String,
        onAuthorized:          ((PayOrcSDKResult) -> Void)? = nil,
        onError:               ((PayOrcError) -> Void)?      = nil
    ) {
        var currency = request.orderDetails.first?.currency.trimmingCharacters(in: .whitespaces) ?? ""
        if currency.isEmpty { currency = fallbackCurrency }

        let billingCountry = request.billingDetails.country.trimmingCharacters(in: .whitespaces)
        let countryCode = !billingCountry.isEmpty ? billingCountry.uppercased() : "AE"

        guard let config = ApplePayConfiguration.resolve(
            customization: checkoutCustomization,
            currencyCode:  currency,
            countryCode:   countryCode
        ) else {
            onError?(.unsupported(feature: "Apple Pay is not configured for this merchant."))
            return
        }

        guard PKPaymentAuthorizationController.canMakePayments(usingNetworks: config.supportedNetworks) else {
            onError?(.unsupported(feature: "Apple Pay is not available on this device."))
            return
        }

        let flow = ApplePayCheckoutFlow(
            request:           request,
            paymentRepository: paymentRepository,
            onAuthorized:      onAuthorized,
            onError:           onError
        )
        flow.start(config: config)
    }

    // MARK: - Private

    private func retain()  { Self.retainedFlows[ObjectIdentifier(self)] = self }
    private func release() { Self.retainedFlows[ObjectIdentifier(self)] = nil }

    private func start(config: ApplePayConfiguration) {
        retain()

        #if DEBUG
        print("[ApplePayFlow] 🍎 Configuration Resolved:")
        print("  Merchant ID: \(config.merchantIdentifier)")
        print("  Display Name: \(config.displayName)")
        print("  Supported Networks: \(config.supportedNetworks.map { $0.rawValue })")
        print("  Currency: \(config.currencyCode)")
        print("  Country: \(config.countryCode)")
        #endif

        let paymentRequest = PKPaymentRequest()
        paymentRequest.merchantIdentifier   = config.merchantIdentifier
        paymentRequest.supportedNetworks     = config.supportedNetworks
        paymentRequest.merchantCapabilities = config.merchantCapabilities
        paymentRequest.countryCode           = config.countryCode
        paymentRequest.currencyCode          = config.currencyCode
        paymentRequest.paymentSummaryItems   = [
            PKPaymentSummaryItem(label: config.displayName, amount: Self.totalAmount(for: request))
        ]

        let controller = PKPaymentAuthorizationController(paymentRequest: paymentRequest)
        controller.delegate = self
        controller.present { [weak self] presented in
            guard let self, !presented else { return }
            self.reportError(.unsupported(feature: "Could not present the Apple Pay sheet."))
            self.release()
        }
    }

    private static func totalAmount(for request: PaymentRequest) -> NSDecimalNumber {
        var total: Decimal = 0
        for order in request.orderDetails {
            let cleaned = order.amount.filter { $0.isNumber || $0 == "." }
            total += Decimal(string: cleaned) ?? 0
        }
        return NSDecimalNumber(decimal: total)
    }

    private func reportError(_ error: PayOrcError) {
        #if DEBUG
        print("[ApplePayFlow] ❌ \(error) — \(error.localizedDescription)")
        #endif
        onError?(error)
    }
}

// MARK: - PKPaymentAuthorizationControllerDelegate

extension ApplePayCheckoutFlow: PKPaymentAuthorizationControllerDelegate {

    public func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        Task {
            do {
                // MARK: - Step 1: Validate and log token data
                let tokenData = payment.token.paymentData
                let dataSize = tokenData.count
                
                #if DEBUG
                print("[ApplePayFlow] 🔑 Token Data Validation:")
                print("  Data Size: \(dataSize) bytes")
                if dataSize > 0 {
                    let hexPreview = tokenData.prefix(50).map { String(format: "%02x", $0) }.joined(separator: " ")
                    print("  Hex Preview (first 50 bytes): \(hexPreview)")
                } else {
                    print("  ⚠️  WARNING: Token data is EMPTY!")
                }
                #endif
                
                // Validate token data is not empty
                guard dataSize > 0 else {
                    throw PayOrcError.requestFailed(
                        underlying: NSError(
                            domain: "ApplePayFlow",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Apple Pay token data is empty. This may indicate a simulator configuration issue or payment method problem."]
                        )
                    )
                }
                
                // MARK: - Step 2: Parse token data
                let decoded = try JSONSerialization.jsonObject(with: tokenData)
                let paymentData = decoded as? [String: Any] ?? [:]
                
                #if DEBUG
                print("[ApplePayFlow] ✅ Token parsed successfully")
                print("  Payment Data Keys: \(Array(paymentData.keys).sorted())")
                #endif

                let wallet = WalletPaymentResult(
                    paymentData:               paymentData,
                    paymentMethodDisplayName:  payment.token.paymentMethod.displayName ?? "",
                    paymentMethodNetwork:      payment.token.paymentMethod.network?.rawValue ?? "",
                    paymentMethodType:         Int(payment.token.paymentMethod.type.rawValue),
                    transactionIdentifier:     payment.token.transactionIdentifier
                )

                #if DEBUG
                print("[ApplePayFlow] 📤 Submitting wallet payment to backend...")
                #endif
                
                let body = try WalletPaymentRequest.json(request: request, wallet: wallet, walletType: "APPLE_PAY")
                let response = try await paymentRepository.submitWalletPayment(body: body)
                
                #if DEBUG
                print("[ApplePayFlow] 📥 Backend response: status=\(response.status), code=\(response.code)")
                #endif

                // Mirrors the Flutter SDK's fix: a 200 response can still carry a
                // business-level failure (e.g. card declined). Previously this was
                // always reported as authorized — now the full backend failure
                // (code + message) is delivered via `onError` instead.
                if response.status.lowercased() == "failed" {
                    let payOrcError = PayOrcError.paymentFailed(code: response.code, message: response.message)
                    didReportResult = true
                    completion(PKPaymentAuthorizationResult(status: .failure, errors: [payOrcError]))
                    await MainActor.run { reportError(payOrcError) }
                    return
                }

                didReportResult = true
                completion(PKPaymentAuthorizationResult(status: .success, errors: nil))

                let result = PayOrcSDKResult(
                    status:        response.status,
                    code:          response.code,
                    message:       response.message,
                    transactionId: payment.token.transactionIdentifier
                )
                await MainActor.run { onAuthorized?(result) }
            } catch let payOrcError as PayOrcError {
                didReportResult = true
                completion(PKPaymentAuthorizationResult(status: .failure, errors: [payOrcError]))
                await MainActor.run { reportError(payOrcError) }
            } catch {
                didReportResult = true
                completion(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
                await MainActor.run { reportError(.requestFailed(underlying: error)) }
            }
        }
    }

    public func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss { [weak self] in
            guard let self else { return }
            if !self.didReportResult {
                self.reportError(.apiFailure(code: "CANCELLED", message: "Apple Pay was cancelled by the user."))
            }
            self.release()
        }
    }
}
