---
title: "xxsnap first feature continuation"
date: 2026-06-08
track: knowledge
component: v2-mac-capture
status: active
---

# xxsnap First Feature Continuation

This document is the durable continuation marker for the CE compound workflow. If context is compacted or lost, continue xxsnap development in `xxsnap`; use the Qt app in `snipory` only as the reference implementation.

## Current Product Direction

- `xxsnap` is the long-term mainline for macOS and Windows.
- Qt `snipory` currently has the working first feature and remains the interaction oracle.
- Shared behavior should move into `xxsnap/core` first when it is useful for Windows reuse.
- Native platform shells should stay thin and use Core models/geometry where practical.

## First Feature Scope

The first feature is the screenshot capture flow:

- choose a screen region;
- keep the overlay open after selection;
- draw rectangle or ellipse annotations in the selected region;
- adjust stroke width, fill, color, and rectangle corner radius;
- undo the latest annotation;
- copy the rendered capture to the clipboard or save it to a file.

## Migrated Qt Interaction Constants

- Shape options toolbar: `630x30`.
- Color swatches: normal fill `12x12`, selected fill `14x14`, selected outline total `18x18`, step `16`, visible gap `4px`.
- Rectangle dropdown: button `26x22`, selected background `30x26`, rectangle icon `11x9`, arrow `7x5`, icon-arrow gap `3px`.
- Corner radius panel: `260x30`, value box `52x24`, value box right gap `3px`, slider starts `panel.left + 78`, slider/value gap `8px`.
- Corner radius value range: `0...30`; arrows must disable at bounds.
- Shape resize handles: rectangle handles sit on the drawn border outline; ellipse cardinal handles sit on top/bottom/left/right of the ellipse outline, corner handles may sit outside the ellipse curve.

## Files To Read First

- `core/include/snipory/core/annotation/AnnotationDocument.h`
- `core/include/snipory/core/selection/SelectionGeometry.h`
- `core/src/annotation/AnnotationRenderer.cpp`
- `platforms/mac/Sources/Overlay/SelectionOverlayWindow.swift`
- `platforms/mac/Sources/Overlay/CaptureAnnotationRenderer.swift`
- `platforms/mac/Sources/App/CaptureCoordinator.swift`
- `platforms/mac/project.yml`

## Verification

Core verification:

```bash
cmake -S . -B build
cmake --build build
ctest --test-dir build --output-on-failure
```

macOS syntax verification when full Xcode is unavailable:

```bash
swiftc -typecheck $(rg --files platforms/mac/Sources | rg '\.swift$')
```

Full macOS app verification requires a complete Xcode developer directory:

```bash
xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug build
```

On 2026-06-08, `xcodebuild` was blocked because `xcode-select` pointed at Command Line Tools instead of a full Xcode install.

## Next Useful Work

- Run the full Xcode build and XCTest suite after selecting a complete Xcode install.
- Manually verify the overlay with screenshots on one and two monitor setups.
- Replace the temporary Swift-only mac annotation export with an ObjC++ bridge into `xxsnap/core` so Windows and macOS share the same final renderer.
- Add Windows shell resources and implement the Windows first feature using the now-expanded Core model and geometry.
