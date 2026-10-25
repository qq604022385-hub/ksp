import XCTest
@testable import KankeCore

final class KankeCoreTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
    func testRC4PublishedVectorAndSymmetry() throws {
        let encoded = try ProtocolCodec.encrypt("Plaintext", key: "Key")
        XCTAssertEqual(encoded, "bbf316e8d940af0ad3")
        XCTAssertEqual(try ProtocolCodec.crypt(ProtocolCodec.unhex(encoded), key: "Key"), Data("Plaintext".utf8))
    }
    func testMalformedHexAndEmptyKeyFail() {
        for invalid in ["", "a", "gg", "12z4"] { XCTAssertThrowsError(try ProtocolCodec.unhex(invalid)) }
        XCTAssertThrowsError(try ProtocolCodec.encrypt("text", key: ""))
    }
    func testJavaFormEncoding() {
        XCTAssertEqual(ProtocolCodec.formEncode("中 文+&/*"), "%E4%B8%AD+%E6%96%87%2B%26%2F*")
        XCTAssertEqual(ProtocolCodec.playbackPayload(account: "demo", password: "test", title: "片 名", episode: "第1集"),
                       "&account=demo&password=test&series=%E7%89%87+%E5%90%8D-%E7%AC%AC1%E9%9B%86&edition=2.9")
    }
    func testEndpointPreservesSlashAndBase64Descriptor() throws {
        let base = try XCTUnwrap(URL(string: "http://example.com:9001/base/"))
        let value = "source-ab+c/de=="
        let url = try ProtocolCodec.endpoint(base, path: "Client/", query: [("url", value)])
        XCTAssertEqual(url.path, "/base/Client/")
        XCTAssertTrue(url.absoluteString.contains("%2B"))
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, value)
        XCTAssertThrowsError(try ProtocolCodec.endpoint(URL(string: "file:///tmp")!, path: "Client/"))
    }
    func testPlainAndEncryptedCatalogsUseSameModels() throws {
        let plain = try fixture("catalog")
        let encrypted = try ProtocolCodec.encrypt(String(decoding: plain, as: UTF8.self), key: "fixture-key")
        for data in [plain, Data(encrypted.utf8)] {
            let page = try JSONDecoder().decode(CatalogPage.self, from: ProtocolCodec.jsonData(data, key: "fixture-key"))
            XCTAssertEqual(page.videos.map(\.id), ["100", "101"])
            XCTAssertEqual(page.videos[0].score, "")
            XCTAssertEqual(page.videos[1].title, "示例影片二")
            XCTAssertEqual(page.totalPages, 3)
        }
    }
    func testSavedSummaryRoundTrip() throws {
        let original = VideoSummary(id: "42", title: "测试片名", picture: "https://example.com/p.jpg", subtitle: "更新中")
        XCTAssertEqual(try JSONDecoder().decode(VideoSummary.self, from: JSONEncoder().encode(original)), original)
    }
    func testDetailsPreserveSourceOrderAndIncludeUnknownSource() throws {
        let detail = try JSONDecoder().decode(VideoDetail.self, from: fixture("detail"))
        let sources = try detail.sources(key: "fixture-key")
        XCTAssertEqual(sources.map(\.id), ["sourceB", "sourceA", "newSource"])
        XCTAssertEqual(sources[0].episodes.count, 2)
        XCTAssertEqual(sources[1].episodes[0].url, "descriptor-a")
        XCTAssertEqual(detail.introduction, "简介文字")
        XCTAssertEqual(detail.actors, ["演员甲", "演员乙"])
    }
    func testPlaybackHeadersAndServerDenial() throws {
        let response = try JSONDecoder().decode(PlaybackResponse.self, from: fixture("playback"))
        XCTAssertEqual(response.url.scheme, "https")
        XCTAssertEqual(response.headers["User-Agent"], "ExamplePlayer/1.0")
        XCTAssertNil(response.headers["Cookie"])
        XCTAssertEqual(response.client, 1)
        XCTAssertThrowsError(try JSONDecoder().decode(PlaybackResponse.self, from: Data(#"{"code":403,"msg":"访问被拒绝"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(PlaybackResponse.self, from: Data(#"{"code":200,"url":"javascript:alert(1)"}"#.utf8)))
    }
    func testCategoryStatusAcceptsStringAndNumber() throws {
        let values = try JSONDecoder().decode([Category].self, from: fixture("categories"))
        XCTAssertEqual(values.filter(\.enabled).map(\.id), ["tvplay", "movie"])
    }
}
