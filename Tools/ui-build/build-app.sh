#!/bin/zsh
#
# 不经过 Xcode 直接编译 SwiftUI 界面，产物是一个 .app。
#
# 用途：xcodebuild 解析本地包时要用 sandbox-exec，如果你的终端/会话不允许
#      嵌套沙盒，就会报 "Could not resolve package dependencies"。
#      这个脚本绕过 Xcode，用 SwiftPM 直接编译同一个 target 的源码。
#
# 用法：Tools/ui-build/build-app.sh [debug|release]
set -e
MODE=${1:-debug}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP_SRC="$ROOT/Multidimensional Analysis MacTag/Multidimensional Analysis MacTag"
WORK="/tmp/matstudio"
BIN_NAME="MA Studio"

rm -rf "$WORK"
mkdir -p "$WORK/Sources/MATStudio"
cp "$APP_SRC"/Studio/*.swift "$WORK/Sources/MATStudio/"
cp "$APP_SRC/Multidimensional_Analysis_MacTagApp.swift" "$WORK/Sources/MATStudio/"

cat > "$WORK/Package.swift" <<PKG
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MATStudio",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "$ROOT/Packages/MATCore")],
    targets: [
        .executableTarget(
            name: "MATStudio",
            dependencies: [.product(name: "MATCore", package: "MATCore")],
            path: "Sources/MATStudio"
        )
    ]
)
PKG

cd "$WORK"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Volumes/ML.Origin/Applications/Xcode.app/Contents/Developer}" \
  swift build --disable-sandbox -c "$MODE"

BIN="$WORK/.build/$MODE/MATStudio"
APP="$WORK/$BIN_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$BIN_NAME"
cp "$ROOT/Tools/icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MA Studio</string>
    <key>CFBundleDisplayName</key><string>MA Studio</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>utopia.Multidimensional-Analysis-MacTag</string>
    <key>CFBundleExecutable</key><string>MA Studio</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>__VERSION__</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# 版本号唯一来源：Xcode 工程的 MARKETING_VERSION
VER="$("$ROOT/Tools/ui-build/version.sh")"
# 用临时文件替换（这台机器的 sed 是 GNU 版，-i '' 语法不通用）
TMP_PLIST="$(mktemp)"
sed "s/__VERSION__/$VER/" "$APP/Contents/Info.plist" > "$TMP_PLIST"
mv "$TMP_PLIST" "$APP/Contents/Info.plist"

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
