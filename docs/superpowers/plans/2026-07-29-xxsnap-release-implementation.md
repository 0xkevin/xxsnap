# XxSnap Release Packaging and Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce repeatable Universal 2 DMG releases for macOS 14.0+ and replace the placeholder client update check with a real, safe manual-update flow.

**Architecture:** A standard-library Python release tool orchestrates Xcode, architecture/signature validation, DMG creation, checksum, and manifest generation. Native Swift services fetch and compare release metadata, coordinate launch/manual checks, and present AppKit update results without downloading or replacing the application.

**Tech Stack:** Python 3 standard library, Xcode/xcodebuild, create-dmg, codesign, lipo, otool, Swift/AppKit, XCTest.

---

### Task 1: Release manifest and command runner

**Files:**
- Create: `tools/release.py`
- Create: `tools/tests/test_release.py`
- Create: `tools/__init__.py`

- [ ] **Step 1: Write failing Python tests for semantic version parsing, Xcode setting parsing, SHA-256 calculation, manifest serialization, command failure reporting, and output-path construction**
- [ ] **Step 2: Run `python3 -m unittest tools.tests.test_release -v`; expect import failures**
- [ ] **Step 3: Implement immutable `ReleaseMetadata`, injected command runner, version validation, checksum, file-size, JSON manifest, and checksums output**
- [ ] **Step 4: Run tests; expect all passing**
- [ ] **Step 5: Commit with `git commit -m "build: add tested release manifest tooling"`**

### Task 2: Universal 2 build, signing, validation, and DMG

**Files:**
- Modify: `tools/release.py`
- Create: `tools/tests/fixtures/otool-load-commands.txt`
- Create: `docs/releasing-macos.md`

- [ ] **Step 1: Add failing tests for arm64/x86_64 validation, macOS 14 deployment-target parsing, ad-hoc codesign assessment handling, DMG content validation, and cleanup after failure**
- [ ] **Step 2: Implement `build` command using explicit Xcode developer directory, Release configuration, `ARCHS=arm64 x86_64`, `ONLY_ACTIVE_ARCH=NO`, and isolated DerivedData**
- [ ] **Step 3: Recursively inspect Mach-O files with `file`/`lipo`, inspect minimum system with `otool`, ad-hoc sign, verify `codesign --deep --strict`, and record expected `spctl` rejection**
- [ ] **Step 4: Create the DMG with XxSnap.app and Applications symlink, mount and inspect it, then generate manifest/checksums under `dist/<version>/`**
- [ ] **Step 5: Run Python tests and `python3 tools/release.py validate-project`; expect version `0.1.0`, build `1`, deployment target `14.0`**
- [ ] **Step 6: Commit with `git commit -m "build: package Universal 2 DMG releases"`**

### Task 3: Release API model and version comparison

**Files:**
- Create: `platforms/mac/Sources/App/UpdateService.swift`
- Create: `platforms/mac/Tests/UpdateServiceTests.swift`
- Modify: `platforms/mac/Sources/App/AppServices.swift`

- [ ] **Step 1: Write failing XCTest cases for JSON decoding, Chinese/English notes, semantic version precedence, build-number tie break, macOS incompatibility, invalid URLs, timeout, and malformed payload**
- [ ] **Step 2: Run the focused XCTest target and verify failures because the production types are missing**
- [ ] **Step 3: Replace `.placeholderUpToDate` with explicit `upToDate`, `updateAvailable(ReleaseInfo)`, `incompatible(ReleaseInfo)`, and `failed(UpdateCheckError)` results**
- [ ] **Step 4: Implement an injected `URLSession` release client for `/api/v1/releases/latest`, strict HTTPS host validation, bundle version lookup, and pure comparison logic**
- [ ] **Step 5: Run focused tests; expect all passing**
- [ ] **Step 6: Commit with `git commit -m "feat: check the public release API"`**

### Task 4: Native update presentation

**Files:**
- Create: `platforms/mac/Sources/App/UpdateWindowController.swift`
- Modify: `platforms/mac/Sources/App/StatusItemController.swift`
- Modify: `platforms/mac/Sources/App/PreferencesWindowController.swift`
- Modify: `platforms/mac/Sources/App/PreferencesSettings.swift`
- Create: `platforms/mac/Tests/UpdatePresentationTests.swift`

- [ ] **Step 1: Write failing tests for localized checking, latest, available, incompatible, and failure presentation models plus download-button visibility**
- [ ] **Step 2: Implement a reusable AppKit update window showing version, build, release notes, size, SHA-256, minimum system, and manual-download action**
- [ ] **Step 3: Make status-menu and preferences checks call the same service and update-window controller; remove the unconditional “latest” alert**
- [ ] **Step 4: Open only the validated service download URL through `NSWorkspace`; do not download, mount, or replace the app**
- [ ] **Step 5: Run focused tests and a Debug build**
- [ ] **Step 6: Commit with `git commit -m "feat: present real update results"`**

### Task 5: Launch and interval scheduling

**Files:**
- Create: `platforms/mac/Sources/App/UpdateScheduler.swift`
- Modify: `platforms/mac/Sources/App/AppDelegate.swift`
- Modify: `platforms/mac/Sources/App/PreferencesWindowController.swift`
- Create: `platforms/mac/Tests/UpdateSchedulerTests.swift`

- [ ] **Step 1: Write failing tests for delayed launch check, disabled setting, 1/6/12/24/48/72-hour interval, cancellation, successful last-check persistence, and failure not advancing last-check**
- [ ] **Step 2: Implement a cancellable scheduler using injected clock/sleep dependencies and the existing `PreferencesSettings` source of truth**
- [ ] **Step 3: Reschedule immediately when launch-check or interval settings change; never block launch or capture flows**
- [ ] **Step 4: Wire the real checker, scheduler, and window controller in `AppDelegate`**
- [ ] **Step 5: Run focused tests**
- [ ] **Step 6: Commit with `git commit -m "feat: schedule safe update checks"`**

### Task 6: Project integration and release verification

**Files:**
- Modify: `platforms/mac/project.yml`
- Modify: `platforms/mac/xxsnap.xcodeproj/project.pbxproj`
- Modify: `README.md`
- Modify: `docs/releasing-macos.md`

- [ ] **Step 1: Add new Swift/XCTest files to project generation inputs and confirm `MACOSX_DEPLOYMENT_TARGET=14.0`, `MARKETING_VERSION=0.1.0`, and `CURRENT_PROJECT_VERSION=1` remain aligned**
- [ ] **Step 2: Run the full Xcode test suite and compare failures with the documented 9-test baseline; no new failures are allowed**
- [ ] **Step 3: Build Release Universal 2 and run the release tool's architecture, deployment, signing, and DMG checks**
- [ ] **Step 4: Mount the DMG, copy XxSnap to a temporary Applications-style directory, launch it, and manually verify check-for-updates states**
- [ ] **Step 5: Document admin upload, publication, website/API verification, tag naming, and rollback**
- [ ] **Step 6: Commit with `git commit -m "docs: complete the macOS release workflow"`**
