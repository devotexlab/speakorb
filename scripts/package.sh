#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.1.0"
APP_NAME="Speakorb"
APP_DIR="dist/${APP_NAME}.app"
ICONSET="dist/Speakorb.iconset"

echo "==> build (release)"
swift build -c release

echo "==> icon"
rm -rf "${ICONSET}" dist/AppIcon.icns dist/icon_2048.png
swift scripts/make_icon.swift dist/icon_2048.png >/dev/null
mkdir -p "${ICONSET}"
gen() { sips -z "$1" "$1" dist/icon_2048.png --out "${ICONSET}/$2" >/dev/null; }
gen 16 icon_16x16.png
gen 32 icon_16x16@2x.png
gen 32 icon_32x32.png
gen 64 icon_32x32@2x.png
gen 128 icon_128x128.png
gen 256 icon_128x128@2x.png
gen 256 icon_256x256.png
gen 512 icon_256x256@2x.png
gen 512 icon_512x512.png
gen 1024 icon_512x512@2x.png
iconutil -c icns "${ICONSET}" -o dist/AppIcon.icns

echo "==> app bundle"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp ".build/release/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp dist/AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"

cat > "${APP_DIR}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Speakorb</string>
  <key>CFBundleIdentifier</key><string>app.speakorb.mac</string>
  <key>CFBundleName</key><string>Speakorb</string>
  <key>CFBundleDisplayName</key><string>Speakorb</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
  <key>NSMicrophoneUsageDescription</key><string>Speakorb needs the microphone to hear what you say.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Speakorb uses macOS dictation to turn your speech into text.</string>
</dict>
</plist>
PLIST

# 中文系统里 App 叫「声球」，英文系统里叫 Speakorb。
mkdir -p "${APP_DIR}/Contents/Resources/zh-Hans.lproj" "${APP_DIR}/Contents/Resources/en.lproj"
cat > "${APP_DIR}/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" <<'STRINGS'
CFBundleDisplayName = "声球";
CFBundleName = "声球";
NSMicrophoneUsageDescription = "声球需要麦克风来听你说话。";
NSSpeechRecognitionUsageDescription = "声球使用系统听写把你的话变成文字。";
STRINGS
cat > "${APP_DIR}/Contents/Resources/en.lproj/InfoPlist.strings" <<'STRINGS'
CFBundleDisplayName = "Speakorb";
CFBundleName = "Speakorb";
STRINGS

codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || true
xattr -cr "${APP_DIR}" 2>/dev/null || true

echo "==> dmg"
rm -rf dist/dmg
mkdir -p dist/dmg
cp -R "${APP_DIR}" dist/dmg/
ln -s /Applications dist/dmg/Applications
cp docs/first-run.txt "dist/dmg/安装说明.txt"
cp scripts/install.command "dist/dmg/安装.command"
chmod 755 "dist/dmg/安装.command"
chmod 644 "dist/dmg/安装说明.txt"
chmod -R a+rX "dist/dmg/Speakorb.app"
rm -f "dist/${APP_NAME}-${VERSION}.dmg"
hdiutil create -quiet -volname "${APP_NAME} ${VERSION}" -srcfolder dist/dmg -ov -format UDZO "dist/${APP_NAME}-${VERSION}.dmg"

echo "==> pkg"
rm -rf dist/pkg-root
mkdir -p dist/pkg-root
ditto --norsrc --noextattr "${APP_DIR}" "dist/pkg-root/Speakorb.app"
chmod -R a+rX dist/pkg-root/Speakorb.app
rm -f "dist/${APP_NAME}-${VERSION}.pkg"
pkgbuild --quiet --root dist/pkg-root --identifier app.speakorb.mac --version "${VERSION}" --install-location /Applications "dist/${APP_NAME}-${VERSION}.pkg"

echo "==> zip"
rm -f "dist/${APP_NAME}-${VERSION}.zip"
(cd dist && ditto -c -k --sequesterRsrc --keepParent "${APP_NAME}.app" "${APP_NAME}-${VERSION}.zip")

echo "==> checksums"
(cd dist && shasum -a 256 "Speakorb-${VERSION}.dmg" "Speakorb-${VERSION}.pkg" "Speakorb-${VERSION}.zip" > SHA256SUMS.txt)

echo
echo "完成："
ls -lh dist/*.dmg dist/*.pkg dist/*.zip | awk '{print "  " $9 "  " $5}'
