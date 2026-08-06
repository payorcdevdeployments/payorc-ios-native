import Foundation
import Combine

// MARK: - CheckoutViewModel

/// View model for the PayOrc card checkout flow.
///
/// Coordinates card validation, payment submission, and
/// checkout customization state. Publishes state changes via Combine.
@MainActor
public final class CheckoutViewModel: ObservableObject {

    // MARK: Published State

    /// `true` while a network request is in-flight.
    @Published public private(set) var isLoading: Bool = false

    /// The last error produced by a validation or API call. `nil` when no error.
    @Published public private(set) var error: PayOrcError?

    /// The most recently fetched checkout customization (may be nil during first load).
    @Published public private(set) var customization: CheckoutCustomizationData?

    // MARK: Dependencies

    public let paymentRequest:     PaymentRequest
    private let paymentRepository: PaymentRepository
    private let validator:         CardValidator

    private var cancellables = Set<AnyCancellable>()

    // MARK: Init

    public init(
        paymentRequest:    PaymentRequest,
        paymentRepository: PaymentRepository,
        validator:         CardValidator = CardValidator()
    ) {
        self.paymentRequest    = paymentRequest
        self.paymentRepository = paymentRepository
        self.validator         = validator

        // Mirror the SDK's current customization immediately
        self.customization = PayOrc.shared?.checkoutCustomization

        // Re-apply whenever the SDK posts a customization update
        NotificationCenter.default
            .publisher(for: PayOrc.checkoutCustomizationDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.customization = notification.object as? CheckoutCustomizationData
            }
            .store(in: &cancellables)
    }

    // MARK: - Validation

    /// Validates all card fields and returns a ``PayOrcError`` on the first failure,
    /// or `nil` when all fields are valid.
    public func validate(card: CardData) -> PayOrcError? {
        let cardNum = card.cardNumber ?? ""

        if !validator.validateCardNumber(cardNum).isValid { return .invalidCardNumber }
        if !validator.validateExpiry(month: card.expiryMonth, year: card.expiryYear).isValid {
            return .invalidExpiryDate
        }
        if !validator.validateCVV(card.cvv, cardNumber: cardNum).isValid { return .invalidCVV }
        if !validator.validateEmail(card.email ?? "").isValid             { return .invalidEmail }
        if !validator.validateMobile(card.mobile ?? "").isValid           { return .invalidMobile }

        return nil
    }

    // MARK: - Submit Payment

    /// Validates the card and submits the payment.
    ///
    /// On success, calls `onSuccess` with the ``PayOrcSDKResult``.
    /// On failure, sets ``error`` and calls `onFailure`.
    ///
    /// All callbacks are dispatched on the main queue.
    public func submit(
        card:      CardData,
        onSuccess: @escaping (PaymentResponse) -> Void,
        onFailure: @escaping (PayOrcError)     -> Void
    ) {
        // 1. Validate
        if let validationError = validate(card: card) {
            error = validationError
            onFailure(validationError)
            return
        }

        // 2. Submit
        error     = nil
        isLoading = true

        Task {
            defer { isLoading = false }

            do {
                let response = try await paymentRepository.submitPayment(
                    request: paymentRequest,
                    card:    card
                )
                onSuccess(response)
            } catch let payOrcError as PayOrcError {

            } catch let payOrcError as PayOrcError {
                error = payOrcError
                onFailure(payOrcError)
            } catch {
                let wrapped = PayOrcError.requestFailed(underlying: error)
                self.error = wrapped
                onFailure(wrapped)
            }
        }
    }

    // MARK: - Clear Error

    /// Clears the current error state (e.g. when the user corrects a field).
    public func clearError() {
        error = nil
    }
}
