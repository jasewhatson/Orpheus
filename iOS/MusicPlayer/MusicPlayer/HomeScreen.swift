//
//  HomeScreen.swift
//  MusicPlayer
//

import SwiftUI

struct HomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal

    private let chips = ["All", "Trance", "Sets & Mixes", "Focus"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if app.settings.serverEnabled { serverShelf } else { quickGrid }

                madeForYou
                newReleases
                jumpBackIn
                artistsFollowed
            }
            .padding(.top, 8)
            .padding(.bottom, 200)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Good morning").font(.system(size: 13)).foregroundStyle(pal.text2)
                    Text("Tonight").font(.tLarge).foregroundStyle(pal.text)
                }
                Spacer()
                HStack(spacing: 6) {
                    Button { app.goTab(.settings) } label: {
                        AuraIcon(name: "history", size: 21, color: pal.text2)
                            .frame(width: 40, height: 40).background(pal.surface2, in: Circle())
                    }.press()
                    Button { app.goTab(.settings) } label: {
                        Text("A").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Palette.likedGradient, in: Circle())
                    }.press()
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(chips.enumerated()), id: \.element) { i, c in
                        Chip(label: c, active: i == 0)
                    }
                }
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 20)
    }

    // A 2-up grid of the user's server playlists (Home, when a server is set).
    private var serverShelf: some View {
        let pls = app.serverPlaylistsList
        return Group {
            if pls.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().tint(pal.accent)
                    Text(app.serverLoading ? "Loading your library…" : "No playlists found")
                        .font(.tSub).foregroundStyle(pal.text2)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 16)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                    ForEach(pls) { p in
                        Button { app.openPlaylist(p.id) } label: {
                            HStack(spacing: 10) {
                                Cover(art: p.cover, url: app.serverCoverURL[p.id], size: 60, radius: 0)
                                Text(p.title).font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(pal.text).lineLimit(2).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 60)
                            .padding(.trailing, 8)
                            .background(pal.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(pal.line, lineWidth: 0.5))
                        }.press()
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16)
            }
        }
    }

    private var quickGrid: some View {
        let items: [(id: String, art: Artwork, title: String, isPl: Bool)] = Catalog.quick.map { id in
            if let p = Catalog.defaultPlaylists[id] ?? app.playlists[id] {
                return (id, p.cover, p.title, true)
            } else {
                let a = Catalog.album(id)
                return (id, a.cover, a.title, false)
            }
        }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
            ForEach(items, id: \.id) { it in
                Button {
                    it.isPl ? app.openPlaylist(it.id) : app.openAlbum(it.id)
                } label: {
                    HStack(spacing: 10) {
                        Cover(art: it.art, size: 60, radius: 0)
                        Text(it.title).font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(pal.text).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 60)
                    .padding(.trailing, 8)
                    .background(pal.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(pal.line, lineWidth: 0.5))
                }
                .press()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var madeForYou: some View {
        AuraSection(title: "Made for you", action: "See all") {
            shelf {
                ForEach(["deep-focus", "sunrise-set", "afterhours"], id: \.self) { id in
                    if let p = app.playlists[id] {
                        CardTile(art: p.cover, title: p.title, subtitle: p.desc) { app.openPlaylist(id) }
                    }
                }
            }
        }
    }

    private var newReleases: some View {
        AuraSection(title: "New from your artists", action: "See all") {
            shelf {
                ForEach(["aurora", "lightyears", "nocturne", "ascend", "sapphire"], id: \.self) { id in
                    let al = Catalog.album(id)
                    CardTile(art: al.cover, title: al.title,
                             subtitle: "\(al.type) · \(Catalog.artist(al.artistId).name)") { app.openAlbum(id) }
                }
            }
        }
    }

    private var jumpBackIn: some View {
        AuraSection(title: "Jump back in", action: "History") {
            VStack(spacing: 0) {
                ForEach(Catalog.recent, id: \.self) { id in
                    TrackRow(track: Catalog.track(id))
                }
            }
        }
    }

    private var artistsFollowed: some View {
        AuraSection(title: "Artists you follow") {
            shelf(spacing: 16) {
                ForEach(["lumora", "skyfold", "astral", "solace", "aeon", "vector"], id: \.self) { id in
                    let ar = Catalog.artist(id)
                    CardTile(art: ar.artwork, title: ar.name, subtitle: "Artist",
                             size: 104, circle: true) { app.openArtist(id) }
                }
            }
        }
    }

    @ViewBuilder
    private func shelf<C: View>(spacing: CGFloat = 14, @ViewBuilder _ content: () -> C) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: spacing) { content() }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
        }
    }
}
