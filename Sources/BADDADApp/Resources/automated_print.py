import subprocess
import time
import sys
import os

GTX_APP_NAME = "Brother GTX File Viewer"

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
    Open an ARXP file in Brother GTX File Viewer, wait for load,
    attempt direct app print/save scripting, then send Escape.
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

        # Wait for GTX viewer window to load
        time.sleep(4)

        # Prefer direct app activation (does not rely on System Events).
        activate_window = f'''
        tell application "{GTX_APP_NAME}"
            activate
        end tell
        '''
        activation = run_osascript(activate_window)
        if activation.returncode != 0:
            activation_error = (activation.stderr or activation.stdout).strip()
            print(f"ERROR: Failed to activate {GTX_APP_NAME}: {activation_error}")
            if "not authorised to send apple events" in activation_error.lower():
                print(
                    "ERROR: macOS blocked Apple Events automation. In System Settings → Privacy & Security → Automation, "
                    "allow this app (Terminal or BADDAD Print Manager) to control Brother GTX File Viewer/System Events."
                )
            return 3

        time.sleep(1)

        # Try direct GTX scripting first so we can avoid System Events keystroke permission requirements.
        direct_commands = [
            f'''tell application "{GTX_APP_NAME}" to print front document''',
            f'''tell application "{GTX_APP_NAME}" to save front document''',
            f'''tell application "{GTX_APP_NAME}" to print document 1''',
            f'''tell application "{GTX_APP_NAME}" to save document 1'''
        ]

        direct_success = False
        direct_errors: list[str] = []
        for cmd in direct_commands:
            direct_result = run_osascript(cmd)
            if direct_result.returncode == 0:
                direct_success = True
                break
            else:
                direct_error = (direct_result.stderr or direct_result.stdout).strip()
                if direct_error:
                    direct_errors.append(direct_error)

        if not direct_success:
            keystrokes_allowed, keystroke_probe_error = can_send_system_keystrokes()
            if not keystrokes_allowed:
                lowered_probe = keystroke_probe_error.lower()
                if "not allowed to send keystrokes" in lowered_probe:
                    print(
                        "ERROR: macOS blocked keyboard automation. Enable Accessibility permission for the app "
                        "running this script (Terminal or BADDAD Print Manager) in System Settings → "
                        "Privacy & Security → Accessibility. If it was already enabled, remove/re-add the app "
                        "entry or run: tccutil reset Accessibility."
                    )
                detail = " | ".join(direct_errors)
                print(
                    f"ERROR: Failed to send print command because keyboard automation is unavailable. "
                    f"Direct scripting errors: {detail or 'none'} | Keystroke probe error: {keystroke_probe_error or 'none'}"
                )
                return 3

            # Fallback to the original known-good trigger: Command+S via System Events.
            send_shortcut = '''
            tell application "System Events"
                keystroke "s" using {command down}
            end tell
            '''
            shortcut_result = run_osascript(send_shortcut)
            if shortcut_result.returncode != 0:
                shortcut_error = (shortcut_result.stderr or shortcut_result.stdout).strip()
                combined_errors = " | ".join(direct_errors)
                lowered = f"{combined_errors} | {shortcut_error}".lower()
                if "not authorised to send apple events" in lowered:
                    print(
                        "ERROR: macOS blocked Apple Events automation. In System Settings → Privacy & Security → "
                        "Automation, allow this app (Terminal or BADDAD Print Manager) to control Brother GTX File Viewer/System Events."
                    )
                if "not allowed to send keystrokes" in lowered:
                    print(
                        "ERROR: macOS blocked keyboard automation. Enable Accessibility permission for the app "
                        "running this script (Terminal or BADDAD Print Manager) in System Settings → "
                        "Privacy & Security → Accessibility, then retry."
                    )
                detail = f"Direct scripting errors: {combined_errors or 'none'} | Shortcut error: {shortcut_error or 'none'}"
                print(f"ERROR: Failed to send print command: {detail}")
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
