# Changelog

## Version 1.0.6 — 2026-04-08

- Added a direct-app automation attempt first (for both `Brother GTX File Viewer` and `Brother GTX Graphics Lab`) to reduce reliance on blocked System Events keystrokes.
- Kept active-window `Command+S` as fallback and now include direct automation errors in failure output for easier debugging.

## Version 1.0.5 — 2026-04-08

- Restored the original print trigger flow to target the active window and send `Command+S` only.
- Removed the Brother GTX app activation dependency that could fail with `Can't get application`.
- Made the Settings title show `Settings — Version X.Y.Z` for clearer in-app visibility.

## Version 1.0.4 — 2026-04-08

- Made the Settings version display high-visibility by adding a version badge in the header.
- Added a dedicated `App Version` row in Settings content so the version is always visible and easy to copy.

## Version 1.0.3 — 2026-04-08

- Added an app version constant and displayed the current version in the Settings window header.
- Added clearer print automation permission diagnostics and remediation guidance for macOS Accessibility/TCC blocks.
