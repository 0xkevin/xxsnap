# XxSnap Windows 区域截图 MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变 macOS 图标、样式和交互语义的前提下，交付可安装的 Windows 区域截图 MVP，并生成 Modern x64、Modern x86、Legacy x64、Legacy x86 四个包。

**Architecture:** 新增纯 C++ 可移植领域层，Windows 原生外壳采用 Win32、Direct2D/DirectWrite、DXGI/GDI 和 WIC。每次截图先固化显示器拓扑与逐屏像素，再显示每屏浮层；所有浮层共享一个选区模型；复制和保存都消费同一份冻结像素。Modern 首选 DXGI 并降级到 GDI，Legacy 以 GDI 为基线，平台 API 均封装在边界内。

**Tech Stack:** C++17 portable core、C++20 Windows host、CMake 3.28、MSVC v143（Modern）、MSVC v142 + Windows SDK 10.0.19041（Legacy）、Win32、D2D1、DWrite、D3D11、DXGI 1.2、WIC、Windows Imaging Component、CTest、WiX Toolset 4、PowerShell。

---

## 执行前约束

- 设计依据：`docs/superpowers/specs/2026-08-04-windows-mvp-design.md`，对应提交 `38166b8`。
- 当前工作区在执行计划生成时位于 `feature/text-qr-recognition`，而设计提交位于 `fix/commercial-free-release-fallback`。开始 Task 1 前必须先由用户确认执行分支；不得把 Windows 实现混入无关功能分支。
- 保留用户现有修改，不得覆盖 `.gitignore`、`README.md`、`platforms/mac/Tests/AppSettingsTests.swift`、`platforms/mac/packaging/README.md` 和未跟踪的 macOS 打包手册。
- Windows 源码从 `\\Mac\Home\Projects\open-source\Snipory\xxsnap` 读取，构建目录必须放在 Windows NTFS（例如 `C:\Users\kevin\build\xxsnap-*`），不得在 Parallels 共享目录内构建。
- 进入 Windows PowerShell 后先执行 `$env:Path = 'C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;' + $env:Path`；下文的 `cmake`、`ctest` 和 `ninja` 命令均在同一个 PowerShell 会话中运行。
- 每个任务先写失败测试，再做最小实现；每个任务只提交列出的文件。
- 不在 MVP 中显示标注、贴图、滚动截图、OCR、教笔、设置或商业功能的占位按钮。
- Windows 快捷键统一保留 macOS 主键与 Shift 组合，只将 Command 映射为 Ctrl：区域截图 `Ctrl+\``、全屏截图 `Ctrl+Shift+1`、OCR `Ctrl+3`、教笔 `Ctrl+2`。本计划只注册区域截图，其余组合由对应后续功能计划实现。

## 固定目录与类型契约

实现期间保持以下目录边界，不另建平行架构：

```text
core/
  include/snipory/core/portable/{Geometry,PixelBuffer}.h
  src/portable/PixelBuffer.cpp
  tests/{TestPortableGeometry,TestPixelBuffer}.cpp
platforms/win/
  src/app/          # WinMain、单实例、托盘、快捷键
  src/capture/      # 拓扑、DXGI/GDI、FrozenDesktop
  src/session/      # 状态机、会话协调器
  src/overlay/      # 选区模型、样式、浮层渲染与输入
  src/export/       # 跨屏合成、剪贴板、PNG
  src/support/      # Win32 RAII、错误与诊断
  resources/        # .rc、应用图标；MVP 按钮由 macOS 原文件嵌入
  tests/            # 单元与 Windows 集成测试
  packaging/        # WiX 源文件与四包配置
tools/windows/      # 构建、资源、导入表、性能和打包脚本
```

固定领域类型：

```cpp
namespace snipory::core::portable {
struct PixelPoint { std::int64_t x; std::int64_t y; };
struct PixelSize { std::int64_t width; std::int64_t height; };
struct PixelRect {
    std::int64_t x;
    std::int64_t y;
    std::int64_t width;
    std::int64_t height;
};
enum class PixelFormat { bgra8Premultiplied };
enum class PixelBufferError { invalidSize, arithmeticOverflow, budgetExceeded, allocationFailed };
class PixelBuffer;
struct PixelBufferAllocation {
    std::unique_ptr<PixelBuffer> value;
    PixelBufferError error;
};
}
```

Windows 捕获边界：

```cpp
struct DisplayDescriptor {
    std::wstring deviceName;
    snipory::core::portable::PixelRect pixelBounds;
    UINT dpiX;
    UINT dpiY;
    DISPLAYCONFIG_ROTATION rotation;
};

struct DisplayTopologySnapshot {
    std::vector<DisplayDescriptor> displays;
    snipory::core::portable::PixelRect virtualBounds;
    std::uint64_t fingerprint;
};

struct FrozenDisplay {
    DisplayDescriptor display;
    snipory::core::portable::PixelBuffer pixels;
};

struct FrozenDesktop {
    DisplayTopologySnapshot topology;
    std::vector<FrozenDisplay> displays;
    std::chrono::steady_clock::time_point capturedAt;
};

enum class CaptureErrorCode {
    accessDenied, deviceLost, unsupported, noFrame,
    memoryLimit, topologyChanged, systemFailure
};

struct CaptureError { CaptureErrorCode code; HRESULT nativeCode; };
using CaptureResult = std::variant<FrozenDesktop, CaptureError>;
```

`std::expected` 不进入共享边界，避免 Legacy 工具链被迫使用 C++23。

## Task 1: 建立 Windows 工具链探针与构建骨架

**Files:**
- Modify: `CMakeLists.txt`
- Create: `platforms/win/CMakeLists.txt`
- Create: `platforms/win/src/build/ToolchainProbe.cpp`
- Create: `platforms/win/tests/TestBuildConfiguration.cpp`
- Create: `cmake/windows/LegacyWindows7.cmake`
- Create: `tools/windows/build-modern.ps1`
- Create: `tools/windows/build-legacy.ps1`

- [ ] **Step 1: 写构建配置失败测试**

`TestBuildConfiguration.cpp` 必须断言编译期定义与位数一致：

