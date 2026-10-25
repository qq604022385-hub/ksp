import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ServiceConfiguration: Sendable {
    public let contentBase: URL
    public let resolverBase: URL
    public let responseKey: String
    public let requestKey: String
    public let account: String
    public let password: String
}

public actor APIClient {
    public static let defaultBootstrap = URL(string: "https://app-1361125462.cos.ap-guangzhou.myqcloud.com/azapp2.json")!
    private let session: URLSession
    private let bootstrap: URL
    private var cached: ServiceConfiguration?
    private var connection: Task<ServiceConfiguration, Error>?
    public init(bootstrap: URL = APIClient.defaultBootstrap, session: URLSession = .shared) {
        self.bootstrap = bootstrap; self.session = session
    }
    public func reconnect() { cached = nil; connection?.cancel(); connection = nil }

    public func configuration() async throws -> ServiceConfiguration {
        if let cached { return cached }
        if let connection { return try await connection.value }
        let task = Task { try await self.bootstrapConfiguration() }
        connection = task
        do {
            let value = try await task.value
            cached = value; connection = nil
            return value
        } catch { connection = nil; throw error }
    }

    private func bootstrapConfiguration() async throws -> ServiceConfiguration {
        let data = try await request(URLRequest(url: bootstrap))
        guard let address = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty,
              let base = URL(string: address.contains("://") ? address : "http://"+address), base.host != nil else {
            throw ClientError.invalidResponse("无法获取服务器地址，请稍后重试")
        }
        let configURL = try ProtocolCodec.endpoint(base, path: "extend/api/set.php", query: [("type", "set")])
        let configData = try await request(URLRequest(url: configURL))
        struct Settings: Decodable {
            struct Value: Decodable { let pgdz: String; let miyao: String; let rck: String; let rgdz: String }
            let code: Int; let data: Value
        }
        let settings = try JSONDecoder().decode(Settings.self, from: configData)
        guard settings.code == 200, let content = URL(string: settings.data.pgdz), content.host != nil,
              !settings.data.miyao.isEmpty, !settings.data.rck.isEmpty else {
            throw ClientError.invalidResponse("服务器配置不完整")
        }
        let credentials = settings.data.rgdz.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard credentials.count == 2 else { throw ClientError.invalidResponse("服务器未提供客户端访问配置") }
        return ServiceConfiguration(contentBase: content, resolverBase: base, responseKey: settings.data.miyao,
            requestKey: settings.data.rck, account: String(credentials[0]), password: String(credentials[1]))
    }

    private func request(_ input: URLRequest) async throws -> Data {
        var request = input
        request.timeoutInterval = 25
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ClientError.server("服务器请求失败（\((response as? HTTPURLResponse)?.statusCode ?? 0)），请重试")
        }
        guard data.count <= 8_000_000 else { throw ClientError.invalidResponse("接口返回内容过大") }
        return data
    }

    public func categories() async throws -> [VideoCategory] {
        let config = try await configuration()
        let url = try ProtocolCodec.endpoint(config.contentBase, path: "api.php/localhost/Category")
        let body = try await request(URLRequest(url: url))
        return try JSONDecoder().decode([VideoCategory].self, from: ProtocolCodec.jsonData(body, key: config.responseKey)).filter { $0.enabled }
    }

    public func catalog(category: String, page: Int = 1, search: String = "") async throws -> CatalogPage {
        let config = try await configuration()
        let path = search.isEmpty ? "api.php/localhost/vod/" : "api.php/localhost/So/"
        var query = [("ac", "list"), ("page", String(page))]
        query.append(search.isEmpty ? ("class", category) : ("zm", search))
        let url = try ProtocolCodec.endpoint(config.contentBase, path: path, query: query)
        let body = try await request(URLRequest(url: url))
        return try JSONDecoder().decode(CatalogPage.self, from: ProtocolCodec.jsonData(body, key: config.responseKey))
    }

    public func detail(id: String) async throws -> (VideoDetail, [VideoSource]) {
        let config = try await configuration()
        let url = try ProtocolCodec.endpoint(config.contentBase, path: "api.php/localhost/vod/", query: [("ac", "detail"), ("ids", id)])
        let body = try await request(URLRequest(url: url))
        let detail = try JSONDecoder().decode(VideoDetail.self, from: ProtocolCodec.jsonData(body, key: config.responseKey))
        return (detail, try detail.sources(key: config.responseKey))
    }

    public func resolve(title: String, episode: Episode, client: Int = 0) async throws -> PlaybackResponse {
        let config = try await configuration()
        let path = "Client" + (client == 0 ? "" : String(client)) + "/"
        let url = try ProtocolCodec.endpoint(config.resolverBase, path: path, query: [("url", episode.url)])
        let payload = ProtocolCodec.playbackPayload(account: config.account, password: config.password, title: title, episode: episode.title)
        let key = try ProtocolCodec.encrypt(payload, key: config.requestKey)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("app=10000&key=\(ProtocolCodec.formEncode(key))".utf8)
        let data = try await request(req)
        return try JSONDecoder().decode(PlaybackResponse.self, from: ProtocolCodec.jsonData(data, key: config.responseKey))
    }
}
