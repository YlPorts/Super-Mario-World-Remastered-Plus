# Android version

This branch adds an Android ARM64 export with a native multitouch overlay.

## Controls

- D-pad: move and navigate menus
- A: jump / confirm
- B: run / cancel
- X: spin jump
- Y: dive
- Pause icon: pause

The overlay calls the existing Godot InputMap actions directly, so multiple buttons can be held at the same time (for example, run + jump).

## Downloading the APK from GitHub Actions

1. Open the repository's **Actions** tab.
2. Select **Android APK**.
3. Open the latest successful run.
4. Download the `smw-remastered-plus-android-arm64` artifact.
5. Extract the ZIP and install `SuperMarioWorldRemasteredPlus.apk`.

Android may ask for permission to install apps from the browser or file manager used to open the APK.

## Building locally

Requirements:

- Godot 4.4.1 with Android export templates
- OpenJDK 17
- Android SDK configured in Godot
- Python 3

Run:

```bash
python3 tools/prepare_android.py
mkdir -p build/android
godot --headless --path . --export-debug Android build/android/SuperMarioWorldRemasteredPlus.apk
```

`tools/prepare_android.py` adds the touch-control autoload and Android-friendly rendering settings to the local `project.godot`. It is safe to run more than once.

## ROM requirement

This project does not include a Super Mario World ROM. Each user must provide a legally obtained original SNES ROM as required by the upstream project.
