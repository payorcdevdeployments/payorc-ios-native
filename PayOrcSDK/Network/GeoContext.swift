import Foundation

// MARK: - GeoContext

/// Fetches and caches the device's public IP and country code.
///
/// Mirrors Flutter's `PayorcGeoContext` — used to populate `X-IP` and
/// `X-IP-COUNTRY` headers on every signed PayOrc request.
///
/// - `ip`          → `X-IP`          (from ipify, fallback `"127.0.0.1"`)
/// - `countryCode` → `X-IP-COUNTRY`  (from device locale, fallback `"ZZ"`)
final class GeoContext {

    // MARK: - Shared state

    /// Cached public IP address string. `nil` until first ``refresh()`` completes.
    private(set) static var ip: String?

    /// Cached ISO 3166-1 alpha-2 country code. Resolved from locale on every refresh.
    private(set) static var countryCode: String?

    // MARK: - Effective header values (mirrors Flutter helpers)

    /// Effective `X-IP` header value — cached IP → `"127.0.0.1"`.
    static var effectiveIP: String {
        let v = ip?.trimmingCharacters(in: .whitespaces) ?? ""
        return v.isEmpty ? "127.0.0.1" : v
    }

    /// Effective `X-IP-COUNTRY` header value — cached code → locale code → `"ZZ"`.
    static var effectiveCountry: String {
        if let cached = countryCode?.trimmingCharacters(in: .whitespaces), !cached.isEmpty {
            return cached.uppercased()
        }
        if let locale = Locale.current.regionCode?.trimmingCharacters(in: .whitespaces),
           !locale.isEmpty {
            return locale.uppercased()
        }
        return "ZZ"
    }

    // MARK: - Refresh

    /// Resolves the public IP from `https://api.ipify.org` (non-blocking, best-effort).
    /// Country is read from the device locale. Both values are cached for the session.
    static func refresh() async {
        // Country from locale (instant, no network)
        countryCode = Locale.current.regionCode

        // IP from ipify (network, best-effort — failure is silently swallowed)
        do {
            guard let url = URL(string: "https://api.ipify.org?format=json") else { return }
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ipVal = json["ip"] as? String, !ipVal.isEmpty {
                ip = ipVal
            }
        } catch {
            // Non-fatal — fallback "127.0.0.1" is used automatically
            #if DEBUG
            print("[PayOrc] GeoContext.refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Manual override

    static func set(ip newIP: String?, countryCode newCode: String?) {
        if let v = newIP, !v.isEmpty { ip = v }
        if let v = newCode, !v.isEmpty { countryCode = v.uppercased() }
    }
}
