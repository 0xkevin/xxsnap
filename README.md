# xxsnap

xxsnap is the native-shell screenshot and annotation rewrite formerly known as Snipory v2:

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
$ pkill -f "/Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/xxsnap.app/Contents/MacOS/xxsnap" || true
$ open -n /Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/xxsnap.app
$ pgrep -af "xxsnap.app/Contents/MacOS/xxsnap"
```

https://github.com/Snipaste/feedback/wiki/PRO
