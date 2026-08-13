[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).ProviderPath
$iconsDirectory = Join-Path $repoRoot "platforms\mac\Resources\Icons"
$toolbarVerifier = Join-Path $PSScriptRoot "verify-toolbar-assets.ps1"
$macCaptureSound = Join-Path $repoRoot "platforms\mac\Resources\Sounds\fullscreencutsound.mp3"
$windowsCaptureSound = Join-Path $repoRoot "platforms\win\resources\sounds\fullscreencutsound.wav"

function Test-AssetHash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedHash,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        [Console]::Error.WriteLine(
            "FAIL: $DisplayName expected=$ExpectedHash actual=<missing> path=$Path"
        )
        return $false
    }

    try {
        $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    catch {
        $hashError = $_.Exception.Message
        [Console]::Error.WriteLine(
            "FAIL: $DisplayName expected=$ExpectedHash actual=<hash-error:$hashError>"
        )
        return $false
    }

    if ($actualHash -ne $ExpectedHash) {
        [Console]::Error.WriteLine(
            "FAIL: $DisplayName expected=$ExpectedHash actual=$actualHash path=$Path"
        )
        return $false
    }

    [Console]::Out.WriteLine("OK: $DisplayName")
    return $true
}

& (Join-Path $PSHOME "powershell.exe") `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $toolbarVerifier
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$expectedAssets = [ordered]@{
    "cancel-capture.png" = "5a0a437c72735a37218286e58549bc46442e8f50ff6462f94b5f970b2171c2ad"
    "save-to-file.png" = "b31ea77ff9937c431f3d57ef9afac2e35e68b23d398b6071c26ccdf72753dc1d"
    "copy-to-clipboard.png" = "60b5e93a85fe7a94d02641775c9fdef446d6cdbc3abcfa00ebdfc3715ecff7ba"
    "settings-more.png" = "5ce11d2a89c0e9ebaee879ff2728691f871362f1822766564b29de76c11726c1"
}

$failed = $false
foreach ($asset in $expectedAssets.GetEnumerator()) {
    $assetPath = Join-Path $iconsDirectory $asset.Key
    if (-not (Test-AssetHash -Path $assetPath -ExpectedHash $asset.Value `
            -DisplayName $asset.Key)) {
        $failed = $true
    }
}

$expectedSounds = [ordered]@{
    $macCaptureSound = "c06b6214373fb4c3cacc695eefa9ca34d2ba948296b4a38203c3a1969a584562"
    $windowsCaptureSound = "60d8b6cf87375ebc0147f043ec5a5c1a9b32bd2f4637677c885cef55eb9d8779"
}
foreach ($asset in $expectedSounds.GetEnumerator()) {
    if (-not (Test-AssetHash -Path $asset.Key -ExpectedHash $asset.Value `
            -DisplayName (Split-Path -Leaf $asset.Key))) {
        $failed = $true
    }
}

if (Test-Path -LiteralPath $windowsCaptureSound -PathType Leaf) {
    $stream = [System.IO.File]::OpenRead($windowsCaptureSound)
    try {
        $header = [byte[]]::new(12)
        if ($stream.Read($header, 0, $header.Length) -ne $header.Length -or
            [Text.Encoding]::ASCII.GetString($header, 0, 4) -ne "RIFF" -or
            [Text.Encoding]::ASCII.GetString($header, 8, 4) -ne "WAVE") {
            [Console]::Error.WriteLine(
                "FAIL: fullscreencutsound.wav is not a RIFF/WAVE resource"
            )
            $failed = $true
        }
    }
    finally {
        $stream.Dispose()
    }
}

if ($failed) {
    exit 1
}

exit 0
