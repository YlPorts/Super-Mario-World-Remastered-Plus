#!/usr/bin/env python3
"""Prepare the Godot project for Android export.

The script is idempotent so local builds and GitHub Actions use the same
mobile renderer, autoloads, landscape orientation and ultrawide scaling.
"""

from __future__ import annotations

from pathlib import Path
import re
import sys

PROJECT_FILE = Path(__file__).resolve().parents[1] / "project.godot"
AUTOLOADS = {
    "PortManager": '"*res://Android/port_manager.gd"',
    "TouchControls": '"*res://Android/touch_controls.gd"',
}


def ensure_setting(text: str, section: str, key: str, value: str) -> str:
    section_header = f"[{section}]"
    line = f"{key}={value}"
    setting_pattern = re.compile(rf"(?m)^{re.escape(key)}=.*$")

    if setting_pattern.search(text):
        return setting_pattern.sub(line, text, count=1)

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


def validate_input_actions(text: str) -> list[str]:
    expected = (
        "move_left_0",
        "move_right_0",
        "move_up_0",
        "move_down_0",
        "jump_0",
        "run_0",
        "spin_jump_0",
        "dive_0",
        "pause",
        "ui_tab_left",
        "ui_tab_right",
        "ui_back",
        "apply_settings",
    )
    return [action for action in expected if not re.search(rf"(?m)^{re.escape(action)}=\{{", text)]


def main() -> int:
    if not PROJECT_FILE.is_file():
        print(f"error: {PROJECT_FILE} was not found", file=sys.stderr)
        return 1

    text = PROJECT_FILE.read_text(encoding="utf-8-sig")
    missing_actions = validate_input_actions(text)
    if missing_actions:
        print(
            "warning: touch controls reference missing InputMap actions: "
            + ", ".join(missing_actions),
            file=sys.stderr,
        )

    for name, value in AUTOLOADS.items():
        text = ensure_autoload(text, name, value)

    text = ensure_setting(text, "display", "window/handheld/orientation", "0")
    text = ensure_setting(text, "display", "window/stretch/mode", '"canvas_items"')
    text = ensure_setting(text, "display", "window/stretch/aspect", '"expand"')
    text = ensure_setting(text, "rendering", "renderer/rendering_method.mobile", '"gl_compatibility"')
    text = ensure_setting(text, "rendering", "renderer/rendering_method", '"gl_compatibility"')
    text = ensure_setting(text, "rendering", "textures/default_filters/use_nearest_mipmap_filter", "false")
    text = ensure_setting(text, "rendering", "2d/snap/snap_2d_transforms_to_pixel", "true")

    PROJECT_FILE.write_text(text, encoding="utf-8", newline="\n")
    print("Android ROM selector, touch controls and ultrawide settings are ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
