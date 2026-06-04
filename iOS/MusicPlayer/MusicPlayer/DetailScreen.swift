//
//  DetailScreen.swift
//  MusicPlayer
//
//  Album / playlist / artist detail with a collapsing glass header.
//

import SwiftUI

// MARK: - Collapsing glass header

private struct DetailHeader: View {
    let title: String
    let scrollY: CGFloat
    var threshold: CGFloat = 230
    let onBack: () -> Void

    private var op: Double { min(1, max(0, Double((scrollY - threshold) / 60))) }

    var body: some View {
        HStack {
            Button(action: onBack) {
                ZStack { AuraIcon(name: "back", size: 22, weight: .semibold, color: .white) }
                    .frame(width: 38, height: 38)
                    .background(Color.black.opacity(0.32), in: Circle())
            }.press()
            Spacer()
            Text(title).font(.system(size: 16.5, weight: .bold)).foregroundStyle(.white)
                .lineLimit(1).opacity(op)
            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
        .frame(height: 96, alignment: .bottom)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).opacity(op > 0.05 ? 1 : 0)
                Rectangle().fill(Color(hex: "0a0a0e").opacity(op * 0.66))
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(op > 0.5 ? 0.1 : 0)).frame(height: 0.5) }
    }
}

// MARK: - Track row within a context

struct TrackRowCtx: View {
    let track: Track
    let index: Int
    let ctx: PlayContext
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal

