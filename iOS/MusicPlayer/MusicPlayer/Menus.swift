//
//  Menus.swift
//  MusicPlayer
//
//  Custom bottom-sheet menus (track, add-to-playlist, create, collection)
//  with a floating rounded card and blurred scrim.
//

import SwiftUI

// MARK: - Sheet container

struct AuraSheet<Content: View>: View {
    let onClose: () -> Void
    @ViewBuilder var content: (_ close: @escaping () -> Void) -> Content
    @Environment(\.palette) private var pal
    @State private var show = false

    private func close() {
        withAnimation(.easeOut(duration: 0.26)) { show = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) { onClose() }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            pal.scrim.opacity(show ? 1 : 0).ignoresSafeArea()
                .background(show ? AnyShapeStyle(.ultraThinMaterial.opacity(0.0)) : AnyShapeStyle(.clear))
                .onTapGesture { close() }

            VStack(spacing: 0) {
                Capsule().fill(pal.line2).frame(width: 40, height: 5).padding(.top, 10).padding(.bottom, 4)
                content(close)
            }
            .frame(maxWidth: .infinity)
            .background(pal.surface1, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(pal.line2, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.4), radius: 24, y: -10)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .offset(y: show ? 0 : 700)
        }
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { show = true } }
    }
}

private struct MenuItem: View {
    let icon: String
    let label: String
    var danger = false
    var accent = false
    var onTap: () -> Void
    @Environment(\.palette) private var pal

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                AuraIcon(name: icon, size: 23, color: danger ? pal.danger : accent ? pal.accent : pal.text2)
                Text(label).font(.system(size: 16, weight: .medium))
                    .foregroundStyle(danger ? pal.danger : accent ? pal.accent : pal.text)
                Spacer()
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Track menu

struct TrackMenu: View {
    let trackId: String
    let ctx: PlayContext?
    let onClose: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal

