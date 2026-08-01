# Windows x64 build

This branch keeps the original desktop startup flow and builds with Godot 4.7.1.

- No Android ROM picker services are loaded.
- No touch-control overlay is loaded.
- Starts centered in a safe 1280x720 window.
- Uses a separate Windows 4.7.1 settings folder so old fullscreen preferences are ignored.
- The window is resizable.
- `canvas_items` with `expand` allows widescreen and ultrawide windows to reveal additional horizontal game space instead of stretching the image out of proportion.
- Exclusive fullscreen is replaced with a safer borderless maximized window.
- GitHub Actions publishes a Windows x64 portable ZIP separately from the Android APK workflow.
