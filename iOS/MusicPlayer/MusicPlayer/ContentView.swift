//
//  ContentView.swift
//  MusicPlayer
//
//  AURA root shell: tab content, per-tab navigation overlays, floating
//  mini-player + tab bar, the Now Playing sheet, menus, and toast.
//

import SwiftUI

struct ContentView: View {
    @State private var app = AppModel.shared

    var body: some View {
        let pal = app.palette
        ZStack {
            // backdrop
            pal.bg.ignoresSafeArea()
            RadialGradient(colors: [pal.bgGradTop, pal.bg],
                           center: UnitPoint(x: 0.5, y: -0.08),
                           startRadius: 0, endRadius: 620)
                .ignoresSafeArea()

            dimmedGroup

            // Now Playing sheet
            if app.nowPlayingOpen {
                NowPlayingView()
                    .transition(.move(edge: .bottom))
                    .zIndex(40)
            }

            // Bottom-sheet menus
            if let modal = app.modal {
                menuView(modal).zIndex(70)
            }

            // Toast
            if let msg = app.toastMsg {
                ToastView(msg: msg)
                    .padding(.bottom, 110)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .allowsHitTesting(false)
                    .zIndex(90)
            }
        }
        .environment(app)
        .environment(\.palette, pal)
        .preferredColorScheme(app.theme == .dark ? .dark : .light)
        .tint(pal.accent)
        .animation(.easeOut(duration: 0.46), value: app.nowPlayingOpen)
        .animation(.easeOut(duration: 0.25), value: app.toastMsg)
    }

    // MARK: Dimmed (tab + overlays + bottom bar)

    private var dimmedGroup: some View {
        let np = app.nowPlayingOpen
        return ZStack(alignment: .bottom) {
            // base tab screen
            tabContent.frame(maxWidth: .infinity, maxHeight: .infinity)

            // pushed route overlay
            if let route = app.topRoute {
                routeView(route)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)))
                    .zIndex(1)
            }

            // floating mini player + tab bar
            if !isManageRoute {
                VStack(spacing: 6) {
                    MiniPlayer().padding(.horizontal, 8)
                    TabBarView()
                }
                .zIndex(2)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.34), value: app.stacks[app.tab]?.count ?? 0)
        .scaleEffect(np ? 0.94 : 1, anchor: .top)
        .offset(y: np ? 8 : 0)
        .brightness(np ? -0.28 : 0)
        .clipShape(RoundedRectangle(cornerRadius: np ? 30 : 0, style: .continuous))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch app.tab {
        case .home: HomeScreen()
        case .search: SearchScreen()
        case .library: LibraryScreen()
        case .settings: SettingsScreen()
        }
    }

    private var isManageRoute: Bool {
        if case .manage = app.topRoute { return true }
        return false
    }

    @ViewBuilder
    private func routeView(_ route: Route) -> some View {
        switch route {
        case .album(let id): DetailScreen(kind: .album, id: id).id("al" + id)
        case .playlist(let id): DetailScreen(kind: .playlist, id: id).id("pl" + id)
        case .artist(let id): ArtistScreen(id: id).id("ar" + id)
        case .manage(let id): ManagePlaylistView(id: id).id("mg" + id)
        }
    }

    @ViewBuilder
    private func menuView(_ modal: Modal) -> some View {
        let close = { app.modal = nil }
        switch modal {
        case .track(let t, let ctx): TrackMenu(trackId: t, ctx: ctx, onClose: close)
        case .add(let t): AddToPlaylistMenu(trackId: t, onClose: close)
        case .create(let add): CreatePlaylistMenu(addTrackId: add, onClose: close)
        case .collection(let kind, let id): CollectionMenu(kind: kind, id: id, onClose: close)
        }
    }
}

#Preview {
    ContentView()
}
