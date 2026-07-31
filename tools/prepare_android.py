#!/usr/bin/env python3
"""Prepare the Godot project for Android export.

The script is intentionally idempotent. It keeps the large upstream
project.godot untouched in Git and applies only the Android-specific settings
inside the CI workspace before exporting.
"""

from __future__ import annotations

from pathlib import Path
import re
import sys

PROJECT_FILE = Path(__file__).resolve().parents[1] / "project.godot"
AUTOLOAD_LINE = 'TouchControls="*res://Android/touch_controls.gd"'


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


def ensure_autoload(text: str) -> str:
    if re.search(r"(?m)^TouchControls=", text):
        return re.sub(r"(?m)^TouchControls=.*$", AUTOLOAD_LINE, text, count=1)
    return ensure_setting(text, "autoload", "TouchControls", '"*res://Android/touch_controls.gd"')


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

    text = ensure_autoload(text)
    text = ensure_setting(text, "display", "window/handheld/orientation", "0")
    text = ensure_setting(text, "rendering", "renderer/rendering_method.mobile", '"gl_compatibility"')
    text = ensure_setting(text, "rendering", "renderer/rendering_method", '"gl_compatibility"')

    PROJECT_FILE.write_text(text, encoding="utf-8", newline="\n")
    print("Android touch controls and mobile renderer settings are ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
