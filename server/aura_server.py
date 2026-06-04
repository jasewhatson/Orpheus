#!/usr/bin/env python3
"""
AURA music server — a tiny, dependency-free REST API that serves a directory of
folders as playlists and the audio files inside them as tracks.

Library layout:

    <MUSIC_ROOT>/
      DeepChillTrance/                 # a playlist
        16BL - Sediment.ogg            # a track
        16BL - Sediment.lrc            # its lyrics (optional, same stem)
        ...
      AnotherPlaylist/
        ...

Run:
    python3 aura_server.py /path/to/MUSIC_ROOT
    MUSIC_ROOT=/path/to/lib python3 aura_server.py
    python3 aura_server.py /lib --host 0.0.0.0 --port 8080

The HTTP layer is pure Python stdlib. Embedded tags + cover art are read via
the optional `mutagen` package (`pip install mutagen`); without it the server
still runs and derives artist/title from filenames.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import quote, unquote, urlparse

# Optional: embedded tag / artwork reading.
try:
    from mutagen import File as MutagenFile  # type: ignore
    HAVE_MUTAGEN = True
except Exception:  # pragma: no cover - mutagen is optional
    HAVE_MUTAGEN = False

VERSION = "1.0.0"
CHUNK = 64 * 1024

# Audio extensions we serve, mapped to their MIME type.
AUDIO_MIME = {
    ".ogg": "audio/ogg",
    ".opus": "audio/ogg",
    ".oga": "audio/ogg",
    ".mp3": "audio/mpeg",
    ".flac": "audio/flac",
    ".m4a": "audio/mp4",
    ".aac": "audio/aac",
    ".wav": "audio/wav",
}

# Set in main().
ROOT = ""


# --------------------------------------------------------------------------- #
# Path safety
# --------------------------------------------------------------------------- #

def safe_segment(name: str) -> bool:
    """A single URL path segment that can't escape its directory."""
    return (
        bool(name)
        and name not in (".", "..")
        and "/" not in name
        and "\\" not in name
        and "\x00" not in name
    )


def within(path: str, base: str) -> bool:
    """True if `path` resolves to somewhere inside `base`."""
    rp = os.path.realpath(path)
    rb = os.path.realpath(base)
    return rp == rb or rp.startswith(rb + os.sep)


def is_audio(name: str) -> bool:
    return os.path.splitext(name)[1].lower() in AUDIO_MIME


# --------------------------------------------------------------------------- #
# Metadata
# --------------------------------------------------------------------------- #

def parse_filename(stem: str):
    """'Artist - Title - Mix' -> (artist, title). Falls back gracefully."""
    parts = [p.strip() for p in stem.split(" - ")]
    if len(parts) >= 2 and parts[0]:
        return parts[0], " - ".join(parts[1:]).strip()
    return "Unknown Artist", stem.strip()


def read_tags(path: str):
    """Embedded tags via mutagen, or None. Lightweight artwork *presence* check."""
    if not HAVE_MUTAGEN:
        return None
    try:
        audio = MutagenFile(path)
    except Exception:
        return None
    if audio is None:
        return None

    tags = audio.tags

    def first(*keys):
        if not tags:
            return None
        for key in keys:
            try:
                val = tags.get(key)
            except Exception:
                val = None
            if val is None:
                continue
            if isinstance(val, list):
                val = val[0] if val else None
            if val is None:
                continue
            text = str(val).strip()
            if text:
                return text
        return None

    duration = None
    try:
        length = getattr(audio.info, "length", None)
        if length:
            duration = round(float(length), 2)
    except Exception:
        pass

    return {
        "title": first("title", "TIT2", "\xa9nam"),
        "artist": first("artist", "TPE1", "\xa9ART"),
        "album": first("album", "TALB", "\xa9alb"),
        "duration": duration,
        "has_art": has_artwork(audio),
    }


def has_artwork(audio) -> bool:
    """Cheap presence check — does not decode the image."""
    try:
        if getattr(audio, "pictures", None):  # FLAC
            return True
        tags = audio.tags
        if not tags:
            return False
        keys = list(tags.keys())
        if "metadata_block_picture" in keys or "METADATA_BLOCK_PICTURE" in keys:
            return True
        if any(str(k).startswith("APIC") for k in keys):  # ID3
            return True
        if "covr" in keys:  # MP4
            return True
    except Exception:
        pass
    return False


