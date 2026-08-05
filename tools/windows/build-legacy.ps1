[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("x64", "x86")]
    [string]$Arch = "x64",

    [Parameter()]
    [string]$Target,

    [Parameter()]
    [string]$BuildRoot = (Join-Path $env:USERPROFILE "build")
)

$ErrorActionPreference = "Stop"

$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$windowsSdkVersion = "10.0.19041.0"
$missing = [System.Collections.Generic.List[string]]::new()
$vsRoot = $null
$vs18Root = "C:\Program Files\Microsoft Visual Studio\18\Community"
$vs18CMake = Join-Path $vs18Root "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
$vs18Ninja = Join-Path $vs18Root "Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
$cmake = $null
$ninja = $null

if ($env:XXSNAP_CMAKE_EXE) {
    if (Test-Path -LiteralPath $env:XXSNAP_CMAKE_EXE -PathType Leaf) {
        $cmake = (Resolve-Path -LiteralPath $env:XXSNAP_CMAKE_EXE).ProviderPath
    } else {
        [Console]::Error.WriteLine(
            "XXSNAP_CMAKE_EXE does not point to a file: $env:XXSNAP_CMAKE_EXE"
        )
        exit 1
    }
} elseif (Test-Path -LiteralPath $vs18CMake -PathType Leaf) {
    $cmake = $vs18CMake
} else {
    $cmakeCommand = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($cmakeCommand) {
        $cmake = $cmakeCommand.Source
    }
}

if (-not $cmake) {
    [Console]::Error.WriteLine("Missing required tool: CMake 3.28 or newer")
    exit 1
}

$cmakeVersionOutput = @(& $cmake --version 2>&1)
$cmakeVersionExitCode = $LASTEXITCODE
if ($cmakeVersionExitCode -ne 0) {
    [Console]::Error.WriteLine(
        "Failed to query CMake version from '$cmake' (exit code $cmakeVersionExitCode)."
    )
    exit $cmakeVersionExitCode
}

$cmakeVersionLine = [string]($cmakeVersionOutput | Select-Object -First 1)
if ($cmakeVersionLine -notmatch '^cmake version (\d+)\.(\d+)\.(\d+)') {
    [Console]::Error.WriteLine("Unable to parse CMake version from: $cmakeVersionLine")
    exit 1
}

$cmakeVersion = [version]::new(
    [int]$Matches[1],
    [int]$Matches[2],
    [int]$Matches[3]
)
if ($cmakeVersion -lt [version]"3.28.0") {
    [Console]::Error.WriteLine(
        "CMake 3.28 or newer is required; detected $cmakeVersion at '$cmake'."
    )
    exit 1
}

if (Test-Path -LiteralPath $vs18Ninja -PathType Leaf) {
    $ninja = $vs18Ninja
} else {
    $ninjaCommand = Get-Command ninja.exe -ErrorAction SilentlyContinue
    if ($ninjaCommand) {
        $ninja = $ninjaCommand.Source
    }
}

if (-not $ninja) {
    [Console]::Error.WriteLine("Missing required tool: Ninja")
    exit 1
}

& $ninja --version | Out-Null
$ninjaVersionExitCode = $LASTEXITCODE
if ($ninjaVersionExitCode -ne 0) {
    [Console]::Error.WriteLine(
        "Failed to run Ninja at '$ninja' (exit code $ninjaVersionExitCode)."
    )
    exit $ninjaVersionExitCode
}

