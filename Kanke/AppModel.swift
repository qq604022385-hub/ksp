import Foundation
import Combine
import KankeCore

@MainActor
final class AppModel: ObservableObject {
    let api = APIClient()
    @Published var categories: [Category] = []
    @Published var category = "tvplay"
    @Published var searchText = ""
    @Published var search = ""
    @Published var videos: [VideoSummary] = []
    @Published var loading = false
    @Published var error: String?
    @Published var page = 0
    @Published var totalPages = 1
    private var generation = UUID()
    var requestKey: String { category + "|" + search }

    func loadCategories() async {
        do { categories = try await api.categories() }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    func submitSearch() { search = searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    func load(reset: Bool) async {
        if !reset && (loading || page >= totalPages) { return }
        let token = UUID()
        generation = token; loading = true; error = nil
        let next = reset ? 1 : page + 1
        defer { if token == generation { loading = false } }
        do {
            let result = try await api.catalog(category: category, page: next, search: search)
            guard token == generation, !Task.isCancelled else { return }
            if reset { videos = [] }
            var seen = Set(videos.map(\.id))
            videos += result.videos.filter { seen.insert($0.id).inserted }
            page = next; totalPages = result.totalPages
        } catch { if token == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }
    func reconnect() async {
        await api.reconnect()
        await loadCategories()
        await load(reset: true)
    }
}

struct PlaybackRecord: Codable, Identifiable {
    var id: String { video.id }
    var video: VideoSummary
    var source: String
    var episode: Int
    var episodeTitle: String
    var position: Double
    var duration: Double
    var updated: Date
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var favorites: [VideoSummary] = []
    @Published private(set) var history: [PlaybackRecord] = []
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "kanke.favorites"), let saved = try? JSONDecoder().decode([VideoSummary].self, from: data) { favorites = saved }
        if let data = defaults.data(forKey: "kanke.history"), let saved = try? JSONDecoder().decode([PlaybackRecord].self, from: data) { history = saved }
    }
    func contains(_ id: String) -> Bool { favorites.contains { $0.id == id } }
    func toggle(_ video: VideoSummary) {
        if contains(video.id) { favorites.removeAll { $0.id == video.id } }
        else { favorites.insert(video, at: 0); favorites = Array(favorites.prefix(500)) }
        persist()
    }
    func record(_ video: VideoSummary, source: String, episode: Int, title: String, position: Double, duration: Double) {
        guard position.isFinite, duration.isFinite, position >= 0 else { return }
        history.removeAll { $0.video.id == video.id }
        history.insert(PlaybackRecord(video: video, source: source, episode: episode, episodeTitle: title,
            position: position, duration: max(0, duration), updated: Date()), at: 0)
        history = Array(history.prefix(100)); persist()
    }
    func removeHistory(_ id: String) { history.removeAll { $0.id == id }; persist() }
    func clearHistory() { history = []; persist() }
    private func persist() {
        if let data = try? JSONEncoder().encode(favorites) { defaults.set(data, forKey: "kanke.favorites") }
        if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: "kanke.history") }
    }
}