def extract_artwork(path: str):
    """Return (image_bytes, mime) for the first embedded cover, or None."""
    if not HAVE_MUTAGEN:
        return None
    try:
        audio = MutagenFile(path)
    except Exception:
        return None
    if audio is None:
        return None

    # FLAC native pictures
    pics = getattr(audio, "pictures", None)
    if pics:
        p = pics[0]
        return p.data, (p.mime or "image/jpeg")

    tags = audio.tags
    if not tags:
        return None

    # Vorbis comment (Ogg/Opus/FLAC): base64-encoded FLAC Picture block
    for key in ("metadata_block_picture", "METADATA_BLOCK_PICTURE"):
        try:
            if key in tags:
                from mutagen.flac import Picture
                data = tags[key]
                if isinstance(data, list):
                    data = data[0]
                pic = Picture(base64.b64decode(data))
                return pic.data, (pic.mime or "image/jpeg")
        except Exception:
            pass

    # ID3 APIC (MP3)
    try:
        for k in tags.keys():
            if str(k).startswith("APIC"):
                apic = tags[k]
                return apic.data, (apic.mime or "image/jpeg")
    except Exception:
        pass

    # MP4 covr
    try:
        covr = tags.get("covr")
        if covr:
            from mutagen.mp4 import MP4Cover
            cover = covr[0]
            mime = "image/png" if cover.imageformat == MP4Cover.FORMAT_PNG else "image/jpeg"
            return bytes(cover), mime
    except Exception:
        pass

    return None


def track_json(playlist: str, fname: str, audio_path: str) -> dict:
    stem = os.path.splitext(fname)[0]
    artist, title = parse_filename(stem)
    album = None
    duration = None
    has_art = False

    tags = read_tags(audio_path)
    if tags:
        artist = tags["artist"] or artist
        title = tags["title"] or title
        album = tags["album"] or album
        duration = tags["duration"]
        has_art = tags["has_art"]

    lrc_path = os.path.join(os.path.dirname(audio_path), stem + ".lrc")
    has_lyrics = os.path.isfile(lrc_path)

    base = "/playlists/" + quote(playlist) + "/tracks/" + quote(fname)
    return {
        "id": fname,
        "file": fname,
        "title": title,
        "artist": artist,
        "album": album,
        "duration": duration,
        "hasLyrics": has_lyrics,
        "audioUrl": base + "/audio",
        "lyricsUrl": base + "/lyrics" if has_lyrics else None,
        "artworkUrl": base + "/artwork" if has_art else None,
    }


# --------------------------------------------------------------------------- #
# HTTP handler
# --------------------------------------------------------------------------- #

