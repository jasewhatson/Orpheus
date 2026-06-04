//
//  Components.swift
//  MusicPlayer
//
//  Reusable atoms: press feedback, equalizer, sections, track rows,
//  card tiles, play button, mini player, tab bar, scrubber, toast.
//

import SwiftUI

// MARK: - Press feedback

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.955 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}
extension View {
    func press() -> some View { buttonStyle(PressStyle()) }
}

// MARK: - Equalizer badge

struct EQBars: View {
    @Environment(\.palette) private var pal
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    let phase = Double(i) * 0.9
                    let f = 0.25 + 0.75 * (0.5 + 0.5 * sin(t * 6 + phase))
                    Capsule().fill(pal.accent)
                        .frame(width: 2.6, height: 14 * f)
                }
            }
            .frame(height: 14)
        }
    }
}

// MARK: - Section

struct AuraSection<Content: View>: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @Environment(\.palette) private var pal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.tSection).foregroundStyle(pal.text)
                Spacer()
                if let action {
                    Button { onAction?() } label: {
                        Text(action).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(pal.text2)
                    }.press()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 13)
            content
        }
        .padding(.top, 26)
    }
}

// MARK: - Track row (generic)

struct TrackRow: View {
    let track: Track
    var showCover = true
    var index: Int? = nil
    var dense = false
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal

    var body: some View {
        let isCur = app.player.trackId == track.id
        let playing = isCur && app.player.isPlaying
        HStack(spacing: 12) {
            if let index, !showCover {
                ZStack {
                    if playing { EQBars() }
                    else {
                        Text("\(index)").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(isCur ? pal.accent : pal.text3)
                    }
                }
                .frame(width: 22)
            }
            if showCover {
                Cover(art: Catalog.album(track.albumId).cover, size: dense ? 44 : 50, radius: 9)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.system(size: 15.5, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(isCur ? pal.accent : pal.text)
                HStack(spacing: 6) {
                    if app.isDownloaded(track.id) {
                        AuraIcon(name: "downloaded", size: 13, color: pal.accent)
                    }
                    Text(Catalog.artistName(track)).font(.tSub).foregroundStyle(pal.text2).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if showCover && playing { EQBars() }
            Button {
                app.openTrackMenu(track.id)
            } label: {
                AuraIcon(name: "more", size: 20, color: pal.text3).padding(6)
            }.press()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, dense ? 7 : 9)
        .contentShape(Rectangle())
        .onTapGesture { app.playTrack(track.id, app.ctx) }
    }
}

// MARK: - Card tile (shelf item)

struct CardTile: View {
    let art: Artwork
    let title: String
    var subtitle: String? = nil
    var size: CGFloat = 158
    var radius: CGFloat = 14
    var circle = false
    var onTap: () -> Void
    @Environment(\.palette) private var pal

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: circle ? .center : .leading, spacing: 2) {
                Cover(art: art, size: size, radius: circle ? size / 2 : radius, shadow: true)
                    .padding(.bottom, 8)
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(pal.text)
                    .lineLimit(1).multilineTextAlignment(circle ? .center : .leading)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.tSub).foregroundStyle(pal.text2)
                        .lineLimit(2).multilineTextAlignment(circle ? .center : .leading)
                }
            }
            .frame(width: size, alignment: circle ? .center : .leading)
        }
        .press()
    }
}

// MARK: - Round play FAB

struct PlayFab: View {
    var size: CGFloat = 56
    var playing: Bool
    var accent = true
    var onTap: () -> Void
    @Environment(\.palette) private var pal

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle().fill(accent ? pal.accent : pal.text)
                AuraIcon(name: playing ? "pause" : "play", size: size * 0.46,
                         color: accent ? pal.onAccent : pal.bg)
            }
            .frame(width: size, height: size)
            .shadow(color: accent ? pal.accent.opacity(0.45) : .clear, radius: 13, y: 8)
        }
        .press()
    }
}

// MARK: - Mini player

