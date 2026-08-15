#!/usr/bin/env bash
#
# 签名发布:打包(Developer ID + hardened runtime)→ 公证 → 装订 → GitHub Release。
# 产物「下载即用」,没有右键打开的门槛。
#
#   ./release.sh v0.2.0
#
# 一次性前置(只需做一遍):
#   1. 装 Developer ID Application 证书:Xcode → Settings → Accounts → 选账号
#      → Manage Certificates… → + → Developer ID Application
#   2. 存公证凭据(app 专用密码在 appleid.apple.com → 登录与安全 → App 专用密码):
#      xcrun notarytool store-credentials openimg-notary \
#        --apple-id 你的AppleID邮箱 --team-id 你的TEAMID --password xxxx-xxxx-xxxx-xxxx
set -euo pipefail

VERSION=${1:?用法: ./release.sh v0.2.0}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# 自动选中钥匙串里的 Developer ID Application 身份
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
[[ -n "$IDENTITY" ]] || { echo "钥匙串里没有 Developer ID Application 证书 —— 见脚本头部前置第 1 步" >&2; exit 1; }
xcrun notarytool history --keychain-profile openimg-notary >/dev/null 2>&1 \
  || { echo "公证凭据 openimg-notary 未配置 —— 见脚本头部前置第 2 步" >&2; exit 1; }

echo "1/5 打包(签名:$IDENTITY)…"
SIGN_IDENTITY="$IDENTITY" ./package-mac.sh release >/dev/null
APP="$ROOT/build/OpenimgMac.app"

echo "2/5 压缩并提交公证…"
ZIP="$ROOT/build/OpenimgMac-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile openimg-notary --wait \
  | tee /tmp/openimg-notary.log
grep -q "status: Accepted" /tmp/openimg-notary.log \
  || { echo "公证未通过 —— xcrun notarytool log <id> --keychain-profile openimg-notary 看详情" >&2; exit 1; }

echo "3/5 装订公证票据…"
xcrun stapler staple "$APP"
# 重新压缩已装订的 .app —— 用户离线首启也能过 Gatekeeper
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "4/5 验证…"
spctl -a -vv "$APP" 2>&1 | sed 's/^/  /'

echo "5/5 创建 GitHub Release…"
gh release create "$VERSION" "$ZIP" \
  --title "$VERSION" \
  --notes "Developer ID 签名并已公证 —— 下载解压,拖进「应用程序」直接打开。" \
  --latest
echo "完成:https://github.com/gentpan/openimg-app/releases/tag/$VERSION"