    var body: some View {
        let isCur = app.player.trackId == track.id
        let playing = isCur && app.player.isPlaying
        HStack(spacing: 13) {
            ZStack {
                if playing { EQBars() }
                else {
                    Text("\(index)").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(isCur ? pal.accent : pal.text3)
                }
            }.frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.system(size: 15.5, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(isCur ? pal.accent : pal.text)
                HStack(spacing: 6) {
                    if app.isDownloaded(track.id) { AuraIcon(name: "downloaded", size: 13, color: pal.accent) }
                    Text(Catalog.artistName(track)).font(.tSub).foregroundStyle(pal.text2).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(Fmt.time(track.dur)).font(.system(size: 13)).monospacedDigit().foregroundStyle(pal.text3)
            Button { app.openTrackMenu(track.id, ctx) } label: {
                AuraIcon(name: "more", size: 20, color: pal.text3).padding(6)
            }.press()
        }
        .padding(.horizontal, 20).padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { app.playTrack(track.id, ctx) }
    }
}

// MARK: - Album / Playlist

struct DetailScreen: View {
    let kind: PlayContext.Kind   // .album or .playlist
    let id: String
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal
    @State private var scrollY: CGFloat = 0

    private var isPlaylist: Bool { kind == .playlist }

    var body: some View {
        let playlist = isPlaylist ? app.getPlaylist(id) : nil
        // Guard: a deleted playlist can briefly remain on the stack.
        if isPlaylist && playlist == nil {
            Color.clear.onAppear { app.back() }
        } else {
            content(playlist: playlist)
        }
    }

    @ViewBuilder
    private func content(playlist: Playlist?) -> some View {
        let album = isPlaylist ? nil : Catalog.album(id)
        let title = playlist?.title ?? album?.title ?? ""
        let desc = playlist?.desc ?? ""
        let cover = playlist?.cover ?? album!.cover
        let trackIds = playlist?.tracks ?? album!.tracks
        let tracks = trackIds.compactMap { Catalog.tracks[$0] }
        let palette = cover.palette
        let totalSec = tracks.reduce(0) { $0 + $1.dur }
        let owner = isPlaylist ? (playlist!.liked ? "AURA" : playlist!.by) : Catalog.artist(album!.artistId).name
        let ctx = PlayContext(kind: kind, id: id)
        let isLikedSongs = isPlaylist && (playlist?.liked ?? false)

        ZStack(alignment: .top) {
            pal.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    hero(title: title, desc: desc, cover: cover, palette: palette,
                         owner: owner, count: tracks.count, minutes: totalSec / 60,
                         isPlaylist: isPlaylist, isLikedSongs: isLikedSongs)
                    actionRow(ctx: ctx, isPlaylist: isPlaylist, isLikedSongs: isLikedSongs)
                    VStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.offset) { i, t in
                            TrackRowCtx(track: t, index: i + 1, ctx: ctx)
                        }
                    }
                    if isPlaylist && !isLikedSongs {
                        Button { app.openManage(id) } label: {
                            HStack(spacing: 11) {
                                ZStack { AuraIcon(name: "plus", size: 24, color: pal.text2) }
                                    .frame(width: 42, height: 42)
                                    .background(pal.surface3, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text("Add to this playlist").font(.system(size: 15.5, weight: .semibold)).foregroundStyle(pal.text2)
                                Spacer()
                            }
                            .padding(.horizontal, 20).padding(.vertical, 14)
                        }.press()
                    }
                    if !isPlaylist {
                        Text("\(album!.year) · AURA Records · \(tracks.count) songs")
                            .font(.system(size: 12.5)).foregroundStyle(pal.text3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20).padding(.top, 18)
                    }
                }
                .padding(.bottom, 200)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, new in scrollY = new }

            DetailHeader(title: title, scrollY: scrollY, onBack: app.back)
                .ignoresSafeArea(edges: .top)
        }
    }

    private func hero(title: String, desc: String, cover: Artwork, palette: [Color],
                      owner: String, count: Int, minutes: Int,
                      isPlaylist: Bool, isLikedSongs: Bool) -> some View {
        ZStack(alignment: .top) {
            LinearGradient(stops: [
                .init(color: palette[1], location: 0),
                .init(color: palette[2], location: 0.55),
                .init(color: pal.bg, location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .opacity(0.92)

            Circle().fill(palette[0]).frame(width: 320, height: 320)
                .blur(radius: 70).opacity(0.4)
                .offset(y: -40)

            VStack(spacing: 0) {
                if isLikedSongs {
                    ZStack { AuraIcon(name: "heart", size: 72, filled: true, color: .white) }
                        .frame(width: 176, height: 176)
                        .background(Palette.likedGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 25, y: 18)
                } else {
                    Cover(art: cover, size: 176, radius: 16, shadow: true)
                }
                Text(title).font(.system(size: 26, weight: .heavy)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).padding(.top, 18)
                if isPlaylist && !desc.isEmpty {
                    Text(desc).font(.system(size: 13.5)).foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center).frame(maxWidth: 300).padding(.top, 7)
                }
                HStack(spacing: 8) {
                    if !isLikedSongs {
                        Circle().fill(isPlaylist ? AnyShapeStyle(Palette.likedGradient)
                            : AnyShapeStyle(angledGradient(140, [palette[0], palette[1]])))
                            .frame(width: 22, height: 22)
                    }
                    Text(owner).font(.system(size: 13.5, weight: .bold)).foregroundStyle(.white)
                    Text("· \(count) songs · \(minutes) min").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
                .padding(.top, 10)
            }
            .padding(.top, 106)
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
    }

    private func actionRow(ctx: PlayContext, isPlaylist: Bool, isLikedSongs: Bool) -> some View {
        HStack {
            HStack(spacing: 18) {
                Button { app.toggleSave(kind == .album ? "album" : "playlist", id) } label: {
                    AuraIcon(name: app.isSaved(kind == .album ? "album" : "playlist", id) ? "check-circle" : "plus-circle",
                             size: 28, color: app.isSaved(kind == .album ? "album" : "playlist", id) ? pal.accent : pal.text2)
                }.press()
                Button { app.toast("Downloading…") } label: {
                    AuraIcon(name: "download", size: 26, color: pal.text2)
                }.press()
                if isPlaylist && !isLikedSongs {
                    Button { app.openManage(id) } label: { AuraIcon(name: "edit", size: 24, color: pal.text2) }.press()
                }
                Button { app.openCollectionMenu(kind == .album ? "album" : "playlist", id) } label: {
                    AuraIcon(name: "more", size: 26, color: pal.text2)
                }.press()
            }
            Spacer()
            HStack(spacing: 14) {
                Button { app.toggleShuffle() } label: {
                    AuraIcon(name: "shuffle", size: 24, color: app.player.shuffle ? pal.accent : pal.text2)
                }.press()
                PlayFab(size: 56, playing: app.isCtxPlaying(ctx)) { app.playContext(ctx) }
            }
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 10)
    }
}

// MARK: - Artist

struct ArtistScreen: View {
    let id: String
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal
    @State private var scrollY: CGFloat = 0

    var body: some View {
        let ar = Catalog.artist(id)
        let albums = Catalog.albums.values.filter { $0.artistId == id }.sorted { $0.year > $1.year }
        let popularIds = Array(albums.flatMap { $0.tracks }.prefix(5))
        let popular = popularIds.map { Catalog.track($0) }
        let ctx = PlayContext(kind: .artist, id: id, tracks: popularIds)

        ZStack(alignment: .top) {
            pal.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        RadialGradient(colors: [Color(hex: ar.mono[0]), Color(hex: ar.mono[1])],
                                       center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0, endRadius: 400)
                        LinearGradient(stops: [.init(color: .clear, location: 0.4), .init(color: .black.opacity(0.55), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(ar.name).font(.system(size: 40, weight: .black)).foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.3), radius: 20, y: 2)
                            Text("\(ar.followers) monthly listeners").font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 20).padding(.bottom, 20)
                    }
                    .frame(height: 340)

                    HStack {
                        Button { app.toggleFollow(id) } label: {
                            Text(app.isFollowing(id) ? "Following" : "Follow")
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(pal.text)
                                .padding(.horizontal, 20).frame(height: 36)
                                .overlay(Capsule().strokeBorder(pal.line2, lineWidth: 1.4))
                        }.press()
                        Spacer()
                        HStack(spacing: 16) {
                            Button { app.toggleShuffle() } label: {
                                AuraIcon(name: "shuffle", size: 24, color: app.player.shuffle ? pal.accent : pal.text2)
                            }.press()
                            PlayFab(size: 54, playing: app.isCtxPlaying(ctx)) { app.playContext(ctx) }
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)

                    AuraSection(title: "Popular") {
                        VStack(spacing: 0) {
                            ForEach(Array(popular.enumerated()), id: \.offset) { i, t in
                                TrackRowCtx(track: t, index: i + 1, ctx: ctx)
                            }
                        }
                    }
                    AuraSection(title: "Discography") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 14) {
                                ForEach(albums) { al in
                                    CardTile(art: al.cover, title: al.title, subtitle: "\(al.type) · \(al.year)") { app.openAlbum(al.id) }
                                }
                            }.padding(.horizontal, 20).padding(.bottom, 4)
                        }
                    }
                    AuraSection(title: "About") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(ar.bio).font(.system(size: 14.5)).foregroundStyle(pal.text2).lineSpacing(4)
                            (Text(ar.followers).font(.system(size: 13, weight: .bold)).foregroundStyle(pal.text)
                             + Text(" monthly listeners").font(.system(size: 13)).foregroundStyle(pal.text3))
                        }
                        .padding(18)
                        .background(angledGradient(150, [Color(hex: ar.mono[0]).opacity(0.13), pal.surface2]),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(pal.line, lineWidth: 0.5))
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 200)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, new in scrollY = new }

            DetailHeader(title: ar.name, scrollY: scrollY, threshold: 220, onBack: app.back)
                .ignoresSafeArea(edges: .top)
        }
    }
}
