# xxsnap Rename and Text Tool Design

## Context

xxsnap is the current native-shell rewrite track. The mac app already ships the screenshot overlay, selection, annotation tools, eyedropper, mosaic, save/copy/pin flows, and a visible toolbar entry for the text tool. The text entry is still an unfinished placeholder.

The product direction changes with this work: the v2 product should become `xxsnap`. The old `Snipory` identity should stop being the name users see, the app bundle should register as a new product, and future debug/run commands should use the new app path.

The selected Bundle ID is `com.xxsnap.mac`.

## Goals

- Rename the v2 directory from `snipory-v2/` to `xxsnap/` for the product formerly known as Snipory v2.
- Rename the mac product from `Snipory` to `xxsnap` in app name, Bundle display name, file names, permission copy, status item copy, save-file defaults, logs, docs, and build/run commands.
- Change the mac app Bundle ID to `com.xxsnap.mac` and tests to a matching test Bundle ID.
- Re-sign and register the debug app as `xxsnap.app`.
- Stop existing running `Snipory.app` instances from the product formerly known as Snipory v2 before launching the renamed app.
- Implement the first shippable text annotation tool on mac.

## Non-Goals

- Do not rename the legacy `../snipory/` Qt reference project in this change.
- Do not rename every shared C++ namespace, include root, or CMake target from `snipory` to `xxsnap` in this iteration.
- Do not implement rich text, custom font families, paragraph wrapping controls, rotation, text outline, shadow, or platform-shared text annotation models.
- Do not change screenshot permission, clipboard, save-panel, pin-window, or existing annotation behavior beyond naming and text-tool integration.

## Recommended Approach

Use a two-part implementation on the new branch:

1. Apply a product rename for the active v2 tree and mac app identity.
2. Add a scoped mac text annotation implementation using the existing overlay annotation model and renderer patterns.

This keeps the user-visible product identity consistent while avoiding a broad shared-core namespace migration. The text tool should be implemented as a real annotation feature, not a placeholder or modal-only input.

## Product Rename Design

Rename the working directory to `xxsnap/` after the design and implementation plan are committed. Update repo-local docs and commands so future work naturally starts in `/Users/kevin/Projects/open-source/Snipory/xxsnap`.

For the mac project:

- project name, scheme, app target, and test target should become `xxsnap` and `xxsnapTests` where practical;
- `PRODUCT_NAME`, `CFBundleDisplayName`, and `CFBundleName` should become `xxsnap`;
- Bundle ID should become `com.xxsnap.mac`;
- test Bundle ID should become `com.xxsnap.mac.tests`;
- `TEST_HOST` should point to `$(BUILT_PRODUCTS_DIR)/xxsnap.app/Contents/MacOS/xxsnap`;
- app icon resource names should move from `Snipory.*` to `xxsnap.*` if the files are part of the app bundle identity;
- user-visible strings should say `xxsnap`, including permission alerts, status item tooltip, default screenshot file name, and manual run instructions.

Internal helper names can be migrated opportunistically when they are close to touched code, but behavior should not depend on a full internal symbol rename.

## Signing and Registration

The system currently has a `Snipory Local Dev` signing identity. For xxsnap, create or use a new local development identity named `xxsnap Local Dev`.

The mac project should sign the renamed debug app with `xxsnap Local Dev`. After build, register the renamed app through the normal Xcode build/LaunchServices path. Because the Bundle ID changes to `com.xxsnap.mac`, macOS will treat this as a new app for privacy permissions.

Before launching the renamed app, stop any running process matching the old debug app path or `Snipory.app/Contents/MacOS/Snipory` from the product formerly known as Snipory v2. Do not delete user data or unrelated apps during this cleanup.

## Text Tool Design

The existing toolbar text button becomes an active annotation tool.

Interaction:

- clicking the text toolbar button toggles text insertion mode;
- while active, clicking inside the locked selection creates a text annotation at that point and starts editing immediately;
- typed characters update the annotation live;
- Enter commits editing; Escape cancels an empty draft or exits editing; Delete removes the selected text annotation;
- clicking an existing text annotation selects it for moving or editing;
- dragging a selected text annotation moves it within the selection;
- activating another tool commits the current text edit and exits text mode.

First-version styling:

- text color uses the existing palette color model;
- text size supports three fixed values: 16 pt, 24 pt, and 32 pt;
- default text color follows the current stroke color;
- the options toolbar for text shows size and color controls only.

The text annotation stores plain text, a local selection-space rect, and style. Its rect should be derived from the rendered text size plus padding so hit testing and export stay predictable.

## Rendering and Data Flow

Text annotations should live alongside existing `CaptureAnnotation` values. Add the minimum model fields needed for plain text and font size while preserving existing shape, arrow, brush, marker, and mosaic behavior.

Overlay preview and export must use the same text metrics as closely as AppKit/CoreGraphics allows:

- preview draws text inside the annotation rect in overlay coordinates;
- export draws text into the final image using the same color, size, and local selection-space placement;
- moving or wheel-resizing the selection should preserve the visible overlay position of text annotations, matching current annotation behavior;
- empty text drafts should not export.

## Error Handling

- If creating a new signing identity fails, keep the implementation blocked at the signing step and report the exact `security` error.
- If Xcode project regeneration is not available, edit `project.yml` and the checked-in `.xcodeproj` consistently.
- If the renamed app lacks screen-recording permission, show xxsnap-specific permission copy and treat it as expected first-run behavior.
- If text input starts outside the locked selection, ignore the click and keep text mode active.
- If a text edit is empty when committed, remove that draft annotation.

## Testing

Add focused mac XCTest coverage for:

- text toolbar button toggles active text mode and selected state;
- clicking inside the selection creates an editable text annotation;
- typing updates preview state and committed annotation text;
- empty text drafts are discarded;
- text annotations can be selected, moved, deleted, and exported;
- color and size controls update selected text annotations;
- export draws text pixels in the expected location and color;
- product Bundle ID, display name, default save name, permission copy, and refresh self-ignore behavior use xxsnap identifiers.

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project platforms/mac/xxsnap.xcodeproj -scheme xxsnap -configuration Debug -derivedDataPath build/xcode-derived test
```

After the directory rename, run from:

```bash
cd /Users/kevin/Projects/open-source/Snipory/xxsnap
```

Manual smoke check:

- stop old Snipory processes;
- build the renamed debug app;
- launch `build/xcode-derived/Build/Products/Debug/xxsnap.app`;
- grant screen-recording permission if macOS prompts for the new Bundle ID;
- create a screenshot selection, add text, move it, change color/size, copy or save, and verify the exported image contains the text.

## Acceptance Criteria

- There is no running old `Snipory.app` debug process from the product formerly known as Snipory v2 after migration.
- The active v2 directory is `xxsnap/`.
- The built mac app is named `xxsnap.app`, signed with `xxsnap Local Dev`, and uses Bundle ID `com.xxsnap.mac`.
- User-facing app strings say `xxsnap`.
- The text toolbar entry is no longer a placeholder and supports create, edit, move, delete, color, size, preview, copy/export.
- Relevant XCTest tests pass with the renamed scheme.