```cpp
#include <cassert>
#include <windows.h>

int main() {
#if !defined(XXSNAP_MODERN) && !defined(XXSNAP_LEGACY)
#error Missing Windows product family
#endif
#if defined(XXSNAP_MODERN) && defined(XXSNAP_LEGACY)
#error Product families are mutually exclusive
#endif
#if defined(_WIN64)
    static_assert(sizeof(void*) == 8);
#else
    static_assert(sizeof(void*) == 4);
#endif
#if defined(XXSNAP_LEGACY)
    static_assert(_WIN32_WINNT == 0x0601);
#endif
    assert(true);
}
```

- [ ] **Step 2: 证明当前工程没有 Windows 目标**

在 Windows PowerShell 运行：

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' `
  -S '\\Mac\Home\Projects\open-source\Snipory\xxsnap' `
  -B 'C:\Users\kevin\build\xxsnap-probe' -G Ninja `
  -DXXSNAP_BUILD_QT_CORE=OFF -DXXSNAP_WINDOWS_FAMILY=modern
```

预期：配置停在 Qt 查找或不存在 `xxsnap_windows` 目标；记录完整输出到任务说明，不把日志提交到仓库。

- [ ] **Step 3: 增加条件式 Windows 子目录**

根 `CMakeLists.txt` 增加 `XXSNAP_BUILD_QT_CORE` 开关，并只在 `WIN32` 时加入 Windows 子目录：

```cmake
option(XXSNAP_BUILD_QT_CORE "Build the existing Qt-dependent core" ON)
if(XXSNAP_BUILD_QT_CORE)
    add_subdirectory(core)
endif()

if(WIN32)
    add_subdirectory(platforms/win)
endif()
```

`platforms/win/CMakeLists.txt` 创建 `xxsnap_build_configuration_test`，并用缓存变量 `XXSNAP_WINDOWS_FAMILY=modern|legacy` 注入互斥定义。非法值使用 `message(FATAL_ERROR ...)`。

- [ ] **Step 4: 固定两个构建脚本的生成器与输出目录**

`build-modern.ps1` 接受 `-Arch x64|x86`，调用 VS 18 的 `VsDevCmd.bat -host_arch=arm64 -arch=<arch>` 后使用 bundled CMake/Ninja，并固定传入 `-DXXSNAP_BUILD_QT_CORE=OFF`。`build-legacy.ps1` 只接受 VS 2019 Build Tools 16.11、`v142`、SDK `10.0.19041.0`，同样关闭 Qt core，并传入 `cmake/windows/LegacyWindows7.cmake`；缺少任一组件时明确失败，不自动下载。

- [ ] **Step 5: 在 Windows VM 编译并运行探针**

```powershell
Set-Location '\\Mac\Home\Projects\open-source\Snipory\xxsnap'
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_build_configuration_test
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R build_configuration --output-on-failure
.\tools\windows\build-modern.ps1 -Arch x86 -Target xxsnap_build_configuration_test
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x86 -R build_configuration --output-on-failure
```

预期：两个测试均显示 `100% tests passed`。Legacy 缺工具链时预期脚本输出精确缺失组件并返回非零；安装固定工具链后再进入 Task 15 的正式验证。

- [ ] **Step 6: 提交构建骨架**

```bash
git add CMakeLists.txt cmake/windows/LegacyWindows7.cmake platforms/win/CMakeLists.txt platforms/win/src/build/ToolchainProbe.cpp platforms/win/tests/TestBuildConfiguration.cpp tools/windows/build-modern.ps1 tools/windows/build-legacy.ps1
git commit -m "build(win): add modern and legacy build skeleton"
```

## Task 2: 抽取无 Qt 的像素几何与受预算缓冲

**Files:**
- Modify: `CMakeLists.txt`
- Modify: `core/CMakeLists.txt`
- Create: `core/include/snipory/core/portable/Geometry.h`
- Create: `core/include/snipory/core/portable/PixelBuffer.h`
- Create: `core/src/portable/PixelBuffer.cpp`
- Create: `core/tests/TestPortableGeometry.cpp`
- Create: `core/tests/TestPixelBuffer.cpp`

- [ ] **Step 1: 写几何失败测试**

覆盖负宽高标准化、负虚拟坐标、相交、平移限制和超过 32 位的中间值：

```cpp
assert(standardized({20, 30, -10, -20}) == PixelRect{10, 10, 10, 20});
assert(intersection({-1920, 0, 1920, 1080}, {-10, 10, 30, 40}) ==
       std::optional<PixelRect>{{-10, 10, 10, 40}});
assert(!checkedByteCount(9'000'000'000LL, 9'000'000'000LL, 4).has_value());
```

- [ ] **Step 2: 写预算失败测试**

```cpp
MemoryBudget budget(512ULL * 1024 * 1024);
auto first = PixelBuffer::allocate(8192, 8192, budget);
assert(first.value != nullptr);
auto second = PixelBuffer::allocate(8192, 8192, budget);
assert(second.value == nullptr);
assert(second.error == PixelBufferError::budgetExceeded);
```

再覆盖零尺寸、负尺寸、stride 对齐、移动后预算只释放一次。

- [ ] **Step 3: 运行测试并确认链接目标不存在**

```bash
cmake --build build --target test_portable_geometry test_pixel_buffer
```

预期：失败，目标不存在。

- [ ] **Step 4: 创建 `snipory_core_portable`**

该 target 使用 `cxx_std_17`，只包含标准库，不公开 Qt 头。根工程无论 `XXSNAP_BUILD_QT_CORE` 取值都加入 `core/`；`core/CMakeLists.txt` 始终定义 portable target，仅在开关为 ON 时定义现有 Qt target 和 Qt 测试。`snipory_core` 链接 portable target，Windows 只链接 `snipory_core_portable`。

- [ ] **Step 5: 实现检查运算和 RAII 预算**

所有乘法先验证 `width > max / height`，缓冲采用 BGRA8 premultiplied，stride 为 `width * 4`；构造失败返回显式错误，不用 `bad_alloc` 表示预算超限。

- [ ] **Step 6: 运行 portable 与现有 Core 回归**

```bash
cmake -S . -B build -DBUILD_TESTING=ON
cmake --build build --target test_portable_geometry test_pixel_buffer
ctest --test-dir build -R 'portable_geometry|pixel_buffer' --output-on-failure
ctest --test-dir build --output-on-failure
```

预期：新测试 100% 通过；现有失败数不得超过基线，任何变化都先定位再提交。

- [ ] **Step 7: 提交 portable core**

```bash
git add CMakeLists.txt core/CMakeLists.txt core/include/snipory/core/portable core/src/portable core/tests/TestPortableGeometry.cpp core/tests/TestPixelBuffer.cpp
git commit -m "refactor(core): add Qt-free capture primitives"
```

## Task 3: 实现截图会话状态机

**Files:**
- Create: `platforms/win/src/session/CaptureSessionStateMachine.h`
- Create: `platforms/win/src/session/CaptureSessionStateMachine.cpp`
- Create: `platforms/win/tests/TestCaptureSessionStateMachine.cpp`
- Modify: `platforms/win/CMakeLists.txt`

- [ ] **Step 1: 写状态转换失败测试**

固定状态 `idle, capturing, selecting, ready, exporting` 和事件 `start, captureSucceeded, selectionCreated, exportStarted, complete, cancel, fail`。断言非 idle 的第二次 `start` 返回 `busy`，任意状态的 `cancel/fail` 回到 idle，非法事件不改变状态。

- [ ] **Step 2: 添加测试目标并验证失败**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_capture_session_state_test
```

