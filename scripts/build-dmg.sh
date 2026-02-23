#!/usr/bin/env bash
set -euo pipefail
xcodebuild clean archive -scheme LockOut-macOS -archivePath build/LockOut.xcarchive
xcodebuild -exportArchive -archivePath build/LockOut.xcarchive -exportPath build/ -exportOptionsPlist scripts/export-options.plist
create-dmg --volname "LockOut" --window-size 540 380 --icon-size 128 --app-drop-link 380 185 dist/LockOut.dmg "build/LockOut.app"
