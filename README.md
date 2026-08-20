# Openimg for macOS

[openimg.io](https://openimg.io) 免费图床的 macOS 原生客户端。上传、图库、AI 生成与修图、
上传前编辑、监控目录自动上传、整库导出 —— 纯 Swift 6 + SwiftUI，**零第三方依赖**。

![概览](docs/overview.png)

服务端与网页端在 [gentpan/openimg](https://github.com/gentpan/openimg)。
本仓库由主仓库的 `apple/` 目录拆出，保留了全部提交历史。

## 下载安装

从 [Releases](https://github.com/gentpan/openimg-app/releases) 下载 zip，解压后把
`Openimg.app` 拖进「应用程序」，**直接双击打开**。

产物经 Developer ID 签名并已通过 Apple 公证，不需要右键打开，也不用去系统设置里放行。

需要 macOS 14 或更新版本，Apple Silicon。

首次运行可以直接在 app 里注册，也可以用已有账号登录 —— 邮箱密码、Google、GitHub、
Passkey 都行。密码只用来换取一枚这台设备专用的长期令牌，不会被保存；令牌进钥匙串，
之后每次打开自动登录。

登录页可以填自建实例的地址，连自己部署的服务端。

## 功能

### 上传

- 拖放 / 选择 / ⌘U，批量队列带整体进度，成功即复制链接（URL / Markdown / HTML / BBCode）
- **上传前抹除定位与设备信息**（EXIF）。图床的链接是公开的，圈里的拍摄地点会跟着一起公开
- 自动转换 WebP / AVIF，可限制最长边
- **监控目录**：挂上文件夹后新图自动上传。本地清单防秒传重复扣配额，
  配额 / 每日上限自动暂停，次日自动恢复

### 图库

- 分页网格、搜索、多选批量删除、全窗灯箱
- 右键直接进编辑器
- **导出全部**到本地目录，已存在的跳过，可中断续传

### 编辑

裁剪（比例预设）、旋转、马赛克（像素化 / 纯色，**刻意不提供可被复原的高斯模糊**）、
文字与图片水印、本机智能修图。

水印在本机合成后再上传，原图模式下监控目录上传不加水印（那是该模式的承诺），
动图也不加（逐帧合成不支持）。

### AI

- **生成图片**：写一句描述出图，结果自动进图库，和手动上传的图完全一样
  （去重、外链、短链、备份都有）
- **修图**：从图库挑 1–4 张或直接拖本地文件，按提示词改图。内置去水印、去除路人杂物、
  换背景、修复老照片、黑白上色、人像精修等 11 个一键预设
- **AI 水印**：让模型生成一枚 logo，落地后本机抠背景
- 生成记录可以删除，删除时可选「只删记录」或「连图一起删」
- 关联 [pic.bi](https://pic.bi) 后可用 4K 清晰度

### 存储

用平台存储池，或绑自己的桶 —— R2 / S3 / B2 / DigitalOcean Spaces / 阿里云 OSS /
腾讯云 COS，以及任何 S3 兼容的自建服务。凭据加密存储，界面只回显掩码。

### 其他

- **概览**：配额、存储构成、格式分布、上传趋势、签到日历、空间流水（Swift Charts）
- **签到**：连续天数、周与月的里程碑奖励。「一天」按你的本地时区算
- **主题**：绿 `#90FF3A` / 紫 `#7624F4` 两套，与网站同步。切换主题时 Dock 图标跟着换
- **中英双语**，切换立即生效

## 从源码构建

```
OpenimgKit/
  Sources/OpenimgKit/     网络层、模型、钥匙串、编辑渲染   ← 为 iOS 复用设计，零依赖
  Sources/OpenimgMac/     macOS 应用（SwiftUI）
  Sources/KitCheck/       454 项自检（可执行目标）
```

```bash
cd OpenimgKit && swift run KitCheck     # 自检
./package-mac.sh release                # 打包 .app
open build/Openimg.app
```

**不要用 `swift run OpenimgMac`。** 裸可执行文件没有 bundle，SwiftUI 找不到需要
保活的 scene，进程 exit 0 就没了 —— 不崩溃、不打日志，看上去像什么都没发生。

构建需要装有 Xcode（SwiftUI 的属性包装宏只随 Xcode 工具链分发；脚本会自动定位
`/Applications/Xcode.app` 或 `Xcode-beta.app`）。打包和 ad-hoc 签名本身不需要
Xcode 工程 —— `.app` 只是一个目录加 `Info.plist`。

### 关于自检

纯逻辑一律下沉到 `OpenimgKit`，`KitCheck` 才盯得住 —— 布局求解、EXIF 剥离、
水印合成、格式清单、签到日界都在里面。写在 View 里的计算，454 项自检一项都碰不到。

## 发布流程（维护者）

```bash
./release.sh v0.3.0
```

打包（Developer ID + hardened runtime）→ 公证 → 装订 → 验证 → 建 GitHub Release。

发版说明放在 `release-notes/<版本>.md`，脚本会读它；没有对应文件时退回一句通用说明。

**验证这一步会真的启动一次 app**，而且带隔离属性启动 —— 走的是用户下载后的那条路径。
`spctl` 只查签名与公证，不查受限授权有没有被描述文件授权：v0.2.0 就是这么发出去过一个
`spctl` 全绿、却谁都打不开的包（AMFI 拒绝加载，报 `Launchd job spawn failed`）。

一次性前置（只需做一遍）：

1. 装 Developer ID Application 证书：Xcode → Settings → Accounts → 选账号 →
   Manage Certificates… → + → Developer ID Application
2. 存公证凭据：
   ```bash
   xcrun notarytool store-credentials openimg-notary \
     --apple-id <你的 Apple ID> --team-id <团队 ID>
   ```

## 服务端接口

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
PATCH  /api/preferences        转换偏好与时区
GET    /api/ai/status          AI 是否开启、还剩几次
POST   /api/ai/generate        文生图
POST   /api/ai/edit            图生图
GET    /api/ai/generations     生成记录
DELETE /api/ai/generations/:id 删除一条记录，?image=1 连图一起删
GET    /api/storage/profiles   存储位置
POST   /auth/native/exchange   OAuth 回调的一次性 code 换长期令牌
```

账号管理路由（删账号、签发令牌）只认 cookie —— 泄露的令牌不该能删号或再签发令牌。
`imageOut` 内嵌整个 `models.Image`，后端字段变更需要同步
`Sources/OpenimgKit/Models.swift`（两仓库拆分后靠这份清单对齐）。

## 下一步

- **iOS 端**：Kit 已按两端共用设计（`.iOS(.v17)` 已声明）。阻塞在一个产品决策：
  App Store 5.1.1(v) 要求 App 内可删账号，而删号是 cookie-only —— 要么 iOS 做
  cookie 登录，要么不提供登录入口（又会撞 4.2 最低功能性）
- Sparkle 自动更新（引第三方依赖，与零依赖纪律的取舍待定）

## 更新记录

见 [CHANGELOG.md](CHANGELOG.md)。

## License

[MIT](LICENSE)
