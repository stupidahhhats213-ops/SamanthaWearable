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
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
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
