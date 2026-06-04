//
//  Theme.swift
//  MusicPlayer
//
//  AURA — design tokens (dark / light), color + gradient helpers.
//

import SwiftUI

// MARK: - Hex color

extension Color {
    init(hex: String, opacity: Double = 1) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            self.init(.sRGB, red: r, green: g, blue: b, opacity: Double(v & 0xFF) / 255)
            return
        }
        r = Double((v >> 16) & 0xFF) / 255
        g = Double((v >> 8) & 0xFF) / 255
        b = Double(v & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Theme

enum AppTheme: String, CaseIterable, Codable {
    case dark, light
}

/// Resolved color palette for the current theme. Mirrors the CSS custom
/// properties from the AURA design tokens.
struct Palette {
    let theme: AppTheme

    // surfaces
    var bg: Color { theme == .dark ? Color(hex: "060608") : Color(hex: "f3f3f7") }
    var bgGradTop: Color { theme == .dark ? Color(hex: "0c0c14") : Color(hex: "ececf3") }
    var surface1: Color { theme == .dark ? Color(hex: "0f0f16") : Color(hex: "ffffff") }
    var surface2: Color { theme == .dark ? Color(hex: "16161f") : Color(hex: "f3f3f8") }
    var surface3: Color { theme == .dark ? Color(hex: "1f1f2b") : Color(hex: "e9e9f0") }
    var surfacePress: Color { theme == .dark ? Color(hex: "262633") : Color(hex: "e2e2ea") }

    // text
    private var textBase: Color { theme == .dark ? Color(hex: "f4f5fa") : Color(hex: "0c0c12") }
    var text: Color { textBase }
    var text2: Color { textBase.opacity(theme == .dark ? 0.64 : 0.60) }
    var text3: Color { textBase.opacity(theme == .dark ? 0.40 : 0.42) }
    var text4: Color { textBase.opacity(0.26) }

    // lines
    var line: Color { theme == .dark ? Color.white.opacity(0.08) : Color(hex: "0a0a14").opacity(0.09) }
    var line2: Color { theme == .dark ? Color.white.opacity(0.13) : Color(hex: "0a0a14").opacity(0.14) }

    // glass / chrome
    var glass: Color { theme == .dark ? Color(hex: "101016").opacity(0.72) : Color(hex: "f8f8fc").opacity(0.74) }
    var tabbar: Color { theme == .dark ? Color(hex: "0a0a0e").opacity(0.82) : Color(hex: "f8f8fc").opacity(0.84) }
    var scrim: Color { theme == .dark ? Color.black.opacity(0.5) : Color(hex: "14141e").opacity(0.35) }

    // accent
    var accent: Color { theme == .dark ? Color(hex: "78a5ef") : Color(hex: "3f6fd6") }
    var accent2: Color { Color(hex: "9c8cf2") }
    var accentSoft: Color { Color(hex: "78a5ef").opacity(0.16) }
    /// Foreground color sitting on top of an accent fill.
    var onAccent: Color { theme == .dark ? Color(hex: "06121f") : .white }

    var danger: Color { Color(hex: "ff6b6b") }

    static let likedGradient = LinearGradient(
        colors: [Color(hex: "9c8cf2"), Color(hex: "5f8ff0")],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(theme: .dark)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Type scale

extension Font {
    static let tLarge = Font.system(size: 30, weight: .heavy).width(.standard)
    static let tTitle = Font.system(size: 22, weight: .bold)
    static let tSection = Font.system(size: 21, weight: .bold)
    static let tRow = Font.system(size: 16, weight: .semibold)
    static let tSub = Font.system(size: 13.5, weight: .medium)
    static let tCap = Font.system(size: 11.5, weight: .bold)
}
