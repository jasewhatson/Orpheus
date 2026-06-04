//
//  LibraryScreen.swift
//  MusicPlayer
//

import SwiftUI

private struct LibItem: Identifiable {
    enum Kind { case playlist, album, artist }
    let id: String
    let kind: Kind
    let title: String
    let art: Artwork
    let liked: Bool
    let subtitle: String
    let downloaded: Bool
    var url: URL? = nil
}

struct LibraryScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal
    @State private var filter = "All"
    @State private var grid = false
    @State private var sort = "Recents"

    private let filters = ["All", "Playlists", "Albums", "Artists", "Downloaded"]

    private var items: [LibItem] {
        var out: [LibItem] = []
        if app.settings.serverEnabled {
            // Real library from the server, plus the local Liked Songs.
            for p in app.serverPlaylistsList {
                out.append(LibItem(id: p.id, kind: .playlist, title: p.title, art: p.cover, liked: false,
                                   subtitle: p.desc.isEmpty ? "Playlist" : "Playlist · \(p.desc)",
                                   downloaded: false, url: app.serverCoverURL[p.id]))
            }
            if let fav = app.playlists["favorites"] {
                out.append(LibItem(id: fav.id, kind: .playlist, title: fav.title, art: fav.cover, liked: true,
                                   subtitle: "Playlist · \(fav.tracks.count) songs", downloaded: false))
            }
        } else {
            for p in orderedPlaylists() {
                out.append(LibItem(id: p.id, kind: .playlist, title: p.title, art: p.cover, liked: p.liked,
                                   subtitle: p.liked ? "Playlist · \(p.tracks.count) songs" : "Playlist · \(p.by)",
                                   downloaded: p.id == "deep-focus"))
            }
            for id in ["aurora", "submerged", "goldenhour"] {
                let a = Catalog.album(id)
                out.append(LibItem(id: id, kind: .album, title: a.title, art: a.cover, liked: false,
                                   subtitle: "Album · \(Catalog.artist(a.artistId).name)", downloaded: false))
            }
            for id in ["lumora", "astral"] {
                let ar = Catalog.artist(id)
                out.append(LibItem(id: id, kind: .artist, title: ar.name, art: ar.artwork, liked: false,
                                   subtitle: "Artist", downloaded: false))
            }
        }
        switch filter {
        case "Playlists": out = out.filter { $0.kind == .playlist }
        case "Albums": out = out.filter { $0.kind == .album }
        case "Artists": out = out.filter { $0.kind == .artist }
        case "Downloaded": out = out.filter { $0.kind == .playlist && $0.id == "deep-focus" }
        default: break
        }
        if sort == "A–Z" { out.sort { $0.title < $1.title } }
        return out
    }

    private func orderedPlaylists() -> [Playlist] {
        // keep stable, defaults first then any created
        let order = ["deep-focus", "sunrise-set", "afterhours", "favorites"]
        var result: [Playlist] = order.compactMap { app.playlists[$0] }
        for (id, p) in app.playlists where !order.contains(id) { result.append(p) }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                controls
                if grid { gridBody } else { listBody }
            }
            .padding(.top, 10)
            .padding(.bottom, 200)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Your Library").font(.tLarge).foregroundStyle(pal.text)
                Spacer()
                Button { app.openCreatePlaylist() } label: {
                    AuraIcon(name: "plus", size: 26, color: pal.text).frame(width: 42, height: 42)
                }.press()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters, id: \.self) { f in
                        Chip(label: f, active: filter == f) { filter = f }
                    }
                }
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
    }

    private var controls: some View {
        HStack {
            Button { sort = sort == "Recents" ? "A–Z" : "Recents" } label: {
                HStack(spacing: 7) {
                    AuraIcon(name: "sort", size: 16, color: pal.text2)
                    Text(sort).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(pal.text2)
                }
            }.press()
            Spacer()
            Button { grid.toggle() } label: {
                AuraIcon(name: grid ? "list" : "grid", size: 20, color: pal.text2)
            }.press()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16).padding(.bottom, 6)
    }

    private var gridBody: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
            ForEach(items) { i in
                CardTile(art: i.art, url: i.url, title: i.title, subtitle: i.subtitle, size: 158,
                         radius: i.liked ? 14 : 12, circle: i.kind == .artist) { open(i) }
            }
        }
        .padding(.horizontal, 20).padding(.top, 8)
    }

    private var listBody: some View {
        VStack(spacing: 0) {
            ForEach(items) { i in
                Button { open(i) } label: { row(i) }.press()
            }
            Button { app.openCreatePlaylist() } label: {
                HStack(spacing: 13) {
                    ZStack { AuraIcon(name: "plus", size: 26, color: pal.text2) }
                        .frame(width: 56, height: 56)
                        .background(pal.surface3, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("Add playlist").font(.system(size: 16, weight: .semibold)).foregroundStyle(pal.text2)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }.press()
        }
        .padding(.horizontal, 8).padding(.top, 4)
    }

    private func row(_ i: LibItem) -> some View {
        HStack(spacing: 13) {
            if i.liked {
                ZStack { AuraIcon(name: "heart", size: 26, filled: true, color: .white) }
                    .frame(width: 56, height: 56)
                    .background(Palette.likedGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Cover(art: i.art, url: i.url, size: 56, radius: i.kind == .artist ? 28 : 11)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(i.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(pal.text).lineLimit(1)
                HStack(spacing: 6) {
                    if i.downloaded { AuraIcon(name: "downloaded", size: 13, color: pal.accent) }
                    Text(i.subtitle).font(.tSub).foregroundStyle(pal.text2).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func open(_ i: LibItem) {
        switch i.kind {
        case .artist: app.openArtist(i.id)
        case .album: app.openAlbum(i.id)
        case .playlist: app.openPlaylist(i.id)
        }
    }
}
