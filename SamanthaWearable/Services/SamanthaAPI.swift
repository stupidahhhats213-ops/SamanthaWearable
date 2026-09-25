// Services/SamanthaAPI.swift
import Foundation

enum SamanthaAPIError: LocalizedError {
    case invalidURL(String)
    case httpStatus(Int, String?)
    case decoding(Error)
    case transport(Error)
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let raw):
            return "Invalid server URL: \(raw)"
        case .httpStatus(let code, let body):
            if let body, !body.isEmpty { return "HTTP \(code): \(body)" }
            return "HTTP \(code)"
        case .decoding(let err):
            return "Decode error: \(err.localizedDescription)"
        case .transport(let err):
            return err.localizedDescription
        case .serverMessage(let msg):
            return msg
        }
    }
}

actor SamanthaAPI {
    private var baseURLString: String
    private var authEnabled: Bool
    private var apiToken: String
    private let session: URLSession

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    init(baseURL: String, authEnabled: Bool = false, apiToken: String = "") {
        self.baseURLString = baseURL
        self.authEnabled = authEnabled
        self.apiToken = apiToken
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    func update(baseURL: String, authEnabled: Bool, apiToken: String) {
        self.baseURLString = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.authEnabled = authEnabled
        self.apiToken = apiToken
    }

    func health() async throws -> (ServerHealth, Double) {
        let (data, ms) = try await get(path: "/health")
        do {
            let decoded = try decoder.decode(ServerHealth.self, from: data)
            return (decoded, ms)
        } catch {
            throw SamanthaAPIError.decoding(error)
        }
    }

    func wearableHealth() async throws -> WearableHealth {
        let (data, _) = try await get(path: "/api/wearable/health")
        do {
            return try decoder.decode(WearableHealth.self, from: data)
        } catch {
            throw SamanthaAPIError.decoding(error)
        }
    }

    func register(_ payload: DeviceRegistration) async throws -> RegistrationResponse {
        let body = try encoder.encode(payload)
        let (data, _) = try await post(path: "/api/wearable/register", body: body)
        do {
            let decoded = try decoder.decode(RegistrationResponse.self, from: data)
            if decoded.ok == false {
                throw SamanthaAPIError.serverMessage(decoded.error ?? "registration failed")
            }
            return decoded
        } catch let err as SamanthaAPIError {
            throw err
        } catch {
            throw SamanthaAPIError.decoding(error)
        }
    }

    func sendHeartbeat(_ payload: HeartbeatPayload) async throws -> HeartbeatResponse {
        let body = try encoder.encode(payload)
        let (data, _) = try await post(path: "/api/wearable/heartbeat", body: body)
        do {
            let decoded = try decoder.decode(HeartbeatResponse.self, from: data)
            if decoded.ok == false {
                throw SamanthaAPIError.serverMessage(decoded.error ?? "heartbeat failed")
            }
            return decoded
        } catch let err as SamanthaAPIError {
            throw err
        } catch {
            throw SamanthaAPIError.decoding(error)
        }
    }

    func sendCommand(deviceID: String, sessionID: String, text: String) async throws -> WearableCommandResponse {
        let payload = WearableCommandRequest(
            deviceId: deviceID,
            sessionId: sessionID,
            source: "meta_glasses",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            text: text
        )
        var req = authorizedRequest(url: try makeURL(path: "/api/wearable/command"), method: "POST", body: try encoder.encode(payload))
        req.timeoutInterval = 20
        let (data, ms) = try await perform(req)
        var decoded = try decoder.decode(WearableCommandResponse.self, from: data)
        decoded.latencyMs = ms
        return decoded
    }

    func fetchAudio(path: String) async throws -> WearableAudio {
        var req = authorizedRequest(url: try makeURL(path: path), method: "GET")
        req.timeoutInterval = 50
        req.setValue("audio/wav", forHTTPHeaderField: "Accept")
        let started = Date()
        let (data, response) = try await session.data(for: req)
        let ms = Date().timeIntervalSince(started) * 1000.0
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SamanthaAPIError.httpStatus(code, "tts audio")
        }
        guard data.count > 44 else {
            throw SamanthaAPIError.serverMessage("tts audio too small")
        }
        func header(_ name: String) -> String? {
            http.value(forHTTPHeaderField: name)
        }
        return WearableAudio(
            data: data,
            downloadMs: ms,
            synthesisMs: Double(header("X-Samantha-Synthesis-Ms") ?? ""),
            audioSec: Double(header("X-Samantha-Audio-Sec") ?? ""),
            rtf: Double(header("X-Samantha-RTF") ?? ""),
            sampleRate: Int(header("X-Samantha-Sample-Rate") ?? "")
        )
    }

    func disconnect(deviceID: String) async throws {
        let body = try encoder.encode(DisconnectRequest(deviceId: deviceID))
        let (data, _) = try await post(path: "/api/wearable/disconnect", body: body)
        if let decoded = try? decoder.decode(DisconnectResponse.self, from: data),
           decoded.ok == false {
            throw SamanthaAPIError.serverMessage(decoded.error ?? "disconnect failed")
        }
    }

    // MARK: - HTTP

    private func makeURL(path: String) throws -> URL {
        let base = baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path) else {
            throw SamanthaAPIError.invalidURL(base + path)
        }
        return url
    }

    private func authorizedRequest(url: URL, method: String, body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if authEnabled {
            let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }
        req.httpBody = body
        return req
    }

    private func get(path: String) async throws -> (Data, Double) {
        let url = try makeURL(path: path)
        let req = authorizedRequest(url: url, method: "GET")
        return try await perform(req)
    }

    private func post(path: String, body: Data) async throws -> (Data, Double) {
        let url = try makeURL(path: path)
        let req = authorizedRequest(url: url, method: "POST", body: body)
        return try await perform(req)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, Double) {
        let started = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let ms = Date().timeIntervalSince(started) * 1000.0
            guard let http = response as? HTTPURLResponse else {
                throw SamanthaAPIError.httpStatus(-1, "non-HTTP response")
            }
            #if DEBUG
            let path = request.url?.path ?? "?"
            print("[SamanthaAPI] \(request.httpMethod ?? "?") \(path) -> \(http.statusCode) (\(Int(ms)) ms)")
            #endif
            guard (200...299).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8)
                throw SamanthaAPIError.httpStatus(http.statusCode, text)
            }
            return (data, ms)
        } catch let err as SamanthaAPIError {
            throw err
        } catch {
            throw SamanthaAPIError.transport(error)
        }
    }
}

