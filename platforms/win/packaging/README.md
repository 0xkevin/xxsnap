# Windows Packaging

Current native Modern deliverables:

- `xxsnap-modern-x64/platforms/win/xxsnap_windows.exe` for Windows 10/11 x64
- `xxsnap-modern-x86/platforms/win/xxsnap_windows.exe` for Windows 10 x86

Run the clean Release build and test matrix from Windows PowerShell:

```powershell
.\tools\windows\run-modern-matrix.ps1
```

Measure shortcut-to-first-present latency after the matrix build:

```powershell
.\tools\windows\measure-capture.ps1 -Arch x64 -Iterations 30
.\tools\windows\measure-capture.ps1 -Arch x86 -Iterations 30
```

The measurement discards three warm-up iterations and reports P50/P95 plus the
DXGI/GDI backend mix. It records timing metadata only, never captured pixels.
Parallels VM results are trend data; the Modern release gate remains P95 <= 250
ms on the native dual-4K x64 reference machine.

Legacy executables and the four MSI packages are added by the following delivery
stages.
