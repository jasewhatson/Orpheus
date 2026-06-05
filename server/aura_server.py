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

import argparse
import base64
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
from urllib.parse import parse_qs, quote, unquote, urlparse

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

# Extensions Apple's AVPlayer can decode natively — served as-is, never
# transcoded. Everything else (e.g. .ogg/.opus) is transcoded to AAC/m4a.
NATIVE_EXTS = set([".mp3", ".m4a", ".aac", ".flac", ".wav", ".alac",
                   ".aif", ".aiff", ".caf"])

# Allowed transcode bitrates (kbps). Requests are clamped to this set so the
# transcode cache can't be blown up with arbitrary values.
ALLOWED_BITRATES = [96, 128, 160, 192, 256, 320]
DEFAULT_BITRATE = 256

# Set in main().
ROOT = ""
TRANSCODE_DIR = ""
FFMPEG_THREADS = 0          # 0 = let ffmpeg auto-pick (use all cores)
HAVE_FFMPEG = shutil.which("ffmpeg") is not None
HAVE_FFPROBE = shutil.which("ffprobe") is not None


def _encoder_available(name):
    if not HAVE_FFMPEG:
        return False
    try:
        out = subprocess.check_output(["ffmpeg", "-hide_banner", "-encoders"],
                                      stderr=subprocess.DEVNULL)
        return name.encode("ascii") in out
    except Exception:
        return False


HAVE_LAME = _encoder_available("libmp3lame")

# In-memory probe cache: realpath -> (mtime, size, meta-dict)
_probe_cache = {}
_probe_guard = threading.Lock()

# Per-source-key locks so concurrent requests don't transcode the same file twice.
_transcode_locks = {}
_transcode_guard = threading.Lock()


def _key_lock(key):
    with _transcode_guard:
        lk = _transcode_locks.get(key)
        if lk is None:
            lk = threading.Lock()
            _transcode_locks[key] = lk
        return lk


# fmt -> (file extension, response MIME, ffmpeg output args)
def _codec_args(fmt, bitrate):
    br = "{}k".format(bitrate)
    if fmt == "mp3":
        # MP3 (libmp3lame) — much faster to encode on ARM than native AAC.
        return "mp3", "audio/mpeg", ["-c:a", "libmp3lame", "-b:a", br, "-f", "mp3"]
    # AAC in an m4a (ipod) container. -f ipod forces the muxer (the ".tmp"
    # extension would otherwise confuse ffmpeg). +faststart for progressive play.
    return "m4a", "audio/mp4", ["-c:a", "aac", "-b:a", br, "-movflags", "+faststart", "-f", "ipod"]


def transcode_mime(fmt):
    return "audio/mpeg" if fmt == "mp3" else "audio/mp4"


def ensure_transcoded(src, bitrate=DEFAULT_BITRATE, fmt="m4a"):
    """Transcode `src` to a cached file at `bitrate` kbps in `fmt` (m4a/aac or
    mp3). Returns its path, or None if ffmpeg is unavailable or the transcode
    fails. Cached by source path+size+mtime+bitrate+fmt so edits/rate/codec
    changes invalidate."""
    if not HAVE_FFMPEG:
        return None
    try:
        st = os.stat(src)
    except OSError:
        return None
    ext, _mime, out_args = _codec_args(fmt, bitrate)
    raw = "{}|{}|{}|{}|{}".format(os.path.realpath(src), st.st_size, int(st.st_mtime), bitrate, fmt)
    key = hashlib.sha1(raw.encode("utf-8")).hexdigest()
    dest = os.path.join(TRANSCODE_DIR, key + "." + ext)
    if os.path.isfile(dest) and os.path.getsize(dest) > 0:
        return dest
    with _key_lock(key):
        if os.path.isfile(dest) and os.path.getsize(dest) > 0:
            return dest
        tmp = dest + ".tmp"
        # -threads lets ffmpeg use multiple cores (0 = auto).
        cmd = ["ffmpeg", "-nostdin", "-y", "-threads", str(FFMPEG_THREADS),
               "-i", src, "-vn"] + out_args + [tmp]
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL,
                                    stderr=subprocess.PIPE)
            proc.communicate()
            if proc.returncode != 0 or not os.path.isfile(tmp):
                _quiet_remove(tmp)
                return None
            os.replace(tmp, dest)
            return dest
        except Exception:
            _quiet_remove(tmp)
            return None


