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

echo "Copying Hammerspoon Lua helper..."
cp print_automation.lua BADDADApp.app/Contents/Resources/print_automation.lua

echo "Copying app icon..."
if [ -f "AppIcon.icns" ]; then
  cp AppIcon.icns BADDADApp.app/Contents/Resources/AppIcon.icns
  echo "Copied AppIcon.icns"
else
  echo "AppIcon.icns not found in repo root"
fi

echo "Copying in-app logo..."
if [ -f "Sources/BADDADApp/Resources/productionmanagerlogo.png" ]; then
  cp "Sources/BADDADApp/Resources/productionmanagerlogo.png" BADDADApp.app/Contents/Resources/
  echo "Copied productionmanagerlogo.png"
else
  echo "productionmanagerlogo.png not found"
fi

echo "Final Resources contents:"
ls -l BADDADApp.app/Contents/Resources

echo "Done: BADDADApp.app created"