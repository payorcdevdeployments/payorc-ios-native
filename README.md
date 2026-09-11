# PayOrcSDK (iOS)

Native iOS SDK for PayOrc checkout: payment-method bottom sheet (Apple Pay, Tabby, pay with card), add‑card / tokenisation flow, 3‑D Secure and card‑verification web views, and the related UI. Merchant keys and the PayOrc service SDK drive **checkout customization** (colors, fonts, available methods, Apple Pay wallet config).

The SDK exposes three integration styles: a presented payment‑options sheet driven by a delegate, drop‑in‑anywhere static helpers (`PayOrc.applePay` / `PayOrc.tabby` / `PayOrc.addNewCard` / `PayOrc.submitOrder`), and embedded `UIView` payment components you place directly in your own layout.

## Requirements

- **iOS 15.0+**.
- **Xcode 26+** / Swift 6.2 toolchain (the package pins `swift-tools-version: 6.2`; it builds in Swift 5 language mode with main‑actor default isolation).
- A PayOrc **merchant key** and **merchant secret** (from the PayOrc dashboard).
- For Apple Pay: the **Apple Pay** capability and a **Merchant ID** entitlement in your host app (see [App setup](#app-setup)).
- **No third‑party dependencies.** The SDK uses only system frameworks — `Foundation`, `UIKit`, `PassKit`, `WebKit`, `CryptoKit`. Card‑network logos ship inside the package as a resource bundle.

## Installation (Swift Package Manager)

The SDK is a Swift package distributed from a public GitHub repository:

```
https://github.com/payorcdevdeployments/payorc-ios-native.git
```

### Xcode

1. *File → Add Package Dependencies…*
2. Paste the URL above.
3. Choose a version rule (e.g. *Up to Next Major* from `1.0.0`) and add the **`PayOrcSDK`** library product to your app target.

### `Package.swift`

```swift
dependencies: [
    .package(url: "https://github.com/payorcdevdeployments/payorc-ios-native.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "PayOrcSDK", package: "payorc-ios-native")
        ]
    )
]
```

### Import

```swift
import PayOrcSDK
```

Everything public — `PayOrc`, `PaymentRequest`, `PayOrcSDKCustomization`, the embedded views — is namespaced under that module. `PayOrcSDKVersion` (currently `"1.0.0"`) is exposed for logging; keep it in sync with the git tag when releasing.

## App setup

There is **no root wrapper to install** — the SDK presents its own `UIViewController`s and posts `Notification`s for customization changes.

The only host‑app configuration is for **Apple Pay**:

1. In *Signing & Capabilities*, add the **Apple Pay** capability and select (or create) your **Merchant ID** — it must match the `identifier` / `merchant_id` PayOrc returns in checkout customization for the `APPLE_PAY` method.
2. Apple Pay is only offered when `PKPaymentAuthorizationController.canMakePayments(usingNetworks:)` is `true` and Apple Pay is enabled in your PayOrc checkout customization. On the simulator, add a test card in *Settings → Wallet & Apple Pay*.

---

## 1. `PayOrc.initialize(configuration:)` — configure the SDK

Call **once** at app launch (e.g. from your `App` initializer or `application(_:didFinishLaunchingWithOptions:)`), before presenting any payment UI.

```swift
let configuration = PayOrcConfiguration(
    merchantKey:    "YOUR_MERCHANT_KEY",
    merchantSecret: "YOUR_MERCHANT_SECRET",
    environment:    .sandbox            // or .production
)

do {
    try PayOrc.initialize(configuration: configuration)
} catch {
    print("PayOrc init failed:", error.localizedDescription)
}
```

When `fetchCheckoutCustomizationOnInit` is `true` (default), the SDK fetches checkout customization from the PayOrc API in the background immediately after `initialize`. It also refreshes geo context so the `X-IP` / `X-IP-COUNTRY` headers are ready for signed calls.

### `PayOrcConfiguration` parameters

| Parameter | Type | Required | Default | Description |
| --------- | ---- | -------- | ------- | ----------- |
| `merchantKey` | `String` | yes | — | PayOrc merchant key. |
| `merchantSecret` | `String` | yes | — | PayOrc merchant secret. |
| `environment` | `PayOrcEnvironment` | no | `.sandbox` | `.sandbox` or `.production` API / gateway host. |
| `fetchCheckoutCustomizationOnInit` | `Bool` | no | `true` | Auto‑fetch checkout customization right after `initialize`. |
| `checkoutCustomizationCurrency` | `String` | no | `"AED"` | Currency sent with the automatic/manual customization request. |
| `checkoutCustomizationAmount` | `Decimal` | no | `1` | Amount used to derive payment‑method availability. |
| `tabbyApiKey` | `String?` | no | `nil` | Tabby public key; when set, Tabby can appear in the options sheet and embeds. |
| `tabbyMerchantCode` | `String` | no | `"ae"` | Tabby merchant code (e.g. `"ae"`, `"sa"`). |
| `appId` | `String?` | no | bundle id | Override for the `X-App-ID` header. |
| `appVersion` | `String?` | no | `CFBundleShortVersionString` | Override for the `X-App-Version` header. |
| `deviceId` | `String?` | no | `identifierForVendor` | Override for the `X-Device-Id` header. |
| `deviceOS` | `String?` | no | `"iOS"` | Override for the `X-Device-OS` header. |
| `deviceModel` | `String?` | no | `UIDevice.current.model` | Override for the `X-Device-Model` header. |
| `deviceBrand` | `String?` | no | `"Apple"` | Override for the `X-DEVICE-BRAND` header. |
| `browserToken` | `String?` | no | `identifierForVendor` | Optional `X-Browser-Token` header value. |

### Return value / access

`initialize` is `@discardableResult` and returns the configured `PayOrc` instance. After that:

| API | Purpose |
| --- | ------- |
| `PayOrc.shared` | The shared instance (`PayOrc?`). `nil` until `initialize` succeeds. |
| `PayOrc.isInitialized` | `Bool` guard — `true` once `initialize` has run. |
| `PayOrc.shared?.configuration` | The active `PayOrcConfiguration`. |
| `PayOrc.shared?.checkoutCustomization` | Last fetched `CheckoutCustomizationData`, or `nil`. |

`initialize` throws `PayOrcError.invalidConfiguration` when `merchantKey` or `merchantSecret` is blank.

---

## 2. `PayOrc.setCustomization(_:)` — host UI overrides

Optional **static** call (any time after `initialize`) to override checkout‑driven colors, fonts, and form chrome.

**Priority:** each non‑nil field you pass **wins** over the checkout `merchant_details` value from the customization API. Omitted fields fall back to the API value, then the SDK default. Resolution order is always **host override → API value → SDK default**. Host overrides persist across customization refreshes.

Calling `setCustomization` posts `PayOrc.uiCustomizationDidChange`, so SDK views and embeds restyle themselves.

```swift
PayOrc.setCustomization(PayOrcSDKCustomization(
    brandColor:  .systemIndigo,
    accentColor: .systemIndigo,
    borderColor: UIColor(white: 0.8, alpha: 1),
    button: PayOrcButtonCustomization(
        backgroundColor: .systemIndigo,
        foregroundColor: .white,
        borderRadius: 12,
        height: 52
    ),
    text: PayOrcTextCustomization(
        primaryColor:   UIColor(white: 0.07, alpha: 1),
        secondaryColor: UIColor(white: 0.4, alpha: 1),
        fontSize: 15
    ),
    textField: PayOrcTextFieldCustomization(height: 48, borderRadius: 8),
    bottomSheet: PayOrcBottomSheetCustomization(itemSpacing: 12, cornerRadius: 16),
    inputBorderStyle: .outline,
    guidanceStyle:    .label,
    addCardForm: PayOrcAddCardFormCustomization(
        titleUseNewCard: "Add card",
        submitButtonTitleVerify: "Verify card"
    )
))
```

### Checkout API mapping (`merchant_details`)

| `PayOrcSDKCustomization` field | Checkout field |
| ----------------------------- | -------------- |
| `brandColor` | `brand_color` |
| `accentColor` | `accent_color` |
| `borderColor` | `border_color` |
| `button.backgroundColor` | `button_color` |
| `text.primaryColor` | `text_primary` |
| `text.secondaryColor` | `text_secondary` |
| `inputBorderStyle` | `field_border` (`outline` / `underline`) |
| `autoselectColor` | `autoselect_color` |
| `text.bodyFont` / `text.titleFont` | `font_name` |
| `guidanceStyle` | host‑only (no checkout equivalent) |

Fully transparent colors (`alpha == 0`) are ignored. Nested objects (`button`, `text`, `textField`, `bottomSheet`) apply field‑by‑field — only non‑nil properties take effect. `addCardForm` **merges** across successive `setCustomization` calls.

### `PayOrcSDKCustomization` parameters

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| `brandColor` | `UIColor?` | Brand / primary color for highlights, active states, logos. |
| `accentColor` | `UIColor?` | Secondary accent (links, selection chrome). |
| `borderColor` | `UIColor?` | Default resting border for SDK chrome and fields. |
| `button` | `PayOrcButtonCustomization?` | Primary CTA styling. Non‑nil fields merge. |
| `text` | `PayOrcTextCustomization?` | Typography bundle (colors, fonts, metrics). Non‑nil fields merge. |
| `textField` | `PayOrcTextFieldCustomization?` | Input‑field height, insets, radius, border color. |
| `bottomSheet` | `PayOrcBottomSheetCustomization?` | Modal sheet padding, spacing, top corner radius. |
| `inputBorderStyle` | `PayOrcInputBorderStyle?` | `.outline` or `.underline`. Host → checkout `field_border`. |
| `guidanceStyle` | `PayOrcGuidanceStyle?` | `.label` (floating label) or `.hint` (placeholder only). Host‑only. Default `.label`. |
| `autoselectColor` | `Int?` | ARGB value for the auto‑selected saved‑card highlight. Host → checkout `autoselect_color`. |
| `addCardForm` | `PayOrcAddCardFormCustomization?` | Add‑card sheet copy (title, subtitle, labels, hints, button labels). Merges across calls. |
| `cardFormValidation` | `PayOrcCardFormValidationCustomization?` | Add‑card validator message overrides. |

---

## 3. Presenting checkout

Build a `PaymentRequest` (see [Core types](#core-types)) and present one of the two SDK flows.

```swift
let request = PaymentRequest(
    orderDetails: [
        OrderDetails(
            mOrderId: "ORDER-1001",
            amount: "10.00",
            convenienceFee: "0.00",
            quantity: "1",
            currency: "AED",
            description: "iOS SDK order"
        )
    ],
    customerDetails: CustomerDetails(
        mCustomerId: "CUST-001",
        name: "Asif Ali",
        email: "asif.ali@payorc.com",
        mobile: "500000000",
        code: "+971"
    ),
    billingDetails: BillingDetails(
        addressLine1: "Dubai Marina",
        city: "Dubai",
        province: "Dubai",
        country: "AE",
        pin: "00000"
    ),
    urls: Urls(webhookUrl: "https://webhook.site/your-endpoint")
)
```

### `PayOrc.shared?.presentPaymentOptions(from:request:delegate:)`

Presents the full payment‑options bottom sheet — Apple Pay / Tabby / Pay with Card, depending on your PayOrc configuration — and owns the whole flow through to a terminal delegate callback.

It adds **failure recovery**: when a card payment started from this sheet fails, instead of an inline error the SDK presents a recovery sheet showing the error, the customer's saved cards (`sdk/customer/cards`), and other methods to retry with.

```swift
final class CheckoutHandler: PayOrcSDKDelegate {
    func payOrcDidComplete(result: PayOrcSDKResult) {
        print("Paid:", result.status, result.code, result.transactionId ?? "")
    }
    func payOrcDidFail(error: PayOrcError) {
        print("Failed:", error.localizedDescription)
    }
    func payOrcDidCancel() {
        print("User cancelled")
    }
}

let handler = CheckoutHandler()   // retain this — the delegate is held weakly
PayOrc.shared?.presentPaymentOptions(from: self, request: request, delegate: handler)
```

### `PayOrc.shared?.presentCheckout(from:request:delegate:)`

Presents just the card‑entry sheet (no method picker, no failure‑recovery sheet — a failed submission surfaces inline on the form). Use it when card is your only method or you drive method selection yourself.

### Parameters (both methods)

| Parameter | Type | Required | Description |
| --------- | ---- | -------- | ----------- |
| `from` | `UIViewController` | yes | The presenting view controller. |
| `request` | `PaymentRequest` | yes | Order, customer, billing, shipping, and webhook details. |
| `delegate` | `PayOrcSDKDelegate` | yes | Receives the flow's terminal outcome. **Held weakly** — keep a strong reference yourself. |

Both are `@MainActor` and return `Void`; the outcome arrives via the delegate.

### `PayOrcSDKDelegate`

```swift
public protocol PayOrcSDKDelegate: AnyObject {
    func payOrcDidComplete(result: PayOrcSDKResult)
    func payOrcDidFail(error: PayOrcError)
    func payOrcDidCancel()   // has a default empty implementation
}
```

### `PayOrcSDKResult`

| Field | Type | Description |
| ----- | ---- | ----------- |
| `status` | `String` | e.g. `"success"`. |
| `code` | `String` | Raw API code (e.g. `"00"`). |
| `message` | `String` | Display message. |
| `transactionId` | `String?` | PayOrc transaction / order id, when present. |

---

## 4. Static helpers — `PayOrc.applePay` / `.tabby` / `.addNewCard` / `.submitOrder`

Drop‑in‑anywhere static entry points, callable from any button action once `PayOrc.initialize` has run. Each is a thin wrapper over the instance flows on `PayOrc.shared`; if the SDK isn't initialized, `onError` fires with `PayOrcError.sdkNotInitialized`.

### `PayOrc.applePay`

Opens the native Apple Pay sheet and submits the resulting token to `POST sdk/wallet/payment`. No presenter needed — `PKPaymentAuthorizationController` presents itself.

```swift
PayOrc.applePay(
    request: request,
    onAuthorized: { result in /* PayOrcSDKResult */ },
    onError:      { error  in /* PayOrcError */ }
)
```

### `PayOrc.tabby`

Runs the full hosted Tabby BNPL flow: `sdk/tabby/init` → Tabby session → in‑app web checkout → `sdk/tabby/confirm`.

```swift
PayOrc.tabby(
    from: viewController,
    request: request,
    onAuthorized: { result in },
    onError:      { error  in }
)
```

### `PayOrc.addNewCard`

Opens the add‑card form, tokenises the card via `POST sdk/add-card`, runs card verification when required, and returns a token‑enriched `CardData` — **without charging it**. Pair with `PayOrc.submitOrder` to charge it now or later.

```swift
PayOrc.addNewCard(
    from: viewController,
    request: request,
    onAddCard: { card in
        // card.paymentToken is populated — charge now, or persist the token
        PayOrc.submitOrder(from: viewController, card: card, request: request,
                           onSuccess: { result in }, onError: { error in })
    },
    onCancel: { },
    onError:  { error in }
)
```

### `PayOrc.submitOrder`

Submits a `CardData` for a `PaymentRequest` with no card‑entry UI (runs the submitting sheet + 3‑D Secure web view as needed).

```swift
PayOrc.submitOrder(
    from: viewController,
    card: card,
    request: request,
    onSuccess: { result in },
    onError:   { error in },
    onCancel:  { }
)
```

### Instance equivalents

The same flows are also on `PayOrc.shared` when you already hold the instance:

| Instance method | Static equivalent |
| --------------- | ----------------- |
| `showApplePayCheckout(request:onAuthorized:onError:)` | `PayOrc.applePay` |
| `showTabbyCheckout(from:request:onAuthorized:onError:)` | `PayOrc.tabby` |

---

## 5. Embedded payment components

Self‑contained `UIView`s you drop straight into a host layout. Each row:

- Styles itself from `PayOrcUIConstants` (host → API → default), so it tracks `setCustomization` automatically.
- **Hides itself** (collapses to zero height) when its method isn't enabled in checkout customization.
- Re‑evaluates on `PayOrc.checkoutCustomizationDidChange` / `PayOrc.uiCustomizationDidChange`.
- Fills its superview's width by default (`fillsSuperviewWidth = false` to size it yourself).
- Resolves a presenter via the responder chain, or set `presentingViewController` explicitly.

| View | Method | Accepts `PayOrcEmbeddedCustomization` |
| ---- | ------ | ------------------------------------- |
| `PayOrcEmbeddedApplePayButton` | Apple Pay (native `PKPaymentButton`) | no |
| `PayOrcEmbeddedTabbyButton` | Tabby hosted checkout | yes |
| `PayOrcEmbeddedPayWithCardButton` | Card‑entry sheet | yes |
| `PayOrcEmbeddedPaymentMethodsView` | All three, stacked in sheet order | per‑row |

```swift
let cardButton = PayOrcEmbeddedPayWithCardButton(paymentRequest: request)
cardButton.onComplete = { result in }
cardButton.onFail     = { error in }
cardButton.onCancel   = { }
stackView.addArrangedSubview(cardButton)

let applePay = PayOrcEmbeddedApplePayButton(paymentRequest: request)
applePay.onAuthorized = { result in }
applePay.onError      = { error in }
stackView.addArrangedSubview(applePay)

let all = PayOrcEmbeddedPaymentMethodsView(paymentRequest: request)
all.onAuthorized   = { result in }   // Apple Pay + Tabby
all.onCardComplete = { result in }   // Pay with Card
all.onError        = { error in }
view.addSubview(all)
```

### Using them from SwiftUI

Wrap each view in a `UIViewRepresentable` and forward the closures in `updateUIView` (see `EmbeddedPaymentDemoView.swift` in the demo app for a complete example).

### `PayOrcEmbeddedCustomization`

Per‑instance style override for a single embedded control; omitted fields fall back to the SDK‑wide resolved value.

| Field | Type | Applies to |
| ----- | ---- | ---------- |
| `buttonBackgroundColor`, `buttonTextColor`, `buttonBorderColor` | `UIColor?` | Pay‑with‑Card button |
| `buttonBorderRadius`, `buttonHeight` | `CGFloat?` | Pay‑with‑Card button |
| `payWithCardTitle` | `String?` | Pay‑with‑Card button title (default `"Pay with Card"`) |
| `tileBackgroundColor`, `tileTitleColor`, `tileSelectedBackgroundColor`, `tileSelectedBorderColor` | `UIColor?` | Tabby tile |
| `tileBorderRadius`, `tileHeight` | `CGFloat?` | Tabby tile |
| `accentColor`, `borderColor` | `UIColor?` | shared |

Presets: `PayOrcEmbeddedCustomization.payWithCard(...)` and `PayOrcEmbeddedCustomization.tabby(...)`.

---

## 6. Manual customization refresh & notifications

Re‑fetch checkout customization for a specific currency / amount pair — e.g. after loading an order summary — before presenting the payment UI.

```swift
// Completion-handler form
PayOrc.refreshCheckoutCustomization(currency: "AED", amount: 100) { result in
    switch result {
    case .success(let data): print("methods:", data.availableMethods.count)
    case .failure(let error): print("failed:", error.localizedDescription)
    }
}

// async/await form
let data = try await PayOrc.refreshCheckoutCustomization(currency: "AED", amount: 100)
```

Both default `currency` / `amount` to the configuration values. A successful refresh posts `PayOrc.checkoutCustomizationDidChange`.

| Notification | Posted when |
| ------------ | ----------- |
| `PayOrc.checkoutCustomizationDidChange` | Checkout customization was fetched & applied (auto or manual). `object` is the `CheckoutCustomizationData`. |
| `PayOrc.uiCustomizationDidChange` | Any UI customization changed (host override or API update). |

---

## Enums (quick reference)

### `PayOrcEnvironment`

| Value | Meaning |
| ----- | ------- |
| `.sandbox` | Dev gateway host (`dev-gateway.payorc.com`). |
| `.production` | Production host (`gateway.payorc.com`). |

### `PayOrcInputBorderStyle`

| Value | Use |
| ----- | --- |
| `.outline` | Full rectangular border around the field. |
| `.underline` | Bottom border only (Material‑style). |

### `PayOrcGuidanceStyle`

| Value | Effect |
| ----- | ------ |
| `.label` | Label floats above the field once focused / filled. SDK default. |
| `.hint` | Label shown only as placeholder text, never floated. |

---

## Customization type reference

### `PayOrcButtonCustomization`

| Field | Type | Description |
| ----- | ---- | ----------- |
| `backgroundColor` | `UIColor?` | Primary CTA fill (checkout `button_color`). |
| `foregroundColor` | `UIColor?` | Label / icon color. |
| `disabledBackgroundColor` | `UIColor?` | Fill when disabled. |
| `sideBorderColor` | `UIColor?` | 1px outline stroke. |
| `borderRadius` | `CGFloat?` | Corner radius. |
| `height` | `CGFloat?` | Fixed button height. |
| `fontWeight` | `UIFont.Weight?` | Title weight. |
| `loadingIndicatorColor` | `UIColor?` | Spinner color while a request is in‑flight. |

### `PayOrcTextCustomization`

| Field | Type | Description |
| ----- | ---- | ----------- |
| `primaryColor` | `UIColor?` | Primary text (headings, labels, amounts) — checkout `text_primary`. |
| `secondaryColor` | `UIColor?` | Secondary text (subtitles, hints) — checkout `text_secondary`. |
| `bodyFont` | `UIFont?` | Font for body / regular text. |
| `titleFont` | `UIFont?` | Font for titles / headers. |
| `fontWeight` | `UIFont.Weight?` | Global weight for SDK text. |
| `fontSize` | `CGFloat?` | Body text size. |
| `letterSpacing` | `CGFloat?` | Character spacing (`kern`). |
| `textAlignment` | `NSTextAlignment?` | Default alignment. |
| `maxLines` | `Int?` | Default max lines (`0` = unlimited). |
| `lineBreakMode` | `NSLineBreakMode?` | Truncation behavior. |
| `underline` / `strikethrough` / `italic` | `Bool?` | Text decoration / style. |
| `wordSpacing` | `CGFloat?` | Extra spacing between words. |
| `shadow` | `NSShadow?` | Optional text shadow. |

### `PayOrcTextFieldCustomization`

| Field | Type | Description |
| ----- | ---- | ----------- |
| `height` | `CGFloat?` | Fixed input‑field height. |
| `contentInsets` | `UIEdgeInsets?` | Padding inside each field. |
| `borderRadius` | `CGFloat?` | Corner radius (outline style only). |
| `borderColor` | `UIColor?` | Resting field border. Falls back to API `border_color`, then default. |

### `PayOrcBottomSheetCustomization`

| Field | Type | Description |
| ----- | ---- | ----------- |
| `contentInsets` | `UIEdgeInsets?` | Sheet content padding. |
| `itemSpacing` | `CGFloat?` | Vertical gap between items. |
| `cornerRadius` | `CGFloat?` | Top corner radius of the sheet. |

### `PayOrcAddCardFormCustomization`

Copy overrides for the add / edit card sheet. Any `nil` field uses the SDK default (English). Strings are shown **as‑is** — not localized. Non‑nil fields **merge** across `setCustomization` calls.

| Field | Description |
| ----- | ----------- |
| `titleUseNewCard` / `titleEditCard` | Sheet header for add vs edit. (`titleEditCard` reserved for a future saved‑card edit mode.) |
| `subtitleAdd` / `subtitleEdit` | Subtitle under the header. |
| `cardHolderNameLabel`, `cardNumberLabel`, `expiryLabel`, `cvvLabel`, `emailLabel`, `mobileLabel` | Field labels. |
| `cardHolderNameHint`, `cardNumberHint`, `expiryHint`, `cvvHint`, `emailHint`, `mobileHint` | Field placeholders (fall back to the matching `*Label`). |
| `countrySearchHint` | Country‑picker search hint. |
| `submitButtonTitleVerify` / `submitButtonTitleSaveChanges` | Primary action label. |

### `PayOrcCardFormValidationCustomization`

Overrides add‑card validation messages. Each field is a `PayOrcCardFieldError` (`required` / `invalid` strings). The validator currently uses `invalid` for every case (`required` is accepted but currently treated the same as `invalid`).

| Field | Overrides |
| ----- | --------- |
| `cardNumberError` | `PayOrcError.invalidCardNumber` |
| `expiryMonthError` / `expiryYearError` | `PayOrcError.invalidExpiryDate` (month/year validated together; `expiryYearError` is the fallback) |
| `cvvError` | `PayOrcError.invalidCVV` |
| `emailError` | `PayOrcError.invalidEmail` |
| `mobileError` | `PayOrcError.invalidMobile` |
| `cardHolderNameError`, `invalidCardError` | Reserved for forward compatibility. |

---

## Core types

### `PaymentRequest`

| Field | Type | Default | Description |
| ----- | ---- | ------- | ----------- |
| `paymentToken` | `String?` | `nil` | Existing checkout / saved‑card token. |
| `orderDetails` | `[OrderDetails]` | — | The order line(s). The first entry drives amount/currency. |
| `customerDetails` | `CustomerDetails` | — | Customer identity + contact. |
| `billingDetails` | `BillingDetails` | — | Billing address. |
| `shippingDetails` | `ShippingDetails` | empty | Shipping address; omitted from the payload when all fields are blank. |
| `urls` | `Urls?` | `nil` | `Urls(webhookUrl:)` — forwarded to add‑card, submit‑order, Tabby, and Apple Pay payloads when non‑empty. |
| `parameters` | `[[String: String]]` | `[]` | Extra `parameters` array in the request body. |
| `customData` | `[[String: String]]` | `[]` | Extra `custom_data` array in the request body. |

### `OrderDetails`

`mOrderId` (default `""`), `amount`, `convenienceFee` (default `""`), `quantity` (default `""`), `currency`, `description` (default `""`) — all `String`.

### `CustomerDetails`

`mCustomerId`, `name`, `email`, `mobile`, `code` — all `String`, all required.

### `BillingDetails`

`addressLine1`, `country` required; `addressLine2`, `city`, `province`, `pin` default `""`.

### `ShippingDetails`

All fields optional (default `""`): `shippingName`, `shippingEmail`, `shippingCode`, `shippingMobile`, `addressLine1`, `addressLine2`, `city`, `province`, `country`, `pin`, `shippingCurrency`, `shippingAmount`.

### `Urls`

`webhookUrl: String`.

### `CardData`

| Field | Type | Description |
| ----- | ---- | ----------- |
| `cardNumber` | `String?` | Full PAN for new cards; last‑4 only for saved cards. |
| `cardholderName` | `String` | Name on card. |
| `expiryMonth` / `expiryYear` | `String` | `MM` / `YY` or `YYYY` (2‑digit years are normalised to `20YY`). |
| `cvv` | `String` | Security code. |
| `email` / `mobile` / `countryCode` | `String?` | Optional contact overrides for the payload. |
| `paymentToken` | `String?` | Token for a saved / tokenised card. |
| `cardNetwork` | `String?` | Scheme (e.g. `"VISA"`), populated for saved cards. `lastFourDigits` and `CardData.fromSDK(_:)` helpers are provided. |

### `PayOrcSDKResult`

See [§3](#payorcsdkresult).

### `PaymentResponse`

Lower‑level API response (`status`, `code`, `message`, `data`) with convenience accessors: `redirectUrl`, `orderStatus`, `isAwait3DS`, `transactionId`, `pOrderId`, `mOrderId`.

---

## Error handling — `PayOrcError`

Typed error enum; use `error.localizedDescription` for display‑ready text.

| Group | Cases |
| ----- | ----- |
| Configuration | `.sdkNotInitialized`, `.invalidConfiguration(String)` |
| Validation | `.invalidCardNumber`, `.invalidExpiryDate`, `.invalidCVV`, `.invalidEmail`, `.invalidMobile`, `.validation(field:message:)` |
| Network | `.noInternetConnection`, `.timeout`, `.serverError(statusCode:message:)`, `.unauthorized`, `.requestFailed(underlying:)` |
| API business logic | `.apiFailure(code:message:)`, `.checkoutCustomizationFailed(String)`, `.paymentFailed(code:message:)` |
| Parsing | `.decodingFailed(String)`, `.unexpectedResponse` |
| Platform | `.unsupported(feature:)` |

Helpers: `error.isValidationError`, `error.isNetworkError`, `error.isRetryable`. User cancellation of an embedded Apple Pay flow is reported as `.apiFailure(code: "CANCELLED", …)`.

---

## Demo app

`PayOrcSPMDemo` (a standalone Xcode project kept next to this package) integrates the SDK **through Swift Package Manager** and exercises every entry point:

| Screen | Demonstrates |
| ------ | ------------ |
| Payment Options | `PayOrc.shared?.presentPaymentOptions` from SwiftUI via a delegate coordinator. |
| Static API | `PayOrc.applePay` / `.tabby` / `.addNewCard` from plain `Button` actions. |
| Embedded Views | Each `PayOrcEmbedded*` view wrapped in `UIViewRepresentable`. |
| Customization | Live `PayOrc.setCustomization` editing. |

The demo references the package by **local path** (`../ios-sdk-swift-packages/ios-sdk-swift-packages`) for development; swap it for the remote URL rule to test a tagged release. SDK setup lives in `PayOrcSPMDemoApp.swift` — replace the placeholder `merchantKey` / `merchantSecret` with your own sandbox credentials.

## Building the package

```bash
xcodebuild -scheme PayOrcSDK -destination 'generic/platform=iOS' build
```

## Releasing

1. Bump `PayOrcSDKVersion` in `Sources/PayOrcSDK/PayOrcSDK.swift`.
2. Commit, then tag: `git tag 1.0.1 && git push origin 1.0.1`.
3. Consumers pick it up via their version rule.

---

## License

See the repository metadata for license terms.