class Handler(BaseHTTPRequestHandler):
    server_version = f"AURA/{VERSION}"

    # ---- low-level helpers ----

    def end_headers(self):
        # Permissive CORS on every response.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Range, Content-Type")
        self.send_header("Access-Control-Expose-Headers",
                         "Content-Range, Accept-Ranges, Content-Length")
        super().end_headers()

    def _json(self, obj, status: int = 200):
        body = json.dumps(obj, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _error(self, status: int, message: str):
        self._json({"error": message, "status": status}, status=status)

    # ---- resolution ----

    def _resolve_playlist(self, pl: str):
        if not safe_segment(pl):
            return None
        d = os.path.join(ROOT, pl)
        if not within(d, ROOT) or not os.path.isdir(d):
            return None
        return d

    def _resolve_track(self, pl: str, fname: str):
        d = self._resolve_playlist(pl)
        if d is None or not safe_segment(fname) or not is_audio(fname):
            return None
        f = os.path.join(d, fname)
        if not within(f, d) or not os.path.isfile(f):
            return None
        return f

    # ---- routing ----

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def do_HEAD(self):
        self._route()

    def do_GET(self):
        self._route()

    def _route(self):
        try:
            path = urlparse(self.path).path
            parts = [unquote(p) for p in path.split("/") if p != ""]

            if not parts or parts == ["health"]:
                return self._health()
            if parts == ["playlists"]:
                return self._list_playlists()
            if len(parts) == 2 and parts[0] == "playlists":
                return self._playlist_detail(parts[1])
            if len(parts) == 4 and parts[0] == "playlists" and parts[2] == "tracks":
                return self._track_detail(parts[1], parts[3])
            if len(parts) == 5 and parts[0] == "playlists" and parts[2] == "tracks":
                pl, fname, sub = parts[1], parts[3], parts[4]
                if sub == "audio":
                    return self._track_audio(pl, fname)
                if sub == "lyrics":
                    return self._track_lyrics(pl, fname)
                if sub == "artwork":
                    return self._track_artwork(pl, fname)

            self._error(404, "not found")
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as exc:  # pragma: no cover
            try:
                self._error(500, f"server error: {exc}")
            except Exception:
                pass

    # ---- endpoints ----

    def _health(self):
        try:
            count = sum(
                1 for d in os.listdir(ROOT)
                if os.path.isdir(os.path.join(ROOT, d)) and not d.startswith(".")
            )
        except OSError:
            count = 0
        self._json({
            "name": "AURA music server",
            "version": VERSION,
            "root": ROOT,
            "playlistCount": count,
            "mutagen": HAVE_MUTAGEN,
        })

    def _list_playlists(self):
        try:
            names = sorted(
                d for d in os.listdir(ROOT)
                if os.path.isdir(os.path.join(ROOT, d)) and not d.startswith(".")
            )
        except OSError:
            return self._error(500, "cannot read library root")
        result = []
        for name in names:
            d = os.path.join(ROOT, name)
            try:
                count = sum(1 for f in os.listdir(d) if is_audio(f) and not f.startswith("."))
            except OSError:
                count = 0
            result.append({"id": name, "name": name, "trackCount": count})
        self._json(result)

    def _playlist_detail(self, pl: str):
        d = self._resolve_playlist(pl)
        if d is None:
            return self._error(404, "playlist not found")
        try:
            files = sorted(
                f for f in os.listdir(d) if is_audio(f) and not f.startswith(".")
            )
        except OSError:
            return self._error(500, "cannot read playlist")
        tracks = [track_json(pl, f, os.path.join(d, f)) for f in files]
        self._json({"id": pl, "name": pl, "tracks": tracks})

    def _track_detail(self, pl: str, fname: str):
        f = self._resolve_track(pl, fname)
        if f is None:
            return self._error(404, "track not found")
        self._json(track_json(pl, fname, f))

    def _track_audio(self, pl: str, fname: str):
        f = self._resolve_track(pl, fname)
        if f is None:
            return self._error(404, "track not found")
        mime = AUDIO_MIME.get(os.path.splitext(fname)[1].lower(), "application/octet-stream")
        self._serve_range(f, mime)

    def _track_lyrics(self, pl: str, fname: str):
        f = self._resolve_track(pl, fname)
        if f is None:
            return self._error(404, "track not found")
        stem = os.path.splitext(f)[0]
        lrc = stem + ".lrc"
        if not os.path.isfile(lrc):
            return self._error(404, "no lyrics for this track")
        try:
            with open(lrc, "rb") as fh:
                data = fh.read()
        except OSError:
            return self._error(500, "cannot read lyrics")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def _track_artwork(self, pl: str, fname: str):
        f = self._resolve_track(pl, fname)
        if f is None:
            return self._error(404, "track not found")
        art = extract_artwork(f)
        if art is None:
            return self._error(404, "no embedded artwork")
        data, mime = art
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "public, max-age=86400")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    # ---- range-aware file streaming ----

    def _serve_range(self, path: str, content_type: str):
        try:
            size = os.path.getsize(path)
        except OSError:
            return self._error(404, "track not found")

        start, end = 0, size - 1
        partial = False
        header = self.headers.get("Range")
        if header:
            m = re.match(r"bytes=(\d*)-(\d*)\s*$", header.strip())
            if m:
                g1, g2 = m.group(1), m.group(2)
                if g1 == "" and g2 == "":
                    pass
                elif g1 == "":  # suffix: last N bytes
                    start = max(0, size - int(g2))
                    partial = True
                else:
                    start = int(g1)
                    end = int(g2) if g2 != "" else size - 1
                    partial = True
                end = min(end, size - 1)
                if start > end or start >= size:
                    self.send_response(416)
                    self.send_header("Content-Range", f"bytes */{size}")
                    self.end_headers()
                    return

        length = end - start + 1
        self.send_response(206 if partial else 200)
        self.send_header("Content-Type", content_type)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        if partial:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()

        if self.command == "HEAD":
            return

        with open(path, "rb") as fh:
            fh.seek(start)
            remaining = length
            while remaining > 0:
                chunk = fh.read(min(CHUNK, remaining))
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    break
                remaining -= len(chunk)

    # ---- logging ----

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #

def main(argv=None):
    parser = argparse.ArgumentParser(description="AURA music server")
    parser.add_argument("root", nargs="?", default=os.environ.get("MUSIC_ROOT"),
                        help="library root (folder of playlist folders); "
                             "or set MUSIC_ROOT")
    parser.add_argument("--host", default=os.environ.get("HOST", "0.0.0.0"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8080")))
    args = parser.parse_args(argv)

    if not args.root:
        parser.error("music root required: pass it as an argument or set MUSIC_ROOT")

    global ROOT
    ROOT = os.path.realpath(os.path.expanduser(args.root))
    if not os.path.isdir(ROOT):
        parser.error(f"not a directory: {ROOT}")

    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"AURA music server v{VERSION}")
    print(f"  root:     {ROOT}")
    print(f"  mutagen:  {'yes' if HAVE_MUTAGEN else 'no (filename metadata only)'}")
    print(f"  serving:  http://{args.host}:{args.port}")
    print("  endpoints: /health  /playlists  /playlists/{name}  "
          ".../tracks/{file}[/audio|/lyrics|/artwork]")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down")
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
