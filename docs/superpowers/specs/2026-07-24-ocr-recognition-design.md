# OCR 识别文字设计

## 目标

在 XxSnap macOS 菜单栏应用中新增一个独立的“识别文字”功能，提供 TextSniper 式的最小 OCR 体验：

1. 从顶部状态栏菜单触发。
2. 使用 `Command + 3` 全局快捷键触发。
3. 用户框选屏幕区域。
4. 本机离线识别选区图像中的文字。
5. 将识别出的纯文本复制到系统剪贴板。

本功能独立于现有截图、标注、贴图、保存和滚动截图工作流。第一版不在截图工具栏中增加 OCR 按钮，也不改变现有截图完成后的复制图片行为。

## 当前状态

- `StatusItemController` 构建顶部状态栏菜单，当前包含“截图”“教笔”“首选项”“检查更新”“关于”“退出”。
- `CaptureHotKeyController` 通过 Carbon 注册全局快捷键，当前动作包括：
  - `capture`：默认 `Command + \``
  - `teachingPen`：默认 `Command + 2`
  - `restoreMostRecentlyHiddenPinnedImage`：默认 `Command + 1`
- `CaptureCoordinator` 管理区域截图、教笔、滚动截图、贴图和长图编辑生命周期。
- `SelectionOverlayWindow` 支持区域选择和工具栏动作，普通区域截图会显示标注工具栏并产出图片动作。
- macOS 工程最低目标版本为 15.0，可以直接使用 Apple Vision 的现代文字识别能力。
- 现有应用已经处理屏幕录制权限；OCR 选区截图应复用同一套权限检查。

## 已选方案

使用 Apple `Vision.framework` 的 `VNRecognizeTextRequest` 实现离线 OCR。

不接入 PaddleOCR、Tesseract 或在线 OCR 服务。TextSniper 本机应用也链接 Apple Vision 和 VisionKit；它包内的 `Paddle.framework` 是授权/支付 SDK，不是 OCR 引擎。选择系统 Vision 可以保持原生、离线、低体积，并避免额外模型管理。

## 用户体验

状态栏菜单新增独立入口：

```text
截图                         Command + `
识别文字                     Command + 3
教笔                         Command + 2
────────────────────────────────────
首选项…
检查更新…
关于
────────────────────────────────────
退出                         Command + Q
```

英文菜单对应：

```text
Capture                       Command + `
Capture Text                  Command + 3
Presentation Pen              Command + 2
Preferences…
Check for Updates…
About
Quit                          Command + Q
```

行为要求：

- 点击“识别文字”或按 `Command + 3` 后，进入独立 OCR 选区模式。
- OCR 选区模式只用于框选识别区域，不展示现有截图标注工具栏，不提供保存、贴图、滚动截图或图片复制按钮。
- 用户拖拽选区并确认后，应用截取该区域图像并执行文字识别。
- 识别成功且结果非空时，清空系统剪贴板并写入 `String`。
- 识别为空时不覆盖剪贴板，提示未识别到文字。
- 用户取消或选区为空时直接结束，不改剪贴板。
- OCR 进行中保持与截图工作流相同的“捕获会话活跃”状态，避免其他全局快捷键干扰覆盖层。

第一版成功提示使用最小 `NSAlert`。后续再做 TextSniper 式菜单栏/HUD 提示。

## 识别规则

第一版采用固定默认策略：

- `recognitionLevel = .accurate`
- `usesLanguageCorrection = true`
- `automaticallyDetectsLanguage = true`
- `recognitionLanguages` 不暴露给用户配置
- 默认保留 Vision 返回结果的行顺序，用换行拼接多行文字

文字排序应按屏幕阅读顺序稳定输出。Vision 返回多个 `VNRecognizedTextObservation` 时，按纵向从上到下、同一行从左到右排序，再取每个 observation 的最高置信候选。

## 架构

### OCR 服务

新增 macOS 平台服务 `OCRTextRecognitionService`：

- 输入：`CGImage` 或 `NSImage`
- 输出：识别文本 `String`
- 依赖：`Vision.framework`
- 责任：配置 `VNRecognizeTextRequest`、执行识别、排序 observation、拼接文本、返回空结果或错误

该服务保持在 `platforms/mac/` 内，不进入 shared C++ core。OCR 依赖 Apple 平台 API，当前第一版也是 macOS 独立功能。

### 捕获协调

`CaptureCoordinator` 增加第三种覆盖层模式 `textRecognition`：

```text
region
teachingPen
textRecognition
```

`startTextRecognition()` 复用现有屏幕录制权限检查、桌面冻结图和选区截取能力，但创建覆盖层时使用 OCR 专用配置：

- 不显示主工具栏按钮。
- 不允许进入标注工具模式。
- 保留选择框、尺寸反馈和取消能力。
- 完成后不渲染标注，不写入图片剪贴板，不更新 `lastCapture`。

如果现有 `SelectionOverlayWindow` 的配置无法完全隐藏截图工具栏，应新增一个小的配置开关或结果动作，而不是把 OCR 行为塞进普通截图分支。

### 快捷键和菜单

`HotKeyAction` 新增稳定标识：

```text
recognizeText
```

默认快捷键：

```text
Command + 3
```

`CaptureHotKeyController` 接收 `recognizeTextHandler` 并注册该动作。现有快捷键冲突检测继续适用于 OCR 动作。首选项快捷键页后续应自然展示该动作；第一版若首选项页已有动态列表，则直接出现；若当前页面文案需要补充，则加上“识别文字”名称和说明。

`StatusItemController` 在截图和教笔之间新增菜单项，并显示当前注册成功的 OCR 快捷键。

## 错误处理

- 无屏幕录制权限：复用现有截图权限引导。
- 选区为空或取消：静默结束。
- 截图失败：记录日志并提示识别失败。
- OCR 请求失败：记录 Vision 错误并提示识别失败。
- OCR 结果为空：提示未识别到文字，不改剪贴板。
- 剪贴板写入失败：记录日志并提示复制失败。
- 快捷键注册失败：沿用现有快捷键错误状态，菜单不显示不可用等效键，点击菜单仍可触发。

## 测试

单元测试和 UI 结构测试应覆盖：

- `HotKeyAction.recognizeText` 的默认快捷键是 `Command + 3`。
- 菜单包含“识别文字”并位于截图和教笔之间。
- OCR 快捷键 handler 能调用 `CaptureCoordinator.startTextRecognition()`。
- OCR 模式完成后写入文本剪贴板，不写入图片剪贴板。
- OCR 结果为空时不覆盖原剪贴板内容。
- OCR 模式取消时结束捕获会话。
- Vision 服务的 observation 排序和文本拼接可用纯模型数据测试；真实 Vision 调用可在 macOS 测试中使用小型生成图片做集成验证。

手工验证：

- 启动 Debug app。
- 从状态栏菜单点击“识别文字”，框选屏幕文字，确认剪贴板得到文本。
- 使用 `Command + 3` 触发同样流程。
- 断网后重复识别，确认 OCR 仍可工作。
- 识别空白区域，确认剪贴板不被清空。
- 普通截图、教笔、贴图恢复快捷键保持原行为。

## 不包含范围

第一版不实现：

- 在线 OCR
- PaddleOCR/Tesseract 模型
- OCR 历史记录
- Additive Clipboard
- 保留/去除换行设置项
- 识别语言偏好设置
- 自定义词
- Text to Speech
- QR/条形码识别
- 截图工具栏 OCR 按钮
- 识别结果编辑窗口

这些能力可以在基础 OCR 稳定后按 TextSniper 功能逐步补齐。
