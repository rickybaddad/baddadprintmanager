import json
import os
import subprocess
import sys
import time
from typing import Dict, List, Optional, Tuple

GTX_APP_CANDIDATES = [
    "Brother GTX File Viewer",
    "Brother GTX Graphics Lab",
]

HS_BIN_CANDIDATES = [
    "/opt/homebrew/bin/hs",
    "/usr/local/bin/hs",
    "hs",
]

HS_PORT_ERROR_FRAGMENTS = [
    "message port was invalidated",
    "error communicating with hammerspoon",
    "cfmessageport",
    "can't access hammerspoon message port",
]


def run_command(cmd: List[str], env: Optional[Dict[str, str]] = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, env=env)


def resolve_hs_binary() -> Optional[str]:
    for candidate in HS_BIN_CANDIDATES:
        if os.path.isabs(candidate):
            if os.path.exists(candidate) and os.access(candidate, os.X_OK):
                return candidate
            continue

        probe = run_command(["/usr/bin/which", candidate])
        if probe.returncode == 0:
            path = (probe.stdout or "").strip()
            if path:
                return path
    return None


def resolve_lua_script_path() -> str:
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "print_automation.lua")


def ensure_hammerspoon_ipc_module() -> None:
    config_dir = os.path.expanduser("~/.hammerspoon")
    config_path = os.path.join(config_dir, "init.lua")
    ipc_line = 'require("hs.ipc")'

    os.makedirs(config_dir, exist_ok=True)

    if not os.path.exists(config_path):
        with open(config_path, "w", encoding="utf-8") as file:
            file.write(f"-- Added by BADDAD print automation\n{ipc_line}\n")
        return

    with open(config_path, "r", encoding="utf-8") as file:
        existing = file.read()

    if "hs.ipc" in existing:
        return

    with open(config_path, "a", encoding="utf-8") as file:
        if not existing.endswith("\n"):
            file.write("\n")
        file.write("\n-- Added by BADDAD print automation\n")
        file.write(f"{ipc_line}\n")


def start_hammerspoon_app() -> None:
    run_command(["open", "-a", "Hammerspoon"])
    time.sleep(2)
    # Reload config in case we just enabled hs.ipc in init.lua.
    run_command(["open", "hammerspoon://reload"])
    time.sleep(1)


def is_hs_port_error(result: subprocess.CompletedProcess) -> bool:
    details = f"{result.stderr or ''} {result.stdout or ''}".lower()
    return any(fragment in details for fragment in HS_PORT_ERROR_FRAGMENTS)


def run_hammerspoon_file(hs_binary: str, lua_script_path: str, env_vars: Dict[str, str]) -> subprocess.CompletedProcess:
    command = [hs_binary, "-c", f'dofile([[{lua_script_path}]])']
    env = os.environ.copy()
    env.update(env_vars)

    result = run_command(command, env=env)
    if result.returncode == 0:
        return result

    if is_hs_port_error(result):
        ensure_hammerspoon_ipc_module()
        start_hammerspoon_app()
        retry_result = run_command(command, env=env)
        return retry_result

    return result


def hammerspoon_keystroke(hs_binary: str, lua_script_path: str, app_names: List[str], key: str, modifiers: List[str]) -> Tuple[bool, str]:
    env_vars = {
        "BADDAD_APP_NAMES": json.dumps(app_names),
        "BADDAD_KEY": key,
        "BADDAD_MODIFIERS": json.dumps(modifiers),
    }

    result = run_hammerspoon_file(hs_binary=hs_binary, lua_script_path=lua_script_path, env_vars=env_vars)
    if result.returncode != 0:
        details = (result.stderr or result.stdout or "").strip()
        return False, details or "Unknown Hammerspoon automation failure."

    output = (result.stdout or "").strip()
    if output.startswith("OK:"):
        return True, output

    return False, output or "Hammerspoon command did not confirm success."


def automated_print(arxp_file: str) -> int:
    if not arxp_file:
        print("ERROR: No file path provided.")
        return 1

    if not os.path.exists(arxp_file):
        print(f"ERROR: File does not exist: {arxp_file}")
        return 2

    hs_binary = resolve_hs_binary()
    if hs_binary is None:
        print(
            "ERROR: Hammerspoon CLI (hs) is not installed or not on PATH. "
            "Install Hammerspoon and enable Accessibility permissions, then retry."
        )
        return 3

    lua_script_path = resolve_lua_script_path()
    if not os.path.exists(lua_script_path):
        print(f"ERROR: Missing Hammerspoon Lua script at: {lua_script_path}")
        return 4

    try:
        ensure_hammerspoon_ipc_module()
        start_hammerspoon_app()

        open_result = run_command(["open", arxp_file])
        if open_result.returncode != 0:
            open_error = (open_result.stderr or open_result.stdout).strip()
            print(f"ERROR: Failed to open ARXP file: {open_error or 'Unknown open(1) failure.'}")
            return 5

        time.sleep(4)

        shortcut_ok, shortcut_details = hammerspoon_keystroke(
            hs_binary=hs_binary,
            lua_script_path=lua_script_path,
            app_names=GTX_APP_CANDIDATES,
            key="s",
            modifiers=["cmd"],
        )
        if not shortcut_ok:
            print(
                "ERROR: Failed to send Command+S via Hammerspoon. "
                "Ensure ~/.hammerspoon/init.lua includes require(\"hs.ipc\"). "
                f"Details: {shortcut_details}"
            )
            return 6

        time.sleep(5)

        escape_ok, escape_details = hammerspoon_keystroke(
            hs_binary=hs_binary,
            lua_script_path=lua_script_path,
            app_names=GTX_APP_CANDIDATES,
            key="escape",
            modifiers=[],
        )
        if not escape_ok:
            print(f"WARN: Escape keystroke failed via Hammerspoon: {escape_details}")

        return 0

    except Exception as exc:
        print(f"ERROR: Unexpected failure: {exc}")
        return 7


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 automated_print.py /full/path/to/file.arxp")
        sys.exit(1)

    target_file = sys.argv[1]
    sys.exit(automated_print(target_file))
