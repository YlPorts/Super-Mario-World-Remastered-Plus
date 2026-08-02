#!/usr/bin/env python3
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

subprocess.run([sys.executable, str(ROOT / "tools" / "prepare_android_mobile.py")], check=True)
project = ROOT / "project.godot"
text = project.read_text(encoding="utf-8-sig")
text = text.replace(
    'MobileTouchControls="*res://Scripts/Autoload/mobile_touch_controls.gd"',
    'MobileTouchControls="*res://Scripts/Autoload/mobile_touch_controls_68.gd"',
)
project.write_text(text, encoding="utf-8", newline="\n")

# The workflow creates this file before project preparation. Godot 4.7 requires
# an explicit EditorSettings resource type in the header; rewrite it in CI so
# Android SDK, Java and debug-signing paths are actually loaded by the exporter.
if os.environ.get("CI", "").lower() == "true":
    sdk_root = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
    java_home = os.environ.get("JAVA_HOME")
    if not sdk_root or not java_home:
        raise RuntimeError("Android SDK or JAVA_HOME is missing in CI")

    home = Path.home()
    editor_settings = home / ".config" / "godot" / "editor_settings-4.7.tres"
    debug_keystore = home / ".android" / "debug.keystore"
    editor_settings.parent.mkdir(parents=True, exist_ok=True)

    def gd_string(value: str | Path) -> str:
        return str(value).replace("\\", "\\\\").replace('"', '\\"')

    editor_settings.write_text(
        "[gd_resource type=\"EditorSettings\" format=3]\n\n"
        "[resource]\n"
        f'export/android/android_sdk_path = "{gd_string(sdk_root)}"\n'
        f'export/android/java_sdk_path = "{gd_string(java_home)}"\n'
        f'export/android/debug_keystore = "{gd_string(debug_keystore)}"\n'
        'export/android/debug_keystore_user = "androiddebugkey"\n'
        'export/android/debug_keystore_pass = "android"\n',
        encoding="utf-8",
        newline="\n",
    )
    print("Godot 4.7 Android editor settings repaired for CI.")

print("Android BUILD 70 hardened mobile controls selected.")