预期：编译失败，因为状态机尚未实现。

- [ ] **Step 3: 实现纯 C++ 状态机**

状态机不得包含 HWND 或后端对象。API 固定为：

```cpp
TransitionResult dispatch(SessionEvent event) noexcept;
CaptureSessionState state() const noexcept;
```

`TransitionResult` 返回 `accepted`、`busy` 或 `invalidTransition`，协调器负责用户提示。

- [ ] **Step 4: 运行测试并提交**

```powershell
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R capture_session_state --output-on-failure
```

预期：100% 通过。

```bash
git add platforms/win/CMakeLists.txt platforms/win/src/session platforms/win/tests/TestCaptureSessionStateMachine.cpp
git commit -m "feat(win): add capture session state machine"
```

## Task 4: 固化显示器拓扑、DPI 与 API 能力

**Files:**
- Create: `platforms/win/src/capture/CaptureTypes.h`
- Create: `platforms/win/src/capture/DisplayTopology.h`
- Create: `platforms/win/src/capture/DisplayTopology.cpp`
- Create: `platforms/win/src/support/RuntimeApis.h`
- Create: `platforms/win/src/support/RuntimeApis.cpp`
- Create: `platforms/win/tests/TestDisplayTopology.cpp`
- Modify: `platforms/win/CMakeLists.txt`

- [ ] **Step 1: 写可注入显示器枚举测试**

使用三块假显示器覆盖左侧负坐标、纵向旋转和 100%/150%/200% DPI，断言虚拟边界、指纹稳定性、DIP↔pixel 往返和枚举顺序无关。

- [ ] **Step 2: 写运行时 API 解析测试**

通过假 `GetProcAddress` 断言缺少 `GetDpiForMonitor`、`SetProcessDpiAwarenessContext` 时选择 Legacy 兼容路径，不产生静态调用。

- [ ] **Step 3: 运行测试并确认失败**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_display_topology_test
```

- [ ] **Step 4: 实现拓扑快照**

用 `EnumDisplayMonitors`、`GetMonitorInfoW` 和 `QueryDisplayConfig`；DPI API 经 `RuntimeApis` 动态解析。指纹按设备名、物理像素边界、DPI、旋转排序后做 FNV-1a 64-bit，禁止使用 `HMONITOR` 数值作为稳定标识。

- [ ] **Step 5: 运行 Modern x64/x86 测试并提交**

```powershell
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R display_topology --output-on-failure
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x86 -R display_topology --output-on-failure
```

预期：两个架构均 100% 通过。

```bash
git add platforms/win/CMakeLists.txt platforms/win/src/capture/CaptureTypes.h platforms/win/src/capture/DisplayTopology.* platforms/win/src/support/RuntimeApis.* platforms/win/tests/TestDisplayTopology.cpp
git commit -m "feat(win): snapshot display topology and DPI"
```

## Task 5: 实现 GDI 冻结桌面后端

**Files:**
- Create: `platforms/win/src/capture/CaptureBackend.h`
- Create: `platforms/win/src/capture/GdiCaptureBackend.h`
- Create: `platforms/win/src/capture/GdiCaptureBackend.cpp`
- Create: `platforms/win/src/support/WinHandle.h`
- Create: `platforms/win/tests/TestGdiCaptureBackend.cpp`
- Modify: `platforms/win/CMakeLists.txt`

- [ ] **Step 1: 写后端契约与像素测试**

在测试代码中生成确定的 4×3 BGRA 图案并画入 memory DC，经后端的 `captureDcRegionForTesting` 获取，逐像素断言通道顺序、alpha=255、top-down 行序。再注入 `BitBlt` 失败，断言返回 `systemFailure` 和原始 `GetLastError`。

- [ ] **Step 2: 写预算与逐屏分配测试**

两块显示器总量超过 x86 512 MiB 时必须在第二块分配前返回 `memoryLimit`，第一块 RAII 资源释放；禁止先创建虚拟桌面巨型 bitmap。

- [ ] **Step 3: 运行测试并确认失败**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_gdi_capture_test
```

- [ ] **Step 4: 实现 GDI 后端**

每屏使用 `CreateCompatibleDC` + top-down 32-bit `CreateDIBSection` + `BitBlt(..., SRCCOPY | CAPTUREBLT)`；成功后复制到 `PixelBuffer`。所有 HDC/HBITMAP 使用 `WinHandle` 定制 RAII，恢复被选入 DC 的旧对象。

- [ ] **Step 5: 运行测试并提交**

```powershell
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R gdi_capture --output-on-failure
```

预期：100% 通过。

