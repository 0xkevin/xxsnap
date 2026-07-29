# XxSnap macOS 发布打包与版本检查设计规格

日期：2026-07-29  
状态：待确认  
仓库：`https://gitee.com/itkevin/xxsnap.git`

## 1. 目标

为 XxSnap 建立可重复、可校验的 macOS 发布流程，产出适用于 macOS 14.0 及以上版本的 Universal 2 DMG，并为客户端加入“检查更新”能力。

当前没有付费 Apple Developer ID。第一阶段使用 ad-hoc 签名，不做 Apple 公证，不实现应用内静默下载、自动替换或增量更新。

## 2. 发布基线

- 产品名：XxSnap
- Bundle ID：`com.xxsnap.mac`
- 最低系统版本：macOS 14.0
- 架构：`arm64 + x86_64`，合并为 Universal 2
- 当前营销版本：`0.1.0`
- 当前构建号：`1`
- 发布格式：DMG
- 签名方式：ad-hoc
- 公证状态：未公证

`MARKETING_VERSION` 是用户可见的语义版本，`CURRENT_PROJECT_VERSION` 是单调递增的构建号。Git 标签使用 `v<MARKETING_VERSION>`，例如 `v0.1.0`。

## 3. 发布产物

每个版本生成：

```text
dist/
└── 0.1.0/
    ├── XxSnap-0.1.0-universal.dmg
    ├── manifest.json
    └── checksums.txt
```

DMG 根目录只包含：

- `XxSnap.app`
- 指向 `/Applications` 的快捷方式

不在 DMG 中放开发文档、源代码、调试符号、测试资源或额外安装脚本。

`manifest.json` 至少包含：

```json
{
  "version": "0.1.0",
  "buildNumber": 1,
  "minimumMacOSVersion": "14.0",
  "architecture": "universal2",
  "fileName": "XxSnap-0.1.0-universal.dmg",
  "fileSize": 0,
  "sha256": "",
  "publishedAt": null
}
```

打包脚本生成实际 `fileSize` 和 `sha256`。`publishedAt` 由管理后台发布时确定，客户端不依赖本地 manifest 的发布时间。

## 4. 构建流程

发布脚本必须显式执行以下步骤：

1. 检查工作区、Xcode 和必要命令；
2. 读取并校验版本号和构建号；
3. 运行 Release 配置测试；
4. 使用 Release 配置构建 `arm64` 和 `x86_64`；
5. 校验应用内所有本项目原生 Mach-O 二进制均包含两个架构；
6. 对应用执行 ad-hoc 签名；
7. 验证签名、Bundle ID、最低系统版本和版本元数据；
8. 组装 DMG；
9. 计算 DMG 大小和 SHA-256；
10. 写入 manifest 与 checksums；
11. 对最终 DMG 挂载并做结构检查。

建议使用 `create-dmg` 生成带应用图标和 Applications 快捷方式的标准 DMG；如果依赖不可用，脚本应明确失败并给出安装命令，不能静默产出不同格式。

构建命令必须显式指定：

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- Release 配置；
- `MACOSX_DEPLOYMENT_TARGET=14.0`
- `ARCHS="arm64 x86_64"`
- `ONLY_ACTIVE_ARCH=NO`
- 独立的发布 DerivedData 目录。

## 5. 签名与权限

没有 Developer ID 时使用：

```bash
codesign --force --deep --sign - XxSnap.app
```

签名前先完成所有二进制和资源写入，签名后不得再修改 App Bundle。

验证至少包括：

```bash
codesign --verify --deep --strict --verbose=2 XxSnap.app
codesign -dv --verbose=4 XxSnap.app
spctl --assess --type execute --verbose=4 XxSnap.app
```

ad-hoc 签名且未公证时，`spctl` 拒绝是已知结果，不作为构建失败条件；签名结构校验失败必须阻止发布。

重新下载或替换 ad-hoc 签名应用后，macOS 可能将其识别为新的代码身份，屏幕录制等隐私权限可能需要用户重新确认。安装文档和版本说明应客观说明这一点。

## 6. 架构与兼容性校验

不能只检查主可执行文件。发布脚本应扫描 App Bundle 内的 Mach-O：

- 主程序；
- Frameworks；
- 动态库；
- XPC 服务或辅助程序（如存在）。

使用 `file`、`lipo -info` 或 `lipo -archs` 验证每个必须通用的二进制都包含 `arm64` 和 `x86_64`。

同时使用 `otool -l` 或等效工具确认最低部署目标不高于 macOS 14.0。若第三方库仅包含单一架构或要求更高系统版本，发布必须失败。

## 7. 版本检查

客户端已经有状态栏“检查更新…”入口、首选项“更新”页和 `UpdateChecking` 抽象，目前由不联网的占位实现返回“已是最新版本”。本期用真实网络实现替换占位服务，保留现有菜单、首选项窗口、设置存储和 AppKit 交互边界。

