import UIKit

// MARK: - CheckoutRepository

/// Data-access layer for the PayOrc checkout customization endpoint.
///
/// Mirrors the Flutter SDK's `PayOrcRepo.fetchCheckoutCustomization()`.
/// Provides both `async/await` and completion-handler APIs for UIKit compatibility.
public final class CheckoutRepository {

    private let networkClient: NetworkClient

    public init(networkClient: NetworkClient) {
        self.networkClient = networkClient
    }

    // MARK: - Fetch Customization

    /// Fetches checkout customization from the PayOrc API.
    ///
    /// Uses the environment-resolved host, same as payment / add-card / etc
    /// (see ``PayOrcEnvironment/checkoutCustomizationURL``).
    ///
    /// - Parameters:
    ///   - currency: Currency code for the request (e.g. `"AED"`).
    ///   - amount:   Amount for the request (used to determine available payment methods).
    /// - Returns: The decoded ``CheckoutCustomizationData``.
    /// - Throws: ``PayOrcError`` on network or API failures.
    public func fetchCustomization(
        currency: String,
        amount: Decimal
    ) async throws -> CheckoutCustomizationData {
        let endpoint = APIEndpoint.checkoutCustomization(currency: currency, amount: amount)
        let response = try await networkClient.request(
            endpoint,
            responseType: CheckoutCustomizationResponse.self
        )

        guard response.isSuccess, let data = response.data else {
            let code    = response.code    ?? "UNKNOWN"
            let message = response.message ?? "Checkout customization returned no data."
            throw PayOrcError.checkoutCustomizationFailed("\(code): \(message)")
        }

        return data
    }

    /// Completion-handler overload of ``fetchCustomization(currency:amount:)``.
    ///
    /// Calls back on the **main queue**.
    public func fetchCustomization(
        currency: String,
        amount: Decimal,
        completion: @escaping (Result<CheckoutCustomizationData, PayOrcError>) -> Void
    ) {
        Task {
            do {
                let data = try await fetchCustomization(currency: currency, amount: amount)
                await MainActor.run { completion(.success(data)) }
            } catch let error as PayOrcError {
                await MainActor.run { completion(.failure(error)) }
            } catch {
                await MainActor.run {
                    completion(.failure(.requestFailed(underlying: error)))
                }
            }
        }
    }
}
