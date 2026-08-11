# XxSnap Windows 区域截图 MVP 设计

日期：2026-08-04  
状态：已确认，进入实施

## 1. 背景与目标

XxSnap 当前由共享 C++ Core、原生 macOS 外壳和尚未实现的 Windows 目录组成。Windows 版本不能直接移植 Swift/AppKit 代码，需要在保持 macOS 产品体验的前提下，建立原生 Windows 外壳和可持续迁移的共享领域层。

本规格只负责第一个可交付子项目：Windows 区域截图 MVP。MVP 的用户目标是通过托盘或全局快捷键开始截图，完成区域选择、移动与缩放，并能复制、保存或取消。后续标注、贴图、滚动截图、OCR、教笔、设置、帮助、诊断和商业授权分别进入后续规格与实施计划。

Windows 视觉没有独立设计方向。macOS 当前实现是唯一视觉基准，Windows 不得替换图标、改变样式、重新排列控件或重新解释交互状态。

## 2. 现状 Review 结论

### 2.1 Windows 现状

`platforms/win/` 目前只有源码、测试和打包占位说明以及应用图标，没有可运行目标、构建脚本或平台实现。

### 2.2 现有功能事实范围

macOS 实际功能已经超出旧需求文档，主要包括：

- 托盘菜单、区域截图、全屏截图、离线 OCR、教笔、恢复最近隐藏贴图等入口；
- 多显示器桌面冻结、区域和窗口选择、选区锁定、移动、缩放、尺寸显示、颜色采样；
- 矩形、椭圆、箭头、画笔、马克笔、马赛克、文字、序号/对勾/叉号、放大镜、橡皮擦和撤销重做；
- 复制、PNG 保存、贴图、滚动截图、长图编辑和全屏截图编辑；
- 中英文设置、可配置快捷键、快捷键冲突反馈、帮助中心、诊断导出；
- 商业策略、试用/授权状态和免费发布回退机制。

### 2.3 共享边界问题

当前 `core/` 仍依赖 Qt 类型，标注模型只覆盖矩形和椭圆。macOS 真正复用的主要是滚动拼接算法；`SnapshotExportBridge` 当前只返回原图。绝大多数标注、渲染和交互逻辑位于 Swift/AppKit 中。

因此 Windows 开发不能把现有 Core 当作已完成的跨平台产品内核。MVP 期间只抽取区域截图真正需要的纯 C++ 领域类型与算法，并为后续工具迁移建立边界，不进行与 MVP 无关的整体重写。

### 2.4 测试基线

本次 Review 实际运行结果：

- macOS：1372 个测试，1362 通过、9 个测试失败、1 个跳过；
- Core：滚动匹配存在两个性能阈值失败；滚动拼接测试出现异常长时间运行并被终止。

这些是 Windows 开发前已经存在的基线问题。实施开始时应重新记录失败清单；Windows 工作不得增加 macOS/Core 失败数量。涉及共享代码的变更必须运行对应回归测试。

## 3. 已确认的产品与平台决策

### 3.1 技术路线

采用纯 C++ 原生 Windows 技术栈：

- Win32：进程、窗口、托盘、全局快捷键、消息循环和系统集成；
- Direct2D/DirectWrite：浮层、选区、尺寸标签和工具栏绘制；
- D3D11/DXGI Desktop Duplication：Windows 10/11 桌面像素获取；
- GDI BitBlt：Windows 10/11 降级后端和 Windows 7 稳定后端；
- WIC：PNG 编解码；
- CMake + MSVC：构建与测试。

不采用 WinUI 3、C# UI 或 Qt Windows 外壳。Windows App SDK 不进入 MVP 运行时依赖。

### 3.2 发布矩阵

MVP 产出四个安装包：

