[CmdletBinding()]
param(
    [Parameter()]
    [string]$Binary,

    [Parameter()]
    [string]$Allowlist,

    [Parameter()]
    [string]$Dumpbin,

    [Parameter()]
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

if (-not $Allowlist) {
    $Allowlist = Join-Path $PSScriptRoot "..\..\platforms\win\tests\allowed-win7-imports.txt"
}

function Get-DumpbinImports([string[]]$Lines) {
    $imports = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $unparsedDlls = [System.Collections.Generic.List[string]]::new()
    $sectionKind = $null
    $currentDll = $null
    $readingSymbols = $false
    $currentSymbolCount = 0

    foreach ($line in $Lines) {
        $text = [string]$line

        if ($text -match '^\s+Section contains the following (delay load )?imports:\s*$') {
            if ($currentDll -and $currentSymbolCount -eq 0) {
                $unparsedDlls.Add($currentDll)
            }
            $sectionKind = if ($Matches[1]) { "delay" } else { "normal" }
            $currentDll = $null
            $readingSymbols = $false
            $currentSymbolCount = 0
            continue
        }
        if ($text -match '^\s+Summary\s*$') {
            if ($currentDll -and $currentSymbolCount -eq 0) {
                $unparsedDlls.Add($currentDll)
            }
            $sectionKind = $null
            $currentDll = $null
            $readingSymbols = $false
            $currentSymbolCount = 0
            break
        }
        if (-not $sectionKind) {
            continue
        }
        if ($text -match '^\s{4}([A-Za-z0-9][A-Za-z0-9._-]*\.dll)\s*$') {
            if ($currentDll -and $currentSymbolCount -eq 0) {
                $unparsedDlls.Add($currentDll)
            }
            $currentDll = $Matches[1]
            $readingSymbols = $false
            $currentSymbolCount = 0
            continue
        }
        if (-not $currentDll) {
            continue
        }
        if ($sectionKind -eq "normal" -and $text -match 'Index of first forwarder reference') {
            $readingSymbols = $true
            continue
        }
        if ($sectionKind -eq "delay" -and $text -match '\btime date stamp\s*$') {
            $readingSymbols = $true
            continue
        }
        if (-not $readingSymbols) {
            continue
        }

        $symbol = $null
        if ($sectionKind -eq "normal") {
            if ($text -match '^\s+Ordinal\s+(\d+)\s*$') {
                $symbol = "#$($Matches[1])"
            } elseif ($text -match '^\s+[0-9A-Fa-f]+\s+(\S(?:.*\S)?)\s*$') {
                $symbol = $Matches[1]
            }
        } else {
            if ($text -match '^\s+[0-9A-Fa-f]+\s+Ordinal\s+(\d+)\s*$') {
                $symbol = "#$($Matches[1])"
            } elseif ($text -match '^\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(\S(?:.*\S)?)\s*$') {
                $symbol = $Matches[1]
            }
        }
        if ($symbol) {
            [void]$imports.Add("$currentDll!$symbol")
            $currentSymbolCount++
        }
    }

    if ($currentDll -and $currentSymbolCount -eq 0) {
        $unparsedDlls.Add($currentDll)
    }
    if ($unparsedDlls.Count -ne 0) {
        throw "Failed to parse symbols for imported DLL segment(s): $($unparsedDlls -join ', ')"
    }
    if ($imports.Count -eq 0) {
        throw "No PE imports were parsed from dumpbin output."
    }
    return $imports
}

function Invoke-ParserSelfTest {
    $fixture = @(
        "  Section contains the following imports:",
        "    KERNEL32.dll",
        "             140000000 Import Address Table",
        "             140000100 Import Name Table",
        "                     0 time date stamp",
        "                     0 Index of first forwarder reference",
        "                         A4 GetTickCount",
        "    d2d1.dll",
        "                     0 Index of first forwarder reference",
        "                        Ordinal 1",
        "    api-ms-win-core-file-l1-2-0.dll",
        "                     0 Index of first forwarder reference",
        "                         B2 GetFileInformationByHandleEx",
        "  Section contains the following delay load imports:",
        "    RPCRT4.dll",
        "              00000001 Characteristics",
        "      00000001400496E0 Address of HMODULE",
        "      000000014004C020 Import Address Table",
        "                     0 time date stamp",
        "                                    000000014002FF8C   174 RpcBindingFree",
        "                                    000000014002FF68   215 RpcStringFreeW",
        "  Summary",
        "        1000 .data"
    )
    $actual = Get-DumpbinImports $fixture
    $expected = @(
        "KERNEL32.dll!GetTickCount",
        "d2d1.dll!#1",
        "api-ms-win-core-file-l1-2-0.dll!GetFileInformationByHandleEx",
        "RPCRT4.dll!RpcBindingFree",
        "RPCRT4.dll!RpcStringFreeW"
    )
    if ($actual.Count -ne $expected.Count) {
        throw "Parser self-test returned $($actual.Count) imports; expected $($expected.Count)."
    }
    foreach ($entry in $expected) {
        if (-not $actual.Contains($entry)) {
            throw "Parser self-test missed import: $entry"
        }
    }
    if ($actual.Contains(".data")) {
        throw "Parser self-test parsed Summary output as an import."
    }

    $failedClosed = $false
    try {
        [void](Get-DumpbinImports @(
            "  Section contains the following delay load imports:",
            "    BROKEN.dll",
            "                     0 time date stamp",
            "             this line is not a delay-load symbol",
            "  Summary"
        ))
    } catch {
        $failedClosed = $_.Exception.Message -match "BROKEN\.dll"
    }
    if (-not $failedClosed) {
        throw "Parser self-test did not fail closed for an unparsed DLL segment."
    }

    Write-Output "dumpbin import parser self-test passed"
}

if ($SelfTest) {
    Invoke-ParserSelfTest
    return
}
if (-not $Binary) {
    throw "Binary is required unless -SelfTest is specified."
}

function Resolve-Dumpbin([string]$ExplicitPath) {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($ExplicitPath) {
        $candidates.Add($ExplicitPath)
    }
    if ($env:XXSNAP_DUMPBIN_EXE) {
        $candidates.Add($env:XXSNAP_DUMPBIN_EXE)
    }

    $command = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
    if ($command) {
        $candidates.Add($command.Source)
    }

    $visualStudioRoots = [System.Collections.Generic.List[string]]::new()
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $vsWhere -PathType Leaf) {
        $installations = @(& $vsWhere -products * -property installationPath)
        foreach ($installation in $installations) {
            if ($installation) {
                $visualStudioRoots.Add(([string]$installation).Trim())
            }
        }
    }
    foreach ($root in $visualStudioRoots) {
        $msvcRoot = Join-Path $root "VC\Tools\MSVC"
        $toolsets = @(Get-ChildItem -LiteralPath $msvcRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending)
        foreach ($toolset in $toolsets) {
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

$binaryPath = (Resolve-Path -LiteralPath $Binary).ProviderPath
$allowlistPath = (Resolve-Path -LiteralPath $Allowlist).ProviderPath
$dumpbinPath = Resolve-Dumpbin $Dumpbin

$allowed = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase)
foreach ($line in Get-Content -LiteralPath $allowlistPath) {
    $entry = $line.Trim()
    if (-not $entry -or $entry.StartsWith("#")) {
        continue
    }
    if ($entry -notmatch '^[^!\s]+\.dll!\S+$') {
        throw "Malformed Windows 7 import allowlist entry: '$entry'"
    }
    [void]$allowed.Add($entry)
}
if ($allowed.Count -eq 0) {
    throw "Windows 7 import allowlist is empty: $allowlistPath"
}

$dump = @(& $dumpbinPath /nologo /imports $binaryPath 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "dumpbin /imports failed for '$binaryPath' with exit code $LASTEXITCODE.`n$($dump -join [Environment]::NewLine)"
}

$imports = Get-DumpbinImports $dump

$forbiddenSymbols = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase)
foreach ($symbol in @(
    "AdjustWindowRectExForDpi",
    "AreDpiAwarenessContextsEqual",
    "EnableNonClientDpiScaling",
    "GetDpiForMonitor",
    "GetDpiForSystem",
    "GetDpiForWindow",
    "GetSystemDpiForProcess",
    "GetSystemMetricsForDpi",
    "GetWindowDpiAwarenessContext",
    "SetProcessDpiAwarenessContext",
    "SetThreadDpiAwarenessContext"
)) {
    [void]$forbiddenSymbols.Add($symbol)
}
$forbiddenImports = @($imports | Where-Object {
    $separator = $_.IndexOf("!")
    $separator -ge 0 -and $forbiddenSymbols.Contains($_.Substring($separator + 1))
} | Sort-Object)
if ($forbiddenImports.Count -ne 0) {
    throw "Windows 7-incompatible static imports found in '$binaryPath':`n$($forbiddenImports -join [Environment]::NewLine)"
}

$unexpected = @($imports | Where-Object { -not $allowed.Contains($_) } | Sort-Object)
if ($unexpected.Count -ne 0) {
    throw "Imports are not in the Windows 7 allowlist for '$binaryPath':`n$($unexpected -join [Environment]::NewLine)"
}

[pscustomobject]@{
    Binary = $binaryPath
    Imports = $imports.Count
    Allowlist = $allowlistPath
    Dumpbin = $dumpbinPath
    Result = "Windows 7 import audit passed"
} | Format-List
