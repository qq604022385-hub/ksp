import SwiftUI
import KankeCore

private let canvas = Color(red: 0.045, green: 0.055, blue: 0.085)

@MainActor struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { CatalogView() }.tabItem { Label("片库", systemImage: "play.rectangle.fill") }
            NavigationStack { SavedView(history: false) }.tabItem { Label("收藏", systemImage: "bookmark.fill") }
            NavigationStack { SavedView(history: true) }.tabItem { Label("历史", systemImage: "clock.fill") }
            NavigationStack { SettingsView() }.tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
    }
}

struct Poster: View {
    let video: VideoSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 13).fill(.white.opacity(0.07))
                AsyncImage(url: URL(string: video.picture)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "film").font(.largeTitle).foregroundStyle(.white.opacity(0.2))
                }
                if !video.subtitle.isEmpty {
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                    Text(video.subtitle).font(.caption2).lineLimit(1).padding(8).foregroundStyle(.white)
                }
            }
            .aspectRatio(0.70, contentMode: .fit).clipped().clipShape(RoundedRectangle(cornerRadius: 13))
            Text(video.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct ErrorNotice: View {
    let text: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.title2)
            Text(text).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("重新加载", action: retry).buttonStyle(.bordered)
        }.frame(maxWidth: .infinity).padding(24)
    }
}

@MainActor struct CatalogView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showing: VideoSummary?
    private let columns = [GridItem(.adaptive(minimum: 105, maximum: 170), spacing: 14)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("留一点时间，给好故事。").font(.title3.weight(.semibold))
                    Text(model.search.isEmpty ? "挑一部想看的，现在开始" : "搜索「\(model.search)」")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.horizontal)
                if model.search.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.categories) { category in
                                Button { model.category = category.id } label: {
                                    Text(category.name).font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 10)
                                        .background(model.category == category.id ? Color.accentColor.opacity(0.25) : .white.opacity(0.05), in: Capsule())
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal)
                    }
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(model.videos) { video in
                        Button { showing = video } label: { Poster(video: video) }.buttonStyle(.plain)
                    }
                }.padding(.horizontal)
                if model.loading { ProgressView("正在加载片库…").frame(maxWidth: .infinity).padding() }
                if let error = model.error { ErrorNotice(text: error) { Task { await model.load(reset: model.videos.isEmpty) } } }
                if !model.loading && model.error == nil && model.videos.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.largeTitle)
                        Text("没有找到相关内容").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(35)
                }
                if !model.videos.isEmpty && model.page < model.totalPages && !model.loading {
                    Button("加载更多") { Task { await model.load(reset: false) } }.frame(maxWidth: .infinity).padding()
                }
            }.padding(.vertical)
        }
        .background(canvas).navigationTitle("看客")
        .searchable(text: $model.searchText, prompt: "搜索影片、剧集")
        .onSubmit(of: .search) { model.submitSearch() }
        .onChange(of: model.searchText) { value in if value.isEmpty { model.search = "" } }
        .refreshable { await model.load(reset: true) }
        .task { await model.loadCategories() }
        .task(id: model.requestKey) { await model.load(reset: true) }
        .sheet(item: $showing) { video in NavigationStack { DetailView(video: video) } }
    }
}

@MainActor struct SavedView: View {
    let history: Bool
    @EnvironmentObject private var library: LibraryStore
    @State private var showing: VideoSummary?
    var body: some View {
        Group {
            if history ? library.history.isEmpty : library.favorites.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: history ? "clock" : "bookmark").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text(history ? "还没有观看记录" : "把想看的影片收藏在这里").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if history {
                        ForEach(library.history) { item in
                            Button { showing = item.video } label: {
                                SavedRow(video: item.video, note: "\(item.episodeTitle) · 看到 \(Int(item.position)/60) 分钟")
                            }.buttonStyle(.plain)
                            .swipeActions { Button("删除", role: .destructive) { library.removeHistory(item.id) } }
                        }
                    } else {
                        ForEach(library.favorites) { video in
                            Button { showing = video } label: { SavedRow(video: video, note: video.subtitle) }.buttonStyle(.plain)
                                .swipeActions { Button("取消收藏", role: .destructive) { library.toggle(video) } }
                        }
                    }
                }.scrollContentBackground(.hidden)
            }
        }.background(canvas).navigationTitle(history ? "观看历史" : "我的收藏")
            .sheet(item: $showing) { video in NavigationStack { DetailView(video: video) } }
    }
}

