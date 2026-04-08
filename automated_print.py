import subprocess
import time
import sys
import os

GTX_APP_CANDIDATES = [
    "Brother GTX File Viewer",
    "Brother GTX Graphics Lab"
]

def run_osascript(script: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["osascript", "-e", script],
        capture_output=True,
        text=True,
    )


def can_send_system_keystrokes() -> tuple[bool, str]:
    """
    Check whether System Events keyboard automation is currently allowed.
    Returns (allowed, details).
    """
    probe = '''
    tell application "System Events"
        key code 63
    end tell
    '''
    result = run_osascript(probe)
    if result.returncode == 0:
        return True, ""
    return False, (result.stderr or result.stdout).strip()


def automated_print(arxp_file: str) -> int:
    """
    Open an ARXP file in the associated app, wait for load,
    then trigger Command+S on the active window and send Escape.
    Returns 0 on success, non-zero on failure.
    """

    if not arxp_file:
        print("ERROR: No file path provided.")
        return 1

    if not os.path.exists(arxp_file):
        print(f"ERROR: File does not exist: {arxp_file}")
        return 2

    try:
        # Open the file in the default associated app (GTX File Viewer)
        open_result = subprocess.run(
            ["open", arxp_file],
            capture_output=True,
            text=True,
        )
        if open_result.returncode != 0:
            open_error = (open_result.stderr or open_result.stdout).strip()
            print(f"ERROR: Failed to open ARXP file: {open_error or 'Unknown open(1) failure.'}")
            return 3

        # Wait for the viewer window to load and become active
        time.sleep(4)

        # First try direct app scripting (no keystrokes required).
        # This is more reliable on systems where System Events keystrokes are blocked.
        direct_errors: list[str] = []
        direct_success = False
        for app_name in GTX_APP_CANDIDATES:
            for command in (
                f'''tell application "{app_name}" to activate''',
                f'''tell application "{app_name}" to save front document''',
                f'''tell application "{app_name}" to print front document''',
                f'''tell application "{app_name}" to save document 1''',
                f'''tell application "{app_name}" to print document 1''',
            ):
                result = run_osascript(command)
                if result.returncode == 0 and ("activate" not in command):
                    direct_success = True
                    break
                if result.returncode != 0:
                    err = (result.stderr or result.stdout).strip()
                    if err:
                        direct_errors.append(f"{app_name}: {err}")
            if direct_success:
                break

        if direct_success:
            time.sleep(5)
            return 0

        # Fall back to active-window Command+S automation.
        send_shortcut = '''
        tell application "System Events"
            keystroke "s" using {command down}
        end tell
        '''
        shortcut_result = run_osascript(send_shortcut)
        if shortcut_result.returncode != 0:
            shortcut_error = (shortcut_result.stderr or shortcut_result.stdout).strip()
            lowered = shortcut_error.lower()
            if "not allowed to send keystrokes" in lowered:
                print(
                    "ERROR: macOS blocked keyboard automation. Enable Accessibility permission for the app "
                    "running this script (Terminal or BADDAD Print Manager) in System Settings → "
                    "Privacy & Security → Accessibility, then retry."
                )
            combined_direct = " | ".join(direct_errors)
            print(
                f"ERROR: Failed to send print command: {shortcut_error or 'Unknown keystroke failure.'} "
                f"| Direct app scripting errors: {combined_direct or 'none'}"
            )
            return 3

        # Wait 5 seconds after print command
        time.sleep(5)

        # Send Escape
        send_escape = '''
        tell application "System Events"
            key code 53
        end tell
        '''
        escape_result = run_osascript(send_escape)
        if escape_result.returncode != 0:
            # Escape is best-effort cleanup only.
            print(f"WARN: Escape keystroke failed: {(escape_result.stderr or escape_result.stdout).strip()}")

        return 0

    except Exception as e:
        print(f"ERROR: Unexpected failure: {e}")
        return 4


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 automated_print.py /full/path/to/file.arxp")
        sys.exit(1)

    target_file = sys.argv[1]
    sys.exit(automated_print(target_file))
