# 参与开发

纯 Swift 6 + SwiftUI，**零第三方依赖**。本仓库由主仓库
[gentpan/openimg](https://github.com/gentpan/openimg) 的 `apple/` 目录拆出，
保留了全部提交历史。

## 结构

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

## 自检

纯逻辑一律下沉到 `OpenimgKit`，`KitCheck` 才盯得住 —— 布局求解、EXIF 剥离、
水印合成、格式清单、签到日界都在里面。**写在 View 里的计算，454 项自检一项都碰不到**，
所以新代码但凡有算术就先想想能不能放进 Kit。

## 发布

```bash
./release.sh v0.3.0
```

打包（Developer ID + hardened runtime）→ 公证 → 装订 → 验证 → 建 GitHub Release。

发版说明放在 `release-notes/<版本>.md`，脚本会读它；没有对应文件时退回一句通用说明。

**验证这一步会真的启动一次 app，而且带隔离属性启动** —— 走的是用户下载后的那条路径。
`spctl` 只查签名与公证，不查受限授权有没有被描述文件授权：v0.2.0 就这样发出去过一个
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
