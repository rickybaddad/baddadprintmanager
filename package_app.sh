#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="BADDADApp"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/$APP_NAME.app"

BIN_PATH="$BUILD_DIR/$APP_NAME"

if [ ! -f "$BIN_PATH" ]; then
  echo "Release binary not found. Run ./build_app.sh first."
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy python helper
cp "$ROOT_DIR/automated_print.py" "$APP_DIR/Contents/Resources/"

# Copy binary as internal executable
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME-bin"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME-bin"

# Create wrapper executable to fix working directory
cat << 'EOF' > "$APP_DIR/Contents/MacOS/$APP_NAME"
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR/../Resources"
"$DIR/$APP_NAME-bin"
EOF
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

# Create Info.plist
cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>BADDADApp</string>
  <key>CFBundleIdentifier</key>
  <string>com.baddad.app</string>
  <key>CFBundleExecutable</key>
  <string>BADDADApp</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>baddadqueue</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>baddadqueue</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
EOF

echo "Packaging complete: $APP_DIR"
