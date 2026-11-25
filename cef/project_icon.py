"""Project icon contract of the CEF Windows player package (README "Project icon").

Resolves, validates and prepares the game's icon for a package, with the Roves icon as the
fallback. Used by the engine workflow (`cef-netrender-probe.yml`, source of truth:
support/cef-netrender-probe/packaging/project_icon.py in DRincs-Productions/roves) and, as an
identical copy, by DRincs-Productions/roves-action `cef/project_icon.py`; Roves Packmaster implements
the same rules in Rust (`src-tauri/src/cef_player.rs`). Keep the three in step.

Sources, first match wins (the PNG and the ICO are resolved independently):

  window PNG  1. --icon-png (explicit)       2. <content>/icon.png
  play.exe    1. --icon-ico (explicit)       2. an ICO generated from the resolved window PNG
              3. <content>/icon.ico          4. <content>/favicon.ico
              5. --fallback-ico (Roves)      6. none: play.exe keeps the base's icon
  window PNG, when none above: the largest frame of a project ICO (explicit or found).
  No project icon at all: no icon.png in the package, the player shows the Roves logo.

Rules (the same limits as the player's `src/icon_rules.rs`): at most 8 MiB; PNG square,
16..=2048 px, fully decodable; ICO a valid icon directory with every frame decodable and a
square largest frame of at least 16 px. An explicit file that breaks them is an error (exit
1); a file found in the content directory that breaks them is a warning and the next source
is tried.

Writes to --out: play.ico (absent only in case 6), icon.png (absent when there is no project
icon), result.env (window_source, exe_source, window_detail, exe_detail). Requires Pillow
(the workflows pin 11.3.0); run with `python -I`.
"""

import argparse
import os
import shutil
import struct
import sys

from PIL import Image

MAX_ICON_BYTES = 8 * 1024 * 1024
MIN_ICON_PX = 16
MAX_ICON_PX = 2048
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]


class IconError(Exception):
    pass


def _read_limited(path):
    if not os.path.isfile(path):
        raise IconError("not a file")
    size = os.path.getsize(path)
    if size > MAX_ICON_BYTES:
        raise IconError(f"{size} bytes exceeds the {MAX_ICON_BYTES}-byte limit")
    with open(path, "rb") as f:
        return f.read()


def _check_edge(width, height):
    if width != height:
        raise IconError(f"{width}x{height} is not square")
    if not MIN_ICON_PX <= width <= MAX_ICON_PX:
        raise IconError(f"{width}x{height} is outside {MIN_ICON_PX}..={MAX_ICON_PX} px")


def check_png(path):
    """Returns the edge of a valid project PNG."""
    data = _read_limited(path)
    if len(data) < 33 or data[:8] != PNG_SIGNATURE or data[8:16] != b"\x00\x00\x00\x0dIHDR":
        raise IconError("not a PNG file (signature or IHDR missing)")
    width, height = struct.unpack(">II", data[16:24])
    _check_edge(width, height)
    try:
        with Image.open(path) as im:
            if im.format != "PNG" or im.size != (width, height):
                raise IconError(f"decoded as {im.format} {im.size}")
            im.load()
    except IconError:
        raise
    except Exception as e:  # Pillow raises several types for damaged files
        raise IconError(f"decode: {e}") from None
    return width


def check_ico(path):
    """Returns the largest frame edge of a valid project ICO."""
    data = _read_limited(path)
    if len(data) < 22 or data[:4] != b"\x00\x00\x01\x00" or struct.unpack("<H", data[4:6])[0] == 0:
        raise IconError("not an ICO file (icon directory header missing)")
    try:
        with Image.open(path) as im:
            if im.format != "ICO":
                raise IconError(f"decoded as {im.format}")
            sizes = sorted(im.info.get("sizes", set()))
            if not sizes:
                raise IconError("no frame")
            for size in sizes:
                im.size = size
                im.load()
    except IconError:
        raise
    except Exception as e:
        raise IconError(f"decode: {e}") from None
    width, height = max(sizes, key=lambda s: s[0] * s[1])
    if width != height or width < MIN_ICON_PX:
        raise IconError(f"largest frame {width}x{height} is not a square of at least {MIN_ICON_PX} px")
    return width


