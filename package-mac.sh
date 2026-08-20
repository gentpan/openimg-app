#!/usr/bin/env bash
#
# Wraps the OpenimgMac build product in a real OpenImg.app bundle.
# (SwiftPM 目标名保留 OpenimgMac 以区分未来的 iOS 端;用户可见的名字一律 OpenImg。)
#
# A bare SwiftPM executable does not work for this app, and the failure is
# quiet: MenuBarExtra has nowhere to install a status item without a bundle, so
# the process starts, finds no scene to keep alive, and exits 0. No crash, no
# log, no icon — it just looks like nothing happened.
#
# None of this needs Xcode. A .app is a directory with an Info.plist, and
# codesign ships with the Command Line Tools. Xcode only enters the picture for
# a Developer ID identity and notarization, i.e. giving the app to someone else.
#
#   ./apple/package-mac.sh              debug 构建
#   ./apple/package-mac.sh release      release 构建
set -euo pipefail

# SwiftUI's property wrappers are macros now, and their plugin ships only with
# Xcode — the Command Line Tools toolchain cannot expand @State at all. So the
# build has to run against Xcode's toolchain even when xcode-select points at
# the CLT, which is the default on a machine that had them first.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app; do
        if [[ -d "$candidate/Contents/Developer/Toolchains" ]]; then
            export DEVELOPER_DIR="$candidate/Contents/Developer"
            break
        fi
    done
fi
[[ -n "${DEVELOPER_DIR:-}" ]] || { echo "找不到 Xcode —— SwiftUI 宏无法展开" >&2; exit 1; }

CONFIG=${1:-debug}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$ROOT/OpenimgKit"
APP="$ROOT/build/OpenImg.app"

