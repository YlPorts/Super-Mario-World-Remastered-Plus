#!/usr/bin/env python3
from pathlib import Path
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
print("Android BUILD 68 hardened mobile controls selected.")
