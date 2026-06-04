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
    let artistId: String
    let albumId: String
    let dur: Int            // seconds
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
}

// MARK: - Time formatting

enum Fmt {
    static func time(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
    static func time(_ seconds: Int) -> String { time(Double(seconds)) }
}
