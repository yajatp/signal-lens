import Foundation

/// Thin async client for the Signal Lens FastAPI backend.
/// Base URL is user-configurable (Settings tab) — defaults to localhost for simulator use.
struct APIClient {
    static var baseURL: URL {
        let raw = UserDefaults.standard.string(forKey: "backendURL") ?? "http://127.0.0.1:8000"
        return URL(string: raw) ?? URL(string: "http://127.0.0.1:8000")!
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFraction = ISO8601DateFormatter()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = iso.date(from: s) ?? isoNoFraction.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "Bad date: \(s)"))
        }
        return d
    }()

    static func predict(lat: Double, lon: Double) async throws -> Prediction {
        var comps = URLComponents(url: baseURL.appendingPathComponent("predict"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lon)),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        return try decoder.decode(Prediction.self, from: data)
    }

    static func towers(lat: Double, lon: Double, limit: Int = 50) async throws -> [Tower] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("towers"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lon)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        return try decoder.decode([Tower].self, from: data)
    }

    @discardableResult
    static func submitMeasurement(_ m: MeasurementIn) async throws -> MeasurementOut {
        var req = URLRequest(url: baseURL.appendingPathComponent("measurements"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(m)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try decoder.decode(MeasurementOut.self, from: data)
    }
}
