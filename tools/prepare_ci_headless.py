#!/usr/bin/env python3
"""Disable editor-only integrations in CI before headless import/export.

The game does not need VCS or editor docks at runtime. Keeping those plugins
active in a clean Actions checkout causes unrelated editor errors and can make
Godot return a failed import even when the game scripts are valid.
"""

from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PROJECT_FILE = ROOT / "project.godot"


def replace_required(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise RuntimeError(f"could not patch {label}")
    return updated


def main() -> int:
    if not PROJECT_FILE.is_file():
        print(f"error: missing {PROJECT_FILE}", file=sys.stderr)
        return 1

    text = PROJECT_FILE.read_text(encoding="utf-8-sig")
    try:
        text = replace_required(
            text,
            r'^run/main_scene=.*$',
            'run/main_scene="res://rom_checker.tscn"',
            "main scene",
        )
        text = replace_required(
            text,
            r'^version_control/plugin_name=.*$',
            'version_control/plugin_name=""',
            "VCS plugin",
        )
        text = replace_required(
            text,
            r'^version_control/autoload_on_startup=.*$',
            'version_control/autoload_on_startup=false',
            "VCS autoload",
        )
        text = replace_required(
            text,
            r'^enabled=PackedStringArray\(.*\)$',
            'enabled=PackedStringArray()',
            "editor plugins",
        )
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    PROJECT_FILE.write_text(text, encoding="utf-8", newline="\n")

    required = (
        'run/main_scene="res://rom_checker.tscn"',
        'version_control/plugin_name=""',
        'version_control/autoload_on_startup=false',
        'enabled=PackedStringArray()',
    )
    for value in required:
        if value not in text:
            print(f"error: CI setting was not applied: {value}", file=sys.stderr)
            return 1

    print("Headless CI project prepared: editor plugins and VCS disabled.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
