# macOS 14 Compatibility Design

## Goal

Lower the XxSnap macOS deployment target from macOS 15.0 to macOS 14.0 while preserving the current capture, annotation, OCR, pinning, settings, and scroll-capture behavior.

## Scope

This change covers the native macOS target only. It does not add macOS 13 compatibility, replace `SCScreenshotManager`, or change any shared-core behavior.

## Compatibility approach

Keep the existing macOS 15 system diagonal resize cursors when they are available. On macOS 14, use matching XxSnap-rendered diagonal resize cursors built by the existing cursor drawing helper. Both paths retain centered hot spots and the existing light/dark background selection logic.

The existing availability checks remain unchanged:

- `SCStreamConfiguration.captureDynamicRange` is set only on macOS 15 or newer.
- `SCContentFilter.includeMenuBar` is set only on macOS 14.2 or newer.

## Project configuration

Set `MACOSX_DEPLOYMENT_TARGET` to `14.0` in both `platforms/mac/project.yml` and the checked-in Xcode project. `LSMinimumSystemVersion` continues to inherit that value through `$(MACOSX_DEPLOYMENT_TARGET)`.

## Testing

Add focused tests for the four dark diagonal fallback cursors:

- each cursor uses the expected 24-by-24 image;
- each cursor uses a centered hot spot;
- opposite corners share the same diagonal orientation.

Run the macOS unit-test target and build the app with an explicit `MACOSX_DEPLOYMENT_TARGET=14.0`. The compatibility build must report no availability errors. Runtime smoke testing should cover selection-resize cursors and capture permission flows on an actual macOS 14 environment when one is available.

## Non-goals

- Supporting macOS 13 or earlier.
- Changing cursor appearance on macOS 15 or newer.
- Reworking ScreenCaptureKit capture paths.
- Changing behavior on macOS 14.0–14.1 where `includeMenuBar` is unavailable.
