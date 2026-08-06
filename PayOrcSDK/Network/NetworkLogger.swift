import Foundation

// MARK: - NetworkLogger

/// Debug-only logger that prints formatted request/response summaries.
/// Compiled out entirely in Release builds (`#if DEBUG` guard).
enum NetworkLogger {

    // MARK: - Request

    static func logRequest(_ request: URLRequest) {
        #if DEBUG
        let method = request.httpMethod ?? "?"
        let url    = request.url?.absoluteString ?? "?"

        var log = """
        ╔══ [PayOrc ▶ Request] ══════════════════════════════╗
          \(method) \(url)
        """

        if let headers = request.allHTTPHeaderFields {
            let hiddenHeaderNames = ["merchant-secret", "X-Signature"]
            let safe = headers.filter { !hiddenHeaderNames.contains($0.key) }
            let hidden = headers.keys.filter { hiddenHeaderNames.contains($0) }.sorted()

            log += "\n  Headers: \(safe)"
            if !hidden.isEmpty {
                log += "\n  Hidden headers present: \(hidden)"
            }
        }

        if let body = request.httpBody,
           let json = try? JSONSerialization.jsonObject(with: body),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let str = String(data: pretty, encoding: .utf8) {
            log += "\n  Body:\n\(str.components(separatedBy: "\\n").map { "    \($0)" }.joined(separator: "\\n"))"
            log += "\n  Curl:\n    \(curlCommand(for: request, bodyString: str))"
        }

        log += "\n╚════════════════════════════════════════════════════╝"
        print(log)
        #endif
    }

    private static func curlCommand(for request: URLRequest, bodyString: String) -> String {
        let url = request.url?.absoluteString ?? ""
        var components = ["curl -X \(request.httpMethod ?? "GET") '", url, "' "]

        if let headers = request.allHTTPHeaderFields {
            for (name, value) in headers.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) {
                let escapedValue = value.replacingOccurrences(of: "'", with: "'\\''")
                components.append("-H '")
                components.append(name)
                components.append(": ")
                components.append(escapedValue)
                components.append("' ")
            }
        }

        let escapedBody = bodyString.replacingOccurrences(of: "'", with: "'\\''")
        components.append("--data-raw '")
        components.append(escapedBody)
        components.append("'")

        return components.joined()
    }

    // MARK: - Response

    static func logResponse(
        _ response: URLResponse?,
        data: Data?,
        error: Error?,
        duration: TimeInterval
    ) {
        #if DEBUG
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let url    = response?.url?.absoluteString ?? "?"

        var log = """
        ╔══ [PayOrc ◀ Response] ═════════════════════════════╗
          \(status) \(url)  (\(String(format: "%.2f", duration))s)
        """

        if let data = data,
           let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let str = String(data: pretty, encoding: .utf8) {
            log += "\n  Body:\n\(str.components(separatedBy: "\n").map { "    \($0)" }.joined(separator: "\n"))"
        }

        if let error {
            log += "\n  Error: \(error.localizedDescription)"
        }

        log += "\n╚════════════════════════════════════════════════════╝"
        print(log)
        #endif
    }
}
