# Windows Toolbar Parity Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the tested Windows toolbar catalog, DIP layout, resource pipeline, state model, renderer integration, and shared hit-testing foundation required to reproduce the macOS toolbar exactly without exposing unfinished feature buttons.

**Architecture:** A portable C++17 toolbar domain owns action order, icon specifications, visibility, and layout in DIPs. The Direct2D renderer and Win32 input router consume the same computed layout, while a deterministic macOS resource generator derives DPI-specific PNGs from the unchanged macOS SVG sources for Modern and Legacy Windows. The current user-visible toolbar remains cancel/save/copy until later feature plans connect each additional action to real behavior.

**Tech Stack:** C++17, Win32, Direct2D, WIC, CMake, CTest, PowerShell 5.1, Swift/AppKit asset generation, MSVC v145 Modern, MSVC v142 Legacy.

**Design:** `docs/superpowers/specs/2026-08-06-windows-full-feature-parity-design.md`

---

## File map

New focused units:

- `platforms/win/src/toolbar/ToolbarCatalog.h`: immutable macOS parity metrics, action order, groups, and icon metadata.
- `platforms/win/src/toolbar/ToolbarLayout.h/.cpp`: pure DIP layout and hit-testing shared by rendering and input.
- `platforms/win/src/toolbar/ToolbarState.h/.cpp`: visible actions and selected/enabled state; defaults to the three currently functional terminal actions.
- `platforms/win/tests/TestToolbarCatalog.cpp`: exact order, metrics, icon mapping, and resource contract.
- `platforms/win/tests/TestToolbarLayout.cpp`: width, positions, extra gaps, constrained placement, and DPI conversion tests.
- `platforms/win/tests/TestToolbarState.cpp`: visibility and enablement tests preventing unfinished buttons from appearing.
- `platforms/win/resources/toolbar/ToolbarAssets.json`: source-resource manifest and generated-size contract.
- `platforms/win/resources/toolbar/{100,125,150,200}/`: mechanically derived PNG resources.
- `tools/windows/generate-toolbar-assets.swift`: deterministic AppKit SVG-to-PNG generator run on macOS.
- `tools/windows/verify-toolbar-assets.ps1`: Windows-side source hash, generated dimensions, and alpha decode verification.

Existing integration points:

- `platforms/win/src/overlay/OverlayRenderer.h/.cpp`: consume toolbar layout and catalog; stop owning button geometry.
- `platforms/win/src/overlay/OverlayHost.h/.cpp`: consume the same layout for terminal-action hit testing.
- `platforms/win/src/overlay/VisualStyleCatalog.h`: retain selection/label styles; remove toolbar action order and width ownership.
- `platforms/win/resources/resource.h` and `xxsnap.rc`: embed the complete generated resource set.
- `platforms/win/CMakeLists.txt`: add libraries, tests, asset verification, and dependencies.

## Task 1: Lock the macOS toolbar catalog

**Files:**
- Create: `platforms/win/src/toolbar/ToolbarCatalog.h`
- Create: `platforms/win/tests/TestToolbarCatalog.cpp`
- Modify: `platforms/win/CMakeLists.txt`
- Modify: `platforms/win/src/overlay/VisualStyleCatalog.h`

- [ ] **Step 1: Write the failing catalog test**

Create a test that includes the not-yet-existing catalog and asserts the complete contract:

