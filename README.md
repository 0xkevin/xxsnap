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
- 用户侧标注工具说明见 `docs/annotation-tools-user-guide.md`
- macOS 功能事实基准见 `docs/requirements/xxsnap-mac-feature-requirements.md`

Restart command：

```bash
$ pkill -f "/Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/XxSnap.app/Contents/MacOS/XxSnap" || true
$ open -n /Users/kevin/Projects/open-source/Snipory/xxsnap/build/xcode-derived/Build/Products/Debug/XxSnap.app
$ pgrep -af "XxSnap.app/Contents/MacOS/XxSnap"
```

https://github.com/Snipaste/feedback/wiki/PRO
