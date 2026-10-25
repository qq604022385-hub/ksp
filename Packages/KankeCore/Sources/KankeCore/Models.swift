import Foundation

extension KeyedDecodingContainer {
    func text(_ key: Key, default fallback: String = "") -> String {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        return fallback
    }
    func number(_ key: Key, default fallback: Int = 0) -> Int {
        if let value = try? decode(Int.self, forKey: key) { return value }
        return Int(text(key)) ?? fallback
    }
    func texts(_ key: Key) -> [String] {
        if let values = try? decode([String].self, forKey: key) { return values.filter { !$0.isEmpty } }
        return text(key).split(separator: ",").map(String.init)
    }
}

public struct VideoSummary: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var picture: String
    public var subtitle: String
    public var kind: String
    public var score: String
    public init(id: String, title: String, picture: String = "", subtitle: String = "", kind: String = "", score: String = "") {
        self.id = id; self.title = title; self.picture = picture; self.subtitle = subtitle; self.kind = kind; self.score = score
    }
    enum CodingKeys: String, CodingKey { case id, title, picture, subtitle, kind, score, pic, nextlink, state, type, tjinfo, tjpicurl, tjtype }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.text(.id)
        if id.isEmpty {
            let link = c.text(.nextlink)
            id = URLComponents(string: "https://placeholder.invalid/"+link)?.queryItems?.first(where: { $0.name == "ids" })?.value ?? ""
        }
        guard !id.isEmpty else { throw ClientError.invalidResponse("片单缺少影片编号") }
        title = c.text(.title, default: c.text(.tjinfo))
        picture = c.text(.picture, default: c.text(.pic, default: c.text(.tjpicurl)))
        subtitle = c.text(.subtitle, default: c.text(.state))
        kind = c.text(.kind, default: c.text(.type, default: c.text(.tjtype)))
        score = c.text(.score)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(title, forKey: .title)
        try c.encode(picture, forKey: .picture); try c.encode(subtitle, forKey: .subtitle)
        try c.encode(kind, forKey: .kind); try c.encode(score, forKey: .score)
    }
}

public struct Category: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let enabled: Bool
    enum CodingKeys: String, CodingKey { case type_en, type_name, type_status }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.text(.type_en); name = c.text(.type_name); enabled = c.number(.type_status, default: 1) == 1
    }
}

public struct CatalogPage: Decodable, Sendable {
    public let videos: [VideoSummary]
    public let page: Int
    public let totalPages: Int
    enum CodingKeys: String, CodingKey { case code, msg, data, pageindex, totalpage }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let code = c.number(.code, default: 200)
        guard code == 200 else { throw ClientError.server(c.text(.msg, default: "片库暂时不可用")) }
        videos = try c.decodeIfPresent([VideoSummary].self, forKey: .data) ?? []
        page = c.number(.pageindex, default: 1); totalPages = c.number(.totalpage, default: 1)
    }
}

public struct Episode: Codable, Hashable, Sendable {
    public let title: String
    public let url: String
    public init(title: String, url: String) { self.title = title; self.url = url }
}

public struct VideoSource: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let episodes: [Episode]
    public init(id: String, name: String, episodes: [Episode]) { self.id = id; self.name = name; self.episodes = episodes }
}

public struct SourceMetadata: Decodable, Sendable {
    public let from: String
    public let show: String
    public let sort: String
}

public struct VideoDetail: Decodable, Sendable {
    public let summary: VideoSummary
    public let introduction: String
    public let actors: [String]
    public let directors: [String]
    public let genres: [String]
    public let year: String
    public let player: String
    public let episodes: [String: [Episode]]
    enum CodingKeys: String, CodingKey { case id, code, msg, title, img_url, trunk, intro, actor, director, type, pubtime, player, videolist }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.number(.code, default: 200) == 200 else { throw ClientError.server(c.text(.msg, default: "影片详情暂时不可用")) }
        summary = VideoSummary(id: c.text(.id), title: c.text(.title), picture: c.text(.img_url), subtitle: c.text(.trunk))
        introduction = c.text(.intro).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        actors = c.texts(.actor); directors = c.texts(.director); genres = c.texts(.type); year = c.text(.pubtime)
        player = c.text(.player); episodes = (try? c.decode([String: [Episode]].self, forKey: .videolist)) ?? [:]
    }
    public func sources(key: String) throws -> [VideoSource] {
        let data = try ProtocolCodec.jsonData(Data(player.utf8), key: key)
        let metadata = try JSONDecoder().decode([SourceMetadata].self, from: data)
        var result = [VideoSource](), seen = Set<String>()
        // Preserve server-defined source order and include source keys unknown to the old APK.
        for m in metadata {
            if let items = episodes[m.from], !items.isEmpty, seen.insert(m.from).inserted {
                result.append(VideoSource(id: m.from, name: m.show.isEmpty ? m.from : m.show, episodes: items))
            }
        }
        for from in episodes.keys.sorted() where !seen.contains(from) {
            if let items = episodes[from], !items.isEmpty { result.append(VideoSource(id: from, name: from, episodes: items)) }
        }
        return result
    }
}

public struct PlaybackResponse: Decodable, Sendable {
    public let url: URL
    public let headers: [String: String]
    public let client: Int
    public let maxClient: Int
    enum CodingKeys: String, CodingKey { case code, msg, url, UserAgent, Referer, Origin, Cookie, Client, maxClient }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.number(.code, default: 200) == 200 else { throw ClientError.server(c.text(.msg, default: "该播放源暂时不可用")) }
        guard let media = URL(string: c.text(.url)), ["http", "https"].contains(media.scheme?.lowercased() ?? "") else {
            throw ClientError.invalidResponse("该线路未返回可播放的视频地址，请切换线路")
        }
        url = media; client = c.number(.Client); maxClient = c.number(.maxClient)
        var fields = [String: String]()
        for (key, name) in [(CodingKeys.UserAgent, "User-Agent"), (.Referer, "Referer"), (.Origin, "Origin"), (.Cookie, "Cookie")] {
            let value = c.text(key)
            if !value.isEmpty && !value.contains("\r") && !value.contains("\n") { fields[name] = value }
        }
        headers = fields
    }
}