echo "构建 ($CONFIG)…"
xcrun swift build --package-path "$PKG" -c "$CONFIG" --product OpenimgMac >/dev/null
BIN="$(xcrun swift build --package-path "$PKG" -c "$CONFIG" --show-bin-path)/OpenimgMac"
[[ -x "$BIN" ]] || { echo "找不到产物：$BIN" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OpenImg"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# 紫色主题那张。Info.plist 只认 AppIcon(绿),紫的是运行时用
# NSApp.applicationIconImage 换上去的,所以它只需要在 Resources 里能被找到。
cp "$ROOT/Resources/AppIcon-Violet.icns" "$APP/Contents/Resources/AppIcon-Violet.icns"
# Ubuntu, registered at launch by BrandFont. Flat in Resources because
# Bundle.main.url(forResource:) does not search subdirectories.
cp "$ROOT"/Resources/Fonts/*.ttf "$APP/Contents/Resources/"
cp "$ROOT/Resources/Fonts/LICENSE-Ubuntu.txt" "$APP/Contents/Resources/"

# No LSUIElement: this is a windowed app, so it should take a Dock icon and its
# own menu bar like any other. The earlier menu-bar-only build set it, and
# leaving it in would give a main-window app no way to be brought back once its
# window is closed.
# 版本号先取好。heredoc 仍用带引号的形式——去掉引号会让 plist 正文里任何
# $ 都被当成变量展开,那是给以后埋雷;所以改成写完之后替换占位符。
#
# 默认版本号取自 git 上最新的 tag,而不是写死一个数。写死的那个(曾经是
# 0.2.0)会在发过 0.3.0 之后继续骗人:直接跑 ./package-mac.sh 出来的包,
# 「关于」里印的是一个几个月前的版本,而它跑的是当前代码。
APP_VERSION="${APP_VERSION:-$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.0.0)}"

# build 号由版本号算出来,算法的唯一权威在 OpenimgKit/UpdateVersion.swift,
# 由 KitCheck 钉住。不在这里用 awk 再写一遍同一个公式:两处各写各的迟早对
# 不上,而对不上的表现是「明明发了新版,老客户端检测不到」——不报错、不打
# 日志,只是永远没有更新。
#
# 原来这里恒为 1。CFBundleVersion 的单调性正是系统用来判断"哪个更新"的依
# 据,恒为 1 等于把那条依据整个作废了。
if [[ -z "${APP_BUILD:-}" ]]; then
  APP_BUILD=$(xcrun swift run --package-path "$PKG" -c "$CONFIG" UpdateTool \
                build-number "$APP_VERSION" 2>/dev/null | tail -1)
  [[ "$APP_BUILD" =~ ^[0-9]+$ ]] || {
    echo "算不出 build 号(版本号 $APP_VERSION)——见 SemanticVersion.buildNumber" >&2
    exit 1
  }
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>          <string>OpenImg</string>
  <key>CFBundleIdentifier</key>          <string>io.openimg.mac</string>
  <key>CFBundleName</key>                <string>OpenImg</string>
  <key>CFBundleDisplayName</key>         <string>OpenImg</string>
  <key>CFBundlePackageType</key>         <string>APPL</string>
  <key>CFBundleShortVersionString</key>  <string>@@APP_VERSION@@</string>
  <key>CFBundleVersion</key>             <string>@@APP_BUILD@@</string>
  <key>LSMinimumSystemVersion</key>      <string>14.0</string>
  <key>CFBundleIconFile</key>            <string>AppIcon</string>
  <!-- The OAuth callback lands here. Without this the system has nothing to
       hand openimg://auth?code=… to, and the sign-in sheet just sits there. -->
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>       <string>io.openimg.mac.auth</string>
      <key>CFBundleURLSchemes</key>    <array><string>openimg</string></array>
    </dict>
  </array>
  <key>NSHighResolutionCapable</key>     <true/>
</dict>
</plist>
PLIST
sed -i "" -e "s|@@APP_VERSION@@|$APP_VERSION|" -e "s|@@APP_BUILD@@|$APP_BUILD|" "$APP/Contents/Info.plist"

# Signing.
#
# Ad-hoc by default: it lets the app run on this machine and nothing more, but
# an unsigned bundle is refused outright on Apple silicon, so it is required
# even locally.
#
# Set SIGN_IDENTITY to a real certificate ("Developer ID Application: Name
# (TEAMID)") to get an application identifier, which is what the passkey and
# data-protection-keychain entitlements are checked against. Ad-hoc has no team
# id, so entitlements embedded into an ad-hoc build are ignored — the passkey
# API answers ASAuthorizationError 1004 and the keychain answers -34018.
#
#   SIGN_IDENTITY="Developer ID Application: 你的名字 (ABCDE12345)" ./package-mac.sh
#
# List what is available with: security find-identity -v -p codesigning
ENTITLEMENTS="$ROOT/Resources/OpenimgMac.entitlements"
if [ -n "${SIGN_IDENTITY:-}" ]; then
  # $(AppIdentifierPrefix) 是 Xcode 的构建变量,由 Xcode 在构建时替换成团队
  # 前缀。我们是手工 codesign,没有任何东西会去展开它——原样签进去就是一条
  # 字面量为 "$(AppIdentifierPrefix)io.openimg.mac" 的非法授权,而 hardened
  # runtime 下 launchd 会直接拒绝启动(报 "Launchd job spawn failed"),
  # spctl 却照样说 accepted。adhoc 签名不校验授权,所以这个坑只在正式签名的
  # 包上才炸,而那正是发给用户的那一份。
  #
  # 团队 ID 从身份字符串末尾的括号里取:"Developer ID Application: X (TEAMID)"。
  TEAM_ID=$(printf '%s' "$SIGN_IDENTITY" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')
  [ -n "$TEAM_ID" ] || { echo "从签名身份里取不到团队 ID: $SIGN_IDENTITY" >&2; exit 1; }
  # 受限授权(keychain-access-groups / associated-domains)必须由一份嵌在
  # bundle 里的描述文件授权。没有它,AMFI 会拒绝加载进程,表现是
  # "Launchd job spawn failed",而 spctl 照样说 accepted——它查的是签名与
  # 公证,不查授权有没有被授权。v0.2.0 就是这么发出去一个谁都打不开的包的。
  PROFILE="${PROVISION_PROFILE:-$ROOT/Resources/Openimg.provisionprofile}"
  if [ -f "$PROFILE" ]; then
    cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
    echo "  已嵌入描述文件：$(basename "$PROFILE")"
  else
    echo "  !! 没有描述文件,将不带授权签名 —— app 内的 Passkey 会失效" >&2
    echo "     (放到 Resources/Openimg.provisionprofile 或设 PROVISION_PROFILE=路径)" >&2
    ENTITLEMENTS=""
  fi
  RESOLVED_ENT="$(mktemp -t openimg-ent).plist"
  trap 'rm -f "$RESOLVED_ENT"' EXIT
  if [ -n "$ENTITLEMENTS" ]; then
    sed "s/\$(AppIdentifierPrefix)/$TEAM_ID./g" "$ENTITLEMENTS" > "$RESOLVED_ENT"
    codesign --force --options runtime --timestamp \
             --sign "$SIGN_IDENTITY" \
             --entitlements "$RESOLVED_ENT" \
             --identifier io.openimg.mac "$APP"
  else
    codesign --force --options runtime --timestamp \
             --sign "$SIGN_IDENTITY" \
             --identifier io.openimg.mac "$APP"
  fi
else
  # No --entitlements here on purpose: ad-hoc cannot honour them, and embedding
  # ones that silently do nothing makes the build look configured when it is not.
  codesign --force --sign - --identifier io.openimg.mac "$APP" 2>/dev/null
fi

echo "已打包：$APP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Signature|TeamIdentifier" | sed 's/^/  /'
echo
echo "运行：open '$APP'"
echo "退出：pkill -x OpenImg"
