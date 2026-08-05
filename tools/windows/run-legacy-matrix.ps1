[CmdletBinding()]
param(
    [Parameter()]
    [string]$BuildRoot = (Join-Path $env:USERPROFILE "build")
)

$ErrorActionPreference = "Stop"

$buildScript = Join-Path $PSScriptRoot "build-legacy.ps1"
$auditScript = Join-Path $PSScriptRoot "verify-imports.ps1"

function Get-VisualStudioRoots {
    $roots = [System.Collections.Generic.List[string]]::new()
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $vsWhere -PathType Leaf) {
        foreach ($installation in @(& $vsWhere -products * -property installationPath)) {
            if ($installation) {
                $roots.Add(([string]$installation).Trim())
            }
        }
    }
    return $roots
}

function Resolve-Ctest {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($env:XXSNAP_CTEST_EXE) {
        $candidates.Add($env:XXSNAP_CTEST_EXE)
    }
    if ($env:XXSNAP_CMAKE_EXE) {
        $candidates.Add((Join-Path (Split-Path -Parent $env:XXSNAP_CMAKE_EXE) "ctest.exe"))
    }
    $command = Get-Command ctest.exe -ErrorAction SilentlyContinue
    if ($command) {
        $candidates.Add($command.Source)
    }
    foreach ($root in Get-VisualStudioRoots) {
        $candidates.Add((Join-Path $root "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe"))
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).ProviderPath
        }
    }
    throw "Missing required tool: ctest.exe"
}

function Resolve-Dumpbin {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($env:XXSNAP_DUMPBIN_EXE) {
        $candidates.Add($env:XXSNAP_DUMPBIN_EXE)
    }
    $command = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
    if ($command) {
        $candidates.Add($command.Source)
    }
    foreach ($root in Get-VisualStudioRoots) {
        $msvcRoot = Join-Path $root "VC\Tools\MSVC"
        foreach ($toolset in @(Get-ChildItem -LiteralPath $msvcRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending)) {
            $candidates.Add((Join-Path $toolset.FullName "bin\Hostarm64\x64\dumpbin.exe"))
            $candidates.Add((Join-Path $toolset.FullName "bin\Hostx64\x64\dumpbin.exe"))
        }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).ProviderPath
        }
    }
    throw "Missing required tool: dumpbin.exe"
}

foreach ($required in @($buildScript, $auditScript)) {
    if (-not $required -or -not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing required script: $required"
    }
}
$ctest = Resolve-Ctest
$dumpbin = Resolve-Dumpbin

$previousBuildType = $env:CMAKE_BUILD_TYPE
$env:CMAKE_BUILD_TYPE = "Release"
$results = [System.Collections.Generic.List[object]]::new()
try {
    foreach ($arch in @("x64", "x86")) {
        $buildDirectory = Join-Path $BuildRoot "xxsnap-legacy-$arch"
        if (Test-Path -LiteralPath $buildDirectory) {
            Remove-Item -LiteralPath $buildDirectory -Recurse -Force
        }

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $buildScript `
            -Arch $arch -BuildRoot $BuildRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Legacy $arch build failed with exit code $LASTEXITCODE"
        }

        & $ctest --test-dir $buildDirectory -C Release --output-on-failure
        if ($LASTEXITCODE -ne 0) {
            throw "Legacy $arch tests failed with exit code $LASTEXITCODE"
        }

        $binary = Join-Path $buildDirectory "platforms\win\xxsnap_windows.exe"
        if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
            throw "Missing Legacy $arch executable: $binary"
        }

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $auditScript `
            -Binary $binary -Dumpbin $dumpbin
        if ($LASTEXITCODE -ne 0) {
            throw "Legacy $arch import audit failed with exit code $LASTEXITCODE"
        }

        $headers = @(& $dumpbin /nologo /headers $binary)
        if ($LASTEXITCODE -ne 0) {
            throw "dumpbin /headers failed for $binary"
        }
        $expectedMachine = if ($arch -eq "x64") { "8664 machine" } else { "14C machine" }
        if (-not ($headers -match [regex]::Escape($expectedMachine))) {
            throw "Unexpected PE architecture for $binary; expected '$expectedMachine'"
        }
        if (-not ($headers -match "6\.01 subsystem version")) {
            throw "Unexpected PE subsystem version for $binary; expected Windows 7 (6.01)"
        }
        if (-not ($headers -match "2 subsystem \(Windows GUI\)")) {
            throw "Unexpected PE subsystem for $binary; expected Windows GUI"
        }

        $results.Add([pscustomobject]@{
            Architecture = $arch
            Configuration = "Release"
            Tests = "passed"
            ImportAudit = "passed"
            Machine = $expectedMachine.Split(" ")[0]
            Subsystem = "Windows 6.01"
            Binary = $binary
        })
    }
}
finally {
    $env:CMAKE_BUILD_TYPE = $previousBuildType
}

$results | Format-Table -AutoSize