struct MiniPlayer: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal

    var body: some View {
        let t = app.currentTrack
        let a = Catalog.album(t.albumId)
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Cover(art: a.cover, size: 44, radius: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.title).font(.system(size: 14.5, weight: .semibold)).lineLimit(1).foregroundStyle(pal.text)
                    Text(Catalog.artistName(t)).font(.system(size: 12.5)).foregroundStyle(pal.text2).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { app.toggleLike(t.id) } label: {
                    AuraIcon(name: "heart", size: 21, filled: app.isLiked(t.id),
                             color: app.isLiked(t.id) ? pal.accent : pal.text2).padding(7)
                }.press()
                Button { app.togglePlay() } label: {
                    AuraIcon(name: app.player.isPlaying ? "pause" : "play", size: 24, color: pal.text).padding(6)
                }.press()
            }
            .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 10))
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(pal.line2)
                    Capsule().fill(pal.accent).frame(width: geo.size.width * app.player.progress)
                }
                .frame(height: 2.5)
                .padding(.horizontal, 10)
            }
            .frame(height: 2.5)
            .padding(.bottom, 3)
        }
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(pal.line2, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 15, y: 10)
        .contentShape(Rectangle())
        .onTapGesture { app.nowPlayingOpen = true }
    }
}

// MARK: - Tab bar

struct TabBarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal

    private let tabs: [(Tab, String, String)] = [
        (.home, "Home", "home"),
        (.search, "Search", "search"),
        (.library, "Library", "library"),
        (.settings, "Settings", "settings"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { tab, label, icon in
                let on = app.tab == tab && !app.overlay
                Button { app.goTab(tab) } label: {
                    VStack(spacing: 4) {
                        AuraIcon(name: icon, size: 25,
                                 filled: on && icon != "settings",
                                 weight: .medium,
                                 color: on ? pal.accent : pal.text3)
                        Text(label).font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(on ? pal.accent : pal.text3)
                    }
                    .frame(maxWidth: .infinity)
                }
                .press()
            }
        }
        .padding(.top, 9)
        .frame(height: 84, alignment: .top)
        .background {
            ZStack { Rectangle().fill(.ultraThinMaterial); pal.tabbar }
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) { Rectangle().fill(pal.line).frame(height: 0.5) }
    }
}

// MARK: - Scrubber

struct Scrubber: View {
    var value: Double
    var duration: Int
    var onSeek: (Double) -> Void
    var big = false
    @Environment(\.palette) private var pal
    @State private var drag: Double? = nil

    var body: some View {
        let v = drag ?? value
        VStack(spacing: 0) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(big ? Color.white.opacity(0.22) : pal.line2)
                    Capsule().fill(big ? Color.white : pal.text)
                        .frame(width: max(0, w * v))
                    if big {
                        Circle().fill(.white)
                            .frame(width: 13, height: 13)
                            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                            .offset(x: max(0, w * v) - 6.5)
                    }
                }
                .frame(height: big ? 6 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in drag = min(1, max(0, g.location.x / w)) }
                        .onEnded { g in
                            let f = min(1, max(0, g.location.x / w))
                            onSeek(f); drag = nil
                        }
                )
            }
            .frame(height: 16)
            if big {
                HStack {
                    Text(Fmt.time(v * Double(duration)))
                    Spacer()
                    Text("-" + Fmt.time(Double(duration) - v * Double(duration)))
                }
                .font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, -2)
            }
        }
    }
}

// MARK: - Toast

struct ToastView: View {
    let msg: String
    @Environment(\.palette) private var pal
    var body: some View {
        Text(msg)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(pal.text)
            .padding(.vertical, 12).padding(.horizontal, 20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(pal.line2, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
    }
}

// MARK: - Chip

struct Chip: View {
    let label: String
    var active = false
    var onTap: () -> Void = {}
    @Environment(\.palette) private var pal
    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? pal.onAccent : pal.text)
                .padding(.horizontal, 15)
                .frame(height: 34)
                .background(active ? pal.accent : pal.surface2, in: Capsule())
                .overlay(active ? nil : Capsule().strokeBorder(pal.line, lineWidth: 0.5))
        }
        .press()
    }
}