struct WearableCommandRequest: Encodable {
    let deviceId: String
    let sessionId: String
    let source: String
    let timestamp: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case sessionId = "session_id"
        case source, timestamp, text
    }
}

struct WearableTTS: Decodable {
    let engine: String
    let audioURL: String
    let fallback: String
    let gpu: Int?
    let voice: String?

    enum CodingKeys: String, CodingKey {
        case engine
        case audioURL = "audio_url"
        case fallback, gpu, voice
    }
}

struct WearableAudio {
    let data: Data
    let downloadMs: Double
    let synthesisMs: Double?
    let audioSec: Double?
    let rtf: Double?
    let sampleRate: Int?
}

struct WearableCommandResponse: Decodable {
    let ok: Bool
    let reply: String
    let intent: String
    let actionTaken: String?
    let speak: Bool
    let needsConfirmation: Bool
    let tts: WearableTTS?
    var latencyMs: Double

    struct DataBox: Decodable {
        let needsConfirmation: Bool?
        enum CodingKeys: String, CodingKey {
            case needsConfirmation = "needs_confirmation"
        }
    }

    enum CodingKeys: String, CodingKey {
        case ok, reply, intent, speak, data, tts
        case actionTaken = "action_taken"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        reply = try container.decodeIfPresent(String.self, forKey: .reply) ?? ""
        intent = try container.decodeIfPresent(String.self, forKey: .intent) ?? ""
        actionTaken = try container.decodeIfPresent(String.self, forKey: .actionTaken)
        speak = try container.decodeIfPresent(Bool.self, forKey: .speak) ?? true
        needsConfirmation = (try container.decodeIfPresent(DataBox.self, forKey: .data))?.needsConfirmation ?? false
        tts = try container.decodeIfPresent(WearableTTS.self, forKey: .tts)
        latencyMs = 0
    }
}
