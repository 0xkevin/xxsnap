# XxSnap 项目规约

## 禁止使用 Git worktree

1. 本项目的任何开发、修复、重构、测试、审查、合并和发布工作都禁止使用 Git worktree。
2. 禁止执行 `git worktree add`，禁止调用任何会创建、复用或依赖 worktree 的技能、脚本、工具或自动化流程，包括但不限于 `ce-worktree` 和 `using-git-worktrees`。
3. 主代理、子代理和外部执行器都必须在本项目的主工作目录中工作；不得为并行任务、分支隔离、代码审查或发布准备创建额外工作目录。
4. 开发工作应在主工作目录中通过普通 Git 分支完成。需要并行处理时，应改为串行执行或采用不创建 worktree 的方式，不得以效率、隔离或工具默认行为为由例外。
5. 如果发现历史遗留 worktree，只允许进行只读审计和必要的分支整合，不得继续在其中开发。移除遗留 worktree 前必须确认其中没有未合并或未保存的功能，并遵守项目的数据安全规则。
6. 本禁令属于强制项目规约。除非用户明确修改本条规则，否则任何代理都不得自行放宽或绕过。

## 版本发布与 `main` 分支

以下规则适用于所有版本发布，包括正式版、测试版、候选版、补丁版，以及 DMG、安装包、更新清单、Git 标签和官网发布。

1. 任何版本都必须先把全部有效代码、功能和分支完整合并到 `main`，然后只基于 `main` 构建、打包、打标签和发布。禁止直接从功能分支、修复分支、临时分支或分离的 worktree 发布版本。
2. `main` 不得遗漏任何本地或远端分支中的有效功能、修复、文档、资源和构建配置。不得仅因分支名称、平台名称或历史用途而擅自跳过未合并分支。
3. 发布前必须执行完整分支审计，至少检查：
   - `git fetch --all --prune`
   - `git branch --no-merged main`
   - `git branch -r --no-merged main`
   - `git worktree list --porcelain`
4. 只要发现任何未合并分支、未整合提交或其他 worktree 中尚未进入 `main` 的功能，就必须停止发布，逐个核对并合并。确需废弃、排除或延后某个分支时，必须先取得用户明确确认并记录原因；不得静默忽略。
5. 合并完成后必须重新确认当前分支是 `main`、工作树符合发布要求，并从当前 `main` 的明确提交 SHA 重新运行测试、构建和打包。之前在其他分支生成的产物不得直接作为发布包。
6. 版本号、构建号、安装包、更新清单、校验文件、Git 标签和官网记录必须对应同一个 `main` 提交。发布记录中应保留该提交 SHA，便于追溯。
7. 在分支审计、合并、测试或产物校验未完成时，不得上传官网、发布更新策略或创建正式版本标签。
8. 本规约是强制发布门禁。任何放宽、绕过或例外都必须由用户明确批准，代理不得自行判断后跳过。

## macOS 版本号与发布产物

以下规则是 macOS 打包的强制约定。生成、上传或交付版本前，必须逐项核对，不得只交付 DMG。

### 版本号和构建号

1. `platforms/mac/project.yml` 中的 `MARKETING_VERSION` 是用户可见版本号，使用 `主版本.次版本.修订号` 的语义版本格式，例如 `1.0.0`：
   - 不兼容变化增加主版本；
   - 向后兼容的新功能增加次版本；
   - 向后兼容的缺陷修复增加修订号。
2. `CURRENT_PROJECT_VERSION` 是纯整数构建号，例如 `1`、`2`、`3`。每个已经上传、发布或交付给用户的新构建都必须严格递增，不得重复或回退；只在从未上传、发布或交付的本地失败构建中才允许复用。
3. 同一用户可见版本重新发包时，只增加构建号。例如上一版已经发布为 `1.0.0（1）`，下一包仍使用版本号 `1.0.0` 时必须是 `1.0.0（2）`。升级用户可见版本时，构建号仍继续递增，不得自动重置为 `1`。
4. 中文界面或文档统一写作 `版本号（构建号）`，例如 `1.0.0（2）`；英文或纯 ASCII 环境写作 `1.0.0 (2)`。括号内只能填写纯整数构建号，不填写 `build`、版本号、日期、架构、渠道或签名状态。
5. `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION` 必须同时写入 `platforms/mac/project.yml` 和生成后的 Xcode 工程配置，并与最终 `.app` 的 `CFBundleShortVersionString`、`CFBundleVersion` 完全一致。正式打包不得只通过 `xcodebuild` 参数临时覆盖而不更新项目配置。
6. 打包前必须查询当前已发布或已上传版本，确认下一个构建号；不得仅根据本地 `dist` 目录猜测。

