#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build dist
swiftc -swift-version 5 SortFlow/Models.swift SortFlow/FileService.swift SortFlow/ScanService.swift Tests/CoreTests.swift -lsqlite3 -o build/core-tests
build/core-tests | tee build/core-tests.log
xcodebuild -project SortFlow.xcodeproj -scheme SortFlow -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build/Derived CODE_SIGNING_ALLOWED=NO ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET=14.0 build > build/xcodebuild.log 2>&1 || { tail -200 build/xcodebuild.log; exit 1; }
APP='build/Derived/Build/Products/Release/SortFlow.app'
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
lipo -info "$APP/Contents/MacOS/SortFlow" | tee build/architectures.log
mkdir -p build/fixture
printf 'SortFlow 2.0 — test uruchomienia aplikacji.\n' > build/fixture/Przyklad.txt
"$APP/Contents/MacOS/SortFlow" --smoke-test --fixture "$PWD/build/fixture" > build/launch.log 2>&1 &
APP_PID=$!
sleep 3
kill -0 "$APP_PID"
screencapture -x build/screenshot.png || true
wait "$APP_PID"
mkdir -p build/DMG
cp -R "$APP" build/DMG/
ln -s /Applications build/DMG/Applications
cp docs/INSTALACJA.txt build/DMG/
hdiutil create -volname 'SortFlow 2.0' -srcfolder build/DMG -ov -format UDZO dist/SortFlow-2.0.dmg
hdiutil verify dist/SortFlow-2.0.dmg
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/SortFlow-2.0.zip
cp docs/INSTALACJA.txt dist/
(cd dist && shasum -a 256 SortFlow-2.0.dmg SortFlow-2.0.zip > SHA256SUMS.txt)
