//
//  Models.swift
//  MusicPlayer
//
//  Core data models for the AURA catalog. Artwork stores the gradient
//  palette (hex strings) so covers are fully generative — no assets.
//

import SwiftUI

// MARK: - Artwork (generative gradient cover)

struct Artwork: Codable, Hashable {
    /// Gradient stops. Normal covers use 3 colors [a, b, c]; radial
    /// artist covers use 2 [inner, outer].
    var hexes: [String]
    var angle: Double = 145
    var radial: Bool = false

    var colors: [Color] { hexes.map { Color(hex: $0) } }
    var palette: [Color] {
        let c = colors
        return c.count >= 3 ? c : [c.first ?? .gray, c.first ?? .gray, c.last ?? .black]
    }

    static func cover(_ a: String, _ b: String, _ c: String, angle: Double = 145) -> Artwork {
        Artwork(hexes: [a, b, c], angle: angle)
    }

    static func artist(_ mono: [String]) -> Artwork {
        Artwork(hexes: mono, radial: true)
    }

    static let placeholder = Artwork(hexes: ["444444", "222222"], radial: true)
}

// MARK: - Entities

struct Artist: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let mono: [String]      // [inner, outer]
    let followers: String
    let bio: String

    var artwork: Artwork { .artist(mono) }
}

struct Album: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let artistId: String
    let year: Int
    let type: String        // Album / EP / Single
    let cover: Artwork
    let tracks: [String]
}

struct Track: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let artist: String          // display name
    var album: String?
    var dur: Double             // seconds (0 if unknown)
    var cover: Artwork          // gradient fallback, always present
    var artworkURL: URL? = nil  // remote cover image (optional)
    var audioURL: URL? = nil    // remote source base URL; nil => demo sample mapping
    var lyricsURL: URL? = nil   // remote .lrc (optional)
    var fileExt: String? = nil  // source extension, for transcode decision
    var artistId: String? = nil // demo-only, for artist navigation
    var albumId: String? = nil  // demo-only

    var isRemote: Bool { audioURL != nil }
}

/// One parsed lyric line; `time` is nil for headers/untimed lines.
struct LyricLine: Hashable {
    var time: Double?
    var text: String
}

struct Playlist: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var desc: String
    var by: String
    var liked: Bool = false
    var cover: Artwork
    var tracks: [String]
}

// MARK: - Player support types

enum RepeatMode: String, Codable { case off, all, one }

struct PlayerState: Codable {
    var trackId: String
    var isPlaying: Bool = false
    var progress: Double = 0      // 0...1
    var shuffle: Bool = false
    var repeatMode: RepeatMode = .off
}

/// Where playback is sourced from. `tracks` is non-nil for ad-hoc contexts
/// (e.g. an artist's popular list).
struct PlayContext: Equatable {
    enum Kind: String { case album, playlist, artist, queue }
    var kind: Kind
    var id: String
    var tracks: [String]? = nil
}

struct Settings: Codable {
    var crossfade: Double = 6
    var gapless: Bool = true
    var normalize: Bool = true
    var quality: String = "Lossless"
    var cellular: Bool = false
    var offline: Bool = false
    var cacheLimitMB: Int = 250

    // Music server
    var serverHost: String = "192.168.20.10"
    var serverPort: Int = 8080
    var serverEnabled: Bool = false
    var transcodeKbps: Int = 256   // AAC bitrate requested for transcoded (.ogg) audio

    init() {}

    // Tolerant decode: any missing key falls back to its default, so adding new
    // settings never wipes a user's saved preferences.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ d: T) -> T { (try? c.decode(T.self, forKey: k)) ?? d }
        crossfade = v(.crossfade, 6)
        gapless = v(.gapless, true)
        normalize = v(.normalize, true)
        quality = v(.quality, "Lossless")
        cellular = v(.cellular, false)
        offline = v(.offline, false)
        cacheLimitMB = v(.cacheLimitMB, 250)
        serverHost = v(.serverHost, "192.168.20.10")
        serverPort = v(.serverPort, 8080)
        serverEnabled = v(.serverEnabled, false)
        transcodeKbps = v(.transcodeKbps, 256)
    }
}

// MARK: - Time formatting

enum Fmt {
    static func time(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
    static func time(_ seconds: Int) -> String { time(Double(seconds)) }
}
