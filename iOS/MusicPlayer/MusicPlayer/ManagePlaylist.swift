//
//  ManagePlaylist.swift
//  MusicPlayer
//
//  Edit a playlist: rename, describe, reorder, remove, and add songs.
//

import SwiftUI

struct ManagePlaylistView: View {
    let id: String
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal

    @State private var name = ""
    @State private var desc = ""
    @State private var order: [String] = []
    @State private var adding = false
    @State private var query = ""
    @State private var loaded = false

    var body: some View {
        ZStack {
            pal.bg.ignoresSafeArea()
            if adding { addSongs } else { editor }
        }
        .onAppear {
            guard !loaded, let pl = app.getPlaylist(id) else { return }
            name = pl.title; desc = pl.desc; order = pl.tracks; loaded = true
        }
    }

    private func saveAndClose() {
        app.savePlaylist(id, title: name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name, desc: desc, tracks: order)
        app.back()
    }

    private var editor: some View {
        VStack(spacing: 0) {
            HStack {
                Button { app.back() } label: { Text("Cancel").font(.system(size: 16, weight: .medium)).foregroundStyle(pal.text2) }.press()
                Spacer()
                Text("Edit playlist").font(.system(size: 16.5, weight: .bold)).foregroundStyle(pal.text)
                Spacer()
                Button { saveAndClose() } label: { Text("Done").font(.system(size: 16, weight: .bold)).foregroundStyle(pal.accent) }.press()
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 0) {
                    if let pl = app.getPlaylist(id) {
                        VStack(spacing: 0) {
                            ZStack {
                                Cover(art: pl.cover, size: 150, radius: 14, shadow: true)
                                VStack(spacing: 6) {
                                    AuraIcon(name: "edit", size: 26, color: .white)
                                    Text("Change").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                }
                                .frame(width: 150, height: 150)
                                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            TextField("", text: $name, prompt: Text("Playlist name").foregroundStyle(pal.text3))
                                .font(.system(size: 24, weight: .heavy)).foregroundStyle(pal.text)
                                .multilineTextAlignment(.center).padding(.top, 18)
                            TextField("", text: $desc, prompt: Text("Add a description").foregroundStyle(pal.text3))
                                .font(.system(size: 14)).foregroundStyle(pal.text2)
                                .multilineTextAlignment(.center).padding(.top, 4)
                        }
                        .padding(.horizontal, 24).padding(.top, 12)
                    }

                    Button { adding = true } label: {
                        HStack(spacing: 14) {
                            ZStack { AuraIcon(name: "plus", size: 24, color: pal.accent) }
                                .frame(width: 42, height: 42)
                                .background(pal.surface3, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text("Add songs").font(.system(size: 16, weight: .bold)).foregroundStyle(pal.accent)
                            Spacer()
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)
                    }.press()

                    if order.isEmpty {
                        Text("No songs yet — add some.").font(.system(size: 14)).foregroundStyle(pal.text3)
                            .frame(maxWidth: .infinity).padding(40)
                    } else {
                        ReorderableList(ids: order, rowHeight: 62, handleColor: pal.text3,
                                        draggingBackground: pal.surface2, onReorder: { order = $0 }) { tid in
                            let t = app.track(tid)
                            HStack(spacing: 12) {
                                Button { order.removeAll { $0 == tid } } label: {
                                    AuraIcon(name: "minus-circle", size: 24, color: pal.danger)
                                }.press()
                                Cover(art: t.cover, url: t.artworkURL, size: 46, radius: 9)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(pal.text).lineLimit(1)
                                    Text(Catalog.artistName(t)).font(.tSub).foregroundStyle(pal.text2).lineLimit(1)
                                }
                            }
                            .padding(.leading, 18)
                        }
                    }
                }
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var addSongs: some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let candidates = Catalog.tracks.values
            .filter { q.isEmpty || ($0.title + Catalog.artistName($0)).lowercased().contains(q) }
            .sorted { $0.title < $1.title }
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 9) {
                    AuraIcon(name: "search", size: 18, color: pal.text3)
                    TextField("", text: $query, prompt: Text("Search songs to add").foregroundStyle(pal.text3))
                        .font(.system(size: 15.5)).foregroundStyle(pal.text)
                }
                .padding(.horizontal, 13).frame(height: 42)
                .background(pal.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(pal.line, lineWidth: 0.5))
                Button { adding = false; query = "" } label: {
                    Text("Done").font(.system(size: 15, weight: .bold)).foregroundStyle(pal.accent)
                }.press()
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(candidates) { t in
                        let has = order.contains(t.id)
                        HStack(spacing: 13) {
                            Cover(art: t.cover, url: t.artworkURL, size: 48, radius: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(pal.text).lineLimit(1)
                                Text(t.artist).font(.tSub).foregroundStyle(pal.text2).lineLimit(1)
                            }
                            Spacer()
                            ZStack {
                                Circle().fill(has ? pal.accent : .clear).frame(width: 30, height: 30)
                                if has { AuraIcon(name: "check", size: 17, weight: .bold, color: pal.onAccent) }
                                else {
                                    Circle().strokeBorder(pal.line2, lineWidth: 2).frame(width: 30, height: 30)
                                    AuraIcon(name: "plus", size: 18, color: pal.text2)
                                }
                            }
                        }
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { if has { order.removeAll { $0 == t.id } } else { order.append(t.id) } }
                    }
                }
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
    }
}