### 文件名和目录

1. 正式 DMG 文件名固定为 `XxSnap-<MARKETING_VERSION>-universal.dmg`，例如 `XxSnap-1.0.0-universal.dmg`。
2. DMG 文件名不得包含构建号或内部状态，包括但不限于 `build2`、`internal`、`unsigned`、`unnotarized`。构建号只存在于应用元数据、后台版本记录和 `manifest.json` 中。
3. 最终交付目录至少包含以下五个文件，缺少任意一个都视为打包未完成：

   ```text
   dist/<MARKETING_VERSION>/
   ├── XxSnap-<MARKETING_VERSION>-universal.dmg
   ├── manifest.json
   ├── checksums.txt
   ├── release-notes-zh-CN.md
   └── release-notes-en.md
   ```

4. 如果同一版本号存在历史构建，生成新包时必须先保留历史产物或使用独立临时目录，未经用户确认不得覆盖旧包；最终上传的 DMG 文件名仍遵循标准名称。
5. `release-notes-zh-CN.md` 和 `release-notes-en.md` 必须分别提供面向用户的中文、英文发布说明，标题必须包含准确的版本号和构建号，正文应说明本次新增、优化和修复内容，不得复制旧版本说明或遗漏本次主要功能。

### 平台隔离

1. macOS 与 Windows 必须独立构建、独立测试、独立打包。用户只要求某个平台时，不得构建、复制或交付另一平台的安装包、可执行文件、调试文件或资源。
2. 从 `main` 发布 macOS 版本时，`main` 可以包含已经合并的 Windows 源码，但 macOS Xcode 工程、归档和 DMG 不得引用或携带 `platforms/win`、Windows 构建目录或 Windows 产物；Windows 代码的存在不得改变 macOS 功能和打包结果。
3. 交付前必须检查最终安装介质的内容，确认其中只有目标平台应用及必要的安装入口；不得仅根据构建命令推断平台隔离已经生效。
4. 除非用户明确要求同时发布多个平台，否则不得因为版本号相同、分支已合并或自动化脚本默认行为而联动打包其他平台。

### `manifest.json` 和校验文件

1. `manifest.json` 必须根据最终 DMG 生成，不得复制旧版本后只修改部分字段。它至少包含：

   ```json
   {
     "version": "1.0.0",
     "buildNumber": 2,
     "minimumMacOSVersion": "14.0",
     "architecture": "universal2",
     "fileName": "XxSnap-1.0.0-universal.dmg",
     "fileSize": 12076842,
     "sha256": "<64 位小写 SHA-256>",
     "publishedAt": null
   }
   ```

2. 字段取值约定：
   - `version` 必须等于应用的 `MARKETING_VERSION`；
   - `buildNumber` 必须等于应用的整数 `CURRENT_PROJECT_VERSION`；
   - `minimumMacOSVersion` 必须等于实际构建目标，当前为 `14.0`；
   - `architecture` 只有在最终应用同时包含 `arm64` 和 `x86_64` 时才能写 `universal2`；
   - `fileName` 必须等于最终 DMG 的实际文件名；
   - `fileSize` 必须是最终 DMG 的精确字节数；
   - `sha256` 必须是最终 DMG 的 64 位小写 SHA-256；
   - `publishedAt` 在本地生成时固定为 `null`，由发布后台填写。
3. `checksums.txt` 必须使用相对文件名，不得写本机绝对路径，格式为 `<sha256><两个空格><DMG 文件名>`。
4. 任何重签名、重新压缩、重建或修改 DMG 的操作都会使文件大小和 SHA-256 失效；发生后必须重新生成 `manifest.json` 和 `checksums.txt`。
5. 交付前必须完成机器校验：JSON 可解析，DMG 文件名、版本号、构建号、最低系统、架构和应用元数据一致，文件大小一致，并且 `shasum -a 256 -c checksums.txt` 通过。
6. 发布后台必须同时上传 DMG 和 `manifest.json`；`checksums.txt` 随交付目录保留用于人工和自动复核。

### 发布交付清单

交付前必须明确报告并核对：来源 `main` 提交 SHA、用户可见版本号、括号内构建号、DMG 文件名、文件大小、SHA-256、双架构结果、签名与公证状态、`manifest.json` 校验结果、中英文发布说明、目标平台隔离检查，以及未执行或失败的测试。用户明确允许跳过 Developer ID 或公证时，可以生成对应包，但仍不得遗漏 manifest、checksum 和中英文发布说明，并且必须在交付说明中明确风险。