def _quiet_remove(path):
    try:
        os.remove(path)
    except OSError:
        pass


# --------------------------------------------------------------------------- #
# HLS (HTTP Live Streaming) — optional low-latency transcode
#
# We serve a *complete VOD playlist up front* (computed from the track's
# duration, with #EXT-X-ENDLIST), then transcode each ~10s segment **on demand**
# when AVPlayer requests it. Because the playlist is VOD, AVPlayer buffers
# aggressively (pulling several segments ahead) instead of hugging a live edge —
# which is what caused the stutter with an EVENT playlist. The ahead-of-time
# segment requests run in parallel, so all CPU cores are used; segments are
# cached for instant, fully-seekable replays.
#
# Trade-off: segments are encoded independently, so a lossy codec can introduce
# tiny boundary artifacts. 10s segments keep boundaries rare.
# --------------------------------------------------------------------------- #

HLS_SEGMENT_SECONDS = 10
PREWARM_SEGMENTS = 6         # how many segments to transcode ahead on playlist load
_seg_pool = None             # ThreadPoolExecutor (set in main) for segment pre-warm


def _hls_audio_args(fmt, bitrate):
    br = "{}k".format(bitrate)
    if fmt == "mp3":
        return ["-c:a", "libmp3lame", "-b:a", br]
    return ["-c:a", "aac", "-b:a", br]


def _hls_dir_key(src_real, size, mtime, bitrate, fmt):
    raw = "{}|{}|{}|{}|{}|hlsvod".format(src_real, size, mtime, bitrate, fmt)
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()


def hls_prepare(src, bitrate, fmt):
    """Create the HLS dir + meta.json for (src,bitrate,fmt). Returns
    (dir, key, duration, segs) or None (e.g. duration unknown)."""
    if not HAVE_FFMPEG:
        return None
    try:
        st = os.stat(src)
    except OSError:
        return None
    info = read_tags(src) or {}
    dur = info.get("duration")
    if not dur or dur <= 0:
        return None
    key = _hls_dir_key(os.path.realpath(src), st.st_size, int(st.st_mtime), bitrate, fmt)
    d = os.path.join(TRANSCODE_DIR, "hls", key)
    try:
        os.makedirs(d, exist_ok=True)
    except OSError:
        return None
    meta_path = os.path.join(d, "meta.json")
    if not os.path.isfile(meta_path):
        try:
            with open(meta_path, "w") as fh:
                json.dump({"src": os.path.realpath(src), "bitrate": bitrate,
                           "fmt": fmt, "dur": dur, "T": HLS_SEGMENT_SECONDS}, fh)
        except (OSError, IOError):
            return None
    segs = int(math.ceil(dur / float(HLS_SEGMENT_SECONDS)))
    return d, key, dur, segs


def hls_playlist_text(key, dur, T):
    n = int(math.ceil(dur / float(T)))
    lines = ["#EXTM3U", "#EXT-X-VERSION:3", "#EXT-X-TARGETDURATION:{}".format(T),
             "#EXT-X-MEDIA-SEQUENCE:0", "#EXT-X-PLAYLIST-TYPE:VOD"]
    for i in range(n):
        seglen = T if i < n - 1 else (dur - (n - 1) * T)
        if seglen <= 0:
            seglen = T
        lines.append("#EXTINF:{:.3f},".format(seglen))
        lines.append("/hls/{}/seg{:04d}.ts".format(key, i))
    lines.append("#EXT-X-ENDLIST")
    return "\n".join(lines) + "\n"


def ensure_segment(key, i):
    """Transcode HLS segment `i` for `key` on demand (cached). Returns path or None."""
    d = os.path.join(TRANSCODE_DIR, "hls", key)
    try:
        with open(os.path.join(d, "meta.json")) as fh:
            m = json.load(fh)
    except (OSError, IOError, ValueError):
        return None
    dest = os.path.join(d, "seg{:04d}.ts".format(i))
    if os.path.isfile(dest) and os.path.getsize(dest) > 0:
        return dest
    with _key_lock("seg:{}:{}".format(key, i)):
        if os.path.isfile(dest) and os.path.getsize(dest) > 0:
            return dest
        start = i * m["T"]
        tmp = dest + ".tmp"
        # -ss before -i = fast input seek. -threads 1 since we parallelise across
        # segments (one ffmpeg per core) rather than within a segment.
        cmd = ["ffmpeg", "-nostdin", "-y", "-threads", "1",
               "-ss", str(start), "-t", str(m["T"]), "-i", m["src"], "-vn"] + \
            _hls_audio_args(m["fmt"], m["bitrate"]) + \
            ["-avoid_negative_ts", "make_zero", "-muxdelay", "0", "-muxpreload", "0",
             "-f", "mpegts", tmp]
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            proc.communicate()
            if proc.returncode != 0 or not os.path.isfile(tmp):
                _quiet_remove(tmp)
                return None
            os.replace(tmp, dest)
            return dest
        except Exception:
            _quiet_remove(tmp)
            return None