| 安装包 | CPU | 目标系统 | 备注 |
|---|---|---|---|
| Modern x64 | x64 | Windows 10 22H2 x64、Windows 11 x64 | Windows 11 的唯一发布包 |
| Modern x86 | x86 | Windows 10 22H2 32 位 | 不作为 Windows 11 版本发布 |
| Legacy x64 | x64 | Windows 7 SP1 64 位 | 需要 Platform Update 和 SHA-2 更新 |
| Legacy x86 | x86 | Windows 7 SP1 32 位 | 需要 Platform Update 和 SHA-2 更新 |

Windows 10 和 Windows 7 已结束微软常规支持，但属于用户明确要求的 XxSnap 兼容目标。安装器必须校验系统代际和 CPU：Modern x86 不得面向 Windows 11 展示；Legacy 包不得覆盖 Modern 安装。

### 3.3 开发环境

主要开发环境为 Apple Silicon Mac 上的 Parallels Windows 11 ARM64。该虚拟机已安装 ARM64 Visual Studio、Windows SDK 10.0.26100.0，以及 HostARM64→x64 和 HostARM64→x86 编译器。

本机可以交叉编译并通过 Windows 11 模拟层运行 x64/x86 程序，但不能替代真实 x64、Windows 10 32 位或 Windows 7 的发布验证。

### 3.4 Windows 快捷键映射

Windows 保持 macOS 快捷键的主键与 Shift 组合，只把 Command 修饰键映射为 Ctrl。四个主要功能的默认组合固定为：区域截图 `Ctrl+\``、全屏截图 `Ctrl+Shift+1`、OCR `Ctrl+3`、教笔 `Ctrl+2`。MVP 只注册范围内的区域截图快捷键，其余三个随对应功能分期实现，不提前注册无行为入口。

## 4. MVP 范围

### 4.1 包含

- 单实例后台进程；
- 与 macOS 一致的托盘图标和区域截图菜单入口；
- 一个默认全局区域截图快捷键；
- 多显示器拓扑、旋转、DPI 和负坐标处理；
- 在浮层显示前冻结全部显示器；
- 区域选择、锁定、移动、八方向缩放和尺寸显示；
- 与 macOS 相同的选区遮罩、边框、控件、光标语义和操作位置；
- 复制、PNG 保存、取消和 Esc；
- 快捷键冲突、截图失败、剪贴板失败和保存失败的明确反馈；
- Modern x64/x86、Legacy x64/x86 构建、安装和卸载。

### 4.2 不包含

- 标注工具和撤销重做；
- 贴图、全屏截图、滚动截图和长图编辑；
- OCR 和教笔；
- 设置窗口、自定义快捷键、更新入口、帮助中心和诊断导出；
- 商业授权和付费策略。

这些功能仍属于完整 Windows 版本目标，但每组功能需要单独规格、实施计划和验收。MVP 不显示不可用的占位按钮，也不用无行为控件伪装完成度。

## 5. 总体架构

### 5.1 分层

1. **AppHost**
   - 建立单实例进程和 Win32 消息循环；
   - 创建消息窗口、托盘图标和快捷键；
   - 将所有入口路由到 `CaptureSessionController`。

2. **CaptureSessionController**
   - 保证同一时间只有一个截图会话；
   - 驱动 `Idle → Capturing → Selecting → Ready → Exporting → Idle`；
   - 统一取消、后端重试、拓扑变化和资源释放。

3. **DisplayTopology**
   - 枚举显示器、虚拟桌面边界、旋转、物理像素、逻辑 DIP 和 DPI；
   - 为每次会话生成不可变拓扑快照；
   - 提供虚拟桌面坐标、显示器局部坐标和像素坐标的显式换算。

4. **CaptureBackend**
   - Modern 首选 DXGI Desktop Duplication，失败时重建设备并重试一次，再降级到 GDI；
   - Legacy 以 GDI BitBlt 为稳定基线，只在运行时确认能力后使用可选 DXGI；
   - 返回统一 BGRA 像素缓冲，不向上层暴露 DXGI/GDI 对象。

