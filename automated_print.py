import subprocess
import time
import sys
import os

def automated_print(arxp_file: str) -> int:
    """
    Open an ARXP file in Brother GTX File Viewer, wait for load,
    send Command+S, wait, then send Escape.
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
        subprocess.run(["open", arxp_file], check=True)

        # Wait for GTX viewer window to load
        time.sleep(4)

        # Bring GTX viewer to front
        activate_window = '''
        tell application "System Events"
            set frontmost of first process whose name contains "GTX" to true
        end tell
        '''
        subprocess.run(["osascript", "-e", activate_window], check=True)

        time.sleep(1)

        # Send Command+S
        send_shortcut = '''
        tell application "System Events"
            keystroke "s" using {command down}
        end tell
        '''
        subprocess.run(["osascript", "-e", send_shortcut], check=True)

        # Wait 5 seconds after print command
        time.sleep(5)

        # Send Escape
        send_escape = '''
        tell application "System Events"
            key code 53
        end tell
        '''
        subprocess.run(["osascript", "-e", send_escape], check=True)

        return 0

    except subprocess.CalledProcessError as e:
        print(f"ERROR: Command failed: {e}")
        return 3
    except Exception as e:
        print(f"ERROR: Unexpected failure: {e}")
        return 4


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 automated_print.py /full/path/to/file.arxp")
        sys.exit(1)

    target_file = sys.argv[1]
    sys.exit(automated_print(target_file))