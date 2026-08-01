#!/usr/bin/env python3
"""Prepare shared bilingual UI resources for desktop and Android exports."""

from __future__ import annotations

from pathlib import Path
import re
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "project.godot"
LANGUAGE_SCENE = ROOT / "Instances" / "UI" / "language_settings.tscn"
FONT_DIR = ROOT / "Assets" / "Fonts"
FONT_FILE = FONT_DIR / "PixelifySans.ttf"
FONT_LICENSE = FONT_DIR / "PixelifySans-OFL.txt"
FONT_URL = "https://raw.githubusercontent.com/google/fonts/main/ofl/pixelifysans/PixelifySans%5Bwght%5D.ttf"
LICENSE_URL = "https://raw.githubusercontent.com/google/fonts/main/ofl/pixelifysans/OFL.txt"


def ensure_setting(text: str, section: str, key: str, value: str) -> str:
    header = f"[{section}]"
    line = f"{key}={value}"
    pattern = re.compile(rf"(?m)^{re.escape(key)}=.*$")
    if pattern.search(text):
        return pattern.sub(line, text, count=1)
    section_pos = text.find(header)
    if section_pos < 0:
        return text.rstrip() + f"\n\n{header}\n\n{line}\n"
    insert_at = text.find("\n", section_pos)
    return text[: insert_at + 1] + f"\n{line}\n" + text[insert_at + 1 :]


def ensure_autoload(text: str, name: str, value: str) -> str:
    pattern = re.compile(rf"(?m)^{re.escape(name)}=.*$")
    line = f"{name}={value}"
    if pattern.search(text):
        return pattern.sub(line, text, count=1)
    return ensure_setting(text, "autoload", name, value)


def download_file(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_file() and destination.stat().st_size > 1024:
        return
    temporary = destination.with_suffix(destination.suffix + ".tmp")
    with urllib.request.urlopen(url, timeout=45) as response:
        temporary.write_bytes(response.read())
    if temporary.stat().st_size <= 1024:
        temporary.unlink(missing_ok=True)
        raise RuntimeError(f"Downloaded file is unexpectedly small: {url}")
    temporary.replace(destination)


def patch_language_selector() -> None:
    text = LANGUAGE_SCENE.read_text(encoding="utf-8-sig")
    text = text.replace(
        'path="res://Scripts/UI/language_settings.gd"',
        'path="res://Scripts/UI/language_settings_fixed.gd"',
    )
    # Give the two-language selector a compact centered area on every aspect ratio.
    text = re.sub(r"anchor_left = 0\.1", "anchor_left = 0.2", text, count=1)
    text = re.sub(r"anchor_right = 0\.883333", "anchor_right = 0.8", text, count=1)
    text = re.sub(r"theme_override_constants/separation = \d+", "theme_override_constants/separation = 10", text, count=1)
    LANGUAGE_SCENE.write_text(text, encoding="utf-8", newline="\n")


def main() -> int:
    download_file(FONT_URL, FONT_FILE)
    download_file(LICENSE_URL, FONT_LICENSE)

    project_text = PROJECT.read_text(encoding="utf-8-sig")
    project_text = ensure_autoload(
        project_text,
        "FontFallbackManager",
        '"*res://Scripts/Autoload/font_fallback_manager.gd"',
    )
    project_text = ensure_setting(
        project_text,
        "rendering",
        "textures/default_filters/use_nearest_mipmap_filter",
        "false",
    )
    PROJECT.write_text(project_text, encoding="utf-8", newline="\n")
    patch_language_selector()

    if not FONT_FILE.is_file():
        raise RuntimeError("Pixelify Sans was not prepared")
    print("Shared bilingual UI and Latin pixel font are ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
