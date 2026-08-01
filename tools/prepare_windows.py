#!/usr/bin/env python3
"""Prepare the original desktop project for a Godot 4.7.1 Windows export.

This intentionally keeps the PC startup flow and removes Android-only
services if the branch is ever rebased onto mobile work. The viewport expands
with the window, allowing widescreen and ultrawide resolutions without touch UI.
"""

from __future__ import annotations

from pathlib import Path
import re
import sys

PROJECT_FILE = Path(__file__).resolve().parents[1] / "project.godot"
ANDROID_AUTOLOADS = ("PortManager", "TouchControls", "TouchControlsRefresh")


def ensure_setting(text: str, section: str, key: str, value: str) -> str:
    section_header = f"[{section}]"
    line = f"{key}={value}"
    pattern = re.compile(rf"(?m)^{re.escape(key)}=.*$")

    if pattern.search(text):
        return pattern.sub(line, text, count=1)

    section_index = text.find(section_header)
    if section_index == -1:
        if not text.endswith("\n"):
            text += "\n"
        return f"{text}\n{section_header}\n\n{line}\n"

    insert_at = text.find("\n", section_index)
    if insert_at == -1:
        return f"{text}\n\n{line}\n"
    return text[: insert_at + 1] + f"\n{line}\n" + text[insert_at + 1 :]


def remove_android_autoloads(text: str) -> str:
    for name in ANDROID_AUTOLOADS:
        text = re.sub(rf"(?m)^{re.escape(name)}=.*\n?", "", text)
    return text


def main() -> int:
    if not PROJECT_FILE.is_file():
        print(f"error: {PROJECT_FILE} was not found", file=sys.stderr)
        return 1

    text = PROJECT_FILE.read_text(encoding="utf-8-sig")
    text = remove_android_autoloads(text)

    # Explicitly target the requested editor/runtime generation.
    text = ensure_setting(
        text,
        "application",
        "config/features",
        'PackedStringArray("4.7")',
    )

    # Keep the native desktop game flow while supporting arbitrary window sizes.
    text = ensure_setting(text, "display", "window/size/viewport_width", "480")
    text = ensure_setting(text, "display", "window/size/viewport_height", "270")
    text = ensure_setting(text, "display", "window/size/window_width_override", "1280")
    text = ensure_setting(text, "display", "window/size/window_height_override", "720")
    text = ensure_setting(text, "display", "window/size/resizable", "true")
    text = ensure_setting(text, "display", "window/stretch/mode", '"canvas_items"')
    text = ensure_setting(text, "display", "window/stretch/aspect", '"expand"')
    text = ensure_setting(text, "display", "window/dpi/allow_hidpi", "true")

    # Compatibility renderer works on a wider range of Windows GPUs.
    text = ensure_setting(
        text,
        "rendering",
        "renderer/rendering_method",
        '"gl_compatibility"',
    )
    text = ensure_setting(
        text,
        "rendering",
        "renderer/rendering_method.mobile",
        '"gl_compatibility"',
    )
    text = ensure_setting(
        text,
        "rendering",
        "textures/default_filters/use_nearest_mipmap_filter",
        "false",
    )
    text = ensure_setting(
        text,
        "rendering",
        "2d/snap/snap_2d_transforms_to_pixel",
        "true",
    )

    PROJECT_FILE.write_text(text, encoding="utf-8", newline="\n")

    for name in ANDROID_AUTOLOADS:
        if re.search(rf"(?m)^{re.escape(name)}=", text):
            print(f"error: Android autoload {name} is still enabled", file=sys.stderr)
            return 1

    print("Windows Godot 4.7.1 widescreen project is ready; touch controls are disabled.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