```cpp
#include "toolbar/ToolbarCatalog.h"

#include <array>
#include <cstdlib>

using namespace xxsnap::win;

int main()
{
    static_assert(ToolbarMetrics::heightDip == 28.0F);
    static_assert(ToolbarMetrics::buttonSizeDip == 20.0F);
    static_assert(ToolbarMetrics::buttonStepDip == 28.0F);
    static_assert(ToolbarMetrics::horizontalPaddingDip == 4.0F);
    static_assert(ToolbarMetrics::groupGapDip == 8.0F);
    static_assert(ToolbarMetrics::cornerRadiusDip == 6.0F);

    constexpr std::array expected{
        ToolbarAction::rectangle,
        ToolbarAction::polyline,
        ToolbarAction::pen,
        ToolbarAction::marker,
        ToolbarAction::eyedropper,
        ToolbarAction::mosaic,
        ToolbarAction::text,
        ToolbarAction::number,
        ToolbarAction::magnifier,
        ToolbarAction::eraser,
        ToolbarAction::scroll,
        ToolbarAction::undo,
        ToolbarAction::redo,
        ToolbarAction::cancel,
        ToolbarAction::pin,
        ToolbarAction::save,
        ToolbarAction::copy,
    };
    static_assert(fullToolbarActions() == expected);
    static_assert(toolbarIcon(ToolbarAction::rectangle).insetDip == -1.0F);
    static_assert(toolbarIcon(ToolbarAction::number).insetDip == 3.0F);
    static_assert(toolbarIcon(ToolbarAction::scroll).insetDip == 0.0F);
    static_assert(extraGapAfter(ToolbarAction::eraser) == 8.0F);
    static_assert(extraGapAfter(ToolbarAction::scroll) == 8.0F);
    static_assert(extraGapAfter(ToolbarAction::redo) == 8.0F);
    return EXIT_SUCCESS;
}
```

Register `xxsnap_toolbar_catalog_test` in CMake and add it to the `/W4 /WX /permissive-` target list.

- [ ] **Step 2: Run the test to verify RED**

Run in the Windows VM:

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_toolbar_catalog_test
```

Expected: compilation fails because `toolbar/ToolbarCatalog.h` does not exist.

- [ ] **Step 3: Implement the immutable catalog**

Define:

```cpp
enum class ToolbarAction : std::uint8_t {
    rectangle, polyline, pen, marker, eyedropper, mosaic, text, number,
    magnifier, eraser, scroll, undo, redo, cancel, pin, save, copy,
};

struct ToolbarIconSpec {
    ToolbarAction action;
    const wchar_t* resourceName;
    float insetDip;
    bool fixedColor;
};

struct ToolbarMetrics {
    inline static constexpr float heightDip = 28.0F;
    inline static constexpr float buttonSizeDip = 20.0F;
    inline static constexpr float buttonStepDip = 28.0F;
    inline static constexpr float horizontalPaddingDip = 4.0F;
    inline static constexpr float groupGapDip = 8.0F;
    inline static constexpr float cornerRadiusDip = 6.0F;
};
```

Provide `constexpr` `fullToolbarActions()`, `terminalToolbarActions()`, `toolbarIcon(action)`, and `extraGapAfter(action)` with the exact values approved in the design. Move only toolbar-owned constants out of `VisualStyleCatalog`; keep selection handles, dimming, label typography, and colors there.

- [ ] **Step 4: Run catalog and existing visual-style tests**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_toolbar_catalog_test
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R "toolbar_catalog|visual_style" --output-on-failure
```

Expected: both tests pass with zero warnings.

- [ ] **Step 5: Commit**

```bash
git add platforms/win/src/toolbar/ToolbarCatalog.h platforms/win/tests/TestToolbarCatalog.cpp platforms/win/src/overlay/VisualStyleCatalog.h platforms/win/CMakeLists.txt
git commit -m "feat(win): lock macOS toolbar parity catalog"
```

## Task 2: Compute all toolbar geometry in DIPs

**Files:**
- Create: `platforms/win/src/toolbar/ToolbarLayout.h`
- Create: `platforms/win/src/toolbar/ToolbarLayout.cpp`
- Create: `platforms/win/tests/TestToolbarLayout.cpp`
- Modify: `platforms/win/CMakeLists.txt`

- [ ] **Step 1: Write failing width and position tests**

Use these public types:

```cpp
struct ToolbarPoint { float x; float y; };
struct ToolbarRect { float x; float y; float width; float height; };
struct ToolbarItemLayout { ToolbarAction action; ToolbarRect rect; };
struct MainToolbarLayout {
    ToolbarRect bounds;
    ToolbarRect leadingDragHandle;
    ToolbarRect trailingDragHandle;
    std::vector<ToolbarItemLayout> items;
};

float toolbarWidth(const std::vector<ToolbarAction>& actions) noexcept;
MainToolbarLayout computeMainToolbarLayout(
    ToolbarPoint origin,
    const std::vector<ToolbarAction>& actions);
std::optional<ToolbarAction> toolbarActionAt(
    const MainToolbarLayout& layout,
    ToolbarPoint point) noexcept;
```

