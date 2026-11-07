# GitHub 连接测试 + 待办考勤 · iOS App（TrollStore 版）

## GitHub 连接测试

这是第一次使用 Git 推送的文件，用来验证 SSH 连接是否正常。

- 提交人：18969668012maqi1102-cpu
- 邮箱：18969668012maqi1102@gmail.com
- 方式：SSH 密钥免密

---

## 待办考勤 · iOS App

「待办 · 考勤」Web 应用的 iOS 壳。**WKWebView 承载线上应用 + 原生通知桥接**。

- 线上应用：https://todo-attendance.app.workbuddy.host/?sharecode=GKDGWPCAGF
- 源码：XcodeGen 工程（`project.yml`）+ Swift（`Sources/`）
- CI：`.github/workflows/build-ipa.yml`（GitHub Actions macOS runner，无需本地 Mac）

## 构建

1. 把本仓库推到 GitHub（main 分支）
2. Actions → Build IPA (TrollStore) → Run workflow
3. 完成后下载 artifact `TodoAttendance-ipa`，里面是 `TodoAttendance.ipa`
4. 传到手机（AirDrop / 微信文件传输 / iCloud Drive）
5. 用 **TrollStore** 打开该 IPA 安装

## 技术要点

| 项 | 说明 |
|---|---|
| 框架 | WKWebView 加载线上链接（路线 A），前端更新即时生效，不用重出 IPA |
| 构建 | XcodeGen 生成工程 → `xcodebuild CODE_SIGNING_ALLOWED=NO` → `ldid -S` 伪签名 → 手工构造 `Payload/` → zip 成 IPA |
| 签名 | 不需要 Apple 开发者账号。TrollStore 会用伪造根证书重签并保留预签 entitlements |
| 权限 | 只要相机（拍照识别）+ 通知。**不申请 platform-application 等高危 entitlement** |
| 网络 | 仅 HTTPS，`NSAllowsArbitraryLoads=false` |

## 数据与安全

- **数据全部在服务端**，App 只是显示器。手机本地不存业务数据
- API 响应带 `Cache-Control: no-store`，业务数据不进 Web 缓存
- 本地只保留一个 HttpOnly 会话 cookie（网页内「退出」可清除）
- 原生层**不打印任何业务数据**，不写日志
- 应用需口令才能读取数据（服务端校验，见 Web 端设置）

## 已知限制

- **App 在后台时**，iOS 会挂起 JS 定时器 → Web 端的轮询式提醒不会触发。
  解决方案：在 App 内「设置 → 日历订阅」订阅一次，由系统日历负责提醒（推荐）。
- 通知授权在首次启动时申请，拒绝后需到「设置 → 通知」手动开启。

## 本地开发（需要 Mac）

```bash
brew install xcodegen
xcodegen generate
open TodoAttendance.xcodeproj
```

改完 `Sources/AppDelegate.swift` 后重新 `xcodegen generate`（XcodeGen 不直接改工程文件）。