5. **FrozenDesktop**
   - 按显示器保存独立缓冲，而不是创建完整虚拟桌面巨型位图；
   - 保存拓扑版本、显示器像素矩形、像素格式和捕获时间；
   - 在会话结束前保持不可变。

6. **OverlayHost**
   - 每个显示器创建一个无边框、置顶、不出现在任务栏的 HWND；
   - 所有 HWND 共享同一个 `SelectionModel`；
   - 统一处理鼠标捕获，使逻辑选区可以正确映射多个显示器。

7. **SelectionModel**
   - 保存逻辑选区和交互状态；
   - 处理创建、标准化、移动、缩放、最小尺寸、边界和命中区域；
   - 不依赖 HWND、D2D 或具体平台截图对象。

8. **VisualStyleCatalog**
   - 记录从当前 macOS 实现核对得到的颜色、尺寸、间距、圆角、描边、透明度和命中区域；
   - Windows 构建直接消费现有 macOS SVG 源文件，不复制、替换或重新绘制图标；
   - MVP 不移动 macOS 资源文件，避免不必要的项目结构变更。

9. **ExportService**
   - 根据选区从多个显示器缓冲裁剪并按虚拟坐标合成；
   - 使用同一个最终像素结果完成剪贴板和 PNG 保存；
   - 不得在用户点击复制或保存后重新截图。

### 5.2 共享 Core 调整

MVP 只进行有直接收益的拆分：

- 将选区几何、坐标、颜色和像素缓冲契约改为不依赖 Qt 的纯 C++ 类型；
- 将现有 Qt 标注/导出能力保留在适配层，避免强迫 Windows Legacy 链接 Qt 6；
- 滚动拼接保持独立，不进入区域截图 MVP 依赖图；
- 平台窗口、字体、剪贴板、文件对话框和系统错误不进入 Core。

共享接口必须能够由 Modern 和 Legacy 工具链编译。实施计划的第一项兼容性试验负责确认 C++ 标准库和运行库组合；若当前 C++20 用法无法在 Windows 7 运行，只收敛共享边界内的语法/库用法，不降低无关目标的全局语言标准。

## 6. 截图数据流

1. 用户点击托盘菜单或按下全局快捷键。
2. `CaptureSessionController` 在 `Idle` 状态接受请求；其他状态返回“截图进行中”。
3. `DisplayTopology` 固化当前显示器拓扑。
4. `CaptureBackend` 在浮层出现前逐屏获取像素，生成 `FrozenDesktop`。
5. 控制器再次核对拓扑版本；若发生变化，丢弃缓冲并完整重试一次。
6. `OverlayHost` 创建每屏浮层并进入 `Selecting`。
7. 用户拖动创建选区；鼠标释放后进入 `Ready`，显示与 macOS 一致的尺寸与操作控件。
8. 用户可以移动、缩放选区，或选择复制、保存、取消。
9. 复制/保存时，`ExportService` 从冻结缓冲裁剪和合成最终图像。
10. 复制写入剪贴板；保存通过 WIC 编码 PNG。取消不产生输出。
11. 所有浮层和捕获资源释放，会话回到 `Idle`。

## 7. 坐标、DPI 与多显示器

- 领域层使用 64 位整数表达物理像素矩形，避免负坐标和大桌面溢出；
- UI 布局使用 DIP，导出使用物理像素，二者不得混用；
- 每个显示器保存独立的 DIP↔像素比例和旋转信息；
- Modern 使用 Per-Monitor DPI 能力；Legacy 通过可用 API和显示器设备信息建立兼容映射；
- 拓扑、DPI、旋转或分辨率在会话中改变时，不修补旧坐标，直接重新开始一次冻结；
- 跨屏裁剪按虚拟桌面坐标合成；与 macOS 当前透明桌面画布行为一致，显示器之间不存在的空洞区域在 PNG 和 `CF_DIBV5` 中保持透明。

## 8. 视觉一致性

