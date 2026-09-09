import Foundation

// MARK: - PayOrcCardFieldError

/// Error message overrides for a single add-card form field.
///
/// Keep a field `nil` to use the SDK default message for that validator.
/// Mirrors Flutter's `CardFormError`.
public struct PayOrcCardFieldError {

    /// Message shown when the field is left empty.
    public var required: String?

    /// Message shown when the field is filled but fails validation.
    public var invalid: String?

    public init(required: String? = nil, invalid: String? = nil) {
        self.required = required
        self.invalid = invalid
    }
}

// MARK: - PayOrcCardFormValidationCustomization

/// Host overrides for add-card form validation error messages.
///
/// Pass to ``PayOrcSDKCustomization/cardFormValidation``. Each field maps to one of
/// ``CheckoutViewModel/validate(card:)``'s failure cases; `invalid` is the message
/// used since the iOS validator does not currently distinguish "empty" from
/// "malformed" per field (`required` is accepted for shape parity with Flutter and
/// reserved for that distinction).
///
/// Mirrors Flutter's `PayorcSdkCardFormValidationCustomization`.
public struct PayOrcCardFormValidationCustomization {

    /// Reserved: the iOS card form does not currently validate cardholder name.
    public var cardHolderNameError: PayOrcCardFieldError?

    /// Overrides ``PayOrcError/invalidCardNumber``'s message.
    public var cardNumberError: PayOrcCardFieldError?

    /// Overrides ``PayOrcError/invalidExpiryDate``'s message (used for both month and year).
    public var expiryMonthError: PayOrcCardFieldError?

    /// Falls back to when ``expiryMonthError`` is unset — mirrors Flutter's separate
    /// month/year fields; the iOS form validates both together.
    public var expiryYearError: PayOrcCardFieldError?

    /// Overrides ``PayOrcError/invalidCVV``'s message.
    public var cvvError: PayOrcCardFieldError?

    /// Overrides a general "unsupported card" message, when the SDK adds card-scheme
    /// gating. Reserved for forward compatibility.
    public var invalidCardError: PayOrcCardFieldError?

    /// Overrides ``PayOrcError/invalidEmail``'s message.
    public var emailError: PayOrcCardFieldError?

    /// Overrides ``PayOrcError/invalidMobile``'s message.
    public var mobileError: PayOrcCardFieldError?

    public init(
        cardHolderNameError: PayOrcCardFieldError? = nil,
        cardNumberError: PayOrcCardFieldError? = nil,
        expiryMonthError: PayOrcCardFieldError? = nil,
        expiryYearError: PayOrcCardFieldError? = nil,
        cvvError: PayOrcCardFieldError? = nil,
        invalidCardError: PayOrcCardFieldError? = nil,
        emailError: PayOrcCardFieldError? = nil,
        mobileError: PayOrcCardFieldError? = nil
    ) {
        self.cardHolderNameError = cardHolderNameError
        self.cardNumberError = cardNumberError
        self.expiryMonthError = expiryMonthError
        self.expiryYearError = expiryYearError
        self.cvvError = cvvError
        self.invalidCardError = invalidCardError
        self.emailError = emailError
        self.mobileError = mobileError
    }
}
