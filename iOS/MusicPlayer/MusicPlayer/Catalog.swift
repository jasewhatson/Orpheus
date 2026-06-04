//
//  Catalog.swift
//  MusicPlayer
//
//  The original AURA trance catalog — artists, albums, tracks, playlists.
//

import Foundation

enum Catalog {

    // MARK: Artists

    static let artists: [String: Artist] = dict([
        Artist(id: "lumora",  name: "Lumora",        mono: ["5f8ff0", "23264a"], followers: "1.24M", bio: "Berlin-based architect of weightless, melodic trance. Lumora's sets drift between euphoria and stillness."),
        Artist(id: "aeon",    name: "Aeon Drift",    mono: ["7be3d4", "10322f"], followers: "842K",  bio: "Live-modular duo exploring the long-form build. Patient, hypnotic, oceanic."),
        Artist(id: "skyfold", name: "Skyfold",       mono: ["b58cf2", "241640"], followers: "2.01M", bio: "Festival mainstage anthems with a soft, reflective core."),
        Artist(id: "halcyon", name: "Nova Halcyon",  mono: ["f0a36b", "3a1d16"], followers: "566K",  bio: "Sunrise sets and golden-hour progressive. Always one more record."),
        Artist(id: "vector",  name: "Veil & Vector", mono: ["7d9bff", "1b2150"], followers: "388K",  bio: "Two engineers, one drum machine, endless reverb tails."),
        Artist(id: "astral",  name: "Astral Tide",   mono: ["67d2f0", "0e2b3e"], followers: "1.6M",  bio: "Deep, tidal techno-trance for the 3am hour."),
        Artist(id: "solace",  name: "Maya Solace",   mono: ["f08fc0", "3a1130"], followers: "923K",  bio: "Vocal-led uplifting trance with cinematic sweep."),
        Artist(id: "polaris", name: "Polaris Six",   mono: ["8affc0", "0d3324"], followers: "274K",  bio: "Cold, crystalline, northern. Minimal melodic."),
    ])

    // MARK: Albums

    static let albums: [String: Album] = dict([
        Album(id: "aurora",     title: "Aurora Borealis", artistId: "lumora",  year: 2025, type: "Album",
              cover: .cover("7aa6f2", "3a4d9e", "161a3a"),
              tracks: ["solstice", "northern-sky", "weightless", "lucid", "aurora-t", "reverie"]),
        Album(id: "submerged",  title: "Submerged", artistId: "aeon", year: 2024, type: "Album",
              cover: .cover("7be3d4", "1d6e72", "08222b"),
              tracks: ["tidal", "event-horizon", "deepfield", "cascade", "stratus"]),
        Album(id: "lightyears", title: "Lightyears", artistId: "skyfold", year: 2025, type: "Album",
              cover: .cover("c39bf5", "6a3fb0", "1f1138"),
              tracks: ["lift", "ascent", "skyline", "mirage", "elevation", "pulsewave"]),
        Album(id: "goldenhour", title: "Golden Hour", artistId: "halcyon", year: 2023, type: "EP",
              cover: .cover("f6b67a", "d4673a", "3a1812"),
              tracks: ["afterglow", "sunrise", "drifting"]),
        Album(id: "nocturne",   title: "Nocturne 432", artistId: "vector", year: 2025, type: "Album",
              cover: .cover("8fa6ff", "3b4192", "12153c"),
              tracks: ["meridian", "halcyon-t", "stratus2", "veil"]),
        Album(id: "sapphire",   title: "Sapphire Coast", artistId: "astral", year: 2024, type: "Album",
              cover: .cover("6fd6f2", "1f7fae", "082b3e"),
              tracks: ["tidal2", "coastline", "undertow", "horizon-line"]),
        Album(id: "ascend",     title: "Ascend", artistId: "solace", year: 2025, type: "Single",
              cover: .cover("f59cc6", "b34a86", "3a1230"),
              tracks: ["ascend-t", "lucid2"]),
        Album(id: "resonance",  title: "Resonance", artistId: "polaris", year: 2022, type: "Album",
              cover: .cover("93ffce", "2c9e74", "0c3324"),
              tracks: ["polaris-t", "crystalline", "minimal-sky", "driftwood"]),
    ])

    // MARK: Tracks

