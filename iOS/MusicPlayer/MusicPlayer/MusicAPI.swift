//
//  MusicAPI.swift
//  MusicPlayer
//
//  Client for the AURA music server (server/aura_server.py).
//

import Foundation

// MARK: - Wire types (match the server JSON)

struct APIPlaylistSummary: Codable {
    let id: String
    let name: String
    let trackCount: Int
}

struct APITrack: Codable {
    let id: String
    let file: String
    let title: String
    let artist: String
    let album: String?
    let duration: Double?
    let hasLyrics: Bool
    let audioUrl: String
    let lyricsUrl: String?
    let artworkUrl: String?
}

struct APIPlaylistDetail: Codable {
    let id: String
    let name: String
    let tracks: [APITrack]
}

struct APIHealth: Codable {
    let name: String
    let version: String?
    let playlistCount: Int
    let mutagen: Bool?
    let ffmpeg: Bool?
}

// MARK: - Client

struct MusicAPI {
    let baseURL: URL

    func health() async throws -> APIHealth { try await get("/health") }
    func playlists() async throws -> [APIPlaylistSummary] { try await get("/playlists") }
    func playlist(_ name: String) async throws -> APIPlaylistDetail {
        try await get("/playlists/" + encode(name))
    }

    /// Resolve a server-relative URL (e.g. `/playlists/…/audio`) to absolute.
    func absolute(_ relative: String) -> URL? {
        if let u = URL(string: relative), u.scheme != nil { return u }
        return URL(string: relative, relativeTo: baseURL)?.absoluteURL
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = absolute(path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }
}

// MARK: - LRC parsing

enum LRC {
    /// Parse `[mm:ss.xx]` timestamped lyrics into ordered lines.
    static func parse(_ text: String) -> [LyricLine] {
        var out: [LyricLine] = []
        let tagRE = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let ns = line as NSString
            let matches = tagRE?.matches(in: line, range: NSRange(location: 0, length: ns.length)) ?? []
            // strip all tags to get the lyric text
            var lyric = line
            for kind in ["\\[\\d{1,2}:\\d{2}(?:[.:]\\d{1,3})?\\]", "\\[[a-zA-Z]+:[^\\]]*\\]"] {
                lyric = lyric.replacingOccurrences(of: kind, with: "", options: .regularExpression)
            }
            lyric = lyric.trimmingCharacters(in: .whitespaces)
            if matches.isEmpty {
                if !lyric.isEmpty { out.append(LyricLine(time: nil, text: lyric)) }
                continue
            }
            for m in matches {
                let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let f = ns.substring(with: m.range(at: 3))
                    frac = (Double(f) ?? 0) / pow(10, Double(f.count))
                }
                out.append(LyricLine(time: mm * 60 + ss + frac, text: lyric))
            }
        }
        return out.sorted { ($0.time ?? .infinity) < ($1.time ?? .infinity) }
    }
}
