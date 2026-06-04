//
//  NowPlaying.swift
//  MusicPlayer
//
//  Full-screen player with animated glow backdrop, scrubber, and the
//  Queue and Lyrics panels.
//

import SwiftUI

private let lyrics = [
    "[ Intro ]", "Lights low, the room dissolves", "a pulse beneath the floor",
    "Hold the breath before the drop", "we don't need anything more",
    "[ Build ]", "Hands up reaching for the sound", "every wall is coming down",
    "Weightless now, we leave the ground", "carried by the afterglow",
    "[ Drop ]", "Let it go, let it go", "into the light we flow",
    "Higher than we've ever known", "never want to come back home",
    "[ Breakdown ]", "And the night becomes a wave", "pulling everything away",
    "Stay with me until the day", "until the morning takes us slow",
]

private enum NPPanel { case main, queue, lyrics }

struct NowPlayingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal
    @State private var panel: NPPanel = .main

    var body: some View {
        let t = app.currentTrack
        let album = Catalog.album(t.albumId)
        let pal3 = album.cover.palette

        ZStack {
            // backdrop
            pal3[2].ignoresSafeArea()
            LinearGradient(stops: [
                .init(color: pal3[1], location: 0),
                .init(color: pal3[2], location: 0.6),
                .init(color: Color(hex: "050507"), location: 1)
            ], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            glows(pal3)

            VStack(spacing: 0) {
                topBar(track: t)
                switch panel {
                case .main: mainPanel(track: t, album: album)
                case .lyrics: LyricsPanel(track: t, onBack: { panel = .main })
                case .queue: QueuePanel(onBack: { panel = .main })
                }
            }
        }
        .onChange(of: app.nowPlayingOpen) { _, open in if open { panel = .main } }
    }

    private func glows(_ p: [Color]) -> some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().fill(p[0]).frame(width: 360, height: 360).blur(radius: 70).opacity(0.5)
                    .offset(x: -130 + 15 * sin(t * 0.7), y: -180 + 20 * sin(t * 0.7))
                Circle().fill(p[1]).frame(width: 300, height: 300).blur(radius: 70).opacity(0.45)
                    .offset(x: 130 - 15 * sin(t * 0.55), y: 220 - 15 * sin(t * 0.55))
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func topBar(track t: Track) -> some View {
        HStack {
            Button { app.nowPlayingOpen = false } label: {
                AuraIcon(name: "down", size: 26, weight: .semibold, color: .white).padding(6)
            }.press()
            Spacer()
            VStack(spacing: 2) {
                Text("PLAYING FROM \(app.contextLabel.uppercased())")
                    .font(.system(size: 10.5, weight: .bold)).tracking(0.8).foregroundStyle(.white.opacity(0.6))
                Text(app.contextTitle).font(.system(size: 13.5, weight: .bold)).foregroundStyle(.white).lineLimit(1)
            }
            Spacer()
            Button { app.openTrackMenu(t.id, app.ctx) } label: {
                AuraIcon(name: "more-v", size: 24, color: .white).padding(6)
            }.press()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func mainPanel(track t: Track, album: Album) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Cover(art: album.cover, size: 320, radius: 18)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.55), radius: 40, y: 30)
                .scaleEffect(app.player.isPlaying ? 1 : 0.86)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: app.player.isPlaying)
                .padding(.horizontal, 20)
            Spacer(minLength: 0)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.title).font(.system(size: 25, weight: .heavy)).foregroundStyle(.white).lineLimit(1)
                    Button { app.openArtist(t.artistId); app.nowPlayingOpen = false } label: {
                        Text(Catalog.artistName(t)).font(.system(size: 16, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                    }.press()
                }
                Spacer()
                Button { app.toggleLike(t.id) } label: {
                    AuraIcon(name: "heart", size: 28, filled: app.isLiked(t.id),
                             color: app.isLiked(t.id) ? pal.accent : .white).padding(6)
                }.press()
            }

            Scrubber(value: app.player.progress, duration: t.dur, onSeek: app.seek, big: true)
                .padding(.top, 8)

            HStack {
                Button { app.toggleShuffle() } label: {
                    AuraIcon(name: "shuffle", size: 24, color: app.player.shuffle ? pal.accent : .white.opacity(0.85)).padding(6)
                }.press()
                Spacer()
                Button { app.prev() } label: { AuraIcon(name: "prev", size: 36, color: .white).padding(4) }.press()
                Spacer()
                Button { app.togglePlay() } label: {
                    ZStack {
                        Circle().fill(.white).frame(width: 74, height: 74)
                        AuraIcon(name: app.player.isPlaying ? "pause" : "play", size: 34, color: Color(hex: "06121f"))
                    }
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 10)
                }.press()
                Spacer()
                Button { app.next() } label: { AuraIcon(name: "next", size: 36, color: .white).padding(4) }.press()
                Spacer()
                Button { app.cycleRepeat() } label: {
                    AuraIcon(name: app.player.repeatMode == .one ? "repeat-one" : "repeat", size: 24,
                             color: app.player.repeatMode != .off ? pal.accent : .white.opacity(0.85)).padding(6)
                }.press()
            }
            .padding(.top, 6).padding(.bottom, 4)

            HStack {
                Button { app.toast("Connect a device") } label: {
                    AuraIcon(name: "devices", size: 21, color: .white.opacity(0.78))
                }.press()
                Spacer()
                HStack(spacing: 26) {
                    footerButton(icon: "lyrics", label: "LYRICS") { panel = .lyrics }
                    footerButton(icon: "queue", label: "QUEUE") { panel = .queue }
                }
                Spacer()
                Button { app.toast("Shared") } label: {
                    AuraIcon(name: "share", size: 20, color: .white.opacity(0.78))
                }.press()
            }
            .padding(.top, 14).padding(.bottom, 26)
        }
        .padding(.horizontal, 26)
    }

    private func footerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                AuraIcon(name: icon, size: 20, color: .white.opacity(0.85))
                Text(label).font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white.opacity(0.85))
            }
        }.press()
    }
}