def hls_prewarm(key, count):
    """Kick off the first `count` segment transcodes in the background pool so
    the player's initial buffer fills fast across all cores."""
    if _seg_pool is None:
        return
    for i in range(count):
        try:
            _seg_pool.submit(ensure_segment, key, i)
        except Exception:
            return


class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    """Threaded server. (http.server.ThreadingHTTPServer needs Python 3.7+;
    this works back to 3.4.)"""
    daemon_threads = True
    allow_reuse_address = True


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
    """Embedded tags. Prefers mutagen; falls back to ffprobe (handy on systems
    where mutagen can't be installed, e.g. old Python on a Raspberry Pi)."""
    if not HAVE_MUTAGEN:
        return read_tags_ffprobe(path)
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


def read_tags_ffprobe(path: str):
    """Tags + duration + artwork presence via ffprobe. Cached per file."""
    if not HAVE_FFPROBE:
        return None
    try:
        st = os.stat(path)
    except OSError:
        return None
    rp = os.path.realpath(path)
    with _probe_guard:
        hit = _probe_cache.get(rp)
        if hit and hit[0] == st.st_mtime and hit[1] == st.st_size:
            return hit[2]
    try:
        out = subprocess.check_output(
            ["ffprobe", "-v", "quiet", "-print_format", "json",
             "-show_format", "-show_streams", path],
            stderr=subprocess.DEVNULL)
        data = json.loads(out.decode("utf-8", "replace"))
    except Exception:
        return None

    fmt = data.get("format", {}) or {}
    tags = {}
    for k, v in (fmt.get("tags") or {}).items():
        tags[k.lower()] = v
    has_art = False
    for stream in data.get("streams", []):
        for k, v in (stream.get("tags") or {}).items():
            tags.setdefault(k.lower(), v)
        if stream.get("codec_type") == "video" and \
           (stream.get("disposition", {}) or {}).get("attached_pic") == 1:
            has_art = True

    duration = None
    try:
        if fmt.get("duration"):
            duration = round(float(fmt["duration"]), 2)
    except (TypeError, ValueError):
        pass

    meta = {
        "title": tags.get("title") or None,
        "artist": tags.get("artist") or tags.get("album_artist") or None,
        "album": tags.get("album") or None,
        "duration": duration,
        "has_art": has_art,
    }
    with _probe_guard:
        _probe_cache[rp] = (st.st_mtime, st.st_size, meta)
    return meta


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


def extract_artwork_ffmpeg(path: str):
    """Extract the embedded cover via ffmpeg (cached), or None."""
    if not HAVE_FFMPEG:
        return None
    try:
        st = os.stat(path)
    except OSError:
        return None
    key = hashlib.sha1(
        ("{}|{}|{}".format(os.path.realpath(path), st.st_size, int(st.st_mtime))).encode("utf-8")
    ).hexdigest()
    dest = os.path.join(TRANSCODE_DIR, "art_" + key + ".jpg")
    if not (os.path.isfile(dest) and os.path.getsize(dest) > 0):
        with _key_lock("art_" + key):
            if not (os.path.isfile(dest) and os.path.getsize(dest) > 0):
                tmp = dest + ".tmp"
                cmd = ["ffmpeg", "-nostdin", "-y", "-i", path, "-an",
                       "-map", "0:v:0", "-c:v", "mjpeg", "-frames:v", "1",
                       "-f", "image2", tmp]
                try:
                    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    proc.communicate()
                    if proc.returncode != 0 or not os.path.isfile(tmp):
                        _quiet_remove(tmp)
                        return None
                    os.replace(tmp, dest)
                except Exception:
                    _quiet_remove(tmp)
                    return None
    try:
        with open(dest, "rb") as fh:
            return fh.read(), "image/jpeg"
    except OSError:
        return None