Assert:

```cpp
CHECK(toolbarWidth(vectorOf(terminalToolbarActions())) == 144.0F);
CHECK(toolbarWidth(vectorOf(fullToolbarActions())) == 560.0F);

const auto full = computeMainToolbarLayout({10.0F, 20.0F}, vectorOf(fullToolbarActions()));
CHECK(full.bounds == ToolbarRect{10.0F, 20.0F, 560.0F, 28.0F});
CHECK(full.leadingDragHandle == ToolbarRect{14.0F, 24.0F, 20.0F, 20.0F});
CHECK(full.items.front().rect == ToolbarRect{42.0F, 24.0F, 20.0F, 20.0F});
CHECK(full.items[10].rect.x - full.items[9].rect.x == 36.0F);
CHECK(full.items[11].rect.x - full.items[10].rect.x == 36.0F);
CHECK(full.items[13].rect.x - full.items[12].rect.x == 36.0F);
CHECK(full.trailingDragHandle == ToolbarRect{546.0F, 24.0F, 20.0F, 20.0F});
```

Also assert that a point on each item resolves to that item and points in drag handles or gaps return `std::nullopt`.

- [ ] **Step 2: Verify RED**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_toolbar_layout_test
```

Expected: target or source files do not exist.

- [ ] **Step 3: Implement minimal pure layout**

Calculate width with the exact macOS formula:

```cpp
float width = ToolbarMetrics::horizontalPaddingDip
    + ToolbarMetrics::buttonStepDip;
for (const auto action : actions) {
    width += ToolbarMetrics::buttonStepDip + extraGapAfter(action);
}
return width + ToolbarMetrics::buttonStepDip;
```

Place buttons at `origin.x + 4 + 28`, `origin.y + 4`; advance by `28 + extraGapAfter(action)`. Do not round DIP values in this layer.

- [ ] **Step 4: Run the layout test**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_toolbar_layout_test
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R toolbar_layout --output-on-failure
```

Expected: all catalog and layout assertions pass.

- [ ] **Step 5: Commit**

```bash
git add platforms/win/src/toolbar/ToolbarLayout.h platforms/win/src/toolbar/ToolbarLayout.cpp platforms/win/tests/TestToolbarLayout.cpp platforms/win/CMakeLists.txt
git commit -m "feat(win): compute macOS toolbar geometry"
```

## Task 3: Add deterministic macOS icon derivation and verification

**Files:**
- Create: `tools/windows/generate-toolbar-assets.swift`
- Create: `tools/windows/verify-toolbar-assets.ps1`
- Create: `platforms/win/resources/toolbar/ToolbarAssets.json`
- Create: `platforms/win/resources/toolbar/100/*.png`
- Create: `platforms/win/resources/toolbar/125/*.png`
- Create: `platforms/win/resources/toolbar/150/*.png`
- Create: `platforms/win/resources/toolbar/200/*.png`
- Modify: `tools/windows/verify-assets.ps1`

- [ ] **Step 1: Write a failing manifest verifier**

The PowerShell verifier must reject an empty or incomplete manifest and require exactly these 20 names:

```powershell
$expected = @(
    'settings-more', 'screenshot', 'arrow', 'pencil-tool', 'highlighter-tool',
    'straw-ranging', 'masaike2', 'text-tool', 'number-sequence',
    'zoom-in-tool', 'eraser-tool', 'scroll-screen2',
    'undo-enabled', 'undo-disabled', 'redo-enabled', 'redo-disabled',
    'cancel-capture', 'pin-to-screen', 'save-to-file', 'copy-to-clipboard'
)
```

The list contains 20 resources; assert count and uniqueness rather than relying on the prose count. Each entry must contain `name`, `source`, `sha256`, `logicalSizeDip`, `insetDip`, `fixedColor`, and generated files for scale keys `100`, `125`, `150`, `200`.

