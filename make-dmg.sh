#!/usr/bin/env bash
#
# 造一张「拖进应用程序」的安装盘。
#
#   ./make-dmg.sh build/OpenImg.app build/OpenImg-v0.3.2.dmg 0.3.2
#
# 为什么要 DMG 而不是只发 zip:zip 解压出来的 app 多半留在「下载」里,用户往往
# 就地双击运行——那会触发 App Translocation(系统把它挂到只读随机路径上跑),
# 而 app 连自己在哪都不知道,**自我更新永久失效**。DMG 那个拖动动作是 macOS
# 认可的路径:经 Finder 拖动会清掉隔离标记,translocation 不会发生。
#
# 不用 create-dmg 之类的第三方工具:这条链上全是系统自带的 hdiutil / osascript,
# 引一个依赖只为省下面这几十行,而它一旦停止维护,发布就卡住了。
set -euo pipefail

APP=${1:?用法: ./make-dmg.sh <app> <输出.dmg> <版本号>}
OUT=${2:?}
VERSION=${3:?}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BG="$ROOT/Resources/dmg/background.png"
VOL="OpenImg $VERSION"

[ -d "$APP" ] || { echo "找不到 app: $APP" >&2; exit 1; }
[ -f "$BG" ]  || { echo "找不到背景图: $BG" >&2; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"; hdiutil detach "/Volumes/$VOL" -quiet 2>/dev/null || true' EXIT

# 盘里就三样:app、「应用程序」的替身、以及藏起来的背景图。
mkdir -p "$STAGE/.background"
cp "$BG" "$STAGE/.background/background.png"
ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT" "$OUT.tmp.dmg"

# 先造可写盘,摆好图标再压成只读。直接造只读盘的话没法写 .DS_Store,
# 用户打开看到的是默认列表视图,那张背景图和箭头一个都看不见。
#
# 尺寸留 60 MB 余量:hdiutil 需要一点额外空间放文件系统元数据,按内容精确算
# 会在边界上偶发 "No space left on device",而那种失败只在某些包大小上出现。
SIZE=$(( $(du -sm "$STAGE" | cut -f1) + 60 ))
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ \
  -format UDRW -size "${SIZE}m" "$OUT.tmp.dmg" >/dev/null

MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$OUT.tmp.dmg" \
        | grep -o '/Volumes/.*' | head -1)
sleep 1

# 用 Finder 摆位置。这段写的是 .DS_Store —— 图标坐标、窗口大小、背景图,
# 全靠它。坐标要和背景图里箭头的两端对上(图标 165 / 替身 495,y=196)。
osascript <<APPLESCRIPT >/dev/null 2>&1 || echo "  !! 摆放图标失败,盘仍可用但会是默认视图" >&2
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set background picture of opts to file ".background:background.png"
    set position of item "$(basename "$APP")" of container window to {165, 196}
    set position of item "Applications" of container window to {495, 196}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT" -quiet
# UDZO 压缩成只读盘。用户拿到的是这一份。
hdiutil convert "$OUT.tmp.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f "$OUT.tmp.dmg"
echo "已造盘：$OUT ($(du -h "$OUT" | cut -f1))"