    private static let trackDefs: [(String, String, String, String, Int)] = [
        ("solstice", "Solstice", "lumora", "aurora", 412),
        ("northern-sky", "Northern Sky", "lumora", "aurora", 388),
        ("weightless", "Weightless", "lumora", "aurora", 451),
        ("lucid", "Lucid (Extended Mix)", "lumora", "aurora", 503),
        ("aurora-t", "Aurora", "lumora", "aurora", 367),
        ("reverie", "Reverie", "lumora", "aurora", 421),
        ("tidal", "Tidal", "aeon", "submerged", 489),
        ("event-horizon", "Event Horizon", "aeon", "submerged", 534),
        ("deepfield", "Deep Field", "aeon", "submerged", 472),
        ("cascade", "Cascade", "aeon", "submerged", 398),
        ("stratus", "Stratus", "aeon", "submerged", 415),
        ("lift", "Lift", "skyfold", "lightyears", 356),
        ("ascent", "Ascent", "skyfold", "lightyears", 402),
        ("skyline", "Skyline", "skyfold", "lightyears", 378),
        ("mirage", "Mirage", "skyfold", "lightyears", 433),
        ("elevation", "Elevation", "skyfold", "lightyears", 467),
        ("pulsewave", "Pulsewave", "skyfold", "lightyears", 344),
        ("afterglow", "Afterglow", "halcyon", "goldenhour", 391),
        ("sunrise", "Sunrise", "halcyon", "goldenhour", 428),
        ("drifting", "Drifting", "halcyon", "goldenhour", 376),
        ("meridian", "Meridian", "vector", "nocturne", 445),
        ("halcyon-t", "Halcyon", "vector", "nocturne", 412),
        ("stratus2", "Stratus II", "vector", "nocturne", 398),
        ("veil", "Veil", "vector", "nocturne", 367),
        ("tidal2", "Tidal Lock", "astral", "sapphire", 478),
        ("coastline", "Coastline", "astral", "sapphire", 401),
        ("undertow", "Undertow", "astral", "sapphire", 456),
        ("horizon-line", "Horizon Line", "astral", "sapphire", 389),
        ("ascend-t", "Ascend", "solace", "ascend", 384),
        ("lucid2", "Lucid (Solace Rework)", "solace", "ascend", 412),
        ("polaris-t", "Polaris", "polaris", "resonance", 423),
        ("crystalline", "Crystalline", "polaris", "resonance", 398),
        ("minimal-sky", "Minimal Sky", "polaris", "resonance", 367),
        ("driftwood", "Driftwood", "polaris", "resonance", 445),
    ]

    static let tracks: [String: Track] = {
        var d: [String: Track] = [:]
        for (id, title, artistId, albumId, dur) in trackDefs {
            let alb = albums[albumId]
            d[id] = Track(id: id, title: title,
                          artist: artists[artistId]?.name ?? "Unknown Artist",
                          album: alb?.title,
                          dur: Double(dur),
                          cover: alb?.cover ?? .placeholder,
                          artistId: artistId, albumId: albumId)
        }
        return d
    }()

    // MARK: Playlists (default library state)

    static let defaultPlaylists: [String: Playlist] = dictPL([
        Playlist(id: "deep-focus", title: "Deep Focus Trance", desc: "Long builds, no vocals. For the work that matters.", by: "You",
                 cover: .cover("7aa6f2", "33408f", "10152e", angle: 160),
                 tracks: ["solstice", "tidal", "deepfield", "meridian", "weightless", "stratus"]),
        Playlist(id: "sunrise-set", title: "Sunrise Set", desc: "Golden hour, hands in the air.", by: "You",
                 cover: .cover("f6b67a", "d4673a", "3a1812", angle: 160),
                 tracks: ["afterglow", "sunrise", "ascent", "lift", "aurora-t"]),
        Playlist(id: "afterhours", title: "Afterhours", desc: "The 3am rabbit hole.", by: "You",
                 cover: .cover("8affc0", "2c9e74", "0c3324", angle: 160),
                 tracks: ["undertow", "event-horizon", "polaris-t", "tidal2"]),
        Playlist(id: "favorites", title: "Liked Songs", desc: "", by: "You", liked: true,
                 cover: .cover("9c8cf2", "5b48c4", "1f1450", angle: 160),
                 tracks: ["aurora-t", "lift", "afterglow", "meridian", "cascade", "ascend-t", "skyline"]),
    ])

    static let quick = ["favorites", "aurora", "deep-focus", "submerged", "sunrise-set", "lightyears"]
    static let recent = ["lift", "tidal", "afterglow", "meridian", "aurora-t", "undertow"]

    // MARK: Lookups

    static func artist(_ id: String) -> Artist { artists[id] ?? artists["lumora"]! }
    static func album(_ id: String) -> Album { albums[id]! }
    static func track(_ id: String) -> Track { tracks[id]! }
    static func artistName(_ t: Track) -> String { t.artist }

    // MARK: helpers

    private static func dict(_ items: [Artist]) -> [String: Artist] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }
    private static func dict(_ items: [Album]) -> [String: Album] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }
    private static func dictPL(_ items: [Playlist]) -> [String: Playlist] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }
}
