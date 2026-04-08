# baddadprintmanager

Designed by Ricky

## Print automation dependency

`automated_print.py` now uses Hammerspoon with a dedicated Lua file (`print_automation.lua`) to send print keystrokes to Brother GTX apps.

- Install Hammerspoon: https://www.hammerspoon.org/
- Ensure the `hs` binary is available (typically `/opt/homebrew/bin/hs` or `/usr/local/bin/hs`).
- In macOS System Settings → Privacy & Security → Accessibility, allow Hammerspoon.
- Keep `print_automation.lua` next to `automated_print.py` (including in bundled app resources).