// MARK: - Lyrics

private struct LyricsPanel: View {
    let track: Track
    let onBack: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let active = Int(app.player.progress * Double(lyrics.count))
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Cover(art: Catalog.album(track.albumId).cover, size: 40, radius: 9)
                VStack(alignment: .leading, spacing: 0) {
                    Text(track.title).font(.system(size: 15, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    Text(Catalog.artistName(track)).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer()
                Button(action: onBack) { AuraIcon(name: "x", size: 22, color: .white).padding(6) }.press()
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lyrics.enumerated()), id: \.offset) { i, line in
                        let head = line.hasPrefix("[")
                        Text(head ? line.uppercased() : line)
                            .font(.system(size: head ? 14 : 23, weight: head ? .bold : .heavy))
                            .foregroundStyle(head ? .white.opacity(0.4) : (i == active ? .white : .white.opacity(0.34)))
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { app.seek(Double(i) / Double(lyrics.count)) }
                    }
                    Text("Lyrics · \(Catalog.artistName(track))")
                        .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white.opacity(0.4)).padding(.top, 20)
                }
                .animation(.easeOut(duration: 0.3), value: active)
                .padding(.horizontal, 26).padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Queue

private struct QueuePanel: View {
    let onBack: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let cur = app.currentTrack
        VStack(spacing: 0) {
            HStack {
                Text("Up Next").font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
                Spacer()
                Button(action: onBack) { AuraIcon(name: "x", size: 22, color: .white).padding(6) }.press()
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("NOW PLAYING").font(.system(size: 11.5, weight: .bold)).tracking(0.7)
                        .foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 12).padding(.bottom, 6)
                    HStack(spacing: 13) {
                        Cover(art: Catalog.album(cur.albumId).cover, size: 48, radius: 10)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(cur.title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(app.palette.accent).lineLimit(1)
                            Text(Catalog.artistName(cur)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                        Spacer()
                        EQBars()
                    }
                    .padding(.horizontal, 12).padding(.bottom, 14)

                    Text("NEXT FROM \(app.contextLabel.uppercased()): \(app.contextTitle.uppercased())")
                        .font(.system(size: 11.5, weight: .bold)).tracking(0.6)
                        .foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 12).padding(.bottom, 8)
                        .lineLimit(1)

                    if app.queue.isEmpty {
                        Text("End of queue").font(.system(size: 14)).foregroundStyle(.white.opacity(0.45))
                            .frame(maxWidth: .infinity).padding(40)
                    } else {
                        ReorderableList(ids: app.queue, rowHeight: 64,
                                        handleColor: .white.opacity(0.5),
                                        draggingBackground: .white.opacity(0.08),
                                        onReorder: app.reorderQueue) { id in
                            let tr = Catalog.track(id)
                            let idx = app.queue.firstIndex(of: id) ?? 0
                            HStack(spacing: 13) {
                                Cover(art: Catalog.album(tr.albumId).cover, size: 48, radius: 10)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(tr.title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                                    Text(Catalog.artistName(tr)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { app.jumpQueue(idx) }
                        }
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
    }
}
