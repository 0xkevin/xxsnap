# Snipory v2

Snipory v2 is the native-shell rewrite of Snipory:

- shared C++ core
- native macOS shell
- future native Windows shell

The legacy Qt project remains in `../snipory` as a migration reference.

Current status:

- `core/` contains the migrated domain types and snapshot export pipeline
- `platforms/mac/` builds a native menu bar placeholder app with a ScreenCaptureKit MVP
- captured macOS MVP output is copied to the clipboard; save-panel wiring exists in code and can be surfaced by later UI work

Restart command：

```bash
$ pkill -f "/Users/kevin/Projects/open-source/Snipory/snipory-v2/build/xcode-derived/Build/Products/Debug/Snipory.app/Contents/MacOS/Snipory" || true
$ open -n /Users/kevin/Projects/open-source/Snipory/snipory-v2/build/xcode-derived/Build/Products/Debug/Snipory.app
$ pgrep -af "Snipory.app/Contents/MacOS/Snipory"
```