- 现有 macOS SVG 是唯一图标源，Windows 包含的资源字节必须通过 SHA-256 一致性检查；
- 控件顺序、可见状态、颜色、尺寸、间距、圆角、描边、遮罩透明度和命中区域以 macOS 当前实现为准；
- Modern 和 Legacy 使用同一个 `VisualStyleCatalog`；系统后端差异不得改变视觉模型；
- 在 100%、125%、150% 和 200% DPI 下生成视觉金图；几何和颜色精确比较；
- 文字内容、字号、字重和布局必须一致。由于 DirectWrite 与 CoreText 栅格化不同，只允许文字边缘抗锯齿存在像素级差异；
- 不使用 Windows 原生控件样式替代 macOS 自绘控件；
- MVP 未实现的后续工具不显示，不提供禁用占位图标。

## 9. 错误处理与降级

### 9.1 快捷键与单实例

- 第二实例把启动请求发送给已运行实例后退出；
- `RegisterHotKey` 冲突时保留托盘入口，显示明确错误并记录系统错误码；
- 不自动改用另一个快捷键。

### 9.2 截图失败

- Modern DXGI 失败后重建设备并重试一次，再尝试 GDI；
- Legacy GDI 失败时结束会话；
- 只在后端返回拒绝访问、无有效帧或设备错误时判定失败；不得用“画面全黑”启发式拒绝合法黑色桌面；
- 安全桌面和受保护内容遵守系统限制，不尝试绕过保护。

### 9.3 拓扑变化

- 捕获后、显示浮层前检查一次拓扑；
- 会话中收到显示器或 DPI 变化时关闭浮层并完整重试一次；
- 第二次仍变化则结束会话并提示，禁止用过期像素继续导出。

### 9.4 内存

- 所有 `width × height × bytesPerPixel` 使用 64 位检查运算；
- 每次分配前计入统一预算；
- x86 初始预算为 512 MiB，x64 初始预算为 2 GiB；
- 超过预算时在分配前结束会话，不依赖 `bad_alloc` 作为正常控制流；
- 预算作为集中常量并纳入测试，后续只能依据真实测量调整。

### 9.5 剪贴板与保存

- 剪贴板被占用时进行有限次数短退避重试；
- Windows 剪贴板至少写入 `CF_DIBV5`，并在目标系统可用时附加注册的 PNG 格式；
- 写剪贴板失败时保留会话最终图像到进程内的最近截图槽，显示失败提示；MVP 不新增“保存最近截图”入口，用户需要重新截图并选择保存；
- PNG 先写入目标目录内的临时文件，成功关闭后再替换目标；
- 取消保存或编码/写盘失败不得破坏已有目标文件，并清理临时文件。

### 9.6 诊断隐私

日志只记录应用版本、包类型、CPU、OS 构建号、后端、显示器数量、像素尺寸、耗时和稳定错误码。不记录截图像素、OCR/剪贴板内容、窗口标题或完整保存路径。

## 10. 构建与打包

### 10.1 Modern

- 同一 Modern 源码生成 x64 和 x86；
- 使用当前 MSVC 和 Windows SDK 10.0.26100.0；
- x64 安装器接受 Windows 10 x64 和 Windows 11 x64；
- x86 安装器只接受 Windows 10 32 位；在 64 位系统启动时提示使用 x64 包。

### 10.2 Legacy

- 同一 Legacy 源码生成 x64 和 x86；
- 使用独立、固定版本的旧平台工具链和 Windows 兼容 SDK；
- 运行时动态探测可选 API，不静态导入 Windows 7 不存在的入口；
- 安装器要求 Windows 7 SP1、Platform Update 和 SHA-2 支持；
- Legacy 与 Modern 使用不同安装标识，避免互相覆盖。

### 10.3 产物

每个包必须包含版本化 EXE、必要运行库、原始图标资源、许可证、卸载信息和可验证的数字签名。安装器名称明确包含目标系统族和 CPU，禁止使用“自动猜测但静默安装错误包”的行为。

## 11. 测试策略

### 11.1 自动化层次

