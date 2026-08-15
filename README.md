# Openimg for macOS

[openimg.io](https://openimg.io) 免费图床的 macOS 原生客户端。上传、图库、配额签到、
上传前编辑（裁剪 / 马赛克 / 旋转 / 水印）、监控目录自动上传、整库导出——
纯 Swift 6 + SwiftUI，**零第三方依赖**。

服务端与网页端在 [gentpan/openimg](https://github.com/gentpan/openimg)。
本仓库由主仓库的 `apple/` 目录拆出，保留了全部提交历史。

## 下载安装

从 [Releases](https://github.com/gentpan/openimg-app/releases) 下载
`OpenimgMac.zip`，解压后把 `OpenimgMac.app` 拖进「应用程序」。

当前版本为 ad-hoc 签名（尚未公证），首次打开会被 Gatekeeper 拦截：
**右键点击 App → 打开 → 再点「打开」**，只需一次。或者在终端执行：

```bash
xattr -d com.apple.quarantine /Applications/OpenimgMac.app
```

需要 macOS 14 及以上（Apple silicon 与 Intel 均可，Release 产物按打包机架构）。

首次运行用邮箱和密码登录。密码只用来换取一枚这台设备专用的长期令牌，不会被
保存；令牌进钥匙串，之后每次打开自动登录。也可以改用访问令牌登录（网站
「账号设置 → API Token」生成）。

## 功能

- **上传**：拖放 / 选择 / ⌘U，批量队列带整体进度，成功即复制链接（URL / Markdown / HTML / BBCode）
- **上传前编辑**：裁剪（比例预设）、马赛克（像素化 / 纯色，刻意不提供可被复原的高斯模糊）、旋转、文字水印
- **监控目录**：挂上文件夹后新图自动上传；本地清单防秒传重复扣配额，配额 / 每日上限自动暂停，每日上限次日自动恢复
- **图库**：分页网格、搜索、多选批量删除、全窗灯箱；**导出全部**到本地目录（已存在跳过，可中断续传）
- **概览**：配额、存储构成、格式分布、签到日历（Swift Charts）
- **设置**：昵称头像、改密码、Passkey、转换偏好、水印样式

## 从源码构建

```
OpenimgKit/
  Sources/OpenimgKit/     网络层、模型、钥匙串、编辑渲染   ← 为 iOS 复用设计，零依赖
  Sources/OpenimgMac/     macOS 应用（SwiftUI）
  Sources/KitCheck/       95 项自检（可执行目标）
```

```bash
cd OpenimgKit && swift run KitCheck     # 自检
./package-mac.sh release                # 打包 .app
open build/OpenimgMac.app
```

**不要用 `swift run OpenimgMac`。** 裸可执行文件没有 bundle，SwiftUI 找不到需要
保活的 scene，进程 exit 0 就没了——不崩溃、不打日志，看上去像什么都没发生。

构建需要装有 Xcode（SwiftUI 的属性包装宏只随 Xcode 工具链分发；脚本会自动定位
`/Applications/Xcode.app` 或 `Xcode-beta.app`）。打包和 ad-hoc 签名本身不需要
Xcode 工程——.app 只是一个目录加 Info.plist。

## 发布流程（维护者）

推送 `v*` 标签会触发 CI 构建并创建带产物的 GitHub Release：

```bash
git tag v0.2.0 && git push origin v0.2.0
```

**签名发布（推荐，产物下载即用）**——一条命令完成 打包 → 公证 → 装订 → Release：

```bash
./release.sh v0.2.0
```

一次性前置（见 `release.sh` 头部注释）：装 Developer ID Application 证书
（Xcode → Settings → Accounts → Manage Certificates）+ 用
`xcrun notarytool store-credentials openimg-notary` 存一次公证凭据
（App 专用密码在 appleid.apple.com 生成）。

没配证书时 CI 的 tag 发布产出 ad-hoc 构建（用户需右键打开一次）；同名
release 已由 release.sh 发过时 CI 自动让位。免费 Personal Team 签出来的
7 天过期且只能本机跑，不能用于分发。

## 几个刻意的选择

**自检是可执行目标，不是 test target。** XCTest 与 swift-testing 都要求完整
Xcode 才能解析——只装 Command Line Tools 时 `swift test` 根本编译不了。
`swift run KitCheck` 在任何有 Swift 的地方都能跑，95 项覆盖几何、清单、
渲染管线的像素级位置断言。

**Kit 收服务器地址，App 不收。** `OpenimgClient` 拿 URL 做参数——它是个库，
写死主机就没法测。但应用本身只面向 Openimg 一家，界面上不出现地址输入框。
`OpenimgClient.init` 拒绝非回环地址的明文 http：令牌逐请求随 header 发送，
一个打错的域名就会把它交给应答的人。

**multipart 组装在磁盘上而不是内存里。** 后台 `URLSession` 只接受
`uploadTask(with:fromFile:)`，内存里的 body 会随进程退出一起消失。

**视图里没有 `@State`（Kit 层）。** 现行 SwiftUI 的 `@State` 是宏，宏插件需要
完整 Xcode；状态集中在单个 `@MainActor` AppModel 里。

**编辑器只做服务端做不了的内容决策。** 压缩与转格式归服务端——本地转码会破坏
SHA 秒传、叠加两代有损。裁剪、马赛克、水印是内容决策，必须发生在上传之前
（尤其马赛克：传上去就在 CDN 带着一年 immutable 缓存了）。

## 与后端的契约

令牌可达的接口（主仓库 `backend/internal/api/router.go` 的 `machine` 组）：

```
POST   /api/upload             multipart，字段名固定 file，单文件
GET    /api/images             limit/offset/q/sort，返回 total
GET    /api/images/:id
DELETE /api/images/:id
POST   /api/images/bulk-delete
POST   /api/images/:id/variant
GET    /auth/me                当前令牌属于谁
GET    /api/quota              档位限制，用于上传前本地拦截
POST   /auth/native/exchange   OAuth 回调的一次性 code 换长期令牌
```

账号管理路由（改密码、删账号、签发令牌）只认 cookie——泄露的令牌不该能删号
或再签发令牌。`imageOut` 内嵌整个 `models.Image`，后端字段变更需要同步
`Sources/OpenimgKit/Models.swift`（两仓库拆分后靠这份清单对齐）。

## 下一步

- **Developer ID 签名 + 公证**：去掉右键打开的门槛（需付费开发者账号）
- **iOS 端**：Kit 已按两端共用设计（`.iOS(.v17)` 已声明）。阻塞在一个产品决策：
  App Store 5.1.1(v) 要求 App 内可删账号，而删号是 cookie-only——要么 iOS 做
  cookie 登录，要么不提供登录入口（又会撞 4.2 最低功能性）
- Sparkle 自动更新（引第三方依赖，与零依赖纪律的取舍待定）

## License

[MIT](LICENSE)