For every generated PNG, use WIC through `System.Drawing.Bitmap` only in the verifier to assert dimensions and a nonempty alpha channel. The expected pixel edge is `round(logicalSizeDip * scale / 100)`.

- [ ] **Step 2: Verify RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\windows\verify-toolbar-assets.ps1
```

Expected: failure because `ToolbarAssets.json` and generated resources do not exist.

- [ ] **Step 3: Implement the deterministic Swift generator**

The generator must:

1. Resolve the repository root from its own file location.
2. Read each approved source from `platforms/mac/Resources/Icons` without modifying it.
3. Prefer SVG when present; use PNG only when no SVG exists.
4. Render transparent PNGs at 100%, 125%, 150%, and 200% using `NSImage`, `NSBitmapImageRep`, and `.copy` interpolation disabled only when the source is already raster.
5. Write files atomically into the four generated directories.
6. Calculate SHA-256 using CryptoKit and write stable, sorted JSON.

Run:

```bash
swift tools/windows/generate-toolbar-assets.swift
```

Expected: four versions of every resource and a sorted manifest are generated.

- [ ] **Step 4: Run the verifier and existing asset lock**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\windows\verify-toolbar-assets.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\windows\verify-assets.ps1
```

Expected: both scripts pass; changing one source byte or one generated dimension makes verification fail.

- [ ] **Step 5: Commit generated assets and generators**

The repository ignores `docs/` but not these resource paths. Confirm no unrelated generated files are staged.

```bash
git add tools/windows/generate-toolbar-assets.swift tools/windows/verify-toolbar-assets.ps1 tools/windows/verify-assets.ps1 platforms/win/resources/toolbar
git commit -m "build(win): derive toolbar assets from macOS icons"
```

## Task 4: Model visible and enabled toolbar actions

**Files:**
- Create: `platforms/win/src/toolbar/ToolbarState.h`
- Create: `platforms/win/src/toolbar/ToolbarState.cpp`
- Create: `platforms/win/tests/TestToolbarState.cpp`
- Modify: `platforms/win/CMakeLists.txt`

- [ ] **Step 1: Write failing state tests**

Define the intended API in tests:

```cpp
ToolbarState state;
CHECK(state.visibleActions() == vectorOf(terminalToolbarActions()));
CHECK(!state.selectedAction().has_value());
CHECK(state.isEnabled(ToolbarAction::cancel));
CHECK(state.isEnabled(ToolbarAction::save));
CHECK(state.isEnabled(ToolbarAction::copy));
CHECK(!state.isVisible(ToolbarAction::rectangle));

state.setCapability(ToolbarAction::rectangle, true);
CHECK(state.isVisible(ToolbarAction::rectangle));
CHECK(state.selectTool(ToolbarAction::rectangle));
CHECK(state.selectedAction() == ToolbarAction::rectangle);

state.setHistoryAvailability(true, false);
CHECK(state.isEnabled(ToolbarAction::undo));
CHECK(!state.isEnabled(ToolbarAction::redo));
```

Also verify that terminal actions cannot become selected tools and that disabling a selected capability clears the selection.

- [ ] **Step 2: Verify RED**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_toolbar_state_test
```

Expected: target or header does not exist.

- [ ] **Step 3: Implement state without placeholders**

Default capabilities must be exactly cancel/save/copy. `setCapability` inserts newly completed actions according to `fullToolbarActions()` order, never call order. Undo and redo are visible only when their capabilities are enabled and are independently enabled by history availability.

- [ ] **Step 4: Run state, layout, and catalog tests**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_toolbar_state_test
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R "toolbar_(catalog|layout|state)" --output-on-failure
```

Expected: all three tests pass.

- [ ] **Step 5: Commit**

```bash
git add platforms/win/src/toolbar/ToolbarState.h platforms/win/src/toolbar/ToolbarState.cpp platforms/win/tests/TestToolbarState.cpp platforms/win/CMakeLists.txt
git commit -m "feat(win): gate toolbar actions by real capability"
```

## Task 5: Embed and decode the complete resource matrix