- **单元测试**：坐标换算、几何标准化、状态机、内存预算、裁剪合成、错误映射；
- **后端测试**：DXGI/GDI 像素、显示器旋转、DPI、设备重建和降级；
- **集成测试**：快捷键→冻结→浮层→复制/保存/取消；
- **安装测试**：系统/架构门禁、升级、卸载、单实例和启动项清理；
- **视觉测试**：资源哈希、布局清单和多 DPI 金图。

### 11.2 运行矩阵

| 环境 | 用途 |
|---|---|
| Parallels Windows 11 ARM64 | Modern x64/x86 日常编译、运行和快速回归 |
| Windows 11 x64 实机或 CI | Modern x64 原生发布验证 |
| Windows 10 22H2 x64 | Modern x64 兼容验证 |
| Windows 10 22H2 x86 VM/实机 | Modern x86 发布验证 |
| Windows 7 SP1 x64 VM/实机 | Legacy x64 发布验证 |
| Windows 7 SP1 x86 VM/实机 | Legacy x86 发布验证 |

Parallels ARM64 结果不能替代其他五个发布环境。Windows 7 测试环境不得连接不受控公网。

### 11.3 性能门槛

- Modern 双 4K 参考机：快捷键到浮层显示 P95 ≤ 250 ms，拖动绘制以 60 FPS 为目标；
- Legacy 1080p 参考机：快捷键到浮层显示 P95 ≤ 500 ms，拖动绘制 ≥ 30 FPS；
- 性能数据从快捷键消息到首个完整浮层帧统一计时；
- VM 可用于趋势监控，发布门槛以规定的原生参考环境为准。

## 12. MVP 验收标准

以下条件全部满足才可发布：

1. 四个安装包在各自目标系统正确安装、启动、升级和卸载；错误系统或架构会被明确阻止。
2. 托盘图标、菜单入口、选区遮罩、边框、尺寸显示和操作控件与 macOS 当前视觉基准一致。
3. 全局快捷键成功时启动截图；冲突时显示错误且托盘入口可用。
4. 浮层不会被截入冻结桌面；多显示器、负坐标、旋转和混合 DPI 下选区与输出像素一致。
5. 选区创建、移动、八方向缩放、最小尺寸、Esc 和取消行为正确。
6. 复制与保存使用同一冻结像素；PNG 尺寸和颜色正确，无二次截图偏差。
7. DXGI 设备丢失、GDI 失败、拓扑变化、内存超限、剪贴板占用和写盘失败均有自动化覆盖。
8. 资源哈希与 macOS SVG 一致，多 DPI 视觉金图通过。
9. Modern 和 Legacy 达到各自性能门槛。
10. macOS/Core 相关测试没有新增失败；共享代码变更的 Windows 测试全部通过。

## 13. 后续分期

本规格完成后，完整 Windows 版本按以下顺序继续拆分：

1. 标注文档模型、渲染器和全部工具；
2. 贴图与全屏截图编辑；
3. 滚动截图、长图编辑和共享拼接核心；
4. OCR 与教笔；
5. 设置、快捷键编辑、帮助、诊断、更新与商业授权。

每一期都必须先核对 macOS 当前行为，再形成独立设计规格。不得通过复制 `SelectionOverlayWindow.swift` 的巨型职责结构，在 Windows 重建另一个单文件实现。

## 14. 官方平台参考

- [Windows on Arm x86/x64 模拟](https://learn.microsoft.com/en-us/windows/arm/apps-on-arm-x86-emulation)
- [Direct2D](https://learn.microsoft.com/en-us/windows/win32/direct2d/direct2d-portal)
- [Desktop Duplication API](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/desktop-dup-api)
- [RegisterHotKey](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey)
- [Shell_NotifyIcon](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shell_notifyiconw)
- [Windows 7 生命周期](https://learn.microsoft.com/en-us/lifecycle/products/windows-7)
- [Windows 7 SHA-2 支持](https://learn.microsoft.com/en-us/security-updates/securityadvisories/2015/3033929)
