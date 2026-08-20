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
APP="$ROOT/build/OpenImg.app"

echo "2/5 压缩并提交公证…"
ZIP="$ROOT/build/OpenImg-$VERSION.zip"
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
ditto "$APP" "$LAUNCH_DIR/OpenImg.app"
xattr -r -w com.apple.quarantine "0083;00000000;Safari;" "$LAUNCH_DIR/OpenImg.app"
# 先把旧实例清干净并等它真的走掉。紧接着 open 会与上一个实例的退出撞车,
# 表现是进程起不来——那是自检自己的假阴性,而一个不可靠的自检比没有更糟:
# 假阴性拦住正常发布,假阳性放过坏包。
pkill -x OpenImg 2>/dev/null || true
for _ in $(seq 1 10); do pgrep -x OpenImg >/dev/null || break; sleep 1; done
sleep 2

/usr/bin/open -n "$LAUNCH_DIR/OpenImg.app" >"$LAUNCH_DIR/err.txt" 2>&1 || true

# 轮询而不是睡一个固定值:冷启动在慢机器上要几秒,写死的等待要么太短要么
# 白等。连续两次看到进程才算数,免得抓到一个正在退出的瞬间。
LAUNCH_OK=0
HITS=0
for _ in $(seq 1 20); do
  if pgrep -x OpenImg >/dev/null; then
    HITS=$((HITS + 1))
    [ "$HITS" -ge 2 ] && { LAUNCH_OK=1; break; }
  else
    HITS=0
  fi
  sleep 1
done

if [ "$LAUNCH_OK" = "1" ]; then
  echo "  ✓ 能启动"
  pkill -x OpenImg 2>/dev/null || true
else
  echo "  ✗ 启动失败,不发布:" >&2
  cat "$LAUNCH_DIR/err.txt" >&2
  exit 1
fi

echo "5/5 创建 GitHub Release…"
# 有 release-notes/<版本>.md 就用它,没有才退回那句通用说明。
#
# 写死一句话的代价是:每次发版的说明都一样,而看到"有新版本"的人第一个问题
# 永远是"改了什么"。让说明和代码一起进版本库,发版时就不会临时去补。
NOTES="$ROOT/release-notes/$VERSION.md"
if [[ -f "$NOTES" ]]; then
  gh release create "$VERSION" "$ZIP" --title "$VERSION" --notes-file "$NOTES" --latest
else
  echo "  (没有 release-notes/$VERSION.md,用通用说明)"
  gh release create "$VERSION" "$ZIP" \
    --title "$VERSION" \
    --notes "Developer ID 签名并已公证 —— 下载解压,拖进「应用程序」直接打开。" \
    --latest
fi
echo "完成:https://github.com/gentpan/openimg-app/releases/tag/$VERSION"

# ---------------------------------------------------------------------------
# 6/6 更新清单
#
# 装了老版本的人靠这份清单才知道有新版。它必须在 GitHub Release 建好之后才生成
# ——清单里写着下载地址和 sha256,而那个地址要等 release 存在才有效。
#
# 私钥不在版本库里,在 ~/.openimg/。没有它就跳过这一步并明说:清单可以事后补签,
# 而一次发不出清单只是"老用户晚几天知道",不值得让整个发布失败。
# ---------------------------------------------------------------------------
KEY="${OPENIMG_UPDATE_KEY:-$HOME/.openimg/update-signing-k1.key}"
PUB="${OPENIMG_UPDATE_PUB:-$HOME/.openimg/update-signing-k1.pub}"
if [[ ! -f "$KEY" ]]; then
  echo
  echo "  ⚠️  没找到签名私钥($KEY),跳过更新清单。"
  echo "     老版本的用户不会收到这次更新的提示。补签:"
  echo "     ./release.sh --manifest-only $VERSION"
  exit 0
fi

echo
echo "6/6 生成更新清单…"
# release.sh 里也要定义 PKG:它只在 package-mac.sh 里有,而那是另一个进程。
# set -u 下漏了这行的表现是——GitHub Release 已经建好、清单却发不出去,崩在
# "unbound variable"。发布走到一半断掉,比一开始就失败难收拾得多。
PKG="$ROOT/OpenimgKit"
TOOL="$(xcrun swift build --package-path "$PKG" -c release --show-bin-path)/UpdateTool"
xcrun swift build --package-path "$PKG" -c release --product UpdateTool >/dev/null

MANIFEST="$ROOT/build/update.json"
"$TOOL" sign \
  --key "$KEY" --key-id k1 \
  --version "${VERSION#v}" \
  --zip "$ZIP" \
  --url "https://github.com/gentpan/openimg-app/releases/download/$VERSION/$(basename "$ZIP")" \
  --notes-url "https://github.com/gentpan/openimg-app/releases/tag/$VERSION" \
  --out "$MANIFEST"

# 用编进 app 的那把公钥回验一遍。签名工具自己已经验过一次,这里是拿**另一个
# 来源**的公钥再验——如果哪天公钥表和私钥对不上了,只有这一步能发现。
if [[ -f "$PUB" ]]; then
  "$TOOL" verify --pubkey "$(cat "$PUB")" --key-id k1 "$MANIFEST" \
    || { echo "清单验签失败,不上传" >&2; exit 1; }
fi

# 传到服务器。清单放自己的域名、包放 GitHub:单独拿下任何一边都拿不到代码执行。
UPLOAD_HOST="${OPENIMG_HOST:-root@88.198.27.78}"
UPLOAD_KEY="${OPENIMG_KEY:-$HOME/Desktop/gentpan.pem}"
UPLOAD_PATH="${OPENIMG_UPDATE_PATH:-/opt/openimg/config/update.json}"
if scp -i "$UPLOAD_KEY" -o BatchMode=yes "$MANIFEST" "$UPLOAD_HOST:$UPLOAD_PATH" >/dev/null 2>&1; then
  echo "  ✓ 清单已上传"
  # 拉回来验实际线上的响应。Content-Type 必须是 application/json ——
  # 落进 SPA 兜底的话会拿到 200 + text/html,而客户端只会静默地"永远没有更新"。
  FEED="https://openimg.io/api/app/mac/update.json"
  # 用 GET 而不是 HEAD。客户端发的就是 GET,而这一步的意义正是"走一遍客户端会
  # 走的路"。曾经写成 curl -sI,拿到的是 text/html —— 那不是清单坏了,是 HEAD
  # 走了另一条分支,而这种"探测方法本身有偏差"的假警报比没有检查更糟。
  CT=$(curl -s -o /dev/null -D - "$FEED" | tr -d '\r' | awk -F': ' 'tolower($1)=="content-type"{print $2}')
  case "$CT" in
    application/json*) echo "  ✓ 线上可取($CT)" ;;
    *) echo "  ✗ 线上返回的不是 JSON:${CT:-无} —— 客户端会拒收,去查那条路由" >&2 ;;
  esac
else
  echo "  ⚠️  清单上传失败,手动传:$MANIFEST → $UPLOAD_HOST:$UPLOAD_PATH" >&2
fi
echo
echo "把这段贴进 release notes(可选):"
echo "  $MANIFEST.pretty.json"
