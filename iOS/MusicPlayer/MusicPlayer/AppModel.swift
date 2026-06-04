//
//  AppModel.swift
//  MusicPlayer
//
//  AURA controller: navigation, the player engine, library state, and
//  persistence. Ported from the design's app.jsx.
//

import SwiftUI
import Observation

enum Tab: String, CaseIterable { case home, search, library, settings }

enum Route: Hashable {
    case album(String), playlist(String), artist(String), manage(String)
}

enum Modal: Identifiable {
    case track(trackId: String, ctx: PlayContext?)
    case add(trackId: String)
    case create(addTrackId: String?)
    case collection(kind: String, id: String)

    var id: String {
        switch self {
        case .track(let t, _): return "track-\(t)"
        case .add(let t): return "add-\(t)"
        case .create(let t): return "create-\(t ?? "new")"
        case .collection(let k, let i): return "col-\(k)-\(i)"
        }
    }
}

@Observable
final class AppModel {

    // MARK: Persisted-ish state
    var theme: AppTheme = .dark { didSet { persist("theme", theme) } }
    var playlists: [String: Playlist] = Catalog.defaultPlaylists { didSet { persist("playlists", playlists) } }
    var liked: [String] = Catalog.defaultPlaylists["favorites"]!.tracks { didSet { persist("liked", liked) } }
    var downloads: [String] = ["solstice", "tidal", "deepfield", "meridian", "weightless", "stratus"] { didSet { persist("downloads", downloads) } }
    var saved: [String] = ["album:aurora", "album:submerged"] { didSet { persist("saved", saved) } }
    var following: [String] = ["lumora", "skyfold", "astral", "solace", "aeon", "vector"] { didSet { persist("following", following) } }
    var settings = Settings() { didSet { persist("settings", settings) } }

    // MARK: Navigation
    var tab: Tab = .home
    var stacks: [Tab: [Route]] = [.home: [], .search: [], .library: [], .settings: []]
    var nowPlayingOpen = false
    var modal: Modal?
    var toastMsg: String?

    // MARK: Player
    var player: PlayerState
    var ctx = PlayContext(kind: .album, id: "aurora")
    var queue: [String]
    var history: [String] = []

    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    var palette: Palette { Palette(theme: theme) }

    // MARK: Init

    init() {
        // initial player
        player = PlayerState(trackId: "aurora-t")
        let album = Catalog.album("aurora")
        let i = album.tracks.firstIndex(of: "aurora-t") ?? 0
        queue = Array(album.tracks[(i + 1)...])
        loadPersisted()
    }

    // MARK: Persistence

