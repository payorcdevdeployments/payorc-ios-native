import Foundation

// MARK: - NetworkClient

/// `URLSession`-backed HTTP client for the PayOrc SDK.
///
/// Features:
/// - `async/await` primary API + completion-handler overloads
/// - Automatic HMAC-SHA256 request signing via ``RequestSigner``
/// - Typed error mapping to ``PayOrcError``
/// - JSON decoding with snake_case key conversion
/// - 1 retry on transient network failures (timeout / connection loss / 5xx)
/// - Debug-only request/response logging
public final class NetworkClient {

    // MARK: - Configuration

    private let configuration: PayOrcConfiguration
    private let session: URLSession
    private let decoder: JSONDecoder

    private static let maxRetryCount = 1

    // MARK: - Init

    public init(configuration: PayOrcConfiguration) {
        self.configuration = configuration

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest  = 30
        sessionConfig.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: sessionConfig)

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = dec
    }

    // MARK: - Core async/await API

    /// Sends a signed request for the given endpoint and decodes the response.
    ///
    /// - Parameters:
    ///   - endpoint:      The ``APIEndpoint`` to call.
    ///   - responseType:  The `Decodable` type to decode the successful response into.
    /// - Returns: The decoded response value.
    /// - Throws: ``PayOrcError`` on any failure (network, HTTP, parsing).
    public func request<T: Decodable>(
        _ endpoint: APIEndpoint,
        responseType: T.Type
    ) async throws -> T {
        let urlRequest = try endpoint.buildRequest(configuration: configuration)
        return try await performWithRetry(urlRequest: urlRequest, responseType: responseType)
    }

    // MARK: - Completion-handler overload

    /// Completion-handler wrapper around ``request(_:responseType:)``.
    /// Calls back on the **main queue**.
    public func request<T: Decodable>(
        _ endpoint: APIEndpoint,
        responseType: T.Type,
        completion: @escaping (Result<T, PayOrcError>) -> Void
    ) {
        Task {
            do {
                let value = try await request(endpoint, responseType: responseType)
                await MainActor.run { completion(.success(value)) }
            } catch let error as PayOrcError {
                await MainActor.run { completion(.failure(error)) }
            } catch {
                await MainActor.run { completion(.failure(.requestFailed(underlying: error))) }
            }
        }
    }

    // MARK: - Internal: Retry Logic

    private func performWithRetry<T: Decodable>(
        urlRequest: URLRequest,
        responseType: T.Type,
        attempt: Int = 0
    ) async throws -> T {
        let startTime = Date()

        do {
            let (data, response) = try await session.data(for: urlRequest)
            let duration = Date().timeIntervalSince(startTime)

            NetworkLogger.logRequest(urlRequest)
            NetworkLogger.logResponse(response, data: data, error: nil, duration: duration)

            guard let http = response as? HTTPURLResponse else {
                throw PayOrcError.unexpectedResponse
            }

            // Map HTTP error status codes
            if !(200..<300).contains(http.statusCode) {
                throw mapHTTPError(statusCode: http.statusCode, data: data)
            }

            // Decode
            do {
                #if DEBUG
                if let rawStr = String(data: data, encoding: .utf8) {
                    print("[PayOrc APIClient] Raw response body: \(rawStr.prefix(1000))")
                }
                #endif
                return try decoder.decode(T.self, from: data)
            } catch {
                #if DEBUG
                print("[PayOrc APIClient] Decoding failed: \(error)")
                #endif
                throw PayOrcError.decodingFailed(error.localizedDescription)
            }

        } catch let error as PayOrcError {
            // Retry transient PayOrc errors
            if error.isRetryable && attempt < Self.maxRetryCount {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                return try await performWithRetry(
                    urlRequest: urlRequest,
                    responseType: responseType,
                    attempt: attempt + 1
                )
            }
            throw error

        } catch let urlError as URLError {
            let duration = Date().timeIntervalSince(startTime)
            NetworkLogger.logResponse(nil, data: nil, error: urlError, duration: duration)

            let payOrcError = mapURLError(urlError)
            if payOrcError.isRetryable && attempt < Self.maxRetryCount {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                return try await performWithRetry(
                    urlRequest: urlRequest,
                    responseType: responseType,
                    attempt: attempt + 1
                )
            }
            throw payOrcError

        } catch {
            throw PayOrcError.requestFailed(underlying: error)
        }
    }

    // MARK: - Error Mapping

    private func mapHTTPError(statusCode: Int, data: Data) -> PayOrcError {
        // Try to extract server message from JSON body
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let serverMessage = body?["message"] as? String
        let serverCode    = body?["code"] as? String ?? "\(statusCode)"

        switch statusCode {
        case 401, 403:
            return .unauthorized
        case 400..<500:
            return .apiFailure(code: serverCode, message: serverMessage ?? "Bad request.")
        case 500..<600:
            return .serverError(statusCode: statusCode, message: serverMessage)
        default:
            return .unexpectedResponse
        }
    }

    private func mapURLError(_ error: URLError) -> PayOrcError {
        switch error.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .dataNotAllowed,
             .internationalRoamingOff:
            return .noInternetConnection
        case .timedOut:
            return .timeout
        default:
            return .requestFailed(underlying: error)
        }
    }
}
