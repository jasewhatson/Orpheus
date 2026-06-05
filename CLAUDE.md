# AURA — project guide for Claude

Two components in this repo:

- **iOS app** — `iOS/MusicPlayer/` (SwiftUI, Xcode project `MusicPlayer.xcodeproj`).
  Plays a demo catalog and/or streams a real library from the music server.
- **Music server** — `server/aura_server.py` (Python **3.4+** stdlib only;
  optional `mutagen`; uses `ffmpeg`/`ffprobe` for transcode/metadata/HLS).
  Runs on a Raspberry Pi (invoke with `python3.9`, which has `mutagen`).

## ⚠️ Versioning — do this on EVERY build/change

Bump the version in **both** the client and the server whenever you make a
change that gets built/deployed, so the running build is identifiable:

- **Server:** `VERSION` in `server/aura_server.py` (reported by `GET /health`
  and the startup banner).
- **iOS:** in `iOS/MusicPlayer/MusicPlayer.xcodeproj/project.pbxproj`, bump
  `MARKETING_VERSION` (e.g. 1.1 → 1.2) and increment `CURRENT_PROJECT_VERSION`
  (the build number) for **all** configs. The app's Settings footer shows
  `CFBundleShortVersionString (CFBundleVersion)` so you can confirm on-device
  which build is running.

Use the version to sanity-check deploys: if a fix "does nothing," first verify
`/health` version and the Settings footer match the new build (stale server /
app not redeployed is the most common cause).

Keep server `VERSION` and iOS `MARKETING_VERSION` in step (same x.y) when shipping
a paired change.

## Build / run

```bash
# iOS (simulator build check)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build -project iOS/MusicPlayer/MusicPlayer.xcodeproj -scheme MusicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/aura_dd CODE_SIGNING_ALLOWED=NO

# Server (Pi: use python3.9 so mutagen is available)
python3.9 server/aura_server.py /path/to/music-library
curl -s localhost:8080/health        # shows version, mutagen, ffmpeg, ffprobe, formats
```

## Server notes
- Folders = playlists, files = tracks; `.lrc` sidecars = lyrics.
- `.ogg`/`.opus` aren't playable by AVPlayer → transcoded on request:
  `?format=m4a|mp3[&bitrate=…]` (cached-file, seekable) or `…/hls.m3u8` (HLS:
  VOD playlist + on-demand parallel segments, lowest latency). `--ffmpeg-threads`
  / `FFMPEG_THREADS` and a CPU-sized pool drive parallelism.
- Bundle id: `net.Mindfsck.MusicPlayer`. ATS allows arbitrary HTTP loads (LAN /
  Tailscale `http://`).

## Git
Work happens on feature branches (`feat/...`); push to `origin`
(`github.com:jasewhatson/Orpheus.git`). Don't commit the gitignored
`*.xcuserstate`.
