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
#   2. 存公证凭据(app 专用密码在 appleid.apple.com → 登录与安全 → App 专用密码
#      生成;省略 --password 会弹安全提示符,密码不进 shell 历史):
#      xcrun notarytool store-credentials openimg-notary \
#        --apple-id 403010@qq.com --team-id WPDUNPG5N8
#      验证: xcrun notarytool history --keychain-profile openimg-notary
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
# 版本号从 tag 推出来,不在 plist 里再写一遍——两处各写各的迟早对不上,
# 而对不上的表现是「关于」里显示的版本和下载文件名不一致,没人会在发布
# 当天发现。
SIGN_IDENTITY="$IDENTITY" APP_VERSION="${VERSION#v}" ./package-mac.sh release >/dev/null
APP="$ROOT/build/Openimg.app"

echo "2/5 压缩并提交公证…"
ZIP="$ROOT/build/Openimg-$VERSION.zip"
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

# spctl 查的是签名与公证,不查授权有没有被描述文件授权。v0.2.0 就是这么发出
# 去一个 spctl 全绿、却谁都打不开的包的(受限授权缺描述文件 → AMFI 拒绝加载,
# 报 "Launchd job spawn failed")。所以这里真的起一次。
#
# 带隔离属性起,走的才是用户下载后的那条路径。
echo "  真实启动自检…"
LAUNCH_DIR=$(mktemp -d)
trap 'rm -rf "$LAUNCH_DIR"' EXIT
ditto "$APP" "$LAUNCH_DIR/Openimg.app"
xattr -r -w com.apple.quarantine "0083;00000000;Safari;" "$LAUNCH_DIR/Openimg.app"
# 先把旧实例清干净并等它真的走掉。紧接着 open 会与上一个实例的退出撞车,
# 表现是进程起不来——那是自检自己的假阴性,而一个不可靠的自检比没有更糟:
# 假阴性拦住正常发布,假阳性放过坏包。
pkill -x Openimg 2>/dev/null || true
for _ in $(seq 1 10); do pgrep -x Openimg >/dev/null || break; sleep 1; done
sleep 2

/usr/bin/open -n "$LAUNCH_DIR/Openimg.app" >"$LAUNCH_DIR/err.txt" 2>&1 || true

# 轮询而不是睡一个固定值:冷启动在慢机器上要几秒,写死的等待要么太短要么
# 白等。连续两次看到进程才算数,免得抓到一个正在退出的瞬间。
LAUNCH_OK=0
HITS=0
for _ in $(seq 1 20); do
  if pgrep -x Openimg >/dev/null; then
    HITS=$((HITS + 1))
    [ "$HITS" -ge 2 ] && { LAUNCH_OK=1; break; }
  else
    HITS=0
  fi
  sleep 1
done

if [ "$LAUNCH_OK" = "1" ]; then
  echo "  ✓ 能启动"
  pkill -x Openimg 2>/dev/null || true
else
  echo "  ✗ 启动失败,不发布:" >&2
  cat "$LAUNCH_DIR/err.txt" >&2
  exit 1
fi

echo "5/5 创建 GitHub Release…"
gh release create "$VERSION" "$ZIP" \
  --title "$VERSION" \
  --notes "Developer ID 签名并已公证 —— 下载解压,拖进「应用程序」直接打开。" \
  --latest
echo "完成:https://github.com/gentpan/openimg-app/releases/tag/$VERSION"
