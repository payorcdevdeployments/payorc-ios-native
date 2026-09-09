import Foundation

// MARK: - PayOrcAddCardFormCustomization

/// Host copy overrides for the add / edit card sheet (``CheckoutViewController``).
///
/// Pass to ``PayOrcSDKCustomization/addCardForm``. Any `nil` field falls back to
/// the SDK default (English copy). Strings are used exactly as provided — they are
/// **not** localized by the SDK. Use this for final merchant copy or pre-translated text.
///
/// Mirrors Flutter's `PayorcSdkAddCardFormCustomization`.
public struct PayOrcAddCardFormCustomization {

    /// Header when adding a card (default: "Use New Card").
    public var titleUseNewCard: String?

    /// Header when editing a saved card (default: "Edit Card").
    ///
    /// Reserved for a future saved-card edit mode — this SDK version always shows
    /// the add-card flow, so this field currently has no effect.
    public var titleEditCard: String?

    /// Subtitle under the header in the add flow (default: "Enter your card details securely").
    public var subtitleAdd: String?

    /// Subtitle in the edit flow (default: "Card ending in …").
    ///
    /// Reserved alongside ``titleEditCard`` for a future saved-card edit mode.
    public var subtitleEdit: String?

    public var cardHolderNameLabel: String?
    public var cardNumberLabel:     String?
    public var expiryLabel:         String?
    public var cvvLabel:            String?
    public var emailLabel:          String?
    public var mobileLabel:         String?

    /// Placeholder text shown before the field is focused / filled.
    /// When `nil`, the corresponding `*Label` value is reused as the placeholder
    /// (matching the SDK's current floating-label behavior).
    public var cardHolderNameHint: String?
    public var cardNumberHint:     String?
    public var expiryHint:         String?
    public var cvvHint:            String?
    public var emailHint:          String?
    public var mobileHint:         String?

    /// Country picker search field hint (default: "Search country").
    public var countrySearchHint: String?

    /// Primary action title when adding a card (default: "Verify").
    public var submitButtonTitleVerify: String?

    /// Primary action title when editing a saved card (default: "Save changes").
    ///
    /// Reserved alongside ``titleEditCard`` for a future saved-card edit mode.
    public var submitButtonTitleSaveChanges: String?

    public init(
        titleUseNewCard: String? = nil,
        titleEditCard: String? = nil,
        subtitleAdd: String? = nil,
        subtitleEdit: String? = nil,
        cardHolderNameLabel: String? = nil,
        cardNumberLabel: String? = nil,
        expiryLabel: String? = nil,
        cvvLabel: String? = nil,
        emailLabel: String? = nil,
        mobileLabel: String? = nil,
        cardHolderNameHint: String? = nil,
        cardNumberHint: String? = nil,
        expiryHint: String? = nil,
        cvvHint: String? = nil,
        emailHint: String? = nil,
        mobileHint: String? = nil,
        countrySearchHint: String? = nil,
        submitButtonTitleVerify: String? = nil,
        submitButtonTitleSaveChanges: String? = nil
    ) {
        self.titleUseNewCard = titleUseNewCard
        self.titleEditCard = titleEditCard
        self.subtitleAdd = subtitleAdd
        self.subtitleEdit = subtitleEdit
        self.cardHolderNameLabel = cardHolderNameLabel
        self.cardNumberLabel = cardNumberLabel
        self.expiryLabel = expiryLabel
        self.cvvLabel = cvvLabel
        self.emailLabel = emailLabel
        self.mobileLabel = mobileLabel
        self.cardHolderNameHint = cardHolderNameHint
        self.cardNumberHint = cardNumberHint
        self.expiryHint = expiryHint
        self.cvvHint = cvvHint
        self.emailHint = emailHint
        self.mobileHint = mobileHint
        self.countrySearchHint = countrySearchHint
        self.submitButtonTitleVerify = submitButtonTitleVerify
        self.submitButtonTitleSaveChanges = submitButtonTitleSaveChanges
    }

    /// Returns a copy of `base` with `next`'s non-nil fields applied on top.
    /// Mirrors Flutter's `PayorcSdkAddCardFormCustomization.merge`.
    static func merge(
        _ base: PayOrcAddCardFormCustomization?,
        _ next: PayOrcAddCardFormCustomization
    ) -> PayOrcAddCardFormCustomization {
        PayOrcAddCardFormCustomization(
            titleUseNewCard: next.titleUseNewCard ?? base?.titleUseNewCard,
            titleEditCard: next.titleEditCard ?? base?.titleEditCard,
            subtitleAdd: next.subtitleAdd ?? base?.subtitleAdd,
            subtitleEdit: next.subtitleEdit ?? base?.subtitleEdit,
            cardHolderNameLabel: next.cardHolderNameLabel ?? base?.cardHolderNameLabel,
            cardNumberLabel: next.cardNumberLabel ?? base?.cardNumberLabel,
            expiryLabel: next.expiryLabel ?? base?.expiryLabel,
            cvvLabel: next.cvvLabel ?? base?.cvvLabel,
            emailLabel: next.emailLabel ?? base?.emailLabel,
            mobileLabel: next.mobileLabel ?? base?.mobileLabel,
            cardHolderNameHint: next.cardHolderNameHint ?? base?.cardHolderNameHint,
            cardNumberHint: next.cardNumberHint ?? base?.cardNumberHint,
            expiryHint: next.expiryHint ?? base?.expiryHint,
            cvvHint: next.cvvHint ?? base?.cvvHint,
            emailHint: next.emailHint ?? base?.emailHint,
            mobileHint: next.mobileHint ?? base?.mobileHint,
            countrySearchHint: next.countrySearchHint ?? base?.countrySearchHint,
            submitButtonTitleVerify: next.submitButtonTitleVerify ?? base?.submitButtonTitleVerify,
            submitButtonTitleSaveChanges: next.submitButtonTitleSaveChanges ?? base?.submitButtonTitleSaveChanges
        )
    }
}
