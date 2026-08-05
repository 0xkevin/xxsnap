[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).ProviderPath
$iconsDirectory = Join-Path $repoRoot "platforms\mac\Resources\Icons"
$expectedAssets = [ordered]@{
    "cancel-capture.png" = "5a0a437c72735a37218286e58549bc46442e8f50ff6462f94b5f970b2171c2ad"
    "save-to-file.png" = "b31ea77ff9937c431f3d57ef9afac2e35e68b23d398b6071c26ccdf72753dc1d"
    "copy-to-clipboard.png" = "60b5e93a85fe7a94d02641775c9fdef446d6cdbc3abcfa00ebdfc3715ecff7ba"
    "settings-more.png" = "5ce11d2a89c0e9ebaee879ff2728691f871362f1822766564b29de76c11726c1"
}

$failed = $false
foreach ($asset in $expectedAssets.GetEnumerator()) {
    $assetPath = Join-Path $iconsDirectory $asset.Key
    if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
        [Console]::Error.WriteLine(
            "FAIL: $($asset.Key) expected=$($asset.Value) actual=<missing> path=$assetPath"
        )
        $failed = $true
        continue
    }

    try {
        $actualHash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    catch {
        $hashError = $_.Exception.Message
        [Console]::Error.WriteLine(
            "FAIL: $($asset.Key) expected=$($asset.Value) actual=<hash-error:$hashError>"
        )
        $failed = $true
        continue
    }

    if ($actualHash -ne $asset.Value) {
        [Console]::Error.WriteLine(
            "FAIL: $($asset.Key) expected=$($asset.Value) actual=$actualHash"
        )
        $failed = $true
        continue
    }

    Write-Output "OK: $($asset.Key)"
}

if ($failed) {
    exit 1
}

exit 0