```bash
git add platforms/win/CMakeLists.txt platforms/win/src/capture/CaptureBackend.h platforms/win/src/capture/GdiCaptureBackend.* platforms/win/src/support/WinHandle.h platforms/win/tests/TestGdiCaptureBackend.cpp
git commit -m "feat(win): capture frozen displays with GDI"
```

## Task 6: 实现 DXGI 后端与确定性降级链

**Files:**
- Create: `platforms/win/src/capture/DxgiCaptureBackend.h`
- Create: `platforms/win/src/capture/DxgiCaptureBackend.cpp`
- Create: `platforms/win/src/capture/FallbackCaptureBackend.h`
- Create: `platforms/win/src/capture/FallbackCaptureBackend.cpp`
- Create: `platforms/win/tests/TestFallbackCaptureBackend.cpp`
- Modify: `platforms/win/CMakeLists.txt`

- [ ] **Step 1: 写降级顺序失败测试**

用假后端记录调用序列，覆盖：DXGI 首次成功；`deviceLost` 后 reset + 重试成功；第二次失败后 GDI 成功；`accessDenied/noFrame/systemFailure` 直接转 GDI；`memoryLimit` 不重试也不转 GDI。

- [ ] **Step 2: 写 DXGI 映射错误测试**

固定映射：`DXGI_ERROR_ACCESS_LOST → deviceLost`、`DXGI_ERROR_WAIT_TIMEOUT → noFrame`、`E_ACCESSDENIED → accessDenied`，其余 HRESULT → `systemFailure`。

- [ ] **Step 3: 实现 Desktop Duplication**

按显示器/adapter 建立 D3D11 device，`DuplicateOutput` 后 `AcquireNextFrame`，复制到 CPU staging texture，再写入统一 BGRA buffer；保证 `ReleaseFrame` 在所有返回路径执行。不得以全黑像素作为失败条件。

- [ ] **Step 4: 链接系统库并运行测试**

Windows target 链接 `d3d11 dxgi d2d1 dwrite windowscodecs shcore`，但 Legacy 可选 API 仍走动态解析。

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_fallback_capture_test
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R fallback_capture --output-on-failure
```

预期：100% 通过。

- [ ] **Step 5: 提交后端链**

```bash
git add platforms/win/CMakeLists.txt platforms/win/src/capture/DxgiCaptureBackend.* platforms/win/src/capture/FallbackCaptureBackend.* platforms/win/tests/TestFallbackCaptureBackend.cpp
git commit -m "feat(win): add DXGI capture with GDI fallback"
```

## Task 7: 实现选区几何、命中和输入状态

**Files:**
- Create: `platforms/win/src/overlay/SelectionModel.h`
- Create: `platforms/win/src/overlay/SelectionModel.cpp`
- Create: `platforms/win/tests/TestSelectionModel.cpp`
- Modify: `platforms/win/CMakeLists.txt`

- [ ] **Step 1: 写创建、标准化和最小尺寸测试**

从四个方向拖动均得到相同标准化矩形；零移动不进入 ready；最小选区固定为 1×1 physical pixel。

- [ ] **Step 2: 写移动和八方向缩放测试**

覆盖 N/NE/E/SE/S/SW/W/NW 命中、拖过对边后的 handle 翻转、跨屏负坐标、虚拟边界夹取。移动保持尺寸，缩放只改对应边。

- [ ] **Step 3: 写 DPI 无关性测试**

同一 physical selection 在 100%/150%/200% 下导出矩形完全相同；仅命中区和绘制布局按当前显示器 DPI 转换。

- [ ] **Step 4: 实现平台无关模型并运行测试**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_selection_model_test
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R selection_model --output-on-failure
```

预期：100% 通过。

- [ ] **Step 5: 提交选区模型**

```bash
git add platforms/win/CMakeLists.txt platforms/win/src/overlay/SelectionModel.* platforms/win/tests/TestSelectionModel.cpp
git commit -m "feat(win): add cross-display selection model"
```

## Task 8: 锁定 macOS 视觉常量与原始资源

**Files:**
- Create: `platforms/win/src/overlay/VisualStyleCatalog.h`
- Create: `platforms/win/resources/resource.h`
- Create: `platforms/win/resources/xxsnap.rc`
- Create: `tools/windows/verify-assets.ps1`
- Create: `platforms/win/tests/TestVisualStyleCatalog.cpp`
- Modify: `platforms/win/CMakeLists.txt`

- [ ] **Step 1: 写样式清单失败测试**

固定 macOS 已核对值：

```cpp
static_assert(VisualStyleCatalog::selectionColor == Rgba8{83, 120, 232, 255});
static_assert(VisualStyleCatalog::dimAlpha == 0.34f);
static_assert(VisualStyleCatalog::selectionBorderDip == 2.0f);
static_assert(VisualStyleCatalog::toolbarHeightDip == 28.0f);
static_assert(VisualStyleCatalog::buttonSizeDip == 20.0f);
static_assert(VisualStyleCatalog::buttonStepDip == 28.0f);
static_assert(VisualStyleCatalog::horizontalPaddingDip == 4.0f);
static_assert(VisualStyleCatalog::mvpToolbarWidthDip == 144.0f);
```

再断言 MVP 操作顺序严格为 `cancel, save, copy`，不含未实现功能。

- [ ] **Step 2: 写资源 SHA-256 验证脚本**

脚本必须检查以下原文件，失败时输出文件名、期望值和实际值：

```text
cancel-capture.png     5a0a437c72735a37218286e58549bc46442e8f50ff6462f94b5f970b2171c2ad
save-to-file.png       b31ea77ff9937c431f3d57ef9afac2e35e68b23d398b6071c26ccdf72753dc1d
copy-to-clipboard.png  60b5e93a85fe7a94d02641775c9fdef446d6cdbc3abcfa00ebdfc3715ecff7ba
settings-more.png      5ce11d2a89c0e9ebaee879ff2728691f871362f1822766564b29de76c11726c1
```

MVP 工具栏嵌入前三个 48×48 RGBA PNG；`settings-more.png` 只做基线校验，不显示。资源通过 `.rc` 的 `RCDATA` 直接引用 `platforms/mac/Resources/Icons`，不得复制、重绘、变色或生成替代文件。

- [ ] **Step 3: 运行 hash 和样式测试**

