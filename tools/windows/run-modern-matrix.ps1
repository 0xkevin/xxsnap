[CmdletBinding()]
param(
    [Parameter()]
    [string]$BuildRoot = (Join-Path $env:USERPROFILE "build"),

    [Parameter()]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = "0.1.0"
)

$ErrorActionPreference = "Stop"

$buildScript = Join-Path $PSScriptRoot "build-modern.ps1"
$vsRoot = "C:\Program Files\Microsoft Visual Studio\18\Community"
$ctest = Join-Path $vsRoot "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe"
$msvcRoot = Join-Path $vsRoot "VC\Tools\MSVC"
$toolset = Get-ChildItem -LiteralPath $msvcRoot -Directory |
    Sort-Object Name -Descending |
    Select-Object -First 1
$dumpbin = Join-Path $toolset.FullName "bin\Hostarm64\x64\dumpbin.exe"

foreach ($required in @($buildScript, $ctest, $dumpbin)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing required tool: $required"
    }
}

$previousBuildType = $env:CMAKE_BUILD_TYPE
$env:CMAKE_BUILD_TYPE = "Release"
$results = [System.Collections.Generic.List[object]]::new()
try {
    foreach ($arch in @("x64", "x86")) {
        $buildDirectory = Join-Path $BuildRoot "xxsnap-modern-$arch"
        if (Test-Path -LiteralPath $buildDirectory) {
            Remove-Item -LiteralPath $buildDirectory -Recurse -Force
        }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $buildScript `
            -Arch $arch -BuildRoot $BuildRoot -Version $Version
        if ($LASTEXITCODE -ne 0) {
            throw "Modern $arch build failed with exit code $LASTEXITCODE"
        }

        & $ctest --test-dir $buildDirectory -C Release --output-on-failure
        if ($LASTEXITCODE -ne 0) {
            throw "Modern $arch tests failed with exit code $LASTEXITCODE"
        }

        $binary = Join-Path $buildDirectory "platforms\win\xxsnap_windows.exe"
        if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
            throw "Missing Modern $arch executable: $binary"
        }
        $versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($binary)
        if ($versionInfo.FileVersion -ne $Version -or
            $versionInfo.ProductVersion -ne $Version) {
            throw "Modern $arch executable version mismatch: expected $Version, file '$($versionInfo.FileVersion)', product '$($versionInfo.ProductVersion)'"
        }
        $headers = @(& $dumpbin /headers $binary)
        if ($LASTEXITCODE -ne 0) {
            throw "dumpbin failed for $binary"
        }
        $expectedMachine = if ($arch -eq "x64") { "8664 machine" } else { "14C machine" }
        if (-not ($headers -match [regex]::Escape($expectedMachine))) {
            throw "Unexpected PE architecture for $binary; expected '$expectedMachine'"
        }
        if (-not ($headers -match "2 subsystem \(Windows GUI\)")) {
            throw "Unexpected PE subsystem for $binary; expected Windows GUI"
        }

        $results.Add([pscustomobject]@{
            Architecture = $arch
            Configuration = "Release"
            Tests = "passed"
            Machine = $expectedMachine.Split(" ")[0]
            Version = $Version
            Binary = $binary
        })
    }
}
finally {
    $env:CMAKE_BUILD_TYPE = $previousBuildType
}

$results | Format-Table -AutoSize