struct SavedRow: View {
    let video: VideoSummary
    let note: String
    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: video.picture)) { image in image.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.2) }
                .frame(width: 54, height: 76).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 7) {
                Text(video.title).font(.headline).lineLimit(2)
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
        }.padding(.vertical, 5)
    }
}

@MainActor struct DetailView: View {
    let video: VideoSummary
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playback = PlayerController()
    @State private var detail: VideoDetail?
    @State private var sources: [VideoSource] = []
    @State private var source = 0
    @State private var episode = 0
    @State private var loaded = false
    @State private var loading = false
    @State private var resolving = false
    @State private var error: String?
    @State private var revision = 0
    @AppStorage("kanke.autoplay") private var autoplay = true
    @AppStorage("kanke.speed") private var speed = 1.0
    private var selected: VideoSource? { sources.indices.contains(source) ? sources[source] : nil }
    private var playKey: String { "\(loaded)-\(source)-\(episode)-\(revision)" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZStack {
                    Color.black
                    NativePlayer(player: playback.player)
                    if resolving || playback.buffering { ProgressView("正在连接视频…").padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)) }
                }.aspectRatio(16/9, contentMode: .fit)
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(detail?.summary.title ?? video.title).font(.title2.bold())
                            Text([detail?.year ?? "", detail?.genres.joined(separator: " / ") ?? "", detail?.summary.subtitle ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { library.toggle(detail?.summary ?? video) } label: {
                            Image(systemName: library.contains(video.id) ? "bookmark.fill" : "bookmark").font(.title3).padding(9)
                        }.accessibilityLabel(library.contains(video.id) ? "取消收藏" : "收藏")
                    }
                    if let message = error ?? playback.error {
                        ErrorNotice(text: message) { if loaded { revision += 1 } else { Task { await load() } } }
                    }
                    if !sources.isEmpty {
                        HStack {
                            Text("播放线路").font(.headline)
                            Spacer()
                            Menu {
                                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                                    Button("\(rate, specifier: "%g")×") { speed = rate; playback.speed = Float(rate); if playback.player.rate != 0 { playback.player.rate = Float(rate) } }
                                }
                            } label: { Text("\(speed, specifier: "%g")×").font(.subheadline) }
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(sources.enumerated()), id: \.element.id) { index, item in
                                    Button { source = index; episode = min(episode, item.episodes.count-1) } label: {
                                        Text(item.name).font(.subheadline).padding(.horizontal, 15).padding(.vertical, 9)
                                            .background(index == source ? Color.accentColor.opacity(0.25) : .white.opacity(0.06), in: Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        HStack {
                            Text("选集").font(.headline)
                            Spacer()
                            Text("共 \(selected?.episodes.count ?? 0) 集").font(.caption).foregroundStyle(.secondary)
                            if let selected, episode+1 < selected.episodes.count { Button("下一集") { episode += 1 }.font(.subheadline) }
                        }
                        if let selected {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 9) {
                                ForEach(Array(selected.episodes.enumerated()), id: \.offset) { index, item in
                                    Button { episode = index } label: {
                                        Text(item.title).font(.subheadline).lineLimit(1).frame(maxWidth: .infinity).padding(.vertical, 12)
                                            .background(index == episode ? Color.accentColor.opacity(0.25) : .white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    } else if loaded { Text("这部影片暂时没有可用播放线路").foregroundStyle(.secondary) }
                    if loading { ProgressView("读取影片信息…") }
                    if let detail {
                        if !detail.actors.isEmpty { Text("主演  " + detail.actors.joined(separator: " / ")).font(.caption).foregroundStyle(.secondary) }
                        if !detail.introduction.isEmpty {
                            Text("剧情简介").font(.headline)
                            Text(detail.introduction).font(.subheadline).foregroundStyle(.secondary).lineSpacing(5)
                        }
                    }
                }.padding(.horizontal).padding(.bottom, 28)
            }
        }
        .background(canvas).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } } }
        .task { await load() }
        .task(id: playKey) { await resolve() }
        .onChange(of: scenePhase) { if $0 != .active { playback.saveProgress() } }
        .onDisappear { playback.stop() }
    }
    @MainActor private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let result = try await model.api.detail(id: video.id)
            guard !Task.isCancelled else { return }
            detail = result.0; sources = result.1
            if let record = library.history.first(where: { $0.id == video.id }), let index = sources.firstIndex(where: { $0.id == record.source }) {
                source = index; episode = min(record.episode, max(0, sources[index].episodes.count-1))
            }
            loaded = true
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    @MainActor private func resolve() async {
        guard loaded, let selected, selected.episodes.indices.contains(episode) else { return }
        playback.stop(); error = nil; resolving = true
        let currentKey = playKey, sourceID = selected.id, episodeIndex = episode, item = selected.episodes[episode]
        defer { if playKey == currentKey { resolving = false } }
        do {
            let response = try await model.api.resolve(title: detail?.summary.title ?? video.title, episode: item)
            guard !Task.isCancelled, playKey == currentKey else { return }
            let saved = library.history.first { $0.id == video.id && $0.source == sourceID && $0.episode == episodeIndex }
            let resume = saved.map { $0.duration > 0 && $0.duration-$0.position < 15 ? 0 : $0.position } ?? 0
            playback.speed = Float(speed)
            playback.load(response, resume: resume) { position, duration in
                library.record(detail?.summary ?? video, source: sourceID, episode: episodeIndex,
                    title: item.title, position: position, duration: duration)
            }
            playback.onEnd = { if autoplay, let selected = self.selected, episode+1 < selected.episodes.count { episode += 1 } }
        } catch { if !Task.isCancelled && playKey == currentKey { self.error = error.localizedDescription } }
    }
}