```powershell
.\tools\windows\verify-assets.ps1
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_visual_style_test
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R visual_style --output-on-failure
```

预期：显示四个 `OK`，测试 100% 通过。

- [ ] **Step 4: 提交视觉契约**

```bash
git add platforms/win/CMakeLists.txt platforms/win/src/overlay/VisualStyleCatalog.h platforms/win/resources/resource.h platforms/win/resources/xxsnap.rc platforms/win/tests/TestVisualStyleCatalog.cpp tools/windows/verify-assets.ps1
git commit -m "feat(win): lock macOS visual assets and metrics"
```

## Task 9: 实现跨屏像素合成器

**Files:**
- Create: `platforms/win/src/export/SelectionComposer.h`
- Create: `platforms/win/src/export/SelectionComposer.cpp`
- Create: `platforms/win/tests/TestSelectionComposer.cpp`
- Modify: `platforms/win/CMakeLists.txt`

- [ ] **Step 1: 写单屏裁剪测试**

用带坐标编码的 8×6 BGRA buffer 裁剪 `{2,1,3,4}`，逐像素验证结果尺寸和颜色。

- [ ] **Step 2: 写跨屏与透明空洞测试**

左屏 `{-4,0,4,4}`、右屏 `{2,0,4,4}`，选区 `{-2,1,7,2}`。断言输出 7×2、左右来源正确、中间两列 BGRA `{0,0,0,0}`。

- [ ] **Step 3: 写预算与越界测试**

输出超过当前架构预算返回 `memoryLimit`；完全不与任何显示器相交返回透明像素而不是读取越界。

- [ ] **Step 4: 实现 stride-aware 合成并运行测试**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_selection_composer_test
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R selection_composer --output-on-failure
```

预期：100% 通过。

- [ ] **Step 5: 提交合成器**

```bash
git add platforms/win/CMakeLists.txt platforms/win/src/export/SelectionComposer.* platforms/win/tests/TestSelectionComposer.cpp
git commit -m "feat(win): compose selections from frozen displays"
```

## Task 10: 实现剪贴板与原子 PNG 保存

**Files:**
- Create: `platforms/win/src/export/ClipboardWriter.h`
- Create: `platforms/win/src/export/ClipboardWriter.cpp`
- Create: `platforms/win/src/export/PngWriter.h`
- Create: `platforms/win/src/export/PngWriter.cpp`
- Create: `platforms/win/tests/TestClipboardWriter.cpp`
- Create: `platforms/win/tests/TestPngWriter.cpp`
- Modify: `platforms/win/CMakeLists.txt`

- [ ] **Step 1: 写 `CF_DIBV5` 布局测试**

断言 header 为 `BITMAPV5HEADER`、负高度表示 top-down、32-bit BGRA、alpha mask 正确、透明空洞保留 alpha=0。把 DIB 构造函数保持为纯内存函数以便单测。

- [ ] **Step 2: 写剪贴板重试测试**

注入前两次 `OpenClipboard` 失败、第三次成功，断言最多 3 次，退避 10/25 ms；三次失败返回稳定错误码且不丢失调用方持有的最终 `PixelBuffer`。

- [ ] **Step 3: 写 WIC PNG 与原子替换测试**

编码 3×2 含 alpha 图案，再用 WIC 解码验证像素。目标已存在且编码失败时，原文件 hash 不变、同目录临时文件被清理；成功时才调用 `MoveFileExW(REPLACE_EXISTING | WRITE_THROUGH)`。

- [ ] **Step 4: 实现双格式剪贴板和 PNG**

至少写入 `CF_DIBV5`；注册 `PNG` 格式并写入 WIC 生成的 PNG stream。`EmptyClipboard` 后任何失败都返回显式结果；HGLOBAL 所有权只在 `SetClipboardData` 成功后移交系统。

- [ ] **Step 5: 运行测试并提交**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_clipboard_writer_test xxsnap_png_writer_test
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R 'clipboard_writer|png_writer' --output-on-failure
```

预期：100% 通过。

```bash
git add platforms/win/CMakeLists.txt platforms/win/src/export/ClipboardWriter.* platforms/win/src/export/PngWriter.* platforms/win/tests/TestClipboardWriter.cpp platforms/win/tests/TestPngWriter.cpp
git commit -m "feat(win): export captures to clipboard and PNG"
```

## Task 11: 实现 Direct2D 浮层绘制

**Files:**
- Create: `platforms/win/src/overlay/OverlayWindow.h`
- Create: `platforms/win/src/overlay/OverlayWindow.cpp`
- Create: `platforms/win/src/overlay/OverlayRenderer.h`
- Create: `platforms/win/src/overlay/OverlayRenderer.cpp`
- Create: `platforms/win/tests/TestOverlayLayout.cpp`
- Modify: `platforms/win/CMakeLists.txt`

- [ ] **Step 1: 写纯布局失败测试**

把尺寸标签、8 个 handle、工具栏和 3 个按钮的 DIP 矩形计算抽为纯函数。覆盖选区靠近屏幕四边时工具栏翻转/夹取、100/125/150/200% DPI，断言按钮顺序和 144 DIP 宽度不变。

- [ ] **Step 2: 创建测试用固定渲染输入**

背景使用 640×360 彩色网格，选区 `{160,90,320,180}`。布局测试输出 JSON 清单，键固定为 `mask, border, sizeLabel, toolbar, cancel, save, copy, handles`，用于后续视觉金图。

- [ ] **Step 3: 实现每屏无边框浮层**

窗口样式：`WS_POPUP`；扩展样式：`WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE`。在 `WM_DPICHANGED` 时通知会话协调器重启，不就地修补冻结会话。背景只绘制 `FrozenDisplay`，不重新截图。

- [ ] **Step 4: 实现 macOS 样式绘制**

使用 Direct2D 绘制 34% 遮罩、#5378E8 2 DIP 边框、尺寸标签、工具栏；按钮 PNG 经 WIC 从 RCDATA 解码，不做 tint。文字内容、字号、字重从 `VisualStyleCatalog` 读取。

