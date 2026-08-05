# Windows packaging

XxSnap publishes four independently upgradeable MSI packages. They have unique
UpgradeCode values and install directories, so Modern and Legacy builds never
replace each other.

| Package | Supported operating system |
| --- | --- |
| `XxSnap-Modern-x64` | Windows 10/11 x64 |
| `XxSnap-Modern-x86` | Windows 10 x86 |
| `XxSnap-Legacy-x64` | Windows 7 SP1 x64 with Platform Update and SHA-2 support |
| `XxSnap-Legacy-x86` | Windows 7 SP1 x86 with Platform Update and SHA-2 support |

Windows 11 has no x86 system package. Its x64 package can still run ordinary
32-bit applications through WOW64, but XxSnap itself is distributed as x64.

Build and test the application binaries first:

```powershell
.\tools\windows\run-modern-matrix.ps1
.\tools\windows\run-legacy-matrix.ps1
```

The packaging machine also needs a .NET SDK, the repository-pinned WiX Toolset
4.0.6, VC143 app-local runtimes, VC142 app-local runtimes, and the Windows SDK
10.0.19041 UCRT payload. The build script discovers Visual Studio with
`vswhere.exe`. Air-gapped build machines can provide explicit runtime folders:

- `XXSNAP_MODERN_RUNTIME_X64` and `XXSNAP_MODERN_RUNTIME_X86`
- `XXSNAP_LEGACY_RUNTIME_X64` and `XXSNAP_LEGACY_RUNTIME_X86`
- `XXSNAP_UCRT_X64` and `XXSNAP_UCRT_X86`

Create locally testable unsigned installers with:

```powershell
.\tools\windows\build-installers.ps1 -Version 0.1.0 -AllowUnsigned
```

Release builds must omit `-AllowUnsigned` and set
`XXSNAP_SIGN_CERT_THUMBPRINT`. `XXSNAP_SIGNTOOL_EXE` and
`XXSNAP_SIGN_TIMESTAMP_URL` can override signing tool discovery and the
timestamp service. A missing SDK, runtime, certificate, executable, or signing
tool fails the build instead of emitting a partial release. The checked-in RTF
is explicitly limited to development builds; an approved XxSnap end-user
license must replace it before a signed release can be created.

Validate package identity, architecture, launch conditions, payload hashes,
original icon bytes, runtimes, and administrative extraction with:

```powershell
.\tools\windows\test-installers.ps1 `
    -Directory C:\Users\kevin\build\xxsnap-installers
```

The Legacy launch gate detects Platform Update through `d2d1.dll` version
`6.2.9200.16492` or newer and SHA-2 support through `wintrust.dll` version
`6.1.7601.24382` or newer, as installed by `KB4474419`. Unsupported systems
receive the package-specific message in `PackageMatrix.json`; the installer
does not continue silently.

## Capture performance measurement

Measure shortcut-to-first-present latency after the matrix build:

```powershell
.\tools\windows\measure-capture.ps1 -Arch x64 -Iterations 30
.\tools\windows\measure-capture.ps1 -Arch x86 -Iterations 30
```

The measurement discards three warm-up iterations and reports P50/P95 plus the
DXGI/GDI backend mix. It records timing metadata only, never captured pixels.
Parallels VM results are trend data; the Modern release gate remains P95 <= 250
ms on the native dual-4K x64 reference machine.
