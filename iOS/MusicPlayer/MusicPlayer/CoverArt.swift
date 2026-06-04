//
//  CoverArt.swift
//  MusicPlayer
//
//  Generative gradient-mesh album/playlist covers, reproducing the CSS
//  `cover()` mesh from the design (two radial halos over an angled base).
//

import SwiftUI

/// Converts a CSS gradient angle (0° = to top, clockwise) into SwiftUI
/// start/end unit points.
func gradientPoints(_ angleDeg: Double) -> (UnitPoint, UnitPoint) {
    let t = angleDeg * .pi / 180
    let dx = sin(t)
    let dy = -cos(t)
    return (UnitPoint(x: 0.5 - dx / 2, y: 0.5 - dy / 2),
            UnitPoint(x: 0.5 + dx / 2, y: 0.5 + dy / 2))
}

func angledGradient(_ angle: Double, _ colors: [Color]) -> LinearGradient {
    let (s, e) = gradientPoints(angle)
    return LinearGradient(colors: colors, startPoint: s, endPoint: e)
}

struct CoverArt: View {
    let art: Artwork
    var cornerRadius: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let dim = max(geo.size.width, geo.size.height)
            ZStack {
                if art.radial {
                    let c = art.colors
                    RadialGradient(
                        colors: [c.first ?? .gray, c.last ?? .black],
                        center: UnitPoint(x: 0.35, y: 0.30),
                        startRadius: 0, endRadius: dim * 1.0)
                } else {
                    let p = art.palette
                    // base angled gradient (b -> a)
                    angledGradient(art.angle, [p[1], p[0]])
                    // halo a, top-left
                    RadialGradient(
                        colors: [p[0], p[0].opacity(0)],
                        center: UnitPoint(x: 0.18, y: 0.12),
                        startRadius: 0, endRadius: dim * 0.66)
                    // halo c, bottom-right
                    RadialGradient(
                        colors: [p[2], p[2].opacity(0)],
                        center: UnitPoint(x: 0.88, y: 0.92),
                        startRadius: 0, endRadius: dim * 0.70)
                }
                // diagonal sheen
                LinearGradient(
                    stops: [.init(color: .white.opacity(0.18), location: 0),
                            .init(color: .clear, location: 0.42)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Square sugar for the common cover usage. When `url` is set, the remote image
/// is shown (cached) with the generative gradient as placeholder/fallback.
struct Cover: View {
    let art: Artwork
    var url: URL? = nil
    var size: CGFloat = 56
    var radius: CGFloat = 12
    var shadow: Bool = false

    var body: some View {
        Group {
            if let url {
                RemoteImage(url: url, fallback: art, radius: radius)
            } else {
                CoverArt(art: art, cornerRadius: radius)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(shadow ? 0.4 : 0), radius: shadow ? 16 : 0, y: shadow ? 12 : 0)
    }
}

/// Loads (and caches) a remote artwork image, showing the gradient until ready.
struct RemoteImage: View {
    let url: URL
    let fallback: Artwork
    var radius: CGFloat = 12
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                CoverArt(art: fallback, cornerRadius: radius)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: url) { image = await CacheStore.shared.image(forURL: url) }
    }
}