- [ ] **Step 5: 运行布局测试**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_overlay_layout_test
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R overlay_layout --output-on-failure
```

预期：100% 通过。

- [ ] **Step 6: 提交绘制层**

```bash
git add platforms/win/CMakeLists.txt platforms/win/src/overlay/OverlayWindow.* platforms/win/src/overlay/OverlayRenderer.* platforms/win/tests/TestOverlayLayout.cpp
git commit -m "feat(win): render macOS-matched capture overlay"
```

## Task 12: 实现多窗口输入编排与选区操作

**Files:**
- Create: `platforms/win/src/overlay/OverlayHost.h`
- Create: `platforms/win/src/overlay/OverlayHost.cpp`
- Create: `platforms/win/tests/TestOverlayInputRouting.cpp`
- Modify: `platforms/win/src/overlay/OverlayWindow.cpp`
- Modify: `platforms/win/CMakeLists.txt`

- [ ] **Step 1: 写跨窗口输入路由测试**

模拟鼠标在左屏按下、跨越主屏、在右屏释放；断言所有 client 坐标先转为 virtual physical pixel，再进入同一个 `SelectionModel`。窗口失去 capture、Esc、cancel 都产生一次取消事件。

- [ ] **Step 2: 写动作命中测试**

工具栏 cancel/save/copy 命中优先于选区移动；handle 命中优先于内部移动；空白区域开始新选区。处于 ready 时显示尺寸标签和工具栏，selecting 时不显示工具栏。

- [ ] **Step 3: 实现每屏 HWND 和共享鼠标捕获**

`OverlayHost` 为拓扑中的每屏创建一个 `OverlayWindow`，共享模型和 action callback。拖动开始时 `SetCapture`，跨屏移动使用 `GetCursorPos` 获取 virtual screen 坐标，结束后 `ReleaseCapture`。

- [ ] **Step 4: 运行测试并进行 VM 手工冒烟**

```powershell
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R overlay_input --output-on-failure
```

随后在 Parallels 设置 100%、125%、150%、200% 四种缩放，验证创建、移动和八方向缩放；每次记录截图到构建目录，不提交人工截图。

- [ ] **Step 5: 提交输入层**

```bash
git add platforms/win/CMakeLists.txt platforms/win/src/overlay/OverlayHost.* platforms/win/src/overlay/OverlayWindow.cpp platforms/win/tests/TestOverlayInputRouting.cpp
git commit -m "feat(win): route multi-display overlay input"
```

## Task 13: 实现单实例、托盘和全局快捷键

**Files:**
- Create: `platforms/win/src/app/SingleInstance.h`
- Create: `platforms/win/src/app/SingleInstance.cpp`
- Create: `platforms/win/src/app/TrayIcon.h`
- Create: `platforms/win/src/app/TrayIcon.cpp`
- Create: `platforms/win/src/app/HotKeyRegistrar.h`
- Create: `platforms/win/src/app/HotKeyRegistrar.cpp`
- Create: `platforms/win/tests/TestAppEntryServices.cpp`
- Modify: `platforms/win/CMakeLists.txt`

- [ ] **Step 1: 写依赖注入的服务测试**

覆盖：第二实例通过命名消息触发首实例后退出；`RegisterHotKey` 冲突保留托盘；不会自动改键；Explorer 重启后的 `TaskbarCreated` 会重新添加图标；退出时注销快捷键和托盘图标。

- [ ] **Step 2: 固定用户可见入口**

托盘菜单 MVP 只包含“区域截图”和“退出”；菜单顺序与 macOS 对应入口一致。macOS 默认区域截图为 Command+`，Windows 固定采用语义对应的 Ctrl+`（`MOD_CONTROL | VK_OEM_3`），并在测试中锁定；快捷键设置 UI 不进入 MVP。

- [ ] **Step 3: 实现服务**

使用命名 mutex + `RegisterWindowMessageW`；托盘使用 `Shell_NotifyIconW(NIM_ADD/NIM_SETVERSION)`；快捷键使用 `RegisterHotKey`。冲突保存 `GetLastError` 并通过托盘气泡或消息框明确提示。

- [ ] **Step 4: 运行测试并提交**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_app_entry_services_test
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R app_entry_services --output-on-failure
```

预期：100% 通过。

```bash
git add platforms/win/CMakeLists.txt platforms/win/src/app/SingleInstance.* platforms/win/src/app/TrayIcon.* platforms/win/src/app/HotKeyRegistrar.* platforms/win/tests/TestAppEntryServices.cpp
git commit -m "feat(win): add tray hotkey and single instance"
```

## Task 14: 组装完整截图会话与 Windows EXE

**Files:**
- Create: `platforms/win/src/session/CaptureSessionCoordinator.h`
- Create: `platforms/win/src/session/CaptureSessionCoordinator.cpp`
- Create: `platforms/win/src/app/AppHost.h`
- Create: `platforms/win/src/app/AppHost.cpp`
- Create: `platforms/win/src/app/WinMain.cpp`
- Create: `platforms/win/tests/TestCaptureSessionCoordinator.cpp`
- Modify: `platforms/win/CMakeLists.txt`

- [ ] **Step 1: 写协调器端到端失败测试**

用 fake topology/capture/overlay/export 依赖覆盖：

```text
start → snapshot topology → capture → recheck topology → show overlay
copy → compose once → clipboard → teardown → idle
save → compose once → file dialog result → WIC save → teardown → idle
cancel/Esc → no compose → teardown → idle
```

断言复制/保存不调用第二次 capture。

- [ ] **Step 2: 写拓扑重试与错误测试**

捕获后指纹变化时完整重试一次；会话中 `WM_DISPLAYCHANGE/WM_DPICHANGED` 也只重试一次；第二次变化提示失败。覆盖 busy、capture failure、clipboard failure、save cancel、save failure，并断言所有路径释放浮层和回到 idle。

- [ ] **Step 3: 实现协调器**

协调器拥有 `FrozenDesktop` 到会话结束；x86 预算 512 MiB，x64 预算 2 GiB。剪贴板失败时把最终 `PixelBuffer` 移入进程内 recent capture slot，但 MVP 不新增恢复入口。

- [ ] **Step 4: 实现 AppHost 和 `wWinMain`**