第一阶段只做版本发现和手动安装：

1. 请求 `https://download.xxsofts.com/api/v1/releases/latest`；
2. 传递当前版本、构建号、系统版本和语言；
3. 对比服务端 `version` 与 `buildNumber`；
4. 有新版时展示版本、发布说明、文件大小、SHA-256 和最低系统版本；
5. 用户点击“下载更新”后打开官网稳定下载页或服务端下载入口；
6. 用户自行退出应用、打开 DMG 并替换 Applications 中的应用。

不在第一阶段实现：

- 后台自动下载；
- 自动挂载 DMG；
- 自动替换当前应用；
- Sparkle；
- 增量更新；
- 强制更新。

### 版本比较

- 优先比较语义版本；
- 语义版本相同则比较整数构建号；
- 服务端版本最低系统要求高于当前系统时，显示“不兼容”而不是下载按钮；
- API 返回非法版本、超时或离线时，显示可恢复错误，不影响截图主流程；
- 应用可以低频自动检查，但只能提示，不能自动开始下载。

现有 `PreferencesSettings` 中的“启动时检查更新”和检查间隔继续作为唯一用户设置来源。本期启用这两个设置：

- 开启时，在应用启动稳定后异步检查一次；
- 按用户选择的 `1 / 6 / 12 / 24 / 48 / 72` 小时间隔安排下一次检查；
- 关闭后取消自动调度，但手动检查始终可用；
- 记录真实成功检查时间，失败请求不伪造最后检查时间；
- 菜单和首选项仍调用同一个 `UpdateChecking` 服务；
- 不因更新服务异常影响截图、贴图、OCR 或应用启动。

## 8. 客户端交互

状态至少包括：

- 正在检查；
- 已是最新版本；
- 发现新版本；
- 当前系统不兼容；
- 网络或服务错误。

更新窗口应支持中英文，并与应用现有原生 AppKit 视觉保持一致。网络请求不能阻塞主线程，窗口关闭或应用退出时应取消无用请求。

客户端不记录下载量；只有用户访问服务端统一下载入口时才由服务端计数。

## 9. 发布操作流程

1. 在发布分支完成代码和版本号修改；
2. 运行完整测试，将结果与已知基线比较，并确认没有新增失败；
3. 执行发布打包脚本；
4. 人工检查 DMG 安装和首次运行；
5. 在 Apple 芯片 Mac 验证原生运行；
6. 在 Intel Mac 或可信的 Intel 环境验证启动和基本截图流程；
7. 通过独立管理后台上传 DMG 和 manifest；
8. 后台校验 SHA-256 后创建草稿；
9. 填写中英文发布说明并发布；
10. 验证官网、最新版本 API、下载 Range 和下载统计；
11. 创建并推送 `vX.Y.Z` 标签。

打包脚本不直接连接生产服务器，也不持有后台管理员密码或服务器 SSH 凭据。

## 10. 失败保护

以下任一条件必须阻止发布产物进入可上传状态：

- 测试出现未确认的新失败；
- 版本号、构建号或标签不一致；
- 主程序或依赖缺少任一目标架构；
- 最低部署版本高于 14.0；
- codesign 结构验证失败；
- DMG 无法挂载或缺少 App/Applications 快捷方式；
- manifest 的文件名、大小或 SHA-256 与 DMG 不一致。

脚本使用独立临时目录；失败时保留必要诊断日志，但清理未完成的 DMG 和 manifest，避免误上传。

## 11. 验收标准

- Release 构建明确支持 macOS 14.0；
- DMG 中的 XxSnap 可在 Apple 芯片和 Intel Mac 上启动；
- 所有应为 Universal 2 的 Mach-O 都通过架构检查；
- App Bundle ad-hoc 签名结构有效；
- DMG 仅包含应用和 Applications 快捷方式；
- manifest 与最终 DMG 的文件大小、SHA-256 完全一致；
- 客户端可查询最新版本并正确处理最新版、新版、不兼容和网络失败；
- 下载更新只打开统一下载入口，不执行自动替换；
- 管理后台能上传并发布生成的 DMG 和 manifest；
- 官网可展示发布信息并完成真实下载。

## 12. 当前基线说明

在 `feature/release-packaging` 分支未修改产品代码前，使用 Xcode 完整运行了 1,153 个测试：

- 通过：1,144；
- 失败测试：9；
- 失败断言：10；
- 结果包：`build/xcode-derived/Logs/Test/Test-xxsnap-2026.07.29_10-18-13-+0800.xcresult`。

失败集中在屏幕抓取颜色容差、悬浮层释放时序、放大镜像素/布局、序号重置图标、序号控件状态和状态栏模板图标。它们发生在本规格与发布功能修改之前，实施阶段必须将其作为已知基线单独记录；新增发布功能不能增加新的失败。
