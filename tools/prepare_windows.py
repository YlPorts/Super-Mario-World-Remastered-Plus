#!/usr/bin/env python3
"""Prepare the original desktop project for a safe Godot 4.7.1 Windows export.

The Windows build stays separate from Android, starts in a centered 1280x720
window, uses a fresh settings directory, and expands the canvas for widescreen
and ultrawide displays without stretching the artwork.
"""

from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PROJECT_FILE = ROOT / "project.godot"
SETTINGS_MANAGER = ROOT / "Scripts" / "Autoload" / "SettingsManager.gd"
ANDROID_AUTOLOADS = ("PortManager", "TouchControls", "TouchControlsRefresh")
WINDOW_AUTOLOADS = {"BossArenaCamera": '"*res://Scripts/Autoload/boss_arena_camera.gd"'}


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


def ensure_autoload(text: str, name: str, value: str) -> str:
    if re.search(rf"(?m)^{re.escape(name)}=", text):
        return re.sub(rf"(?m)^{re.escape(name)}=.*$", f"{name}={value}", text, count=1)
    return ensure_setting(text, "autoload", name, value)


def remove_android_autoloads(text: str) -> str:
    for name in ANDROID_AUTOLOADS:
        text = re.sub(rf"(?m)^{re.escape(name)}=.*\n?", "", text)
    return text


def patch_safe_video_defaults() -> None:
    if not SETTINGS_MANAGER.is_file():
        raise FileNotFoundError(f"missing {SETTINGS_MANAGER}")

    text = SETTINGS_MANAGER.read_text(encoding="utf-8-sig")
    text = text.replace('"resolution": Vector2(1440, 810),', '"resolution": Vector2(1280, 720),', 1)
    text = text.replace('"window_type": 0,', '"window_type": 0,', 1)

    # Prevent a stale or user-selected exclusive fullscreen setting from taking
    # over the monitor during startup. Option 2 becomes a safe borderless,
    # maximized desktop window instead of exclusive fullscreen.
    old_fullscreen = '''\t\t2:\n\t\t\tDisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)\n\t\t\tDisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)\n\t\t\tDisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MAX, true)'''
    safe_fullscreen = '''\t\t2:\n\t\t\tDisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)\n\t\t\tDisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)\n\t\t\tDisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MAX, true)'''
    if old_fullscreen in text:
        text = text.replace(old_fullscreen, safe_fullscreen, 1)

    SETTINGS_MANAGER.write_text(text, encoding="utf-8", newline="\n")


def main() -> int:
    if not PROJECT_FILE.is_file():
        print(f"error: {PROJECT_FILE} was not found", file=sys.stderr)
        return 1

    text = PROJECT_FILE.read_text(encoding="utf-8-sig")
    text = remove_android_autoloads(text)
    for name, value in WINDOW_AUTOLOADS.items():
        text = ensure_autoload(text, name, value)

    text = ensure_setting(text, "application", "config/features", 'PackedStringArray("4.7")')
    # Separate settings prevent an older fullscreen preference from being reused.
    text = ensure_setting(
        text,
        "application",
        "config/custom_user_dir_name",
        '"SuperMarioWorldRemastered-Windows-4.7.1"',
    )

    text = ensure_setting(text, "display", "window/size/viewport_width", "480")
    text = ensure_setting(text, "display", "window/size/viewport_height", "270")
    text = ensure_setting(text, "display", "window/size/window_width_override", "1280")
    text = ensure_setting(text, "display", "window/size/window_height_override", "720")
    text = ensure_setting(text, "display", "window/size/mode", "0")
    text = ensure_setting(text, "display", "window/size/initial_position_type", "2")
    text = ensure_setting(text, "display", "window/size/resizable", "true")
    text = ensure_setting(text, "display", "window/stretch/mode", '"canvas_items"')
    text = ensure_setting(text, "display", "window/stretch/aspect", '"expand"')
    text = ensure_setting(text, "display", "window/dpi/allow_hidpi", "true")

    text = ensure_setting(text, "rendering", "renderer/rendering_method", '"gl_compatibility"')
    text = ensure_setting(text, "rendering", "renderer/rendering_method.mobile", '"gl_compatibility"')
    text = ensure_setting(text, "rendering", "textures/default_filters/use_nearest_mipmap_filter", "false")
    text = ensure_setting(text, "rendering", "2d/snap/snap_2d_transforms_to_pixel", "true")

    PROJECT_FILE.write_text(text, encoding="utf-8", newline="\n")
    patch_safe_video_defaults()

    for name in ANDROID_AUTOLOADS:
        if re.search(rf"(?m)^{re.escape(name)}=", text):
            print(f"error: Android autoload {name} is still enabled", file=sys.stderr)
            return 1
    for name in WINDOW_AUTOLOADS:
        if not re.search(rf"(?m)^{re.escape(name)}=", text):
            print(f"error: Windows autoload {name} is missing", file=sys.stderr)
            return 1

    print("Windows Godot 4.7.1 safe windowed widescreen project is ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
