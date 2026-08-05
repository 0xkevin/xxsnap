[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [Parameter()]
    [string]$BuildRoot = (Join-Path $env:USERPROFILE "build"),

    [Parameter()]
    [string]$OutputDirectory,

    [Parameter()]
    [switch]$AllowUnsigned,

    [Parameter()]
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).ProviderPath
$matrixPath = Join-Path $sourceRoot "platforms\win\packaging\PackageMatrix.json"
$wixSource = Join-Path $sourceRoot "platforms\win\packaging\Product.wxs"
$license = Join-Path $sourceRoot "platforms\win\packaging\License.rtf"
$icon = Join-Path $sourceRoot "platforms\win\resources\icons\Snipory.ico"
$testScript = Join-Path $PSScriptRoot "test-installers.ps1"
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $BuildRoot "xxsnap-installers"
}

function Assert-File([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing $Description`: $Path"
    }
}

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

function Resolve-DotnetSdk {
    $command = Get-Command dotnet.exe -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Missing required tool: .NET SDK for the pinned WiX 4 tool manifest."
    }
    $sdks = @(& $command.Source --list-sdks 2>&1)
    if ($LASTEXITCODE -ne 0 -or $sdks.Count -eq 0) {
        throw "The dotnet host is installed, but no .NET SDK is available for WiX 4."
    }
    return $command.Source
}

function Resolve-VcRuntimeDirectory([string]$Family, [string]$Architecture) {
    $overrideName = "XXSNAP_$($Family.ToUpperInvariant())_RUNTIME_$($Architecture.ToUpperInvariant())"
    $override = [Environment]::GetEnvironmentVariable($overrideName)
    if ($override) {
        if (-not (Test-Path -LiteralPath $override -PathType Container)) {
            throw "$overrideName does not point to a directory: $override"
        }
        return (Resolve-Path -LiteralPath $override).ProviderPath
    }

    $crtFolder = if ($Family -eq "legacy") {
        "Microsoft.VC142.CRT"
    } else {
        "Microsoft.VC143.CRT"
    }
    foreach ($root in Get-VisualStudioRoots) {
        $redistRoot = Join-Path $root "VC\Redist\MSVC"
        foreach ($versionDirectory in @(Get-ChildItem -LiteralPath $redistRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending)) {
            $candidate = Join-Path $versionDirectory.FullName "$Architecture\$crtFolder"
            if (Test-Path -LiteralPath (Join-Path $candidate "vcruntime140.dll") -PathType Leaf) {
                return $candidate
            }
        }
    }
    throw "Missing $crtFolder app-local runtime for $Architecture. Set $overrideName to its directory."
}

function Resolve-UcrtDirectory([string]$Architecture) {
    $overrideName = "XXSNAP_UCRT_$($Architecture.ToUpperInvariant())"
    $override = [Environment]::GetEnvironmentVariable($overrideName)
    if ($override) {
        if (-not (Test-Path -LiteralPath $override -PathType Container)) {
            throw "$overrideName does not point to a directory: $override"
        }
        return (Resolve-Path -LiteralPath $override).ProviderPath
    }
    $candidate = "${env:ProgramFiles(x86)}\Windows Kits\10\Redist\10.0.19041.0\ucrt\DLLs\$Architecture"
    if (Test-Path -LiteralPath (Join-Path $candidate "ucrtbase.dll") -PathType Leaf) {
        return $candidate
    }
    throw "Missing Windows SDK 10.0.19041 UCRT payload for $Architecture. Set $overrideName to its directory."
}

function Resolve-SignTool {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($env:XXSNAP_SIGNTOOL_EXE) {
        $candidates.Add($env:XXSNAP_SIGNTOOL_EXE)
    }
    $command = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($command) {
        $candidates.Add($command.Source)
    }
    $kitsBin = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
    foreach ($directory in @(Get-ChildItem -LiteralPath $kitsBin -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending)) {
        $candidates.Add((Join-Path $directory.FullName "x64\signtool.exe"))
        $candidates.Add((Join-Path $directory.FullName "x86\signtool.exe"))
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).ProviderPath
        }
    }
    throw "Missing required tool: signtool.exe"
}

function Copy-RuntimePayload($Package, [string]$StageDirectory) {
    $vcRuntime = Resolve-VcRuntimeDirectory $Package.family $Package.architecture
    foreach ($runtime in @(Get-ChildItem -LiteralPath $vcRuntime -Filter "*.dll" -File)) {
        Copy-Item -LiteralPath $runtime.FullName -Destination $StageDirectory
    }
    foreach ($required in @("msvcp140.dll", "vcruntime140.dll")) {
        Assert-File (Join-Path $StageDirectory $required) "$($Package.name) VC runtime"
    }

    if ($Package.family -eq "legacy") {
        $ucrt = Resolve-UcrtDirectory $Package.architecture
        foreach ($runtime in @(Get-ChildItem -LiteralPath $ucrt -Filter "*.dll" -File)) {
            Copy-Item -LiteralPath $runtime.FullName -Destination $StageDirectory
        }
        foreach ($required in @("ucrtbase.dll", "api-ms-win-crt-runtime-l1-1-0.dll")) {
            Assert-File (Join-Path $StageDirectory $required) "$($Package.name) UCRT runtime"
        }
    }
}

function Write-PayloadManifest([string]$StageDirectory) {
    $files = @(
        Get-ChildItem -LiteralPath $StageDirectory -File -Recurse |
            Sort-Object FullName |
            ForEach-Object {
                [pscustomobject]@{
                    relativePath = $_.FullName.Substring($StageDirectory.Length).TrimStart([char]'\')
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                    length = $_.Length
                }
            }
    )
    [pscustomobject]@{
        schemaVersion = 1
        files = $files
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $StageDirectory "payload-manifest.json") -Encoding UTF8
}

function Write-PayloadWixSource([string]$StageDirectory, [string]$OutputPath) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">')
    $lines.Add('  <Fragment>')
    $lines.Add('    <ComponentGroup Id="PayloadComponents" Directory="INSTALLFOLDER">')
    $index = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $StageDirectory -File | Sort-Object Name)) {
        $source = [System.Security.SecurityElement]::Escape($file.FullName)
        $name = [System.Security.SecurityElement]::Escape($file.Name)
        $id = $index.ToString("D3")
        $lines.Add("      <Component Id=`"PayloadComponent_$id`" Guid=`"*`">")
        $lines.Add("        <File Id=`"PayloadFile_$id`" Source=`"$source`" Name=`"$name`" KeyPath=`"yes`" />")
        $lines.Add('      </Component>')
        $index++
    }
    if ($index -eq 0) {
        throw "Cannot generate an empty WiX payload for $StageDirectory"
    }
    $lines.Add('    </ComponentGroup>')
    $lines.Add('  </Fragment>')
    $lines.Add('</Wix>')
    $lines | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}

function Publish-ValidatedInstallers([string]$StagingPath, [string]$PublishPath) {
    $installers = @(Get-ChildItem -LiteralPath $StagingPath -Filter "*.msi" -File)
    $packagePattern = '^XxSnap-(Modern|Legacy)-(x64|x86)-\d+\.\d+\.\d+\.msi$'
    if ($installers.Count -ne 4 -or
        @($installers | Where-Object { $_.Name -notmatch $packagePattern }).Count -ne 0) {
        throw "Refusing to publish $($installers.Count) installers; expected exactly four."
    }

    $publishParent = Split-Path -Parent $PublishPath
    $publishLeaf = Split-Path -Leaf $PublishPath
    New-Item -ItemType Directory -Path $publishParent -Force | Out-Null
    New-Item -ItemType Directory -Path $PublishPath -Force | Out-Null
    $backupPath = Join-Path $publishParent ".$publishLeaf.backup-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $backupPath | Out-Null
    $publishedNames = [System.Collections.Generic.List[string]]::new()
    $succeeded = $false
    try {
        foreach ($existing in @(Get-ChildItem -LiteralPath $PublishPath -Filter "*.msi" -File |
            Where-Object { $_.Name -match $packagePattern })) {
            Move-Item -LiteralPath $existing.FullName -Destination $backupPath
        }
        foreach ($installer in $installers) {
            Move-Item -LiteralPath $installer.FullName -Destination $PublishPath
            $publishedNames.Add($installer.Name)
        }
        if (@(Get-ChildItem -LiteralPath $PublishPath -Filter "*.msi" -File |
            Where-Object { $_.Name -match $packagePattern }).Count -ne 4) {
            throw "Published installer directory does not contain exactly four MSI files."
        }
        $succeeded = $true
    }
    finally {
        if (-not $succeeded) {
            foreach ($name in $publishedNames) {
                $published = Join-Path $PublishPath $name
                if (Test-Path -LiteralPath $published -PathType Leaf) {
                    Remove-Item -LiteralPath $published -Force
                }
            }
            foreach ($backup in @(Get-ChildItem -LiteralPath $backupPath -File -ErrorAction SilentlyContinue)) {
                Move-Item -LiteralPath $backup.FullName -Destination $PublishPath
            }
        }
        if (Test-Path -LiteralPath $backupPath) {
            Remove-Item -LiteralPath $backupPath -Recurse -Force
        }
    }
}

foreach ($required in @($matrixPath, $wixSource, $license, $icon, $testScript)) {
    Assert-File $required "packaging input"
}
& $testScript -Matrix $matrixPath -MatrixOnly

$licenseText = Get-Content -LiteralPath $license -Raw
if (-not $AllowUnsigned -and -not $SelfTest -and
    $licenseText -match "DEVELOPMENT BUILD NOTICE") {
    throw "Release packaging requires approved XxSnap license text in $license"
}

if ($SelfTest) {
    $selfTestRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $selfTestRoot | Out-Null
    try {
        Copy-Item -LiteralPath $icon -Destination (Join-Path $selfTestRoot "Snipory.ico")
        Copy-Item -LiteralPath $license -Destination (Join-Path $selfTestRoot "License.rtf")
        Write-PayloadManifest $selfTestRoot
        $generatedSource = Join-Path $selfTestRoot "Payload.wxs"
        Write-PayloadWixSource $selfTestRoot $generatedSource
        [xml]$generated = Get-Content -LiteralPath $generatedSource -Raw
        $components = @($generated.Wix.Fragment.ComponentGroup.Component)
        if ($generated.Wix.Fragment.ComponentGroup.Id -ne "PayloadComponents" -or
            $components.Count -ne 3) {
            throw "Generated WiX 4 payload self-test failed."
        }

        $publishStaging = Join-Path $selfTestRoot "publish-staging"
        $publishTarget = Join-Path $selfTestRoot "publish-target"
        New-Item -ItemType Directory -Path $publishStaging,$publishTarget | Out-Null
        $oldPackage = Join-Path $publishTarget "XxSnap-Modern-x64-0.0.9.msi"
        $unrelatedPackage = Join-Path $publishTarget "Vendor-Tools-1.0.0.msi"
        "old" | Set-Content -LiteralPath $oldPackage
        "unrelated" | Set-Content -LiteralPath $unrelatedPackage
        foreach ($name in @(
            "XxSnap-Modern-x64-0.1.0.msi",
            "XxSnap-Modern-x86-0.1.0.msi",
            "XxSnap-Legacy-x64-0.1.0.msi",
            "XxSnap-Legacy-x86-0.1.0.msi"
        )) {
            "new" | Set-Content -LiteralPath (Join-Path $publishStaging $name)
        }
        Publish-ValidatedInstallers $publishStaging $publishTarget
        $publishedXxSnap = @(Get-ChildItem -LiteralPath $publishTarget -Filter "XxSnap-*.msi" -File)
        if ($publishedXxSnap.Count -ne 4 -or
            (Test-Path -LiteralPath $oldPackage) -or
            -not (Test-Path -LiteralPath $unrelatedPackage)) {
            throw "Transactional installer publish self-test failed."
        }
        Write-Output "WiX 4 payload generation and transactional publish self-tests passed."
    }
    finally {
        if (Test-Path -LiteralPath $selfTestRoot) {
            Remove-Item -LiteralPath $selfTestRoot -Recurse -Force
        }
    }
    return
}

$thumbprint = ([string]$env:XXSNAP_SIGN_CERT_THUMBPRINT).Replace(" ", "")
$signTool = $null
if ($thumbprint) {
    $signTool = Resolve-SignTool
} elseif (-not $AllowUnsigned) {
    throw "Release MSI signing requires XXSNAP_SIGN_CERT_THUMBPRINT. Use -AllowUnsigned only for local validation."
}

$dotnet = Resolve-DotnetSdk
$definition = Get-Content -LiteralPath $matrixPath -Raw | ConvertFrom-Json
$packages = @($definition.packages)
$publishPath = [System.IO.Path]::GetFullPath($OutputDirectory)
$publishParent = Split-Path -Parent $publishPath
$publishLeaf = Split-Path -Leaf $publishPath
if (-not $publishParent -or -not $publishLeaf) {
    throw "OutputDirectory must be a dedicated non-root directory: $publishPath"
}
New-Item -ItemType Directory -Path $publishParent -Force | Out-Null
$outputPath = Join-Path $publishParent ".$publishLeaf.staging-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null

try {
    Push-Location $sourceRoot
    try {
        & $dotnet tool restore
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet tool restore failed with exit code $LASTEXITCODE"
        }

        foreach ($package in $packages) {
            $binary = Join-Path $BuildRoot "$($package.buildDirectory)\platforms\win\xxsnap_windows.exe"
            Assert-File $binary "$($package.name) executable"
            $versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($binary)
            if ($versionInfo.FileVersion -ne $Version -or
                $versionInfo.ProductVersion -ne $Version) {
                throw "$($package.name) executable must have FileVersion and ProductVersion $Version; found '$($versionInfo.FileVersion)' and '$($versionInfo.ProductVersion)'."
            }

            $stageDirectory = Join-Path $outputPath "stage\$($package.name)"
            New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
            Copy-Item -LiteralPath $binary -Destination (Join-Path $stageDirectory "xxsnap_windows.exe")
            Copy-Item -LiteralPath $icon -Destination (Join-Path $stageDirectory "Snipory.ico")
            Copy-Item -LiteralPath $license -Destination (Join-Path $stageDirectory "License.rtf")
            Copy-RuntimePayload $package $stageDirectory
            Write-PayloadManifest $stageDirectory

            $msi = Join-Path $outputPath "$($package.name)-$Version.msi"
            $intermediate = Join-Path $outputPath "obj\$($package.name)"
            New-Item -ItemType Directory -Path $intermediate -Force | Out-Null
            $payloadWixSource = Join-Path $intermediate "Payload.wxs"
            Write-PayloadWixSource $stageDirectory $payloadWixSource
            $wixArguments = @(
                "tool", "run", "wix", "--", "build", $wixSource, $payloadWixSource,
                "-arch", $package.architecture,
                "-d", "ProductName=$($package.productName)",
                "-d", "Version=$Version",
                "-d", "UpgradeCode=$($package.upgradeCode)",
                "-d", "InstallFolder=$($package.installFolder)",
                "-d", "StageDir=$stageDirectory",
                "-d", "PlatformUpdateD2DMinVersion=$($definition.win7Prerequisites.platformUpdateD2DMinVersion)",
                "-d", "Sha2WinTrustMinVersion=$($definition.win7Prerequisites.sha2WinTrustMinVersion)",
                "-d", "LaunchCondition=$($package.launchCondition)",
                "-d", "LaunchMessage=$($package.launchMessage)",
                "-intermediateFolder", $intermediate,
                "-pdbtype", "none",
                "-out", $msi
            )
            & $dotnet @wixArguments
            if ($LASTEXITCODE -ne 0) {
                throw "WiX build failed for $($package.name) with exit code $LASTEXITCODE"
            }
            Assert-File $msi "$($package.name) MSI"
        }
    }
    finally {
        Pop-Location
    }

    $timestampUrl = if ($env:XXSNAP_SIGN_TIMESTAMP_URL) {
        $env:XXSNAP_SIGN_TIMESTAMP_URL
    } else {
        "http://timestamp.digicert.com"
    }
    if ($thumbprint) {
        foreach ($msi in @(Get-ChildItem -LiteralPath $outputPath -Filter "*.msi" -File)) {
            & $signTool sign /sha1 $thumbprint /fd SHA256 /tr $timestampUrl /td SHA256 $msi.FullName
            if ($LASTEXITCODE -ne 0) {
                throw "Signing failed for $($msi.Name) with exit code $LASTEXITCODE"
            }
            & $signTool verify /pa $msi.FullName
            if ($LASTEXITCODE -ne 0) {
                throw "Signature verification failed for $($msi.Name) with exit code $LASTEXITCODE"
            }
        }
    } else {
        Write-Warning "Building unsigned MSI files for local validation only."
    }

    & $testScript -Directory $outputPath -Matrix $matrixPath
    $validatedHashes = @{}
    foreach ($msi in @(Get-ChildItem -LiteralPath $outputPath -Filter "*.msi" -File)) {
        $validatedHashes[$msi.Name] = (Get-FileHash -LiteralPath $msi.FullName -Algorithm SHA256).Hash
    }
    Publish-ValidatedInstallers $outputPath $publishPath
    foreach ($name in $validatedHashes.Keys) {
        $published = Join-Path $publishPath $name
        Assert-File $published "published MSI"
        if ((Get-FileHash -LiteralPath $published -Algorithm SHA256).Hash -ne $validatedHashes[$name]) {
            throw "Published MSI hash changed after validation: $name"
        }
    }
    Write-Output "Built four validated installers in $publishPath"
}
finally {
    if (Test-Path -LiteralPath $outputPath) {
        Remove-Item -LiteralPath $outputPath -Recurse -Force
    }
}
