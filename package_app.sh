#!/bin/bash
set -e

if [ ! -d "BADDADApp.app" ]; then
  echo "BADDADApp.app not found. Run ./build_app.sh first."
  exit 1
fi

echo "Registering app with Launch Services..."
touch BADDADApp.app

echo "Opening app once so macOS sees it..."
open BADDADApp.app

echo "Done."
echo "Now test with:"
echo 'open "baddadqueue://load?payload=%7B%22jobs%22%3A%5B%7B%22queue%22%3A%22black_front%22,%22path%22%3A%22/Users/yourname/Desktop/test.arxp%22,%22qty%22%3A1%7D%5D%7D"'