def extract_artwork(path: str):
    """Return (image_bytes, mime) for the first embedded cover, or None."""
    if not HAVE_MUTAGEN:
        return extract_artwork_ffmpeg(path)
    try:
        audio = MutagenFile(path)
    except Exception:
        return None
    if audio is None:
        return extract_artwork_ffmpeg(path)

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

    return extract_artwork_ffmpeg(path)


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
    server_version = "AURA/" + VERSION

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
            parsed = urlparse(self.path)
            parts = [unquote(p) for p in parsed.path.split("/") if p != ""]
            query = parse_qs(parsed.query)

            if not parts or parts == ["health"]:
                return self._health()
            if parts == ["playlists"]:
                return self._list_playlists()
            if len(parts) == 2 and parts[0] == "playlists":
                return self._playlist_detail(parts[1])
            # HLS segment/playlist files: /hls/<key>/<name>
            if len(parts) == 3 and parts[0] == "hls":
                return self._hls_file(parts[1], parts[2])
            if len(parts) == 4 and parts[0] == "playlists" and parts[2] == "tracks":
                return self._track_detail(parts[1], parts[3])
            if len(parts) == 5 and parts[0] == "playlists" and parts[2] == "tracks":
                pl, fname, sub = parts[1], parts[3], parts[4]
                if sub == "audio":
                    fmt = (query.get("format") or [None])[0]
                    bitrate = self._bitrate(query)
                    return self._track_audio(pl, fname, fmt, bitrate)
                if sub == "hls.m3u8":
                    fmt = (query.get("format") or [None])[0]
                    bitrate = self._bitrate(query)
                    return self._track_hls(pl, fname, fmt, bitrate)
                if sub == "lyrics":
                    return self._track_lyrics(pl, fname)
                if sub == "artwork":
                    return self._track_artwork(pl, fname)

            self._error(404, "not found")
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as exc:  # pragma: no cover
            try:
                self._error(500, "server error: {}".format(exc))
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
            "ffmpeg": HAVE_FFMPEG,
            "ffprobe": HAVE_FFPROBE,
            "libmp3lame": HAVE_LAME,
            "formats": ["m4a"] + (["mp3"] if HAVE_LAME else []),
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
        # Metadata probing (ffprobe) is per-file and slowish; run in parallel.
        if files:
            workers = min(8, len(files))
            with ThreadPoolExecutor(max_workers=workers) as ex:
                tracks = list(ex.map(lambda f: track_json(pl, f, os.path.join(d, f)), files))
        else:
            tracks = []
        self._json({"id": pl, "name": pl, "tracks": tracks})

    def _track_detail(self, pl: str, fname: str):
        f = self._resolve_track(pl, fname)
        if f is None:
            return self._error(404, "track not found")
        self._json(track_json(pl, fname, f))

    def _bitrate(self, query):
        """Validated transcode bitrate (kbps) from the query, clamped to the
        allowed set."""
        raw = (query.get("bitrate") or query.get("br") or [None])[0]
        try:
            v = int(raw)
        except (TypeError, ValueError):
            return DEFAULT_BITRATE
        return v if v in ALLOWED_BITRATES else DEFAULT_BITRATE

    def _track_audio(self, pl: str, fname: str, fmt=None, bitrate=DEFAULT_BITRATE):
        f = self._resolve_track(pl, fname)
        if f is None:
            return self._error(404, "track not found")
        ext = os.path.splitext(fname)[1].lower()
        # Transcode non-native formats (e.g. .ogg) to AAC/m4a or MP3 on request so
        # AVPlayer can play them; native formats are always served as-is.
        if fmt in ("m4a", "aac", "mp3") and ext not in NATIVE_EXTS:
            if not HAVE_FFMPEG:
                return self._error(503, "transcoding unavailable (ffmpeg not installed)")
            if fmt == "mp3" and not HAVE_LAME:
                return self._error(503, "mp3 transcoding unavailable (libmp3lame not built into ffmpeg)")
            codec = "mp3" if fmt == "mp3" else "m4a"
            dest = ensure_transcoded(f, bitrate, codec)
            if dest is None:
                return self._error(502, "transcode failed")
            return self._serve_range(dest, transcode_mime(codec))
        mime = AUDIO_MIME.get(ext, "application/octet-stream")
        self._serve_range(f, mime)

    # ---- HLS ----

    def _send_m3u8(self, text):
        data = text.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/vnd.apple.mpegurl")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def _track_hls(self, pl: str, fname: str, fmt=None, bitrate=DEFAULT_BITRATE):
        f = self._resolve_track(pl, fname)
        if f is None:
            return self._error(404, "track not found")
        if not HAVE_FFMPEG:
            return self._error(503, "hls unavailable (ffmpeg not installed)")
        codec = "mp3" if fmt == "mp3" else "aac"
        if codec == "mp3" and not HAVE_LAME:
            return self._error(503, "mp3 hls unavailable (libmp3lame not built into ffmpeg)")
        res = hls_prepare(f, bitrate, codec)
        if res is None:
            return self._error(502, "hls prepare failed (unknown duration?)")
        d, key, dur, segs = res
        # Pre-warm the first segments in parallel so the player's buffer fills fast.
        hls_prewarm(key, min(segs, PREWARM_SEGMENTS))
        self._send_m3u8(hls_playlist_text(key, dur, HLS_SEGMENT_SECONDS))

    def _hls_file(self, key: str, name: str):
        if not re.match(r"^[0-9a-f]{40}$", key):
            return self._error(404, "not found")
        d = os.path.join(TRANSCODE_DIR, "hls", key)
        if name == "index.m3u8":
            try:
                with open(os.path.join(d, "meta.json")) as fh:
                    m = json.load(fh)
            except (OSError, IOError, ValueError):
                return self._error(404, "not found")
            return self._send_m3u8(hls_playlist_text(key, m["dur"], m["T"]))
        seg = re.match(r"^seg(\d+)\.ts$", name)
        if not seg:
            return self._error(404, "not found")
        dest = ensure_segment(key, int(seg.group(1)))
        if dest is None:
            return self._error(404, "segment unavailable")
        self._serve_range(dest, "video/mp2t")

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
                    self.send_header("Content-Range", "bytes */{}".format(size))
                    self.end_headers()
                    return

        length = end - start + 1
        self.send_response(206 if partial else 200)
        self.send_header("Content-Type", content_type)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        if partial:
            self.send_header("Content-Range", "bytes {}-{}/{}".format(start, end, size))
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
    parser.add_argument("--cache-dir", default=os.environ.get("TRANSCODE_DIR"),
                        help="where transcoded audio is cached "
                             "(default: system temp /aura-transcode)")
    parser.add_argument("--ffmpeg-threads", type=int,
                        default=int(os.environ.get("FFMPEG_THREADS", "0")),
                        help="threads per ffmpeg transcode (0 = auto/all cores)")
    args = parser.parse_args(argv)

    if not args.root:
        parser.error("music root required: pass it as an argument or set MUSIC_ROOT")

    global ROOT, TRANSCODE_DIR, FFMPEG_THREADS, _seg_pool, PREWARM_SEGMENTS
    ROOT = os.path.realpath(os.path.expanduser(args.root))
    if not os.path.isdir(ROOT):
        parser.error("not a directory: {}".format(ROOT))

    FFMPEG_THREADS = max(0, args.ffmpeg_threads)
    TRANSCODE_DIR = args.cache_dir or os.path.join(tempfile.gettempdir(), "aura-transcode")
    os.makedirs(TRANSCODE_DIR, exist_ok=True)

    # Parallel HLS segment transcoding across all cores.
    cores = os.cpu_count() or 4
    _seg_pool = ThreadPoolExecutor(max_workers=cores)
    PREWARM_SEGMENTS = cores + 2

    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    print("AURA music server v" + VERSION)
    print("  root:     " + ROOT)
    meta_src = "mutagen" if HAVE_MUTAGEN else ("ffprobe" if HAVE_FFPROBE else "filenames only")
    print("  metadata: " + meta_src + " (tags/duration/artwork)")
    print("  ffmpeg:   " + ("yes" if HAVE_FFMPEG else "no (.ogg/.opus won't transcode)")
          + (" (threads: " + ("auto" if FFMPEG_THREADS == 0 else str(FFMPEG_THREADS)) + ")" if HAVE_FFMPEG else ""))
    print("  codecs:   " + ", ".join(["aac/m4a"] + (["mp3"] if HAVE_LAME else [])))
    print("  hls:      VOD playlist + on-demand parallel segments ({} cores)".format(cores))
    print("  cache:    " + TRANSCODE_DIR)
    print("  serving:  http://{}:{}".format(args.host, args.port))
    print("  endpoints: /health  /playlists  /playlists/{name}  "
          ".../tracks/{file}[/audio|/lyrics|/artwork]")
    sys.stdout.flush()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down")
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