if (Test-Path -LiteralPath $vsWhere -PathType Leaf) {
    $vsMatches = @(& $vsWhere -latest -products Microsoft.VisualStudio.Product.BuildTools `
        -version "[16.11,16.12)" -property installationPath)
    if ($vsMatches.Count -gt 0) {
        $vsRoot = $vsMatches[0].Trim()
    }
}

if (-not $vsRoot) {
    $missing.Add("Visual Studio 2019 Build Tools 16.11")
    $missing.Add("MSVC v142 (14.29) $Arch compiler tools")
} else {
    $msvcRoot = Join-Path $vsRoot "VC\Tools\MSVC"
    $v142 = @(Get-ChildItem -LiteralPath $msvcRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "14.29.*" } |
        Sort-Object Name -Descending |
        Select-Object -First 1)
    if ($v142.Count -eq 0 -or
        -not (Test-Path -LiteralPath (Join-Path $v142[0].FullName "bin\Hostx64\$Arch\cl.exe") -PathType Leaf)) {
        $missing.Add("MSVC v142 (14.29) $Arch compiler tools")
    }
}

$windowsKitsRoot = "${env:ProgramFiles(x86)}\Windows Kits\10"
$sdkInclude = Join-Path $windowsKitsRoot "Include\$windowsSdkVersion\um\Windows.h"
$sdkLibrary = Join-Path $windowsKitsRoot "Lib\$windowsSdkVersion\um\$Arch\kernel32.lib"
if (-not (Test-Path -LiteralPath $sdkInclude -PathType Leaf) -or
    -not (Test-Path -LiteralPath $sdkLibrary -PathType Leaf)) {
    $missing.Add("Windows SDK $windowsSdkVersion")
}

if ($missing.Count -gt 0) {
    foreach ($component in $missing) {
        [Console]::Error.WriteLine("Missing required component: $component")
    }
    exit 1
}

$vsDevCmd = Join-Path $vsRoot "Common7\Tools\VsDevCmd.bat"

if (-not (Test-Path -LiteralPath $vsDevCmd -PathType Leaf)) {
    [Console]::Error.WriteLine("Missing required tool: $vsDevCmd")
    exit 1
}

$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).ProviderPath
$buildDirectory = Join-Path $BuildRoot "xxsnap-legacy-$Arch"
$legacyConfiguration = Join-Path $sourceRoot "cmake\windows\LegacyWindows7.cmake"
$environmentCommand = "`"$vsDevCmd`" -no_logo -host_arch=x64 -arch=$Arch -vcvars_ver=14.29 -winsdk=$windowsSdkVersion && set"
$environmentLines = & $env:ComSpec /d /s /c $environmentCommand
$vsDevExitCode = $LASTEXITCODE
if ($vsDevExitCode -ne 0) {
    [Console]::Error.WriteLine(
        "VsDevCmd.bat failed for the v142/$windowsSdkVersion toolchain (exit code $vsDevExitCode)."
    )
    exit $vsDevExitCode
}

foreach ($line in $environmentLines) {
    $separator = $line.IndexOf("=")
    if ($separator -gt 0) {
        [Environment]::SetEnvironmentVariable(
            $line.Substring(0, $separator),
            $line.Substring($separator + 1),
            "Process"
        )
    }
}

$actualVcToolsVersion = ([string]$env:VCToolsVersion).TrimEnd([char]'\')
$actualWindowsSdkVersion = ([string]$env:WindowsSDKVersion).TrimEnd([char]'\')
if ($actualVcToolsVersion -notlike "14.29.*") {
    [Console]::Error.WriteLine(
        "VsDevCmd selected unexpected VCToolsVersion: expected 14.29.*, actual '$actualVcToolsVersion'."
    )
    exit 1
}
if ($actualWindowsSdkVersion -ne $windowsSdkVersion) {
    [Console]::Error.WriteLine(
        "VsDevCmd selected unexpected WindowsSDKVersion: expected $windowsSdkVersion, actual '$actualWindowsSdkVersion'."
    )
    exit 1
}

$configureArguments = @(
    "-S", $sourceRoot,
    "-B", $buildDirectory,
    "--fresh",
    "-G", "Ninja",
    "--toolchain", $legacyConfiguration,
    "-DCMAKE_MAKE_PROGRAM=$ninja",
    "-DXXSNAP_BUILD_QT_CORE=OFF",
    "-DXXSNAP_WINDOWS_FAMILY=legacy",
    "-DBUILD_TESTING=ON"
)

& $cmake @configureArguments
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$buildArguments = @("--build", $buildDirectory)
if ($Target) {
    $buildArguments += @("--target", $Target)
}

& $cmake @buildArguments
exit $LASTEXITCODE