def _note(kind, message):
    print(f"::{kind}::project icon: {message}", flush=True)


def _pick(candidates, check):
    """First valid (path, label, edge); explicit invalid files raise."""
    for path, label, explicit in candidates:
        if not path:
            continue
        if not explicit and not os.path.isfile(path):
            continue
        try:
            return path, label, check(path)
        except IconError as e:
            if explicit:
                raise IconError(f"{label} {path}: {e}") from None
            _note("warning", f"ignoring {label} ({e}); trying the next source")
    return None


def resolve(content, icon_png, icon_ico, fallback_ico, out):
    os.makedirs(out, exist_ok=True)
    png = _pick(
        [(icon_png, "icon-png", True), (os.path.join(content, "icon.png"), "game icon.png", False)],
        check_png,
    )
    explicit_ico = _pick([(icon_ico, "icon-ico", True)], check_ico)
    found_ico = _pick(
        [
            (os.path.join(content, "icon.ico"), "game icon.ico", False),
            (os.path.join(content, "favicon.ico"), "game favicon.ico", False),
        ],
        check_ico,
    )
    result = {}
    play_ico = os.path.join(out, "play.ico")
    window_png = os.path.join(out, "icon.png")

    if png:
        shutil.copyfile(png[0], window_png)
        result["window_source"] = "project"
        result["window_detail"] = f"{png[1]} {png[2]}x{png[2]}"
    else:
        ico = explicit_ico or found_ico
        if ico:
            with Image.open(ico[0]) as im:
                im.size = (ico[2], ico[2])
                im.load()
                im.convert("RGBA").save(window_png, format="PNG")
            check_png(window_png)
            result["window_source"] = "project"
            result["window_detail"] = f"largest frame of {ico[1]} {ico[2]}x{ico[2]}"
        else:
            result["window_source"] = "roves"
            result["window_detail"] = "no project icon (embedded Roves logo)"

    if explicit_ico:
        shutil.copyfile(explicit_ico[0], play_ico)
        result["exe_source"] = "project"
        result["exe_detail"] = explicit_ico[1]
    elif png:
        with Image.open(png[0]) as im:
            sizes = [(s, s) for s in ICO_SIZES if s <= png[2]]
            im.convert("RGBA").save(play_ico, format="ICO", sizes=sizes)
        check_ico(play_ico)
        result["exe_source"] = "project"
        result["exe_detail"] = f"ICO generated from {png[1]}"
    elif found_ico:
        shutil.copyfile(found_ico[0], play_ico)
        result["exe_source"] = "project"
        result["exe_detail"] = found_ico[1]
    elif fallback_ico and os.path.isfile(fallback_ico):
        check_ico(fallback_ico)
        shutil.copyfile(fallback_ico, play_ico)
        result["exe_source"] = "roves"
        result["exe_detail"] = "Roves fallback icon"
    else:
        result["exe_source"] = "unchanged"
        result["exe_detail"] = "no project icon and no Roves fallback icon in the base"

    with open(os.path.join(out, "result.env"), "w", encoding="utf-8", newline="\n") as f:
        for key in ("window_source", "window_detail", "exe_source", "exe_detail"):
            f.write(f"{key}={result[key]}\n")
    _note(
        "notice",
        f"window={result['window_source']} ({result['window_detail']}); "
        f"play.exe={result['exe_source']} ({result['exe_detail']})",
    )
    return result


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--content", required=True)
    parser.add_argument("--icon-png", default="")
    parser.add_argument("--icon-ico", default="")
    parser.add_argument("--fallback-ico", default="")
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    if os.path.exists(args.out) and os.listdir(args.out):
        _note("error", f"{args.out} is not empty")
        return 1
    try:
        resolve(args.content, args.icon_png, args.icon_ico, args.fallback_ico, args.out)
    except IconError as e:
        _note("error", str(e))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