进程启动前设置最佳可用 DPI awareness；创建隐藏消息窗口、COM apartment、D2D/DWrite/WIC 工厂、托盘、快捷键和消息循环。Release 目标为 `WIN32` subsystem，不弹控制台。

- [ ] **Step 5: 运行自动化与手工闭环**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_windows xxsnap_capture_session_coordinator_test
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R capture_session_coordinator --output-on-failure
& C:\Users\kevin\build\xxsnap-modern-x64\platforms\win\xxsnap_windows.exe
```

手工完成：托盘启动、快捷键启动、创建/移动/八方向缩放、copy 粘贴到 Paint、save 后重新打开 PNG、Esc、cancel、第二实例。预期所有操作闭环且浮层本身不出现在输出中。

- [ ] **Step 6: 提交可运行 MVP**

```bash
git add platforms/win/CMakeLists.txt platforms/win/src/session/CaptureSessionCoordinator.* platforms/win/src/app/AppHost.* platforms/win/src/app/WinMain.cpp platforms/win/tests/TestCaptureSessionCoordinator.cpp
git commit -m "feat(win): deliver region capture application flow"
```

## Task 15: 验证 Modern x64/x86 和内存边界

**Files:**
- Create: `tools/windows/run-modern-matrix.ps1`
- Create: `tools/windows/measure-capture.ps1`
- Create: `platforms/win/tests/TestMemoryBudgetMatrix.cpp`
- Modify: `platforms/win/CMakeLists.txt`
- Modify: `platforms/win/packaging/README.md`

- [ ] **Step 1: 写架构预算测试**

x86 编译断言 512 MiB，x64 编译断言 2 GiB；模拟双 4K、三 4K、超大虚拟桌面，验证在分配前拒绝且无 32 位溢出。

- [ ] **Step 2: 创建全量矩阵脚本**

脚本清理各自 NTFS 构建目录后配置、Release 构建、CTest；输出 exe 架构（`dumpbin /headers`）和测试摘要，任一步失败即非零退出。

- [ ] **Step 3: 创建统一性能计时**

从 `WM_HOTKEY`/托盘命令进入协调器开始，到所有 overlay 首次完成 present 结束。脚本跑 30 次，丢弃 3 次预热，输出 P50/P95 与后端，不记录屏幕内容。

- [ ] **Step 4: 运行 Modern 矩阵**

```powershell
.\tools\windows\run-modern-matrix.ps1
.\tools\windows\measure-capture.ps1 -Arch x64 -Iterations 30
.\tools\windows\measure-capture.ps1 -Arch x86 -Iterations 30
```

预期：x64/x86 所有测试通过；VM 性能只记录趋势。原生双 4K x64 发布门槛 P95 ≤ 250 ms，交互目标 60 FPS。

- [ ] **Step 5: 提交 Modern 验证设施**

```bash
git add platforms/win/CMakeLists.txt platforms/win/tests/TestMemoryBudgetMatrix.cpp platforms/win/packaging/README.md tools/windows/run-modern-matrix.ps1 tools/windows/measure-capture.ps1
git commit -m "test(win): verify modern architecture matrix"
```

## Task 16: 建立 Windows 7 Legacy 兼容门禁

**Files:**
- Create: `tools/windows/verify-imports.ps1`
- Create: `tools/windows/run-legacy-matrix.ps1`
- Create: `platforms/win/tests/TestLegacyRuntimeApis.cpp`
- Create: `platforms/win/tests/allowed-win7-imports.txt`
- Modify: `cmake/windows/LegacyWindows7.cmake`
- Modify: `platforms/win/CMakeLists.txt`

- [ ] **Step 1: 写 API 能力降级测试**

在所有 Modern-only API 为空时，断言 DPI 走兼容映射、capture 选择 GDI、应用仍能启动。Legacy 代码不得静态引用 `SetProcessDpiAwarenessContext`、`GetDpiForWindow`、`GetSystemMetricsForDpi` 等 Windows 7 缺失入口。

- [ ] **Step 2: 写 PE 导入表检查**

`verify-imports.ps1` 用 `dumpbin /imports` 读取 EXE/DLL，将系统 DLL/符号与 `allowed-win7-imports.txt` 比较。出现不在 allowlist 的入口立即失败；禁止仅凭 `_WIN32_WINNT` 认为兼容。

- [ ] **Step 3: 用固定工具链构建 x64/x86**

```powershell
.\tools\windows\build-legacy.ps1 -Arch x64 -Target xxsnap_windows
.\tools\windows\build-legacy.ps1 -Arch x86 -Target xxsnap_windows
.\tools\windows\verify-imports.ps1 -Binary C:\Users\kevin\build\xxsnap-legacy-x64\platforms\win\xxsnap_windows.exe
.\tools\windows\verify-imports.ps1 -Binary C:\Users\kevin\build\xxsnap-legacy-x86\platforms\win\xxsnap_windows.exe
```

预期：PE 架构分别为 x64/x86，import audit 通过。

- [ ] **Step 4: 在隔离 Windows 7 SP1 环境运行**

环境必须装 Platform Update 和 SHA-2 更新且不连接不受控公网。x64/x86 各运行全套 CTest 和 Task 14 手工闭环；Legacy 1080p 参考机截图到浮层 P95 ≤ 500 ms，交互 ≥ 30 FPS。

- [ ] **Step 5: 提交 Legacy 门禁**

```bash
git add cmake/windows/LegacyWindows7.cmake platforms/win/CMakeLists.txt platforms/win/tests/TestLegacyRuntimeApis.cpp platforms/win/tests/allowed-win7-imports.txt tools/windows/verify-imports.ps1 tools/windows/run-legacy-matrix.ps1
git commit -m "test(win): enforce Windows 7 runtime compatibility"
```

## Task 17: 生成并门禁四个安装包

**Files:**
- Create: `platforms/win/packaging/Product.wxs`
- Create: `platforms/win/packaging/PackageMatrix.json`
- Create: `platforms/win/packaging/License.rtf`
- Create: `.config/dotnet-tools.json`
- Create: `tools/windows/build-installers.ps1`
- Create: `tools/windows/test-installers.ps1`
- Modify: `platforms/win/packaging/README.md`

- [ ] **Step 1: 固定四包身份**

`PackageMatrix.json` 为四个包配置不同 UpgradeCode、安装目录和显示名：

```text
XxSnap-Modern-x64
XxSnap-Modern-x86
XxSnap-Legacy-x64
XxSnap-Legacy-x86
```

Modern 与 Legacy 不共享 UpgradeCode，不能互相覆盖；同一 family 的版本升级可替换旧版。

- [ ] **Step 2: 写安装条件测试**

矩阵必须断言：Modern x64 只接受 Win10/11 x64；Modern x86 只接受 Win10 32 位；Legacy x64/x86 只接受 Windows 7 SP1 对应架构，并检查 Platform Update 与 SHA-2 前置条件。错误包显示明确提示并返回失败，不能静默继续。

- [ ] **Step 3: 实现 WiX 4 安装器**

仓库通过 `.config/dotnet-tools.json` 固定 WiX Toolset `4.0.6`，先运行 `dotnet tool restore`。安装器包含版本化 EXE、VC runtime、`Snipory.ico`、许可证、开始菜单/卸载信息。安装器文件名固定为 `<name>-<semver>.msi`；签名步骤要求 `XXSNAP_SIGN_CERT_THUMBPRINT`，Release 无签名时失败，local debug 可显式 `-AllowUnsigned`。

- [ ] **Step 4: 构建四包并检查内容**

```powershell
.\tools\windows\build-installers.ps1 -Version 0.1.0 -AllowUnsigned
.\tools\windows\test-installers.ps1 -Directory C:\Users\kevin\build\xxsnap-installers
```

预期：恰好 4 个 MSI；架构、ProductName、UpgradeCode、LaunchCondition、文件 hash 检查全部通过。

- [ ] **Step 5: 在六个发布环境执行安装验收**

Windows 11 x64、Windows 10 x64、Windows 10 x86、Windows 7 x64、Windows 7 x86 分别验证正确包的安装/启动/升级/卸载，并至少在一个错误架构/系统上验证每条阻止条件。Windows 11 不提供也不宣传 x86 包。

- [ ] **Step 6: 提交打包实现**

```bash
git add .config/dotnet-tools.json platforms/win/packaging tools/windows/build-installers.ps1 tools/windows/test-installers.ps1
git commit -m "build(win): package four gated Windows installers"
```

## Task 18: 建立视觉金图、CI 和最终回归

**Files:**
- Create: `platforms/win/tests/visual/README.md`
- Create: `platforms/win/tests/visual/overlay-fixture.json`
- Create: `platforms/win/tests/visual/compare-overlay.ps1`
- Create: `.github/workflows/windows-modern.yml`
- Create: `.github/workflows/windows-legacy.yml`
- Modify: `platforms/win/src/README.md`
- Modify: `platforms/win/tests/README.md`
- Modify: `README.md`

- [ ] **Step 1: 固定视觉基准流程**

基准输入与 Task 11 相同，在 100/125/150/200% DPI 输出 PNG 和布局 JSON。比较器对非文字区域做逐像素颜色/几何精确比较；DirectWrite 与 CoreText 的文字边缘只允许预先定义的抗锯齿容差，不能扩大到控件、图标、间距或边框。

- [ ] **Step 2: 生成并人工核对第一版金图**

在 Windows 渲染结果与当前 macOS 截图并排核对。任何图标、顺序、颜色、尺寸、间距、圆角、描边、遮罩或命中区差异都先修实现；不得通过更新金图接受差异。确认后提交基准及来源说明。

- [ ] **Step 3: 配置 CI 矩阵**

Modern workflow 构建 x64/x86、运行 CTest、hash 和 visual checks。Legacy workflow 只运行在已隔离且带固定 VS2019/v142/SDK 的 self-hosted Windows 7 runners；若无 runner 则 job 明确保持 pending/required，不假装通过。

- [ ] **Step 4: 运行最终全量验证**

macOS：

```bash
cmake -S . -B build -DBUILD_TESTING=ON
cmake --build build
ctest --test-dir build --output-on-failure
```

Windows：

```powershell
.\tools\windows\verify-assets.ps1
.\tools\windows\run-modern-matrix.ps1
.\tools\windows\run-legacy-matrix.ps1
.\tools\windows\test-installers.ps1 -Directory C:\Users\kevin\build\xxsnap-installers
.\platforms\win\tests\visual\compare-overlay.ps1
```

预期：Windows 新测试全部通过；macOS/Core 不新增基线失败；四包安装矩阵和视觉比较全部通过。把真实结果、环境和已知基线失败写入 `platforms/win/tests/README.md`。

- [ ] **Step 5: 完成文档和最终提交**

`platforms/win/src/README.md` 记录模块边界和错误降级；测试 README 记录六环境矩阵；根 README 只声明已经验证过的 Windows 能力，不提前宣传后续功能。

```bash
git add .github/workflows/windows-modern.yml .github/workflows/windows-legacy.yml platforms/win/tests/visual platforms/win/src/README.md platforms/win/tests/README.md README.md
git commit -m "test(win): add release and visual verification gates"
```

## 完成定义

只有以下项目全部成立，计划才可标记完成：

- 四个安装包在规定环境安装、升级、启动、截图和卸载通过，错误系统/架构被阻止。
- 托盘、默认快捷键、冻结桌面、创建/移动/八向缩放、尺寸标签、copy/save/cancel/Esc 全部可用。
- 复制和保存只使用会话开始时的同一份冻结像素。
- 多显示器负坐标、旋转、混合 DPI、跨屏透明空洞和拓扑变化均有自动化覆盖。
- DXGI reset/retry/GDI fallback、GDI 失败、预算超限、剪贴板占用和原子保存失败均有测试。
- MVP 图标字节与 macOS 原资源 hash 一致；所有视觉常量和四档 DPI 金图通过。
- Modern x64/x86、Legacy x64/x86 的 PE 架构和 Windows 7 import audit 通过。
- 原生参考环境达到 Modern/Legacy 性能门槛。
- macOS/Core 没有新增失败，用户原有修改保持不变。