    private func persist<T: Encodable>(_ key: String, _ value: T) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: "aura_" + key)
        }
    }
    private func read<T: Decodable>(_ key: String, _ type: T.Type) -> T? {
        guard let data = UserDefaults.standard.data(forKey: "aura_" + key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private func loadPersisted() {
        if let v = read("theme", AppTheme.self) { theme = v }
        if let v = read("playlists", [String: Playlist].self) { playlists = v }
        if let v = read("liked", [String].self) { liked = v }
        if let v = read("downloads", [String].self) { downloads = v }
        if let v = read("saved", [String].self) { saved = v }
        if let v = read("following", [String].self) { following = v }
        if let v = read("settings", Settings.self) { settings = v }
    }

    // MARK: Derived

    var currentTrack: Track { Catalog.track(player.trackId) }

    func getPlaylist(_ id: String) -> Playlist? { playlists[id] }

    func ctxList(_ c: PlayContext) -> [String] {
        if let t = c.tracks { return t }
        switch c.kind {
        case .album: return Catalog.album(c.id).tracks
        case .playlist: return getPlaylist(c.id)?.tracks ?? []
        default: return [player.trackId]
        }
    }

    var contextLabel: String {
        switch ctx.kind {
        case .album: return "Album"
        case .playlist: return "Playlist"
        case .artist: return "Artist"
        case .queue: return "Queue"
        }
    }
    var contextTitle: String {
        switch ctx.kind {
        case .album: return Catalog.album(ctx.id).title
        case .playlist: return getPlaylist(ctx.id)?.title ?? "Playlist"
        case .artist: return Catalog.artist(ctx.id).name
        case .queue: return "AURA"
        }
    }

    // MARK: Toast

    func toast(_ msg: String) {
        toastMsg = msg
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.9))
            if !Task.isCancelled { self?.toastMsg = nil }
        }
    }

    // MARK: Ticker

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.player.isPlaying else { return }
            let dur = Double(self.currentTrack.dur)
            let np = self.player.progress + 1 / dur / 4
            if np >= 1 {
                self.advance(auto: true)
            } else {
                self.player.progress = np
            }
        }
    }
    private func stopTicker() { ticker?.invalidate(); ticker = nil }

    private func syncTicker() { player.isPlaying ? startTicker() : stopTicker() }

    // MARK: Playback

    private func shuffled(_ arr: [String]) -> [String] { arr.shuffled() }

    private func startQueue(_ list: [String], startId: String, shuffle: Bool) {
        let ordered = shuffle ? [startId] + self.shuffled(list.filter { $0 != startId }) : list
        let i = ordered.firstIndex(of: startId) ?? 0
        queue = Array(ordered[(i + 1)...])
        history = []
    }

    func playTrack(_ id: String, _ context: PlayContext? = nil) {
        let c = context ?? ctx
        ctx = c
        startQueue(ctxList(c), startId: id, shuffle: player.shuffle)
        player.trackId = id
        player.isPlaying = true
        player.progress = 0
        syncTicker()
    }

    func playContext(_ c: PlayContext) {
        let list = ctxList(c)
        guard !list.isEmpty else { return }
        let sh = player.shuffle
        let first = sh ? (shuffled(list).first ?? list[0]) : list[0]
        ctx = c
        let ordered = sh ? [first] + shuffled(list.filter { $0 != first }) : list
        queue = Array(ordered.dropFirst())
        history = []
        player.trackId = first
        player.isPlaying = true
        player.progress = 0
        syncTicker()
    }

    func togglePlay() { player.isPlaying.toggle(); syncTicker() }

    func seek(_ f: Double) { player.progress = max(0, min(0.999, f)) }

    func advance(auto: Bool) {
        if auto && player.repeatMode == .one {
            player.progress = 0
            return
        }
        if queue.isEmpty {
            if player.repeatMode == .all {
                let list = ctxList(ctx)
                guard let first = list.first else { player.isPlaying = false; return }
                history.append(player.trackId)
                player.trackId = first
                player.progress = 0
                player.isPlaying = true
                queue = Array(list.dropFirst())
                syncTicker()
                return
            }
            player.isPlaying = false
            player.progress = 1
            syncTicker()
            return
        }
        let nextId = queue.removeFirst()
        history.append(player.trackId)
        player.trackId = nextId
        player.progress = 0
        player.isPlaying = true
        syncTicker()
    }

    func next() { advance(auto: false) }

    func prev() {
        if player.progress > 0.04 { seek(0); return }
        guard let prevId = history.last else { seek(0); return }
        history.removeLast()
        queue.insert(player.trackId, at: 0)
        player.trackId = prevId
        player.progress = 0
        player.isPlaying = true
        syncTicker()
    }

    func toggleShuffle() {
        let s = !player.shuffle
        player.shuffle = s
        if s {
            queue = shuffled(queue)
        } else {
            let list = ctxList(ctx)
            if let i = list.firstIndex(of: player.trackId) {
                queue = Array(list[(i + 1)...])
            }
        }
    }

    func cycleRepeat() {
        player.repeatMode = player.repeatMode == .off ? .all : player.repeatMode == .all ? .one : .off
    }

    func isCtxPlaying(_ c: PlayContext) -> Bool {
        player.isPlaying && ctxList(c).contains(player.trackId) && (c.id == ctx.id || c.id.isEmpty)
    }

    // MARK: Queue ops

    func addToQueue(_ id: String) { queue.append(id); toast("Added to queue") }
    func playNext(_ id: String) { queue.insert(id, at: 0); toast("Playing next") }
    func reorderQueue(_ order: [String]) { queue = order }
    func jumpQueue(_ index: Int) {
        guard index < queue.count else { return }
        let id = queue[index]
        history.append(contentsOf: [player.trackId] + Array(queue[..<index]))
        queue = Array(queue[(index + 1)...])
        player.trackId = id
        player.progress = 0
        player.isPlaying = true
        syncTicker()
    }

    // MARK: Likes / downloads / saves / follow

    func isLiked(_ id: String) -> Bool { liked.contains(id) }
    func toggleLike(_ id: String) { liked.contains(id) ? liked.removeAll { $0 == id } : liked.insert(id, at: 0) }

    func isDownloaded(_ id: String) -> Bool { downloads.contains(id) }
    func toggleDownload(_ id: String) { downloads.contains(id) ? downloads.removeAll { $0 == id } : downloads.append(id) }

    func isSaved(_ kind: String, _ id: String) -> Bool { saved.contains("\(kind):\(id)") }
    func toggleSave(_ kind: String, _ id: String) {
        let k = "\(kind):\(id)"
        let was = saved.contains(k)
        if was { saved.removeAll { $0 == k } } else { saved.append(k) }
        toast(was ? "Removed from Library" : "Added to Library")
    }

    func isFollowing(_ id: String) -> Bool { following.contains(id) }
    func toggleFollow(_ id: String) { following.contains(id) ? following.removeAll { $0 == id } : following.append(id) }

    // MARK: Playlist mutation

    func togglePlaylistTrack(_ plId: String, _ trackId: String) {
        if plId == "favorites" { toggleLike(trackId); return }
        guard var p = playlists[plId] else { return }
        if p.tracks.contains(trackId) { p.tracks.removeAll { $0 == trackId } }
        else { p.tracks.append(trackId) }
        playlists[plId] = p
    }
    func removeFromPlaylist(_ plId: String, _ trackId: String) {
        guard var p = playlists[plId] else { return }
        p.tracks.removeAll { $0 == trackId }
        playlists[plId] = p
        toast("Removed from playlist")
    }
    func savePlaylist(_ id: String, title: String? = nil, desc: String? = nil, tracks: [String]? = nil) {
        guard var p = playlists[id] else { return }
        if let title { p.title = title }
        if let desc { p.desc = desc }
        if let tracks { p.tracks = tracks }
        playlists[id] = p
        toast("Playlist updated")
    }
    @discardableResult
    func createPlaylist(_ name: String, addTrackId: String? = nil) -> String {
        let id = "pl_\(Int(Date().timeIntervalSince1970 * 1000))"
        let p = Playlist(id: id, title: name, desc: "", by: "You",
                         cover: .cover("9c8cf2", "5b48c4", "1f1450", angle: 160),
                         tracks: addTrackId.map { [$0] } ?? [])
        playlists[id] = p
        toast(addTrackId != nil ? "Added to \(name)" : "Playlist created")
        if addTrackId == nil {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.openManage(id)
            }
        }
        return id
    }
    func deletePlaylist(_ id: String) {
        playlists[id] = nil
        back()
        toast("Playlist deleted")
    }

    // MARK: Navigation

    var topRoute: Route? { stacks[tab]?.last }
    var overlay: Bool { !(stacks[tab]?.isEmpty ?? true) }

    func push(_ r: Route) { stacks[tab, default: []].append(r) }
    func back() { if !(stacks[tab]?.isEmpty ?? true) { stacks[tab]?.removeLast() } }
    func goTab(_ t: Tab) {
        if t == tab, !(stacks[t]?.isEmpty ?? true) { stacks[t] = [] }
        tab = t
    }
    func openAlbum(_ id: String) { push(.album(id)) }
    func openPlaylist(_ id: String) { push(.playlist(id)) }
    func openArtist(_ id: String) { push(.artist(id)) }
    func openManage(_ id: String) { push(.manage(id)) }

    // MARK: Modals

    func openTrackMenu(_ id: String, _ c: PlayContext? = nil) { modal = .track(trackId: id, ctx: c) }
    func openAddToPlaylist(_ id: String) { modal = .add(trackId: id) }
    func openCreatePlaylist(_ id: String? = nil) { modal = .create(addTrackId: id) }
    func openCollectionMenu(_ kind: String, _ id: String) { modal = .collection(kind: kind, id: id) }

    // MARK: Settings

    func cycleQuality() {
        let opts = ["Normal", "High", "Lossless", "Hi-Res"]
        let i = opts.firstIndex(of: settings.quality) ?? 0
        settings.quality = opts[(i + 1) % opts.count]
    }
}
