import UIKit

// MARK: - PaymentRepository

/// Data-access layer for PayOrc payment-related endpoints.
///
/// Provides `async/await` + completion-handler APIs for all payment flows:
/// card payment, wallet (Apple Pay), add-card, and customer cards.
public final class PaymentRepository {

    private let networkClient: NetworkClient

    public init(networkClient: NetworkClient) {
        self.networkClient = networkClient
    }

    // MARK: - Card Payment

    /// Submits a card payment to `POST sdk/payment`.
    ///
    /// - Parameters:
    ///   - request: The ``PaymentRequest`` describing the order.
    ///   - card:    The ``CardData`` with card details.
    /// - Returns: The decoded ``PaymentResponse``.
    /// - Throws: ``PayOrcError`` on validation, network, or API failure.
    public func submitPayment(
        request: PaymentRequest,
        card: CardData
    ) async throws -> PaymentResponse {
        // payloadData(for:) builds JSON in Flutter's exact insertion-order with no \/
        // escaping — byte-for-byte matching Dart's jsonEncode(toJson(card)).
        let bodyData = try request.payloadData(for: card)
        let endpoint = APIEndpoint.payment(bodyData: bodyData)
        return try await networkClient.request(endpoint, responseType: PaymentResponse.self)
    }

    /// Completion-handler overload of ``submitPayment(request:card:)``.
    public func submitPayment(
        request: PaymentRequest,
        card: CardData,
        completion: @escaping (Result<PaymentResponse, PayOrcError>) -> Void
    ) {
        Task {
            do {
                let result = try await submitPayment(request: request, card: card)
                await MainActor.run { completion(.success(result)) }
            } catch let error as PayOrcError {
                await MainActor.run { completion(.failure(error)) }
            } catch {
                await MainActor.run {
                    completion(.failure(.requestFailed(underlying: error)))
                }
            }
        }
    }

    // MARK: - Add Card

    /// Tokenises (saves) a card via `POST sdk/add-card`.
    ///
    /// - Parameters:
    ///   - body: The pre-built request payload dictionary.
    /// - Returns: The decoded ``PaymentResponse`` for the add-card operation.
    /// - Throws: ``PayOrcError`` on failure.
    public func addCard(body: [String: Any]) async throws -> PaymentResponse {
        let endpoint = APIEndpoint.addCard(body: body)
        return try await networkClient.request(endpoint, responseType: PaymentResponse.self)
    }

    /// Completion-handler overload of ``addCard(body:)``.
    public func addCard(
        body: [String: Any],
        completion: @escaping (Result<PaymentResponse, PayOrcError>) -> Void
    ) {
        Task {
            do {
                let result = try await addCard(body: body)
                await MainActor.run { completion(.success(result)) }
            } catch let error as PayOrcError {
                await MainActor.run { completion(.failure(error)) }
            } catch {
                await MainActor.run {
                    completion(.failure(.requestFailed(underlying: error)))
                }
            }
        }
    }

    // MARK: - Customer Cards

    /// Fetches the saved cards for a customer via `POST sdk/customer/cards`.
    ///
    /// - Parameter body: The customer-cards request payload.
    /// - Returns: A raw `[String: Any]` dictionary (decoded to your customer-cards model).
    /// - Throws: ``PayOrcError`` on failure.
    public func fetchCustomerCards(body: [String: Any]) async throws -> PaymentResponse {
        let endpoint = APIEndpoint.customerCards(body: body)
        return try await networkClient.request(endpoint, responseType: PaymentResponse.self)
    }

    // MARK: - Wallet Payment

    /// Submits a wallet payment (Apple Pay token) via `POST sdk/wallet/payment`.
    ///
    /// - Parameter body: The wallet payment payload built from the Apple Pay token.
    /// - Returns: The decoded ``PaymentResponse``.
    /// - Throws: ``PayOrcError`` on failure.
    public func submitWalletPayment(body: [String: Any]) async throws -> PaymentResponse {
        let endpoint = APIEndpoint.walletPayment(body: body)
        return try await networkClient.request(endpoint, responseType: PaymentResponse.self)
    }

    /// Completion-handler overload of ``submitWalletPayment(body:)``.
    public func submitWalletPayment(
        body: [String: Any],
        completion: @escaping (Result<PaymentResponse, PayOrcError>) -> Void
    ) {
        Task {
            do {
                let result = try await submitWalletPayment(body: body)
                await MainActor.run { completion(.success(result)) }
            } catch let error as PayOrcError {
                await MainActor.run { completion(.failure(error)) }
            } catch {
                await MainActor.run {
                    completion(.failure(.requestFailed(underlying: error)))
                }
            }
        }
    }

    // MARK: - Tabby

    /// Initiates a Tabby checkout session via `POST sdk/tabby/init`.
    public func initTabby(body: [String: Any]) async throws -> PaymentResponse {
        let endpoint = APIEndpoint.tabbyInit(body: body)
        return try await networkClient.request(endpoint, responseType: PaymentResponse.self)
    }

    /// Completion-handler overload of ``initTabby(body:)``.
    public func initTabby(
        body: [String: Any],
        completion: @escaping (Result<PaymentResponse, PayOrcError>) -> Void
    ) {
        Task {
            do {
                let result = try await initTabby(body: body)
                await MainActor.run { completion(.success(result)) }
            } catch let error as PayOrcError {
                await MainActor.run { completion(.failure(error)) }
            } catch {
                await MainActor.run {
                    completion(.failure(.requestFailed(underlying: error)))
                }
            }
        }
    }

    /// Confirms a Tabby checkout via `POST sdk/tabby/confirm`.
    public func confirmTabby(body: [String: Any]) async throws -> PaymentResponse {
        let endpoint = APIEndpoint.tabbyConfirm(body: body)
        return try await networkClient.request(endpoint, responseType: PaymentResponse.self)
    }

    /// Completion-handler overload of ``confirmTabby(body:)``.
    public func confirmTabby(
        body: [String: Any],
        completion: @escaping (Result<PaymentResponse, PayOrcError>) -> Void
    ) {
        Task {
            do {
                let result = try await confirmTabby(body: body)
                await MainActor.run { completion(.success(result)) }
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
