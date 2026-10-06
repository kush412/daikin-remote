import DaikinCore
import Foundation

enum TimerSlot: String, Identifiable, CaseIterable {
    case on, off
    var id: String { rawValue }
    var power: Bool { self == .on }
}

struct BridgeInfo: Decodable {
    struct Timers: Decodable {
        let on: Int
        let off: Int
    }

    let device: String
    let version: Int
    let timers: Timers

    /// Seconds until the slot fires, or nil if not armed.
    func remaining(_ slot: TimerSlot) -> Int? {
        let s = slot == .on ? timers.on : timers.off
        return s < 0 ? nil : s
    }
}

struct BridgeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// HTTP client for the ESP32/ESP8266 IR bridge (firmware/daikin-ir-bridge).
struct BridgeClient {
    let host: String

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    func info() async throws -> BridgeInfo {
        let data = try await request("GET", "/info")
        do {
            return try JSONDecoder().decode(BridgeInfo.self, from: data)
        } catch {
            throw BridgeError(message: "\(host) answered, but it isn't a Daikin IR bridge.")
        }
    }

    func send(_ frame: IrFrame) async throws {
        _ = try await request("POST", "/send", body: Self.body(frame))
    }

    func setTimer(_ slot: TimerSlot, inSeconds seconds: Int, frame: IrFrame) async throws {
        _ = try await request("POST", "/timer/\(slot.rawValue)", query: [URLQueryItem(name: "in", value: String(seconds))],
                              body: Self.body(frame))
    }

    func cancelTimer(_ slot: TimerSlot) async throws {
        _ = try await request("DELETE", "/timer/\(slot.rawValue)")
    }

    private static func body(_ frame: IrFrame) -> String {
        ([frame.frequencyHz] + frame.pattern).map(String.init).joined(separator: " ")
    }

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: String? = nil) async throws -> Data {
        guard let url = makeURL(path, query) else {
            throw BridgeError(message: "“\(host)” isn't a valid host name or IP address.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.httpBody = Data(body.utf8)
            req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: req)
        } catch {
            throw BridgeError(message: "Can't reach the bridge at \(host). Is it powered and on the same Wi-Fi?")
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw BridgeError(message: "Bridge error \(http.statusCode): \(text)")
        }
        return data
    }

    /// Accepts "name.local", "192.168.1.20" or "host:port".
    private func makeURL(_ path: String, _ query: [URLQueryItem]) -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var c = URLComponents(string: "http://\(trimmed)") else { return nil }
        guard c.host?.isEmpty == false else { return nil }
        c.path = path
        c.queryItems = query.isEmpty ? nil : query
        return c.url
    }
}