**Files:**
- Modify: `platforms/win/resources/resource.h`
- Modify: `platforms/win/resources/xxsnap.rc`
- Modify: `platforms/win/src/toolbar/ToolbarCatalog.h`
- Modify: `platforms/win/tests/TestToolbarCatalog.cpp`
- Modify: `platforms/win/CMakeLists.txt`

- [ ] **Step 1: Extend the catalog test to require every DPI resource ID**

Add:

```cpp
for (const auto action : fullToolbarActions()) {
    const auto icon = toolbarIcon(action);
    CHECK(icon.resourceIdAt96Dpi > 0);
    CHECK(icon.resourceIdAt120Dpi > 0);
    CHECK(icon.resourceIdAt144Dpi > 0);
    CHECK(icon.resourceIdAt192Dpi > 0);
}
CHECK(dragHandleIcon().resourceIdAt96Dpi > 0);
```

Add a Win32 resource decode loop based on the existing `embeddedToolbarResources()` test. It must call `FindResourceW`, `LoadResource`, `LockResource`, WIC decode, and assert the expected pixel dimensions for all resources.

- [ ] **Step 2: Verify RED**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_toolbar_catalog_test
```

Expected: compilation fails because the DPI resource fields and IDs are absent.

- [ ] **Step 3: Assign stable resource IDs and embed PNGs**

Reserve nonoverlapping ranges:

```text
1000-1099: 96 DPI
1100-1199: 120 DPI
1200-1299: 144 DPI
1300-1399: 192 DPI
```

The action index must be identical in all four ranges. Add a `toolbarResourceId(icon, dpi)` helper that selects the smallest bucket at or above the current DPI and returns 192-DPI resources above 192 DPI. Embed all paths in `xxsnap.rc` as `RCDATA`.

- [ ] **Step 4: Run decode and asset verification**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_toolbar_catalog_test
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R toolbar_catalog --output-on-failure
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\windows\verify-toolbar-assets.ps1
```

Expected: every embedded image decodes with the manifest dimensions.

- [ ] **Step 5: Commit**

```bash
git add platforms/win/resources/resource.h platforms/win/resources/xxsnap.rc platforms/win/src/toolbar/ToolbarCatalog.h platforms/win/tests/TestToolbarCatalog.cpp platforms/win/CMakeLists.txt
git commit -m "feat(win): embed complete DPI toolbar resources"
```

## Task 6: Make renderer and input share toolbar layout

**Files:**
- Modify: `platforms/win/src/overlay/OverlayRenderer.h`
- Modify: `platforms/win/src/overlay/OverlayRenderer.cpp`
- Modify: `platforms/win/src/overlay/OverlayHost.h`
- Modify: `platforms/win/src/overlay/OverlayHost.cpp`
- Modify: `platforms/win/tests/TestOverlayLayout.cpp`
- Modify: `platforms/win/tests/TestOverlayInputRouting.cpp`
- Modify: `platforms/win/CMakeLists.txt`

- [ ] **Step 1: Write failing shared-layout integration tests**

Replace three independent action rectangles with:

```cpp
struct OverlayToolbarItem {
    ToolbarAction action;
    DipRect rect;
    bool selected;
    bool enabled;
};

struct OverlayLayout {
    // existing mask, border, label, handles
    MainToolbarLayout toolbar;
    std::vector<OverlayToolbarItem> toolbarItems;
};
```

Tests must assert:

```cpp
CHECK(layout.toolbar.bounds.width == 144.0F);
CHECK(layout.toolbarItems.size() == 3U);
CHECK(layout.toolbarItems[0].action == ToolbarAction::cancel);
CHECK(layout.toolbarItems[1].action == ToolbarAction::save);
CHECK(layout.toolbarItems[2].action == ToolbarAction::copy);
```

At 144 DPI, click the physical center derived from every item and assert the router emits exactly the mapped terminal action. Click one pixel outside each physical rectangle and assert no action fires.

