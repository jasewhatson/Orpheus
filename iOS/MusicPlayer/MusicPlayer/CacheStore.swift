//
//  CacheStore.swift
//  MusicPlayer
//
//  On-device cache for streamed audio, resized artwork JPEGs, and track
//  metadata. Enforces a user-configurable byte budget with LRU eviction
//  (oldest-accessed content is purged first).
//

import Foundation
import UIKit

struct TrackMeta: Codable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
}

final class CacheStore {
    static let shared = CacheStore()

    // Serialises all manifest + filesystem mutations.
    private let queue = DispatchQueue(label: "fm.aura.cache")

    private let root: URL
    private let audioDir: URL
    private let artworkDir: URL
    private let metaDir: URL
    private let manifestURL: URL

    private struct Entry: Codable {
        var file: String        // filename within its category dir
        var size: Int64
        var lastAccess: Double
        var category: String    // "audio" | "artwork" | "meta"
    }
    private var manifest: [String: Entry] = [:]
    private var inflight = Set<String>()

    /// Byte budget. Mutating it triggers eviction down to the new limit.
    private(set) var maxBytes: Int64 = 250 * 1024 * 1024

    /// Called on the main queue after the cache contents change.
    var onChange: (() -> Void)?

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        root = caches.appendingPathComponent("AURACache", isDirectory: true)
        audioDir = root.appendingPathComponent("audio", isDirectory: true)
        artworkDir = root.appendingPathComponent("artwork", isDirectory: true)
        metaDir = root.appendingPathComponent("meta", isDirectory: true)
        manifestURL = root.appendingPathComponent("manifest.json")
        for d in [root, audioDir, artworkDir, metaDir] {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        loadManifest()
    }

    // MARK: Public — budget & stats

    func setMaxBytes(_ bytes: Int64) {
        queue.sync {
            maxBytes = bytes
            enforceBudgetLocked()
            saveManifestLocked()
        }
        notify()
    }

    func totalBytes() -> Int64 {
        queue.sync { manifest.values.reduce(0) { $0 + $1.size } }
    }

    func clearAll() {
        queue.sync {
            for cat in [audioDir, artworkDir, metaDir] {
                let items = (try? FileManager.default.contentsOfDirectory(at: cat, includingPropertiesForKeys: nil)) ?? []
                for f in items { try? FileManager.default.removeItem(at: f) }
            }
            manifest.removeAll()
            saveManifestLocked()
        }
        notify()
    }

    // MARK: Audio

    private func audioKey(_ url: URL) -> String { "audio_" + url.lastPathComponent }

    /// Local file URL if this remote audio is already cached (touches LRU).
    func localAudio(for url: URL) -> URL? {
        queue.sync {
            let key = audioKey(url)
            guard var e = manifest[key] else { return nil }
            let f = audioDir.appendingPathComponent(e.file)
            guard FileManager.default.fileExists(atPath: f.path) else { manifest[key] = nil; return nil }
            e.lastAccess = now; manifest[key] = e; saveManifestLocked()
            return f
        }
    }

    /// Downloads + caches the audio in the background if not already present.
    func cacheAudioIfNeeded(_ url: URL) {
        let key = audioKey(url)
        let shouldStart: Bool = queue.sync {
            if manifest[key] != nil || inflight.contains(key) { return false }
            inflight.insert(key)
            return true
        }
        guard shouldStart else { return }

        URLSession.shared.downloadTask(with: url) { [weak self] temp, _, err in
            guard let self else { return }
            defer { self.queue.sync { _ = self.inflight.remove(key) } }
            guard let temp, err == nil else { return }
            let dest = self.audioDir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            guard (try? FileManager.default.moveItem(at: temp, to: dest)) != nil else { return }
            let size = Self.fileSize(dest)
            self.queue.sync {
                self.manifest[key] = Entry(file: url.lastPathComponent, size: size, lastAccess: self.now, category: "audio")
                self.enforceBudgetLocked(protecting: key)
                self.saveManifestLocked()
            }
            self.notify()
        }.resume()
    }

    // MARK: Artwork (rendered + cached as resized JPEG)

    /// Returns a cached resized artwork image, rendering and caching it on a
    /// miss. `size` is the pixel dimension of the square output.
    func artworkImage(for art: Artwork, size: CGFloat, render: (CGFloat) -> UIImage) -> UIImage {
        let key = "art_\(art.hexes.joined(separator: "-"))_\(Int(art.angle))_\(art.radial)_\(Int(size))"

        if let cached: UIImage = queue.sync(execute: {
            guard var e = manifest[key] else { return nil }
            let f = artworkDir.appendingPathComponent(e.file)
            guard let data = try? Data(contentsOf: f), let img = UIImage(data: data) else {
                manifest[key] = nil; return nil
            }
            e.lastAccess = now; manifest[key] = e; saveManifestLocked()
            return img
        }) { return cached }

        let image = render(size)
        if let data = image.jpegData(compressionQuality: 0.8) {
            let file = key + ".jpg"
            let dest = artworkDir.appendingPathComponent(file)
            try? data.write(to: dest)
            queue.sync {
                manifest[key] = Entry(file: file, size: Int64(data.count), lastAccess: now, category: "artwork")
                enforceBudgetLocked(protecting: key)
                saveManifestLocked()
            }
            notify()
        }
        return image
    }

    // MARK: Metadata

    func meta(_ trackId: String) -> TrackMeta? {
        queue.sync {
            let key = "meta_" + trackId
            guard var e = manifest[key] else { return nil }
            let f = metaDir.appendingPathComponent(e.file)
            guard let data = try? Data(contentsOf: f), let m = try? JSONDecoder().decode(TrackMeta.self, from: data) else {
                manifest[key] = nil; return nil
            }
            e.lastAccess = now; manifest[key] = e; saveManifestLocked()
            return m
        }
    }

    func storeMeta(_ m: TrackMeta, id: String) {
        guard let data = try? JSONEncoder().encode(m) else { return }
        let key = "meta_" + id
        let file = key + ".json"
        let dest = metaDir.appendingPathComponent(file)
        try? data.write(to: dest)
        queue.sync {
            manifest[key] = Entry(file: file, size: Int64(data.count), lastAccess: now, category: "meta")
            enforceBudgetLocked(protecting: key)
            saveManifestLocked()
        }
        notify()
    }

    // MARK: LRU eviction (call on queue)

    private func enforceBudgetLocked(protecting: String? = nil) {
        var total = manifest.values.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }
        // oldest first
        let order = manifest.sorted { $0.value.lastAccess < $1.value.lastAccess }
        for (key, entry) in order {
            if total <= maxBytes { break }
            if key == protecting { continue }
            let dir = directory(for: entry.category)
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(entry.file))
            manifest[key] = nil
            total -= entry.size
        }
    }

    // MARK: Helpers

    private var now: Double { Date().timeIntervalSince1970 }

    private func directory(for category: String) -> URL {
        switch category {
        case "audio": return audioDir
        case "artwork": return artworkDir
        default: return metaDir
        }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? Int64) ?? 0
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let m = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        manifest = m
    }
    private func saveManifestLocked() {
        if let data = try? JSONEncoder().encode(manifest) { try? data.write(to: manifestURL) }
    }
    private func notify() {
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }
}