    var body: some View {
        let t = app.track(trackId)
        let subtitle = [t.artist, t.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        let inPlaylist = ctx?.kind == .playlist && !(app.getPlaylist(ctx!.id)?.liked ?? true)
            && !app.isRemotePlaylist(ctx?.id ?? "")
        AuraSheet(onClose: onClose) { close in
            VStack(spacing: 0) {
                HStack(spacing: 13) {
                    Cover(art: t.cover, url: t.artworkURL, size: 52, radius: 11)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.system(size: 16.5, weight: .bold)).foregroundStyle(pal.text).lineLimit(1)
                        Text(subtitle).font(.tSub).foregroundStyle(pal.text2).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 16)
                .overlay(alignment: .bottom) { Rectangle().fill(pal.line).frame(height: 0.5) }

                ScrollView {
                    VStack(spacing: 0) {
                        let lk = app.isLiked(trackId)
                        MenuItem(icon: "heart", label: lk ? "Remove from Liked Songs" : "Add to Liked Songs", accent: lk) { app.toggleLike(trackId); close() }
                        MenuItem(icon: "add-list", label: "Add to playlist") { close(); after { app.openAddToPlaylist(trackId) } }
                        MenuItem(icon: "queue", label: "Add to queue") { app.addToQueue(trackId); close() }
                        MenuItem(icon: "next", label: "Play next") { app.playNext(trackId); close() }
                        let dl = app.isDownloaded(trackId)
                        MenuItem(icon: dl ? "downloaded" : "download", label: dl ? "Downloaded" : "Download", accent: dl) { app.toggleDownload(trackId); close() }
                        if let aid = t.artistId {
                            MenuItem(icon: "user", label: "Go to artist") { close(); after { app.openArtist(aid) } }
                        }
                        if let alid = t.albumId {
                            MenuItem(icon: "spinner-disc", label: "Go to album") { close(); after { app.openAlbum(alid) } }
                        }
                        MenuItem(icon: "share", label: "Share") { app.toast("Shared"); close() }
                        if inPlaylist {
                            MenuItem(icon: "minus-circle", label: "Remove from this playlist", danger: true) { app.removeFromPlaylist(ctx!.id, trackId); close() }
                        }
                    }
                }
                .frame(maxHeight: 460)
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - Add to playlist

struct AddToPlaylistMenu: View {
    let trackId: String
    let onClose: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal

    var body: some View {
        let t = app.track(trackId)
        let lists = orderedPlaylists()
        AuraSheet(onClose: onClose) { close in
            VStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("Add to playlist").font(.system(size: 17, weight: .heavy)).foregroundStyle(pal.text)
                    Text(t.title).font(.tSub).foregroundStyle(pal.text2).lineLimit(1).padding(.horizontal, 60)
                }
                .padding(.top, 4).padding(.bottom, 14)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottom) { Rectangle().fill(pal.line).frame(height: 0.5) }

                Button { close(); after { app.openCreatePlaylist(trackId) } } label: {
                    HStack(spacing: 14) {
                        ZStack { AuraIcon(name: "plus", size: 26, color: pal.accent) }
                            .frame(width: 50, height: 50)
                            .background(pal.surface3, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        Text("New playlist").font(.system(size: 16, weight: .bold)).foregroundStyle(pal.accent)
                        Spacer()
                    }
                    .padding(.horizontal, 22).padding(.vertical, 16).contentShape(Rectangle())
                }.buttonStyle(.plain)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(lists) { p in
                            let has = p.tracks.contains(trackId)
                            Button { app.togglePlaylistTrack(p.id, trackId) } label: {
                                HStack(spacing: 14) {
                                    if p.liked {
                                        ZStack { AuraIcon(name: "heart", size: 22, filled: true, color: .white) }
                                            .frame(width: 50, height: 50)
                                            .background(Palette.likedGradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                    } else { Cover(art: p.cover, size: 50, radius: 11) }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(p.title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(pal.text).lineLimit(1)
                                        Text("\(p.tracks.count) songs").font(.system(size: 12.5)).foregroundStyle(pal.text2)
                                    }
                                    Spacer()
                                    ZStack {
                                        Circle().fill(has ? pal.accent : .clear).frame(width: 26, height: 26)
                                        if has { AuraIcon(name: "check", size: 16, weight: .bold, color: pal.onAccent) }
                                        else { Circle().strokeBorder(pal.line2, lineWidth: 2).frame(width: 26, height: 26) }
                                    }
                                }
                                .padding(.horizontal, 22).padding(.vertical, 9).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 380)

                Button { close() } label: {
                    Text("Done").font(.system(size: 16, weight: .bold)).foregroundStyle(pal.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(pal.accent, in: Capsule())
                }.press()
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
            }
        }
    }

    private func orderedPlaylists() -> [Playlist] {
        let order = ["deep-focus", "sunrise-set", "afterhours", "favorites"]
        var result: [Playlist] = order.compactMap { app.playlists[$0] }
        for (id, p) in app.playlists where !order.contains(id) { result.append(p) }
        return result
    }
}

// MARK: - Create playlist

struct CreatePlaylistMenu: View {
    let addTrackId: String?
    let onClose: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal
    @State private var name = ""

    var body: some View {
        AuraSheet(onClose: onClose) { close in
            VStack(spacing: 0) {
                Text("New playlist").font(.system(size: 17, weight: .heavy)).foregroundStyle(pal.text).padding(.bottom, 18)
                ZStack { AuraIcon(name: "sparkle", size: 40, color: .white.opacity(0.85)) }
                    .frame(width: 120, height: 120)
                    .background(Palette.likedGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.bottom, 18)
                TextField("", text: $name, prompt: Text("Playlist name").foregroundStyle(pal.text3))
                    .font(.system(size: 22, weight: .heavy)).foregroundStyle(pal.text)
                    .multilineTextAlignment(.center).padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(pal.line2).frame(height: 1.5) }
                HStack(spacing: 10) {
                    Button { close() } label: {
                        Text("Cancel").font(.system(size: 15, weight: .semibold)).foregroundStyle(pal.text)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .overlay(Capsule().strokeBorder(pal.line2, lineWidth: 1.2))
                    }.press()
                    Button {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty { app.createPlaylist(n, addTrackId: addTrackId); close() }
                    } label: {
                        Text("Create").font(.system(size: 16, weight: .bold)).foregroundStyle(pal.onAccent)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(pal.accent, in: Capsule())
                            .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    }.press()
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 16)
        }
    }
}

// MARK: - Collection menu

struct CollectionMenu: View {
    let kind: String
    let id: String
    let onClose: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal

    var body: some View {
        let isPlaylist = kind == "playlist"
        let pl = isPlaylist ? app.getPlaylist(id) : nil
        let album = isPlaylist ? nil : Catalog.album(id)
        let title = pl?.title ?? album?.title ?? ""
        let cover = pl?.cover ?? album?.cover ?? .placeholder
        let sub = isPlaylist ? "Playlist" : "\(album!.type) · \(Catalog.artist(album!.artistId).name)"
        let isOwn = isPlaylist && !(pl?.liked ?? true)
        AuraSheet(onClose: onClose) { close in
            VStack(spacing: 0) {
                HStack(spacing: 13) {
                    Cover(art: cover, size: 52, radius: 11)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 16.5, weight: .bold)).foregroundStyle(pal.text).lineLimit(1)
                        Text(sub).font(.tSub).foregroundStyle(pal.text2).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 16)
                .overlay(alignment: .bottom) { Rectangle().fill(pal.line).frame(height: 0.5) }

                VStack(spacing: 0) {
                    let saved = app.isSaved(kind, id)
                    MenuItem(icon: saved ? "check-circle" : "plus-circle", label: saved ? "Added to Library" : "Add to Library", accent: saved) { app.toggleSave(kind, id); close() }
                    MenuItem(icon: "download", label: "Download") { app.toast("Downloading…"); close() }
                    MenuItem(icon: "radio", label: "Go to radio") { app.toast("Starting radio"); close() }
                    if isOwn { MenuItem(icon: "edit", label: "Edit playlist") { close(); after { app.openManage(id) } } }
                    MenuItem(icon: "share", label: "Share") { app.toast("Shared"); close() }
                    if isOwn { MenuItem(icon: "trash", label: "Delete playlist", danger: true) { app.deletePlaylist(id); close() } }
                }
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - helper

/// Defer an action briefly so a sheet finishes dismissing first.
func after(_ block: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: block)
}
