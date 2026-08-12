[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).ProviderPath
$manifestPath = Join-Path $repoRoot "platforms\win\resources\toolbar\ToolbarAssets.json"
$expectedNames = @(
    "settings-more", "screenshot", "arrow", "pencil-tool", "highlighter-tool",
    "straw-ranging", "masaike2", "text-tool", "number-sequence",
    "zoom-in-tool", "eraser-tool", "scroll-screen2",
    "undo-enabled", "undo-disabled", "redo-enabled", "redo-disabled",
    "cancel-capture", "pin-to-screen", "save-to-file", "copy-to-clipboard",
    "refresh-svgrepo-com3"
)
$expectedScales = @("100", "125", "150", "200")

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Toolbar asset manifest is missing: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$assets = @($manifest.assets)
if ($assets.Count -ne $expectedNames.Count) {
    throw "Expected $($expectedNames.Count) toolbar assets, found $($assets.Count)."
}

$actualNames = @($assets | ForEach-Object { $_.name })
if (@($actualNames | Sort-Object -Unique).Count -ne $actualNames.Count) {
    throw "Toolbar asset names must be unique."
}
foreach ($name in $expectedNames) {
    if ($actualNames -notcontains $name) {
        throw "Toolbar asset manifest is missing '$name'."
    }
}

Add-Type -AssemblyName System.Drawing
foreach ($asset in $assets) {
    foreach ($property in @(
        "name", "source", "sha256", "logicalSizeDip", "insetDip",
        "fixedColor", "generated"
    )) {
        if ($null -eq $asset.PSObject.Properties[$property]) {
            throw "Toolbar asset '$($asset.name)' is missing '$property'."
        }
    }

    $sourcePath = Join-Path $repoRoot ($asset.source -replace "/", "\")
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Toolbar source is missing: $sourcePath"
    }
    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($sourceHash -ne $asset.sha256) {
        throw "Toolbar source hash mismatch for '$($asset.name)'."
    }

    foreach ($scale in $expectedScales) {
        $generatedProperty = $asset.generated.PSObject.Properties[$scale]
        if ($null -eq $generatedProperty) {
            throw "Toolbar asset '$($asset.name)' is missing scale '$scale'."
        }
        $imagePath = Join-Path $repoRoot ($generatedProperty.Value -replace "/", "\")
        if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
            throw "Generated toolbar asset is missing: $imagePath"
        }

        $expectedEdge = [Math]::Round(
            [double]$asset.logicalSizeDip * [double]$scale / 100.0,
            [MidpointRounding]::AwayFromZero
        )
        $bitmap = [System.Drawing.Bitmap]::new($imagePath)
        try {
            if ($bitmap.Width -ne $expectedEdge -or $bitmap.Height -ne $expectedEdge) {
                throw "Unexpected dimensions for '$imagePath': $($bitmap.Width)x$($bitmap.Height), expected ${expectedEdge}x${expectedEdge}."
            }
            $hasAlpha = $false
            for ($y = 0; $y -lt $bitmap.Height -and -not $hasAlpha; ++$y) {
                for ($x = 0; $x -lt $bitmap.Width; ++$x) {
                    if ($bitmap.GetPixel($x, $y).A -gt 0) {
                        $hasAlpha = $true
                        break
                    }
                }
            }
            if (-not $hasAlpha) {
                throw "Generated toolbar asset has an empty alpha channel: $imagePath"
            }
        }
        finally {
            $bitmap.Dispose()
        }
    }
}

Write-Output "Toolbar asset verification passed ($($assets.Count) assets x $($expectedScales.Count) scales)."
