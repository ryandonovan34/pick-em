import Foundation
import OSLog

/// Logs every outgoing request and incoming response to the Xcode console.
///
/// To filter in Xcode: type "Network" in the console filter bar, or
/// in Console.app filter by subsystem "com.pickem" + category "Network".
///
/// Format:
///   → POST /auth/login  (authenticated)
///   ← 200 POST /auth/login  (143ms)
///   { ... pretty JSON ... }
enum NetworkLogger {
    private static let logger = Logger(subsystem: "com.pickem", category: "Network")

    static func logRequest(_ request: URLRequest) {
        let method = request.httpMethod ?? "?"
        let path = request.url?.path() ?? request.url?.absoluteString ?? "?"
        let auth = request.value(forHTTPHeaderField: "Authorization") != nil ? "  🔑" : ""
        var output = "→ \(method) \(path)\(auth)"

        if let body = request.httpBody, let pretty = prettyJSON(body) {
            output += "\n\(pretty)"
        }

        logger.debug("\(output)")
    }

    static func logResponse(_ response: HTTPURLResponse, data: Data, duration: TimeInterval, for request: URLRequest) {
        let method = request.httpMethod ?? "?"
        let path = request.url?.path() ?? request.url?.absoluteString ?? "?"
        let ms = Int(duration * 1000)
        let status = response.statusCode
        var output = "← \(status) \(method) \(path)  (\(ms)ms)"

        if let cacheStatus = response.value(forHTTPHeaderField: "X-Cache") {
            output += "  [odds-cache: \(cacheStatus)]"
        }

        if let pretty = prettyJSON(data) {
            output += "\n\(pretty)"
        } else if !data.isEmpty, let raw = String(data: data, encoding: .utf8) {
            output += "\n\(raw)"
        }

        if status >= 400 {
            logger.error("\(output)")
        } else {
            logger.debug("\(output)")
        }
    }

    static func logCache(hit: Bool, for key: String) {
        let icon = hit ? "💾" : "🌐"
        let status = hit ? "HIT" : "MISS"
        logger.debug("\(icon) Local cache \(status): \(key)")
    }

    private static func prettyJSON(_ data: Data) -> String? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8) else { return nil }
        return string
    }
}
