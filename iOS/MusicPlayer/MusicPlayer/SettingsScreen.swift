//
//  SettingsScreen.swift
//  MusicPlayer
//

import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal

    var body: some View {
        @Bindable var app = app
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings").font(.tLarge).foregroundStyle(pal.text)
                    .padding(.horizontal, 20).padding(.top, 8)

                profileCard
                appearance

                Group(header: "Music server") {
                    SettingsRow(icon: "devices", iconBg: Color(hex: "5f8ff0"), title: "Host") {
                        TextField("192.168.20.10", text: $app.settings.serverHost)
                            .multilineTextAlignment(.trailing).frame(width: 150)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.numbersAndPunctuation)
                            .foregroundStyle(pal.text2)
                    }
                    sep
                    SettingsRow(icon: "radio", iconBg: Color(hex: "7be3d4"), title: "Port") {
                        TextField("8080", value: $app.settings.serverPort, format: .number.grouping(.never))
                            .multilineTextAlignment(.trailing).frame(width: 80)
                            .keyboardType(.numberPad)
                            .foregroundStyle(pal.text2)
                    }
                    sep
                    SettingsRow(icon: "sparkle", iconBg: Color(hex: "9c8cf2"),
                                title: "Use server library", sub: app.settings.serverEnabled ? "On" : "Off") {
                        AuraToggle(on: Binding(
                            get: { app.settings.serverEnabled },
                            set: { app.applyServerSettings(host: app.settings.serverHost,
                                                           port: app.settings.serverPort, enabled: $0) }))
                    }
                    sep
                    SettingsRow(icon: "cast", iconBg: Color(hex: "f0a36b"),
                                title: "Test connection", onTap: { app.testConnection() }) {
                        Text("Test").font(.system(size: 14, weight: .semibold)).foregroundStyle(pal.accent)
                    }
                }

                Group(header: "Playback") {
                    SettingsRow(icon: "volume", iconBg: Color(hex: "5f8ff0"),
                                title: "Crossfade", sub: app.settings.crossfade == 0 ? "Off" : "\(Int(app.settings.crossfade)) s") {
                        Slider(value: $app.settings.crossfade, in: 0...12, step: 1).frame(width: 110).tint(pal.accent)
                    }
                    sep
                    SettingsRow(icon: "radio", iconBg: Color(hex: "7be3d4"), title: "Gapless playback") {
                        AuraToggle(on: $app.settings.gapless)
                    }
                    sep
                    SettingsRow(icon: "volume-min", iconBg: Color(hex: "9c8cf2"),
                                title: "Normalize volume", sub: "Same level for all tracks") {
                        AuraToggle(on: $app.settings.normalize)
                    }
                    sep
                    SettingsRow(icon: "sparkle", iconBg: Color(hex: "f0a36b"),
                                title: "Audio quality", sub: app.settings.quality, onTap: { app.cycleQuality() }) {
                        HStack(spacing: 4) {
                            Text(app.settings.quality).font(.system(size: 14)).foregroundStyle(pal.text2)
                            AuraIcon(name: "chev", size: 16, color: pal.text4)
                        }
                    }
                }

                Group(header: "Downloads & data") {
                    SettingsRow(icon: "download", iconBg: Color(hex: "67d2f0"), title: "Download using cellular") {
                        AuraToggle(on: $app.settings.cellular)
                    }
                    sep
                    SettingsRow(icon: "downloaded", iconBg: Color(hex: "8affc0"),
                                title: "Downloaded only", sub: "Hide songs you can't play offline") {
                        AuraToggle(on: $app.settings.offline)
                    }
                }

                Group(header: "Storage") {
                    SettingsRow(icon: "downloaded", iconBg: Color(hex: "67d2f0"),
                                title: "Cache size",
                                sub: "\(fmtBytes(app.cacheBytes)) used",
                                onTap: { app.cycleCacheLimit() }) {
                        HStack(spacing: 4) {
                            Text(limitLabel(app.settings.cacheLimitMB)).font(.system(size: 14)).foregroundStyle(pal.text2)
                            AuraIcon(name: "chev", size: 16, color: pal.text4)
                        }
                    }
                    sep
                    SettingsRow(icon: "trash", iconBg: pal.danger,
                                title: "Clear cache", sub: "Audio, artwork & metadata",
                                onTap: { app.clearCache() }) {
                        Text("Clear").font(.system(size: 14, weight: .semibold)).foregroundStyle(pal.danger)
                    }
                }

                Group(header: "Account") {
                    SettingsRow(icon: "user", iconBg: Color(hex: "f08fc0"), title: "Account", sub: "alex@aura.fm") { chevron }
                    sep
                    SettingsRow(icon: "bell", iconBg: Color(hex: "7d9bff"), title: "Notifications") { chevron }
                    sep
                    SettingsRow(icon: "devices", iconBg: Color(hex: "b58cf2"), title: "Connect a device") { chevron }
                }

                VStack(spacing: 16) {
                    Button { app.toast("Signed out (demo)") } label: {
                        Text("Sign out").font(.system(size: 15.5, weight: .bold)).foregroundStyle(pal.danger)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(pal.surface1, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(pal.line, lineWidth: 0.5))
                    }.press()
                    Text("AURA · v2.4.0 · Made for trance").font(.system(size: 12)).foregroundStyle(pal.text4)
                }
                .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 10)
            }
            .padding(.bottom, 200)
        }
        .scrollIndicators(.hidden)
        .onAppear { app.refreshCacheUsage() }
    }

    private func fmtBytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
    private func limitLabel(_ mb: Int) -> String {
        mb >= 1024 ? "\(mb / 1024) GB" : "\(mb) MB"
    }

    private var chevron: some View { AuraIcon(name: "chev", size: 17, color: pal.text4) }
    private var sep: some View { Rectangle().fill(pal.line).frame(height: 0.5).padding(.leading, 59) }

    private var profileCard: some View {
        HStack(spacing: 14) {
            Text("A").font(.system(size: 26, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 60, height: 60).background(Palette.likedGradient, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text("Alex Rivera").font(.system(size: 19, weight: .bold)).foregroundStyle(pal.text)
                HStack(spacing: 5) {
                    AuraIcon(name: "sparkle", size: 12, color: pal.onAccent)
                    Text("AURA PREMIUM").font(.system(size: 11, weight: .heavy)).foregroundStyle(pal.onAccent)
                }
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(pal.accent, in: Capsule())
            }
            Spacer()
            AuraIcon(name: "chev", size: 18, color: pal.text3)
        }
        .padding(18)
        .background(angledGradient(140, [pal.accentSoft, pal.surface1]), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(pal.line, lineWidth: 0.5))
        .padding(.horizontal, 14).padding(.top, 18)
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("APPEARANCE").font(.tCap).tracking(0.7).foregroundStyle(pal.text3)
                .padding(.horizontal, 20).padding(.bottom, 8)
            HStack(spacing: 6) {
                ForEach([(AppTheme.dark, "moon"), (AppTheme.light, "sun")], id: \.0) { theme, icon in
                    let on = app.theme == theme
                    Button { withAnimation(.easeInOut(duration: 0.25)) { app.theme = theme } } label: {
                        VStack(spacing: 7) {
                            AuraIcon(name: icon, size: 22, color: on ? pal.onAccent : pal.text2)
                            Text(theme.rawValue.capitalized).font(.system(size: 13, weight: .bold))
                                .foregroundStyle(on ? pal.onAccent : pal.text2)
                        }
                        .frame(maxWidth: .infinity).frame(height: 70)
                        .background(on ? pal.accent : pal.surface2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }.press()
                }
            }
            .padding(6)
            .background(pal.surface1, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(pal.line, lineWidth: 0.5))
            .padding(.horizontal, 14)
        }
        .padding(.top, 22)
    }

    // group container
    private func Group<C: View>(header: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header.uppercased()).font(.tCap).tracking(0.7).foregroundStyle(pal.text3)
                .padding(.horizontal, 20).padding(.bottom, 8)
            VStack(spacing: 0) { content() }
                .background(pal.surface1, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(pal.line, lineWidth: 0.5))
                .padding(.horizontal, 14)
        }
        .padding(.top, 22)
    }
}

private struct SettingsRow<Trailing: View>: View {
    let icon: String
    let iconBg: Color
    let title: String
    var sub: String? = nil
    var onTap: (() -> Void)? = nil
    @ViewBuilder var trailing: Trailing
    @Environment(\.palette) private var pal

    var body: some View {
        HStack(spacing: 13) {
            ZStack { AuraIcon(name: icon, size: 18, color: .white) }
                .frame(width: 30, height: 30)
                .background(iconBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 15.5, weight: .medium)).foregroundStyle(pal.text)
                if let sub { Text(sub).font(.system(size: 12.5)).foregroundStyle(pal.text2) }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

struct AuraToggle: View {
    @Binding var on: Bool
    @Environment(\.palette) private var pal
    var body: some View {
        Button { on.toggle() } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? pal.accent : pal.surface3).frame(width: 50, height: 30)
                Circle().fill(.white).frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                    .padding(2)
            }
            .animation(.easeOut(duration: 0.2), value: on)
        }
        .buttonStyle(.plain)
    }
}
