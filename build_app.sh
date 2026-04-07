#!/bin/bash
set -e

echo "Cleaning old build..."
rm -rf .build
rm -rf BADDADApp.app

echo "Building release binary..."
swift build -c release

echo "Creating app bundle structure..."
mkdir -p BADDADApp.app/Contents/MacOS
mkdir -p BADDADApp.app/Contents/Resources

echo "Copying executable..."
cp .build/release/BADDADApp BADDADApp.app/Contents/MacOS/BADDADApp
chmod +x BADDADApp.app/Contents/MacOS/BADDADApp

echo "Copying Info.plist..."
cp Info.plist BADDADApp.app/Contents/Info.plist

echo "Copying Python helper..."
cp automated_print.py BADDADApp.app/Contents/Resources/automated_print.py

echo "Copying in-app logo if present..."
if [ -f "Sources/BADDADApp/Resources/productionmanagerlogo.png" ]; then
  cp "Sources/BADDADApp/Resources/productionmanagerlogo.png" BADDADApp.app/Contents/Resources/
fi

echo "Copying app icon if present..."
if [ -f "AppIcon.icns" ]; then
  cp AppIcon.icns BADDADApp.app/Contents/Resources/AppIcon.icns
fi

echo "Done: BADDADApp.app created"