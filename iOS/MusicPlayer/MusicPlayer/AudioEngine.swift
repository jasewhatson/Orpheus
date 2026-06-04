//
//  AudioEngine.swift
//  MusicPlayer
//
//  Real audio playback (AVPlayer) streaming the sample MP3s, plus
//  lock-screen / Control Center integration via MPNowPlayingInfoCenter
//  and MPRemoteCommandCenter.
//

import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import SwiftUI

@MainActor
final class AudioEngine {

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    /// (currentTime, duration) in seconds — fires ~4×/second.
    var onTime: ((Double, Double) -> Void)?
    /// Track finished playing to the end.
    var onEnd: (() -> Void)?

    // Remote command callbacks (lock screen / Control Center / headphones)
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrev: (() -> Void)?
    var onSeek: ((Double) -> Void)?      // absolute seconds
    var onToggle: (() -> Void)?

    // Cached Now Playing metadata so the periodic observer can refresh
    // elapsed time without rebuilding artwork each tick.
    private var nowPlaying: [String: Any] = [:]
    private var artworkTrackId: String?

    init() {
        configureSession()
        addObservers()
        configureRemoteCommands()
    }

    // MARK: Session

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
    }

    private func activate() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: Observers

    private func addObservers() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let cur = time.seconds
            Task { @MainActor in
                guard let self else { return }
                let dur = self.player.currentItem?.duration.seconds ?? 0
                let duration = (dur.isFinite && dur > 0) ? dur : 0
                self.onTime?(cur, duration)
                self.refreshElapsed(cur, duration: duration)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onEnd?() }
        }
    }

    // MARK: Transport

    func load(url: URL, autoplay: Bool) {
        // Prefer a cached local copy; otherwise stream and cache in background.
        let cache = CacheStore.shared
        let local = cache.localAudio(for: url)
        let item = AVPlayerItem(url: local ?? url)
        player.replaceCurrentItem(with: item)
        if autoplay { play() }
        if local == nil { cache.cacheAudioIfNeeded(url) }
    }

    func play() {
        activate()
        player.play()
        player.rate = 1
    }

    func pause() { player.pause() }

    func seek(toFraction f: Double) {
        let dur = player.currentItem?.duration.seconds ?? 0
        guard dur.isFinite, dur > 0 else { return }
        player.seek(to: CMTime(seconds: dur * f, preferredTimescale: 600))
    }

    // MARK: Now Playing info

    func setTrack(title: String, artist: String, album: String, artwork: Artwork, trackId: String, isPlaying: Bool) {
        var info = nowPlaying
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = artist
        info[MPMediaItemPropertyAlbumTitle] = album
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0

        if artworkTrackId != trackId {
            // Cached, resized JPEG artwork (rendered on a miss).
            let image = CacheStore.shared.artworkImage(for: artwork, size: 600) { s in
                AlbumArtRenderer.image(for: artwork, size: CGSize(width: s, height: s))
            }
            let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = art
            artworkTrackId = trackId
        }
        nowPlaying = info
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }

    /// Replace the lock-screen artwork (e.g. once a remote image has loaded).
    func setArtwork(_ image: UIImage, trackId: String) {
        nowPlaying[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        artworkTrackId = trackId
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying
    }

    func setRate(_ playing: Bool) {
        nowPlaying[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nowPlaying
        // Explicitly drive the system playback state — setting the rate in the
        // info dict alone does not reliably flip the lock-screen player state.
        center.playbackState = playing ? .playing : .paused
    }

    private func refreshElapsed(_ elapsed: Double, duration: Double) {
        guard !nowPlaying.isEmpty else { return }
        nowPlaying[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        if duration > 0 { nowPlaying[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying
    }

    // MARK: Remote commands

    private func configureRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.onPlay?(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.onPause?(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.onToggle?(); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.onNext?(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.onPrev?(); return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.onSeek?(e.positionTime)
            return .success
        }
        c.nextTrackCommand.isEnabled = true
        c.previousTrackCommand.isEnabled = true
    }

    deinit {
        if let t = timeObserver { player.removeTimeObserver(t) }
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
    }
}

// MARK: - Album art rendering

enum AlbumArtRenderer {
    /// Renders an Artwork's generative gradient mesh to a UIImage for the
    /// lock screen / Control Center.
    static func image(for art: Artwork, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: size)
            let space = CGColorSpaceCreateDeviceRGB()

            if art.radial {
                let colors = [uiColor(art.hexes.first ?? "444444"), uiColor(art.hexes.last ?? "111111")]
                if let grad = CGGradient(colorsSpace: space, colors: colors.map { $0.cgColor } as CFArray, locations: [0, 1]) {
                    let center = CGPoint(x: size.width * 0.35, y: size.height * 0.30)
                    cg.drawRadialGradient(grad, startCenter: center, startRadius: 0,
                                          endCenter: center, endRadius: size.width, options: [.drawsAfterEndLocation])
                }
            } else {
                let p = art.palette3
                // base angled gradient (b -> a)
                if let base = CGGradient(colorsSpace: space, colors: [uiColor(p.1).cgColor, uiColor(p.0).cgColor] as CFArray, locations: [0, 1]) {
                    let t = art.angle * .pi / 180
                    let dx = CGFloat(sin(t)), dy = CGFloat(-cos(t))
                    let start = CGPoint(x: size.width * (0.5 - dx / 2), y: size.height * (0.5 - dy / 2))
                    let end = CGPoint(x: size.width * (0.5 + dx / 2), y: size.height * (0.5 + dy / 2))
                    cg.drawLinearGradient(base, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
                // halo a, top-left
                drawHalo(cg, color: uiColor(p.0), center: CGPoint(x: size.width * 0.18, y: size.height * 0.12), radius: size.width * 0.66, space: space)
                // halo c, bottom-right
                drawHalo(cg, color: uiColor(p.2), center: CGPoint(x: size.width * 0.88, y: size.height * 0.92), radius: size.width * 0.70, space: space)
            }
        }
    }

    private static func drawHalo(_ cg: CGContext, color: UIColor, center: CGPoint, radius: CGFloat, space: CGColorSpace) {
        let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        if let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            cg.drawRadialGradient(grad, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }
    }

    private static func uiColor(_ hex: String) -> UIColor {
        UIColor(Color(hex: hex))
    }
}

extension Artwork {
    /// (a, b, c) convenience for rendering.
    var palette3: (String, String, String) {
        let h = hexes
        let a = h.first ?? "444444"
        let b = h.count > 1 ? h[1] : a
        let c = h.last ?? "111111"
        return (a, b, c)
    }
}