@MainActor struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore
    @AppStorage("kanke.autoplay") private var autoplay = true
    @AppStorage("kanke.speed") private var speed = 1.0
    @State private var reconnecting = false
    @State private var clearing = false
    var body: some View {
        Form {
            Section("播放偏好") {
                Toggle("自动播放下一集", isOn: $autoplay)
                Picker("默认播放速度", selection: $speed) {
                    ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { Text("\($0, specifier: "%g")×").tag($0) }
                }
            }
            Section("连接") {
                Button(reconnecting ? "正在重新连接…" : "重新连接片库") {
                    reconnecting = true
                    Task { await model.reconnect(); reconnecting = false }
                }.disabled(reconnecting)
                Text("部分线路失效时，可在播放页切换线路。可播放格式和外部服务状态可能因影片而异。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("本机数据") {
                LabeledContent("收藏", value: "\(library.favorites.count) 部")
                LabeledContent("观看记录", value: "\(library.history.count) 部")
                Button("清空观看记录", role: .destructive) { clearing = true }
            }
            Section {
                Text("看客 · iOS\n原生播放器，无广告 SDK\n收藏和观看记录只保存在本机。")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
            }
        }.navigationTitle("设置").scrollContentBackground(.hidden).background(canvas)
            .confirmationDialog("清空本机观看记录？", isPresented: $clearing, titleVisibility: .visible) {
                Button("清空记录", role: .destructive) { library.clearHistory() }
            }
    }
}
