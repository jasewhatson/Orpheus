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

    /// Single shared instance. `@State var app = AppModel()` in a SwiftUI view
    /// re-evaluates its initializer whenever the view struct is re-created, which
    /// would spin up throwaway models (extra AudioEngines, duplicate network
    /// loads). Using one shared instance guarantees init side effects run once.
    static let shared = AppModel()

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

    /// Real playback time + asset duration (seconds) from the audio engine.
    var currentTime: Double = 0
    var duration: Double = 0

    // MARK: Remote library (server-backed; not persisted)
    /// All known tracks by id (seeded with the demo catalog, merged with server).
    var library: [String: Track] = Catalog.tracks
    var serverPlaylists: [String: Playlist] = [:]
    var serverPlaylistOrder: [String] = []
    var serverCoverURL: [String: URL] = [:]   // playlist id -> first-track artwork
    var serverIndexLoaded = false
    var serverLoading = false
    /// Parsed lyrics for the current track (empty if none/canned).
    var currentLyrics: [LyricLine] = []

    @ObservationIgnored private let engine = AudioEngine()
    @ObservationIgnored private let cache = CacheStore.shared
    @ObservationIgnored private var metaStored: Set<String> = []
    @ObservationIgnored private var loadingPlaylists: Set<String> = []
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    /// Current on-device cache usage in bytes (observable for Settings).
    var cacheBytes: Int64 = 0
    static let cacheOptionsMB = [50, 100, 250, 500, 1024]

    var palette: Palette { Palette(theme: theme) }

    /// Maps each track deterministically to one of the 6 sample MP3s.
    static func url(for trackId: String) -> URL {
        let n = trackId.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 6
        return URL(string: "https://audio-samples.github.io/samples/mp3/music_primed/sample-\(n).mp3")!
    }

    // MARK: Init

    init() {
        // initial player
        player = PlayerState(trackId: "aurora-t")
        let album = Catalog.album("aurora")
        let i = album.tracks.firstIndex(of: "aurora-t") ?? 0
        queue = Array(album.tracks[(i + 1)...])
        loadPersisted()
        cache.setMaxBytes(Int64(settings.cacheLimitMB) * 1024 * 1024)
        cache.onChange = { [weak self] in self?.refreshCacheUsage() }
        refreshCacheUsage()
        wireEngine()
        loadCurrent()   // prime the first track (paused) so lock-screen has info
        if settings.serverEnabled { Task { await loadServerLibrary() } }
    }

    private func wireEngine() {
        engine.onTime = { [weak self] cur, dur in
            guard let self else { return }
            self.currentTime = cur
            if dur > 0 {
                self.duration = dur
                self.player.progress = min(1, cur / dur)
                self.cacheMetaIfNeeded(duration: dur)
            }
        }
        engine.onEnd = { [weak self] in self?.advance(auto: true) }
        engine.onPlay = { [weak self] in self?.setPlaying(true) }
        engine.onPause = { [weak self] in self?.setPlaying(false) }
        engine.onToggle = { [weak self] in self?.togglePlay() }
        engine.onNext = { [weak self] in self?.next() }
        engine.onPrev = { [weak self] in self?.prev() }
        engine.onSeek = { [weak self] sec in
            guard let self else { return }
            self.seek(self.duration > 0 ? sec / self.duration : 0)
        }
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

    var currentTrack: Track { track(player.trackId) }

    /// Resolve any track id (demo or server) through the registry.
    func track(_ id: String) -> Track {
        library[id] ?? Track(id: id, title: "Unknown", artist: "", album: nil, dur: 0, cover: .placeholder)
    }

    func getPlaylist(_ id: String) -> Playlist? { playlists[id] ?? serverPlaylists[id] }

    func isRemotePlaylist(_ id: String) -> Bool { id.hasPrefix("srv:") }

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

    // MARK: Engine bridge

    /// Loads the current track into the engine (playing iff `isPlaying`) and
    /// refreshes the lock-screen Now Playing info.
    private func loadCurrent() {
        let t = currentTrack
        player.progress = 0
        currentTime = 0
        // prefill duration: cached metadata, else the track's own duration
        duration = cache.meta(t.id)?.duration ?? t.dur
        engine.load(url: playbackURL(for: t), autoplay: player.isPlaying)
        updateNowPlaying()
        loadLyrics(for: t)
    }

    /// Final streamable URL: remote tracks use their server URL (requesting an
    /// AAC transcode for non-native formats); demo tracks use the sample mapping.
    func playbackURL(for t: Track) -> URL {
        guard let base = t.audioURL else { return AppModel.url(for: t.id) }
        guard needsTranscode(t.fileExt),
              var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        comps.queryItems = (comps.queryItems ?? []) + [
            URLQueryItem(name: "format", value: settings.transcodeFormat),
            URLQueryItem(name: "bitrate", value: String(settings.transcodeKbps)),
        ]
        return comps.url ?? base
    }

    static let bitrateOptions = [128, 192, 256, 320]
    static let formatOptions = ["m4a", "mp3"]

    func cycleBitrate() {
        let opts = AppModel.bitrateOptions
        let i = opts.firstIndex(of: settings.transcodeKbps) ?? 2
        settings.transcodeKbps = opts[(i + 1) % opts.count]
        // Applies to the next track loaded (the cache key includes the bitrate,
        // so a new rate fetches a fresh stream rather than reusing the old one).
    }

    func cycleFormat() {
        let opts = AppModel.formatOptions
        let i = opts.firstIndex(of: settings.transcodeFormat) ?? 0
        settings.transcodeFormat = opts[(i + 1) % opts.count]
    }

    /// Display label for the current transcode codec.
    var transcodeFormatLabel: String { settings.transcodeFormat == "mp3" ? "MP3" : "AAC (m4a)" }

    private func needsTranscode(_ ext: String?) -> Bool {
        guard let e = ext?.lowercased() else { return false }
        let native: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "alac", "aif", "aiff", "caf"]
        return !native.contains(e)
    }

    private func cacheMetaIfNeeded(duration: Double) {
        let t = currentTrack
        // Backfill a missing list duration from the real asset length.
        if var lib = library[t.id], lib.dur <= 0, duration > 0 {
            lib.dur = duration
            library[t.id] = lib
        }
        guard !metaStored.contains(t.id) else { return }
        metaStored.insert(t.id)
        cache.storeMeta(TrackMeta(title: t.title, artist: t.artist,
                                  album: t.album ?? "", duration: duration), id: t.id)
    }

    // MARK: Cache controls

    func refreshCacheUsage() { cacheBytes = cache.totalBytes() }

    func cycleCacheLimit() {
        let opts = AppModel.cacheOptionsMB
        let i = opts.firstIndex(of: settings.cacheLimitMB) ?? 2
        settings.cacheLimitMB = opts[(i + 1) % opts.count]
        cache.setMaxBytes(Int64(settings.cacheLimitMB) * 1024 * 1024)
        refreshCacheUsage()
    }

    func clearCache() {
        cache.clearAll()
        metaStored.removeAll()
        refreshCacheUsage()
        toast("Cache cleared")
    }

    /// Sets the play/pause state without toggling, driving the engine.
    private func setPlaying(_ playing: Bool) {
        player.isPlaying = playing
        playing ? engine.play() : engine.pause()
        engine.setRate(playing)
    }

    private func updateNowPlaying() {
        let t = currentTrack
        engine.setTrack(title: t.title, artist: t.artist, album: t.album ?? "",
                        artwork: t.cover, trackId: t.id, isPlaying: player.isPlaying)
        // Replace the gradient with real artwork on the lock screen once loaded.
        if let url = t.artworkURL {
            Task { @MainActor in
                if let img = await cache.image(forURL: url), self.player.trackId == t.id {
                    self.engine.setArtwork(img, trackId: t.id)
                }
            }
        }
    }

    private func loadLyrics(for t: Track) {
        currentLyrics = []
        guard let url = t.lyricsURL else { return }
        Task { @MainActor in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let text = String(data: data, encoding: .utf8),
                  self.player.trackId == t.id else { return }
            self.currentLyrics = LRC.parse(text)
        }
    }

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
        loadCurrent()
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
        loadCurrent()
    }

    func togglePlay() { setPlaying(!player.isPlaying) }

    func seek(_ f: Double) {
        let v = max(0, min(0.999, f))
        player.progress = v
        currentTime = duration * v
        engine.seek(toFraction: v)
    }

    func advance(auto: Bool) {
        if auto && player.repeatMode == .one {
            seek(0)
            if player.isPlaying { engine.play() }
            return
        }
        if queue.isEmpty {
            if player.repeatMode == .all {
                let list = ctxList(ctx)
                guard let first = list.first else { setPlaying(false); return }
                history.append(player.trackId)
                player.trackId = first
                player.isPlaying = true
                queue = Array(list.dropFirst())
                loadCurrent()
                return
            }
            player.isPlaying = false
            player.progress = 1
            engine.pause()
            updateNowPlaying()
            return
        }
        let nextId = queue.removeFirst()
        history.append(player.trackId)
        player.trackId = nextId
        player.isPlaying = true
        loadCurrent()
    }

    func next() { advance(auto: false) }

    func prev() {
        if player.progress > 0.04 { seek(0); return }
        guard let prevId = history.last else { seek(0); return }
        history.removeLast()
        queue.insert(player.trackId, at: 0)
        player.trackId = prevId
        player.isPlaying = true
        loadCurrent()
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
        player.isPlaying = true
        loadCurrent()
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
    func openPlaylist(_ id: String) {
        if isRemotePlaylist(id), serverPlaylists[id]?.tracks.isEmpty ?? false {
            Task { await loadServerPlaylist(id) }
        }
        push(.playlist(id))
    }
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

    // MARK: Server

    var serverBaseURL: URL? {
        let host = settings.serverHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return nil }
        return URL(string: "http://\(host):\(settings.serverPort)")
    }
    var api: MusicAPI? { serverBaseURL.map { MusicAPI(baseURL: $0) } }

    var serverPlaylistsList: [Playlist] { serverPlaylistOrder.compactMap { serverPlaylists[$0] } }
    /// Remote tracks that have been loaded (for Search).
    var serverTracks: [Track] { library.values.filter { $0.isRemote } }

    func applyServerSettings(host: String, port: Int, enabled: Bool) {
        settings.serverHost = host
        settings.serverPort = port
        settings.serverEnabled = enabled
        if enabled {
            Task { await loadServerLibrary() }
        } else {
            serverPlaylists = [:]; serverPlaylistOrder = []; serverCoverURL = [:]; serverIndexLoaded = false
            library = library.filter { !$0.value.isRemote }
        }
    }

    func testConnection() {
        guard let api else { toast("Enter a server host"); return }
        Task { @MainActor in
            do {
                let h = try await api.health()
                let ff = (h.ffmpeg ?? false) ? "" : " · no ffmpeg!"
                toast("Connected · \(h.playlistCount) playlists\(ff)")
                settings.serverEnabled = true
                await loadServerLibrary()
            } catch {
                toast("Couldn't reach server")
            }
        }
    }

    func loadServerLibrary() async {
        guard let api else { return }
        serverLoading = true
        defer { serverLoading = false }
        do {
            let pls = try await api.playlists()
            var order: [String] = []
            for s in pls {
                let pid = "srv:" + s.id
                order.append(pid)
                if serverPlaylists[pid] == nil {
                    serverPlaylists[pid] = Playlist(
                        id: pid, title: s.name, desc: "\(s.trackCount) track" + (s.trackCount == 1 ? "" : "s"),
                        by: "Server", cover: Self.gradient(for: s.name), tracks: [])
                }
            }
            serverPlaylistOrder = order
            serverIndexLoaded = true
            // Background: load each playlist's tracks (covers + search index).
            Task { for pid in order { await self.loadServerPlaylist(pid) } }
        } catch {
            toast("Couldn't load library")
        }
    }

    @discardableResult
    func loadServerPlaylist(_ pid: String) async -> Bool {
        guard let api, let pl = serverPlaylists[pid], pl.tracks.isEmpty else { return true }
        guard !loadingPlaylists.contains(pid) else { return true }   // dedupe concurrent fetches
        loadingPlaylists.insert(pid)
        defer { loadingPlaylists.remove(pid) }
        let name = String(pid.dropFirst(4))  // strip "srv:"
        do {
            let detail = try await api.playlist(name)
            var ids: [String] = []
            for t in detail.tracks {
                let gid = "srv:" + name + "/" + t.id
                ids.append(gid)
                library[gid] = makeRemoteTrack(gid: gid, api: t)
            }
            var updated = pl
            updated.tracks = ids
            serverPlaylists[pid] = updated
            if let first = ids.first, let art = library[first]?.artworkURL { serverCoverURL[pid] = art }
            return true
        } catch {
            return false
        }
    }

    private func makeRemoteTrack(gid: String, api t: APITrack) -> Track {
        let ext = (t.file as NSString).pathExtension.lowercased()
        let resolve: (String?) -> URL? = { rel in rel.flatMap { self.api?.absolute($0) } }
        return Track(id: gid, title: t.title, artist: t.artist, album: t.album,
                     dur: t.duration ?? 0,
                     cover: Self.gradient(for: t.artist + "·" + t.title),
                     artworkURL: resolve(t.artworkUrl),
                     audioURL: resolve(t.audioUrl),
                     lyricsURL: resolve(t.lyricsUrl),
                     fileExt: ext)
    }

    /// Deterministic gradient from a seed string (reuses the album palettes).
    static func gradient(for seed: String) -> Artwork {
        let palettes: [[String]] = [
            ["7aa6f2", "3a4d9e", "161a3a"], ["7be3d4", "1d6e72", "08222b"],
            ["c39bf5", "6a3fb0", "1f1138"], ["f6b67a", "d4673a", "3a1812"],
            ["8fa6ff", "3b4192", "12153c"], ["6fd6f2", "1f7fae", "082b3e"],
            ["f59cc6", "b34a86", "3a1230"], ["93ffce", "2c9e74", "0c3324"],
        ]
        var h: UInt64 = 5381
        for b in seed.utf8 { h = (h &* 33) &+ UInt64(b) }
        let p = palettes[Int(h % UInt64(palettes.count))]
        return .cover(p[0], p[1], p[2], angle: 160)
    }
}