- [ ] **Step 2: Verify RED**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_overlay_layout_test
```

Expected: compilation fails because `OverlayLayout` still exposes `cancel`, `save`, and `copy` rectangles.

- [ ] **Step 3: Integrate the shared layout**

Append `std::vector<ToolbarAction> toolbarActions` to `OverlayLayoutInput`, defaulted to `terminalToolbarActions()`. `computeOverlayLayout` calls `computeMainToolbarLayout` with `input.toolbarActions` and converts the result to local overlay DIPs. Existing aggregate initializers therefore keep the three functional terminal actions until a later vertical feature slice passes a `ToolbarState::visibleActions()` result. The renderer iterates `toolbarItems`, chooses the resource ID using the surface DPI, applies catalog inset and tint semantics, and draws separators after eraser/scroll/redo.

`OverlayInputRouter::hitAction` calls `toolbarActionAt` on the same layout. Map only terminal actions:

```cpp
case ToolbarAction::cancel: return OverlayInputAction::cancel;
case ToolbarAction::save: return OverlayInputAction::save;
case ToolbarAction::copy: return OverlayInputAction::copy;
default: return std::nullopt;
```

Remove the obsolete `MvpToolbarAction`, fixed `mvpToolbarWidthDip`, three resource array, and duplicated rectangle calculations after all callers migrate.

- [ ] **Step 4: Run overlay regressions**

```powershell
.\tools\windows\build-modern.ps1 -Arch x64 -Target xxsnap_overlay_input_verification
ctest --test-dir C:\Users\kevin\build\xxsnap-modern-x64 -R "toolbar_|overlay_(layout|input)|visual_style" --output-on-failure
```

Expected: current three-button user flow is behaviorally unchanged and all new parity tests pass.

- [ ] **Step 5: Commit**

```bash
git add platforms/win/src/overlay/OverlayRenderer.h platforms/win/src/overlay/OverlayRenderer.cpp platforms/win/src/overlay/OverlayHost.h platforms/win/src/overlay/OverlayHost.cpp platforms/win/tests/TestOverlayLayout.cpp platforms/win/tests/TestOverlayInputRouting.cpp platforms/win/CMakeLists.txt
git commit -m "refactor(win): share toolbar layout across render and input"
```

## Task 7: Verify Modern and Legacy matrices

**Files:**
- Modify: `platforms/win/packaging/README.md`
- Modify: `docs/superpowers/specs/2026-08-06-windows-full-feature-parity-design.md` only if verified implementation constraints require a factual correction

- [ ] **Step 1: Run formatting and manifest checks**

```bash
git diff --check
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\windows\verify-toolbar-assets.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\windows\verify-assets.ps1
```

Expected: all commands exit zero.

- [ ] **Step 2: Run full Modern matrix**

```powershell
.\tools\windows\run-modern-matrix.ps1 -Version 0.1.0
```

Expected: Modern x64 and x86 build; all tests pass; PE machines are `8664` and `14C`.

- [ ] **Step 3: Run full Legacy matrix**

```powershell
.\tools\windows\run-legacy-matrix.ps1 -Version 0.1.0
```

Expected: Legacy x64 and x86 build with v142; all tests and Win7 import audits pass; subsystem is Windows 6.01.

- [ ] **Step 4: Manually inspect the current functional toolbar**

Run the Modern x64 executable in Parallels at 100%, 150%, and 200%. Confirm the still-functional cancel/save/copy toolbar remains 28 DIPs high, each button is 20 DIPs, icons retain their approved 16-DIP display bounds, and hit targets align. This plan does not expose unfinished annotation buttons.

- [ ] **Step 5: Document the foundation and commit**

Update the packaging README with the asset-generation prerequisite and the rule that generated toolbar assets are verified before packaging.

```bash
git add platforms/win/packaging/README.md
git commit -m "docs(win): document toolbar parity asset pipeline"
```

## Completion gate

This foundation plan is complete only when:

- Full toolbar catalog order and 560-DIP width are tested.
- Current visible toolbar remains exactly cancel/save/copy and 144 DIPs wide.
- No unfinished action is user-visible.
- All 20 original macOS toolbar resources are hashed, mechanically rasterized, embedded, and decoded at four DPI buckets.
- Renderer and input use the same toolbar layout result.
- Modern and Legacy matrices pass.

The next implementation plan starts `AnnotationDocument`, undo/redo, and rectangle/ellipse as the first newly exposed vertical feature slice.
