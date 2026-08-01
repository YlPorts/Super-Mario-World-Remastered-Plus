# Windows x64 build

This branch keeps the original desktop startup flow and builds with Godot 4.7.1.

- No Android ROM picker services are loaded.
- No touch-control overlay is loaded.
- The window is resizable.
- `canvas_items` with `expand` allows widescreen and ultrawide windows to reveal additional horizontal game space instead of stretching the image out of proportion.
- GitHub Actions publishes a Windows x64 portable ZIP separately from the Android APK workflow.
- The workflow is registered independently in the Actions tab as `Windows x64 - Godot 4.7.1`.
- Windows x64 validation is enabled for this branch and its pull request.
