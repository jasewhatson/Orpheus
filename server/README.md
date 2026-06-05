# AURA music server

A tiny REST API that serves a directory of folders as **playlists** and the
audio files inside them as **tracks** — with HTTP range streaming, `.lrc`
lyrics, filename-parsed metadata, and (optionally) embedded tags + cover art.

The HTTP layer is pure Python standard library — no framework, no install
needed to run it.

## Library layout

Point the server at a folder whose subfolders are playlists:

```
MUSIC_ROOT/
  DeepChillTrance/                                  # playlist
    16BL - Sediment.ogg                             # track
    4 Strings - Safe From Harm - Extended Mix.ogg
    4 Strings - Safe From Harm - Extended Mix.lrc   # lyrics for the track above
    Above & Beyond - Can't Sleep - Original Mix.ogg
    Above & Beyond - Can't Sleep - Original Mix.lrc
  AnotherPlaylist/
    ...
```

- A subfolder = a playlist.
- Each audio file (`.ogg .opus .oga .mp3 .flac .m4a .aac .wav`) = a track.
- A `.lrc` file with the **same stem** next to a track = its lyrics.

## Run

```bash
# positional argument
python3 aura_server.py /path/to/MUSIC_ROOT

# or via environment variable
MUSIC_ROOT=/path/to/MUSIC_ROOT python3 aura_server.py

# choose host/port (defaults: 0.0.0.0:8080)
python3 aura_server.py /path/to/MUSIC_ROOT --host 127.0.0.1 --port 9000
```

Requires Python **3.4+** (uses only the standard library; tested on 3.4 through
3.13 — handy for older Raspberry Pi installs).

### Optional: embedded tags + artwork

```bash
pip install -r requirements.txt   # installs mutagen
```

With `mutagen` available the server reads title/artist/album/duration and cover
art embedded in the files. Without it, the server still runs and parses
`Artist - Title - Mix.ext` filenames; `duration` and `artworkUrl` come back
`null`.

> Note: current `mutagen` releases require Python 3.8+. On an old interpreter
> (e.g. Python 3.4) the import simply fails and the server runs in
> filename-only mode — or `pip install "mutagen<1.46"` for an older compatible
> build.

## API

All responses include permissive CORS headers (`Access-Control-Allow-Origin: *`).

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Server info: `{ name, version, root, playlistCount, mutagen, ffmpeg }` |
| GET | `/playlists` | `[{ id, name, trackCount }]` — one per folder |
| GET | `/playlists/{playlist}` | `{ id, name, tracks: [Track…] }` |
| GET | `/playlists/{playlist}/tracks/{file}` | a single `Track` |
| GET | `/playlists/{playlist}/tracks/{file}/audio` | audio bytes, **Range-aware** (206) |
| GET | `/playlists/{playlist}/tracks/{file}/audio?format=m4a[&bitrate=256]` | **transcoded** to AAC/m4a (for `.ogg`/`.opus`) |
| GET | `/playlists/{playlist}/tracks/{file}/lyrics` | `.lrc` text, or 404 |
| GET | `/playlists/{playlist}/tracks/{file}/artwork` | embedded cover image, or 404 |

### Transcoding (`?format=m4a`)

Apple's `AVPlayer` (iOS) can't decode Ogg Vorbis/Opus. Requesting
`/audio?format=m4a` transcodes non-native formats to AAC in an `.m4a` container
using **ffmpeg** (`-c:a aac -b:a 256k -movflags +faststart`). Native formats
(`.mp3 .m4a .aac .flac .wav .alac .aif/.aiff .caf`) are always served as-is, even
with `?format=m4a`.

- `bitrate` (kbps) selects the AAC rate; clamped to {96, 128, 160, 192, 256,
  320}, default 256. Each rate is cached separately.
- `--ffmpeg-threads N` (or `FFMPEG_THREADS`) sets threads per transcode
  (0 = auto/all cores). Different tracks also transcode concurrently.
- Requires ffmpeg on the host: `sudo apt install ffmpeg` (Raspberry Pi) /
  `brew install ffmpeg`. `/health` reports `"ffmpeg": true/false`.
- Transcodes are cached to disk (`--cache-dir`, default system-temp
  `aura-transcode`), keyed by source path+size+mtime, and served Range-aware — so
  seeking works and subsequent plays are instant.
- Returns `503` if ffmpeg is missing, `502` on transcode failure.

`{playlist}` and `{file}` are URL-encoded path segments; `{file}` is the full
audio filename (e.g. `16BL%20-%20Sediment.ogg`). Clients should use the
ready-made `audioUrl` / `lyricsUrl` / `artworkUrl` from the listing rather than
constructing these by hand.

### Track object

```json
{
  "id": "16BL - Sediment.ogg",
  "file": "16BL - Sediment.ogg",
  "title": "Sediment",
  "artist": "16BL",
  "album": null,
  "duration": 372.4,
  "hasLyrics": true,
  "audioUrl":   "/playlists/DeepChillTrance/tracks/16BL%20-%20Sediment.ogg/audio",
  "lyricsUrl":  "/playlists/DeepChillTrance/tracks/16BL%20-%20Sediment.ogg/lyrics",
  "artworkUrl": null
}
```

`lyricsUrl` / `artworkUrl` are `null` when that content isn't available.

## Examples

```bash
curl -s localhost:8080/playlists | python3 -m json.tool
curl -s localhost:8080/playlists/DeepChillTrance | python3 -m json.tool

# stream / seek with a byte range
curl -s -D - -o /dev/null -r 0-1023 \
  "localhost:8080/playlists/DeepChillTrance/tracks/16BL%20-%20Sediment.ogg/audio"

# lyrics
curl -s "localhost:8080/playlists/DeepChillTrance/tracks/16BL%20-%20Sediment.ogg/lyrics"
```

## Notes

- Path-traversal is blocked: segments containing `/`, `\`, or `..` are rejected
  and every resolved path is verified to live inside the library root.
- Only audio extensions (and matching `.lrc`) are ever served.
- `ThreadingHTTPServer` handles concurrent range requests.
- **OGG/Opus caveat:** Apple's `AVPlayer` (used by the AURA iOS app) does not
  natively decode OGG Vorbis/Opus. To stream this library to the iOS app you'd
  need MP3/AAC/ALAC sources or server-side transcoding.
```
