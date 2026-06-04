//
//  SearchScreen.swift
//  MusicPlayer
//

import SwiftUI

private let genres: [(String, [String])] = [
    ("Trance", ["5f8ff0", "23264a"]),
    ("Progressive", ["7be3d4", "10322f"]),
    ("Uplifting", ["f0a36b", "3a1d16"]),
    ("Psy-Trance", ["b58cf2", "241640"]),
    ("Ambient", ["67d2f0", "0e2b3e"]),
    ("Melodic Techno", ["8affc0", "0d3324"]),
    ("DJ Sets", ["f08fc0", "3a1130"]),
    ("Festival", ["7d9bff", "1b2150"]),
    ("Focus Flow", ["9c8cf2", "1f1450"]),
    ("Late Night", ["ff9d7a", "3a1410"]),
]

struct SearchScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal
    @State private var query = ""
    @FocusState private var focused: Bool

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    // Search the server library when configured, otherwise the demo catalog.
    private var serverMode: Bool { app.settings.serverEnabled }

    private var tracks: [Track] {
        let pool = serverMode ? app.serverTracks : Array(Catalog.tracks.values)
        return pool.filter {
            $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
        }.sorted { $0.title < $1.title }.prefix(serverMode ? 30 : 8).map { $0 }
    }
    private var artists: [Artist] {
        guard !serverMode else { return [] }
        return Catalog.artists.values.filter { $0.name.lowercased().contains(q) }
            .sorted { $0.name < $1.name }.prefix(4).map { $0 }
    }
    private var albums: [Album] {
        guard !serverMode else { return [] }
        return Catalog.albums.values.filter { $0.title.lowercased().contains(q) }
            .sorted { $0.title < $1.title }.prefix(4).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchBar
                if q.isEmpty { browseAll }
                else { results }
            }
            .padding(.top, 10)
            .padding(.bottom, 200)
        }
        .scrollIndicators(.hidden)
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !focused {
                Text("Search").font(.tLarge).foregroundStyle(pal.text).padding(.bottom, 16)
            }
            HStack(spacing: 10) {
                HStack(spacing: 9) {
                    AuraIcon(name: "search", size: 19, weight: .medium, color: pal.text3)
                    TextField("", text: $query, prompt: Text("Artists, songs, sets").foregroundStyle(pal.text3))
                        .focused($focused)
                        .font(.system(size: 16))
                        .foregroundStyle(pal.text)
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button { query = "" } label: { AuraIcon(name: "x", size: 18, color: pal.text3) }.press()
                    }
                }
                .padding(.horizontal, 13)
                .frame(height: 44)
                .background(pal.surface2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(pal.line, lineWidth: 0.5))

                if focused {
                    Button { query = ""; focused = false } label: {
                        Text("Cancel").font(.system(size: 15, weight: .semibold)).foregroundStyle(pal.accent)
                    }.press()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .animation(.easeOut(duration: 0.2), value: focused)
    }

    private var browseAll: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Browse all").font(.tSection).foregroundStyle(pal.text)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)], spacing: 11) {
                ForEach(genres, id: \.0) { name, c in
                    Button { } label: {
                        ZStack(alignment: .topLeading) {
                            angledGradient(135, [Color(hex: c[0]), Color(hex: c[1])])
                            Text(name).font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.3), radius: 8, y: 1)
                                .padding(13)
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.black.opacity(0.22))
                                .frame(width: 64, height: 64)
                                .rotationEffect(.degrees(28))
                                .offset(x: 0, y: 50)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                .offset(x: 14, y: 14)
                        }
                        .frame(height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }.press()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    @ViewBuilder private var results: some View {
        let topArtist = artists.first
        let topAlbum = albums.first
        VStack(alignment: .leading, spacing: 0) {
            if let a = topArtist {
                topResult(art: a.artwork, title: a.name, sub: "Artist", circle: true) { app.openArtist(a.id) }
            } else if let al = topAlbum {
                topResult(art: al.cover, title: al.title,
                          sub: "\(al.type) · \(Catalog.artist(al.artistId).name)", circle: false) { app.openAlbum(al.id) }
            } else if let t = tracks.first {
                if let aid = t.artistId {
                    let ar = Catalog.artist(aid)
                    topResult(art: ar.artwork, title: ar.name, sub: "Artist", circle: true) { app.openArtist(ar.id) }
                } else {
                    topResult(art: t.cover, url: t.artworkURL, title: t.title, sub: t.artist, circle: false) {
                        app.playTrack(t.id, app.ctx)
                    }
                }
            }

            if !tracks.isEmpty {
                AuraSection(title: "Songs") {
                    VStack(spacing: 0) { ForEach(tracks) { TrackRow(track: $0, dense: true) } }
                }
            }
            if !artists.isEmpty {
                AuraSection(title: "Artists") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(artists) { ar in
                                CardTile(art: ar.artwork, title: ar.name, subtitle: "Artist", size: 104, circle: true) { app.openArtist(ar.id) }
                            }
                        }.padding(.horizontal, 20).padding(.bottom, 4)
                    }
                }
            }
            if !albums.isEmpty {
                AuraSection(title: "Albums & EPs") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(albums) { al in
                                CardTile(art: al.cover, title: al.title, subtitle: "\(al.type) · \(al.year)") { app.openAlbum(al.id) }
                            }
                        }.padding(.horizontal, 20).padding(.bottom, 4)
                    }
                }
            }
            if topArtist == nil && topAlbum == nil && tracks.isEmpty {
                VStack(spacing: 6) {
                    Text("No results for “\(query)”").font(.system(size: 17, weight: .semibold)).foregroundStyle(pal.text2)
                    Text("Try “Lumora”, “Tidal” or “Trance”.").font(.tSub).foregroundStyle(pal.text3)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            }
        }
    }

    private func topResult(art: Artwork, url: URL? = nil, title: String, sub: String, circle: Bool, onTap: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOP RESULT").font(.tCap).tracking(0.8).foregroundStyle(pal.text3)
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 0) {
                    Cover(art: art, url: url, size: 66, radius: circle ? 33 : 12)
                    Text(title).font(.system(size: 21, weight: .heavy)).foregroundStyle(pal.text).padding(.top, 12)
                    Text(sub).font(.tSub).foregroundStyle(pal.text2).padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(pal.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(pal.line, lineWidth: 0.5))
            }.press()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
