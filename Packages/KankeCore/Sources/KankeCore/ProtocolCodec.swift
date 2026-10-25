import Foundation

public enum ClientError: LocalizedError {
    case invalidResponse(String)
    case server(String)
    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let message), .server(let message): return message
        }
    }
}

/// Wire compatibility with com.shenma.tvlauncher.utils.g from the supplied APK.
/// RC4 is required by this legacy service; this is not transport encryption.
public enum ProtocolCodec {
    public static func crypt(_ input: Data, key: String) throws -> Data {
        let bytes = Array(key.utf8)
        guard !bytes.isEmpty else { throw ClientError.invalidResponse("接口密钥为空，请重新连接服务") }
        var s = Array(0...255), j = 0
        for i in 0...255 {
            j = (j + s[i] + Int(bytes[i % bytes.count])) & 255
            s.swapAt(i, j)
        }
        var i = 0
        j = 0
        var result = Data(capacity: input.count)
        for byte in input {
            i = (i + 1) & 255
            j = (j + s[i]) & 255
            s.swapAt(i, j)
            result.append(byte ^ UInt8(s[(s[i] + s[j]) & 255]))
        }
        return result
    }

    public static func unhex(_ text: String) throws -> Data {
        let bytes = Array(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard bytes.count % 2 == 0, !bytes.isEmpty else {
            throw ClientError.invalidResponse("接口返回的加密数据格式不正确")
        }
        func digit(_ c: UInt8) -> UInt8? {
            switch c { case 48...57: return c-48; case 65...70: return c-55; case 97...102: return c-87; default: return nil }
        }
        var result = Data(capacity: bytes.count/2)
        for i in stride(from: 0, to: bytes.count, by: 2) {
            guard let a = digit(bytes[i]), let b = digit(bytes[i+1]) else {
                throw ClientError.invalidResponse("接口返回的加密数据不是十六进制")
            }
            result.append((a << 4) | b)
        }
        return result
    }

    public static func encrypt(_ text: String, key: String) throws -> String {
        try crypt(Data(text.utf8), key: key).map { String(format: "%02x", $0) }.joined()
    }

    public static func jsonData(_ data: Data, key: String) throws -> Data {
        guard var text = String(data: data, encoding: .utf8) else {
            throw ClientError.invalidResponse("接口返回了无法识别的文字编码")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}")))
        if text.hasPrefix("{") || text.hasPrefix("[") { return Data(text.utf8) }
        return try crypt(unhex(text), key: key)
    }

    /// java.net.URLEncoder compatible, including spaces as '+' before RC4.
    public static func formEncode(_ text: String) -> String {
        text.utf8.map { c -> String in
            switch c {
            case 65...90, 97...122, 48...57, 45, 46, 95, 42: return String(UnicodeScalar(c))
            case 32: return "+"
            default: return String(format: "%%%02X", c)
            }
        }.joined()
    }

    public static func endpoint(_ base: URL, path: String, query: [(String, String)] = []) throws -> URL {
        guard var parts = URLComponents(url: base, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), parts.host != nil else {
            throw ClientError.invalidResponse("服务器地址无效")
        }
        parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        parts.path = "/" + ([parts.path, path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))]
            .filter { !$0.isEmpty }.joined(separator: "/"))
        if path.hasSuffix("/") && !parts.path.hasSuffix("/") { parts.path += "/" }
        // Escape '+' as well, so base64 descriptors survive PHP query decoding.
        parts.percentEncodedQuery = query.isEmpty ? nil : query.map {
            formEncode($0.0).replacingOccurrences(of: "+", with: "%20") + "=" +
            formEncode($0.1).replacingOccurrences(of: "+", with: "%20")
        }.joined(separator: "&")
        guard let url = parts.url else { throw ClientError.invalidResponse("无法生成接口地址") }
        return url
    }

    public static func playbackPayload(account: String, password: String, title: String, episode: String) -> String {
        "&account=\(account)&password=\(password)&series=\(formEncode(title + "-" + episode))&edition=2.9"
    }
}
