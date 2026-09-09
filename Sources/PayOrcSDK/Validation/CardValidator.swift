import Foundation

public struct ValidationResult: Equatable {
    public let isValid: Bool
    public let errorMessage: String?

    public init(isValid: Bool, errorMessage: String? = nil) {
        self.isValid = isValid
        self.errorMessage = errorMessage
    }
}

public final class CardValidator {
    public init() {}

    public func validateCardNumber(_ value: String) -> ValidationResult {
        let digits = value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        guard digits.count >= 13, digits.count <= 19 else {
            return ValidationResult(isValid: false, errorMessage: "Enter a valid card number")
        }

        if !isLuhnValid(digits) {
            return ValidationResult(isValid: false, errorMessage: "Enter a valid card number")
        }

        return ValidationResult(isValid: true)
    }

    public func validateExpiry(month: String, year: String) -> ValidationResult {
        let monthValue = Int(month) ?? 0
        let yearValue = Int(year) ?? 0
        guard monthValue >= 1, monthValue <= 12 else {
            return ValidationResult(isValid: false, errorMessage: "Enter a valid expiry date")
        }

        let gregorian = Calendar(identifier: .gregorian)
        let currentYear = gregorian.component(.year, from: Date()) % 100
        let currentMonth = gregorian.component(.month, from: Date())
        if yearValue < currentYear || (yearValue == currentYear && monthValue < currentMonth) {
            return ValidationResult(isValid: false, errorMessage: "Enter a valid expiry date")
        }

        return ValidationResult(isValid: true)
    }

    public func validateCVV(_ value: String, cardNumber: String? = nil) -> ValidationResult {
        let digits = value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        let expectedLength = cardNumber?.hasPrefix("34") == true || cardNumber?.hasPrefix("37") == true ? 4 : 3
        guard digits.count == expectedLength else {
            return ValidationResult(isValid: false, errorMessage: "CVV is required")
        }
        return ValidationResult(isValid: true)
    }

    public func validateEmail(_ value: String) -> ValidationResult {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let regex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
        guard !trimmed.isEmpty, predicate.evaluate(with: trimmed) else {
            return ValidationResult(isValid: false, errorMessage: "Enter a valid email")
        }
        return ValidationResult(isValid: true)
    }

    public func validateMobile(_ value: String) -> ValidationResult {
        let digits = value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        guard digits.count >= 6 else {
            return ValidationResult(isValid: false, errorMessage: "Enter a valid mobile number")
        }
        return ValidationResult(isValid: true)
    }

    private func isLuhnValid(_ value: String) -> Bool {
        let digits = Array(value)
        var sum = 0
        var isSecond = false

        for index in stride(from: digits.count - 1, through: 0, by: -1) {
            var digit = Int(String(digits[index])) ?? 0
            if isSecond {
                digit *= 2
                if digit > 9 {
                    digit -= 9
                }
            }
            sum += digit
            isSecond.toggle()
        }

        return sum % 10 == 0
    }
}
