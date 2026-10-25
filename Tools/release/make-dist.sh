#!/bin/zsh
#
# 一条命令出两个发布包（都放在仓库根目录）：
#   MA-Studio-<版本>-source.zip   纯源码 + LICENSE + README（不含文档/构建产物/第三方）
#   MA-Studio-<版本>.dmg          安装包（app + Applications 快捷方式）
#
# 版本号来自 Xcode 工程的 MARKETING_VERSION，不在这里重复维护。
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
VER="$("$ROOT/Tools/ui-build/version.sh")"
STAGE="/tmp/masrc/MA-Studio-$VER"
DMG_STAGE="/tmp/madmg-$VER"
APP="/tmp/matstudio/MA Studio.app"

echo "== 版本 $VER =="

# ---------- 1. 源码包 ----------
echo "== 暂存源码 =="
rm -rf /tmp/masrc "$DMG_STAGE"
mkdir -p "$STAGE"
rsync -a \
  --exclude 'Docs/' --exclude 'build/' --exclude '.workbuddy/' --exclude 'Vendor/' \
  --exclude 'multidimensionalanalysistagger-source code/' --exclude '.build/' \
  --exclude '*.xcuserstate' --exclude '.DS_Store' --exclude '*.profraw' --exclude '*.app/' \
  --exclude 'Tools/parity/build/' --exclude 'Tools/groundtruth/baseline/' \
  --exclude '*.dmg' --exclude '*.zip' \
  "$ROOT/" "$STAGE/"
find "$STAGE" -type d -name xcuserdata -exec rm -rf {} + 2>/dev/null || true
find "$STAGE" -name .DS_Store -delete 2>/dev/null || true

echo "== 打 zip =="
(cd /tmp/masrc && rm -f "MA-Studio-$VER-source.zip" && zip -r -X -q "MA-Studio-$VER-source.zip" "MA-Studio-$VER")
cp "/tmp/masrc/MA-Studio-$VER-source.zip" "$ROOT/"

# ---------- 2. 安装包 ----------
echo "== 编译 release =="
"$ROOT/Tools/ui-build/build-app.sh" release >/dev/null

echo "== 组装 DMG =="
mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
codesign --force --deep --sign - "$DMG_STAGE/MA Studio.app" >/dev/null 2>&1 || true

rm -f "$ROOT/MA-Studio-$VER.dmg"
hdiutil create -volname "MA Studio $VER" -srcfolder "$DMG_STAGE" -ov -format UDZO \
  -imagekey zlib-level=9 "$ROOT/MA-Studio-$VER.dmg" >/dev/null

echo "完成："
ls -lh "$ROOT/MA-Studio-$VER-source.zip" "$ROOT/MA-Studio-$VER.dmg"
