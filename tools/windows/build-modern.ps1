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

$vsRoot = "C:\Program Files\Microsoft Visual Studio\18\Community"
$vsDevCmd = Join-Path $vsRoot "Common7\Tools\VsDevCmd.bat"
$cmake = Join-Path $vsRoot "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
$ninja = Join-Path $vsRoot "Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).ProviderPath
$buildDirectory = Join-Path $BuildRoot "xxsnap-modern-$Arch"

foreach ($requiredFile in @($vsDevCmd, $cmake, $ninja)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        [Console]::Error.WriteLine("Missing required tool: $requiredFile")
        exit 1
    }
}

$environmentCommand = "`"$vsDevCmd`" -no_logo -host_arch=arm64 -arch=$Arch && set"
$environmentLines = & $env:ComSpec /d /s /c $environmentCommand
$vsDevExitCode = $LASTEXITCODE
if ($vsDevExitCode -ne 0) {
    [Console]::Error.WriteLine(
        "VsDevCmd.bat failed for target architecture '$Arch' (exit code $vsDevExitCode)."
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

$configureArguments = @(
    "-S", $sourceRoot,
    "-B", $buildDirectory,
    "--fresh",
    "-G", "Ninja",
    "-DCMAKE_MAKE_PROGRAM=$ninja",
    "-DXXSNAP_BUILD_QT_CORE=OFF",
    "-DXXSNAP_WINDOWS_FAMILY=modern",
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
