#!/usr/bin/env python3
"""Prepare the shared project for the Android mobile export."""

from __future__ import annotations

from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "project.godot"
ROM_SCENE = ROOT / "rom_checker.tscn"
SETTINGS_SCENE = ROOT / "Instances" / "UI" / "Menus" / "settings_menu.tscn"
SETTINGS_SCRIPT = ROOT / "Scripts" / "UI" / "settings_menu.gd"
ANDROID_PRESET = ROOT / "export_presets_android_mobile.cfg"
EXPORT_PRESET = ROOT / "export_presets.cfg"


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


def remove_autoload(text: str, name: str) -> str:
    return re.sub(rf"(?m)^{re.escape(name)}=.*\n?", "", text)


def patch_project() -> None:
    text = PROJECT.read_text(encoding="utf-8-sig")
    text = remove_autoload(text, "BossArenaCamera")
    text = ensure_autoload(text, "LanguageManager", '"*res://Scripts/Autoload/language_manager.gd"')
    text = ensure_autoload(text, "MobileTouchControls", '"*res://Scripts/Autoload/mobile_touch_controls.gd"')
    text = ensure_setting(text, "application", "config/features", 'PackedStringArray("4.7")')
    text = ensure_setting(text, "application", "config/custom_user_dir_name", '"SuperMarioWorldRemastered-Mobile"')
    text = ensure_setting(text, "display", "window/size/viewport_width", "480")
    text = ensure_setting(text, "display", "window/size/viewport_height", "270")
    text = ensure_setting(text, "display", "window/stretch/mode", '"canvas_items"')
    text = ensure_setting(text, "display", "window/stretch/aspect", '"expand"')
    text = ensure_setting(text, "rendering", "renderer/rendering_method", '"gl_compatibility"')
    text = ensure_setting(text, "rendering", "renderer/rendering_method.mobile", '"gl_compatibility"')
    text = ensure_setting(text, "rendering", "textures/default_filters/use_nearest_mipmap_filter", "false")
    PROJECT.write_text(text, encoding="utf-8", newline="\n")


def patch_rom_picker() -> None:
    text = ROM_SCENE.read_text(encoding="utf-8-sig")
    text = re.sub(
        r'path="res://Scripts/UI/(?:rom_checker_windows_58|rom_checker)\.gd"',
        'path="res://Scripts/UI/rom_checker_android_67.gd"',
        text,
        count=1,
    )
    text = text.replace('text = "SELECT ROM"', 'text = "ADD ROM"')
    ROM_SCENE.write_text(text, encoding="utf-8", newline="\n")


def patch_settings_menu_scene() -> None:
    text = SETTINGS_SCENE.read_text(encoding="utf-8-sig")
    resource_line = '[ext_resource type="PackedScene" path="res://Instances/UI/mobile_settings.tscn" id="16_mobile"]\n'
    if "res://Instances/UI/mobile_settings.tscn" not in text:
        sub_pos = text.find("[sub_resource")
        if sub_pos < 0:
            raise RuntimeError("Could not locate settings-menu subresources")
        text = text[:sub_pos] + resource_line + "\n" + text[sub_pos:]

    sections_match = re.search(r"(?m)^sections = \[(.*)\]$", text)
    if sections_match and 'NodePath("MobileSettings")' not in sections_match.group(0):
        replacement = sections_match.group(0).replace(
            'NodePath("LanguageSettings")',
            'NodePath("LanguageSettings"), NodePath("MobileSettings")',
        )
        text = text[: sections_match.start()] + replacement + text[sections_match.end() :]

    if '[node name="MobileSettings"' not in text:
        marker = '[node name="AbilitySettings"'
        marker_pos = text.find(marker)
        if marker_pos < 0:
            raise RuntimeError("Could not locate AbilitySettings insertion point")
        mobile_node = '[node name="MobileSettings" parent="." instance=ExtResource("16_mobile")]\nmetadata/_edit_use_anchors_ = true\n\n'
        text = text[:marker_pos] + mobile_node + text[marker_pos:]
    SETTINGS_SCENE.write_text(text, encoding="utf-8", newline="\n")


def patch_settings_menu_script() -> None:
    text = SETTINGS_SCRIPT.read_text(encoding="utf-8-sig")
    text = text.replace(
        '[$DisplaySettings, $AudioSettings, $GameplaySettings, $LanguageSettings, $AbilitySettings]',
        '[$DisplaySettings, $AudioSettings, $GameplaySettings, $LanguageSettings, $MobileSettings, $AbilitySettings]',
    )
    SETTINGS_SCRIPT.write_text(text, encoding="utf-8", newline="\n")


def main() -> int:
    if not ANDROID_PRESET.is_file():
        raise FileNotFoundError(ANDROID_PRESET)
    patch_project()
    patch_rom_picker()
    patch_settings_menu_scene()
    patch_settings_menu_script()
    shutil.copyfile(ANDROID_PRESET, EXPORT_PRESET)
    print("Android mobile project with bilingual UI, ROM picker and movable controls is ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
