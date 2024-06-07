#!/usr/bin/env bash

set -euo pipefail

error_exit() {
  echo "Error: $1"
  exit 1
}

cd /Users/simon/XCode/MiddleMouseFocus || error_exit "Failed to change directory to /Users/simon/XCode/MiddleMouseFocus"

make clean && make || error_exit "Build failed"

rm -rf MiddleMouseFocus-Installer.dmg

create-dmg \
  --volname "MiddleMouseFocus Installer" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "MiddleMouseFocus.app" 200 190 \
  --hide-extension "MiddleMouseFocus.app" \
  --app-drop-link 600 185 \
  "MiddleMouseFocus-Installer.dmg" \
  "MiddleMouseFocus.app" || error_exit "Creating MiddleMouseFocus-Installer.dmg failed"

echo "Process completed successfully."