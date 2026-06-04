//
//  Icons.swift
//  MusicPlayer
//
//  Maps the design's stroke icon set to SF Symbols, sized by point value
//  to roughly match the original 24pt viewBox glyphs.
//

import SwiftUI

struct AuraIcon: View {
    let name: String
    var size: CGFloat = 24
    var filled: Bool = false
    var weight: Font.Weight = .regular
    var color: Color? = nil

    var body: some View {
        let resolved = filled ? Self.symbol(name, filled: true) : Self.symbol(name, filled: false)
        Image(systemName: resolved.0)
            .font(.system(size: size * 0.86, weight: weight))
            .symbolVariant(resolved.1 ? .fill : .none)
            .rotationEffect(.degrees(resolved.2))
            .foregroundStyle(color ?? .primary)
    }

    /// Returns (symbolName, forceFill, rotationDegrees).
    static func symbol(_ name: String, filled: Bool) -> (String, Bool, Double) {
        switch name {
        case "home":        return (filled ? "house.fill" : "house", false, 0)
        case "search":      return ("magnifyingglass", false, 0)
        case "library":     return (filled ? "books.vertical.fill" : "books.vertical", false, 0)
        case "settings":    return (filled ? "gearshape.fill" : "gearshape", false, 0)
        case "play":        return ("play.fill", false, 0)
        case "pause":       return ("pause.fill", false, 0)
        case "next":        return ("forward.end.fill", false, 0)
        case "prev":        return ("backward.end.fill", false, 0)
        case "shuffle":     return ("shuffle", false, 0)
        case "repeat":      return ("repeat", false, 0)
        case "repeat-one":  return ("repeat.1", false, 0)
        case "heart":       return (filled ? "heart.fill" : "heart", false, 0)
        case "more":        return ("ellipsis", false, 0)
        case "more-v":      return ("ellipsis", false, 90)
        case "back":        return ("chevron.left", false, 0)
        case "down":        return ("chevron.down", false, 0)
        case "chev":        return ("chevron.right", false, 0)
        case "up":          return ("chevron.up", false, 0)
        case "plus":        return ("plus", false, 0)
        case "plus-circle": return ("plus.circle", false, 0)
        case "check":       return ("checkmark", false, 0)
        case "check-circle": return ("checkmark.circle.fill", true, 0)
        case "queue":       return ("text.line.first.and.arrowtriangle.forward", false, 0)
        case "list":        return ("list.bullet", false, 0)
        case "lyrics":      return ("quote.bubble", false, 0)
        case "share":       return ("square.and.arrow.up", false, 0)
        case "download":    return ("arrow.down.to.line", false, 0)
        case "downloaded":  return ("arrow.down.circle.fill", true, 0)
        case "devices":     return ("rectangle.on.rectangle", false, 0)
        case "x":           return ("xmark", false, 0)
        case "clock":       return ("clock", false, 0)
        case "sort":        return ("arrow.up.arrow.down", false, 0)
        case "grid":        return ("square.grid.2x2", false, 0)
        case "edit":        return ("pencil", false, 0)
        case "trash":       return ("trash", false, 0)
        case "minus-circle": return ("minus.circle", false, 0)
        case "drag":        return ("line.3.horizontal", false, 0)
        case "sun":         return ("sun.max", false, 0)
        case "moon":        return ("moon", false, 0)
        case "cast":        return ("dot.radiowaves.up.forward", false, 0)
        case "volume":      return ("speaker.wave.2", false, 0)
        case "volume-min":  return ("speaker.wave.1", false, 0)
        case "mic":         return ("mic", false, 0)
        case "sparkle":     return ("sparkles", false, 0)
        case "radio":       return ("dot.radiowaves.left.and.right", false, 0)
        case "user":        return ("person", false, 0)
        case "add-list":    return ("text.badge.plus", false, 0)
        case "bell":        return ("bell", false, 0)
        case "history":     return ("clock.arrow.circlepath", false, 0)
        case "spinner-disc": return ("opticaldisc", false, 0)
        default:            return ("questionmark", false, 0)
        }
    }
}
