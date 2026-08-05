[CmdletBinding()]
param(
    [Parameter()]
    [string]$Directory = (Join-Path $env:USERPROFILE "build\xxsnap-installers"),

    [Parameter()]
    [string]$Matrix,

    [Parameter()]
    [switch]$MatrixOnly
)

$ErrorActionPreference = "Stop"

if (-not $Matrix) {
    $Matrix = Join-Path $PSScriptRoot "..\..\platforms\win\packaging\PackageMatrix.json"
}

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Test-PackageAcceptance($Package, $Environment) {
    $requirements = $Package.requirements
    if ($Environment.productType -ne 1 -or
        $Environment.major -lt $requirements.minimumMajor -or
        $Environment.major -gt $requirements.maximumMajor) {
        return $false
    }
    if ($null -ne $requirements.exactMinor -and
        $Environment.minor -ne $requirements.exactMinor) {
        return $false
    }
    if ($Environment.servicePack -lt $requirements.minimumServicePack -or
        $Environment.architecture -ne $Package.architecture) {
        return $false
    }
    if ($requirements.platformUpdate -and -not $Environment.platformUpdate) {
        return $false
    }
    if ($requirements.sha2 -and -not $Environment.sha2) {
        return $false
    }
    return $true
}

function Invoke-ComMethod($Object, [string]$Name, [object[]]$Arguments) {
    return $Object.GetType().InvokeMember(
        $Name,
        [System.Reflection.BindingFlags]::InvokeMethod,
        $null,
        $Object,
        $Arguments)
}

function Read-MsiScalar($Database, [string]$Sql) {
    $view = Invoke-ComMethod $Database "OpenView" @($Sql)
    [void](Invoke-ComMethod $view "Execute" @())
    $record = Invoke-ComMethod $view "Fetch" @()
    if (-not $record) {
        throw "MSI query returned no rows: $Sql"
    }
    return [string]$record.StringData(1)
}

function Get-PeMachine([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    Assert-True ($bytes.Length -ge 0x40) "PE file is too small: $Path"
    Assert-True ($bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A) "Missing MZ signature: $Path"
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    Assert-True ($peOffset -ge 0 -and $peOffset + 6 -le $bytes.Length) "Invalid PE offset: $Path"
    Assert-True (
        $bytes[$peOffset] -eq 0x50 -and
        $bytes[$peOffset + 1] -eq 0x45 -and
        $bytes[$peOffset + 2] -eq 0 -and
        $bytes[$peOffset + 3] -eq 0) "Missing PE signature: $Path"
    return [BitConverter]::ToUInt16($bytes, $peOffset + 4)
}

$matrixPath = (Resolve-Path -LiteralPath $Matrix).ProviderPath
$sourceIcon = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\platforms\win\resources\icons\Snipory.ico")).ProviderPath
$sourceIconHash = (Get-FileHash -LiteralPath $sourceIcon -Algorithm SHA256).Hash
$definition = Get-Content -LiteralPath $matrixPath -Raw | ConvertFrom-Json
$packages = @($definition.packages)
$expectedNames = @(
    "XxSnap-Modern-x64",
    "XxSnap-Modern-x86",
    "XxSnap-Legacy-x64",
    "XxSnap-Legacy-x86"
)
$expectedConditions = @{
    "XxSnap-Modern-x64" = 'ACTION = "ADMIN" OR Installed OR (MsiNTProductType = 1 AND XXSNAP_WINDOWS_MAJOR AND VersionNT64)'
    "XxSnap-Modern-x86" = 'ACTION = "ADMIN" OR Installed OR (MsiNTProductType = 1 AND XXSNAP_WINDOWS_MAJOR AND NOT VersionNT64)'
    "XxSnap-Legacy-x64" = 'ACTION = "ADMIN" OR Installed OR (MsiNTProductType = 1 AND VersionNT = 601 AND ServicePackLevel >= 1 AND VersionNT64 AND XXSNAP_PLATFORM_UPDATE AND XXSNAP_SHA2)'
    "XxSnap-Legacy-x86" = 'ACTION = "ADMIN" OR Installed OR (MsiNTProductType = 1 AND VersionNT = 601 AND ServicePackLevel >= 1 AND NOT VersionNT64 AND XXSNAP_PLATFORM_UPDATE AND XXSNAP_SHA2)'
}

Assert-True ($definition.schemaVersion -eq 1) "Package matrix schemaVersion must be 1."
Assert-True (
    $definition.win7Prerequisites.platformUpdateD2DMinVersion -eq "6.2.9200.16492" -and
    $definition.win7Prerequisites.sha2Update -eq "KB4474419" -and
    $definition.win7Prerequisites.sha2WinTrustMinVersion -eq "6.1.7601.24382") `
    "Windows 7 prerequisite probes must match Platform Update and KB4474419."
Assert-True ($packages.Count -eq 4) "Package matrix must contain exactly four packages."
Assert-True (
    (@($packages.name | Sort-Object) -join "|") -eq
    (@($expectedNames | Sort-Object) -join "|")) `
    "Package matrix names do not match the four approved deliverables."
Assert-True ((@($packages.name | Select-Object -Unique)).Count -eq 4) `
    "Package names must be unique."
Assert-True ((@($packages.upgradeCode | Select-Object -Unique)).Count -eq 4) `
    "UpgradeCode values must be unique."
Assert-True ((@($packages.installFolder | Select-Object -Unique)).Count -eq 4) `
    "Install folders must be unique."

foreach ($package in $packages) {
    $guid = [guid]::Empty
    Assert-True ([guid]::TryParse([string]$package.upgradeCode, [ref]$guid)) `
        "Invalid UpgradeCode for $($package.name)."
    Assert-True ($guid -ne [guid]::Empty) "UpgradeCode cannot be empty for $($package.name)."
    Assert-True ($package.productName -eq $package.name) `
        "ProductName must match package name for $($package.name)."
    Assert-True ($package.launchCondition -eq $expectedConditions[$package.name]) `
        "Unexpected LaunchCondition for $($package.name)."
    Assert-True ($package.launchMessage) "LaunchCondition message is required for $($package.name)."
    Assert-True ($package.requirements.minimumMajor -le $package.requirements.maximumMajor) `
        "Invalid OS range for $($package.name)."
    if ($package.family -eq "modern") {
        Assert-True (
            $package.requirements.minimumMajor -eq 10 -and
            $package.requirements.maximumMajor -eq 10 -and
            $package.requirements.minimumServicePack -eq 0 -and
            -not $package.requirements.platformUpdate -and
            -not $package.requirements.sha2) `
            "Modern requirements are invalid for $($package.name)."
    } elseif ($package.family -eq "legacy") {
        Assert-True (
            $package.requirements.minimumMajor -eq 6 -and
            $package.requirements.maximumMajor -eq 6 -and
            $package.requirements.exactMinor -eq 1 -and
            $package.requirements.minimumServicePack -eq 1 -and
            $package.requirements.platformUpdate -and
            $package.requirements.sha2) `
            "Legacy requirements are invalid for $($package.name)."
    } else {
        throw "Unknown package family '$($package.family)'."
    }
}

$environments = @(
    [pscustomobject]@{ name = "Windows 11 x64"; productType = 1; major = 10; minor = 0; servicePack = 0; architecture = "x64"; platformUpdate = $true; sha2 = $true; expected = "XxSnap-Modern-x64" },
    [pscustomobject]@{ name = "Windows 10 x64"; productType = 1; major = 10; minor = 0; servicePack = 0; architecture = "x64"; platformUpdate = $true; sha2 = $true; expected = "XxSnap-Modern-x64" },
    [pscustomobject]@{ name = "Windows 10 x86"; productType = 1; major = 10; minor = 0; servicePack = 0; architecture = "x86"; platformUpdate = $true; sha2 = $true; expected = "XxSnap-Modern-x86" },
    [pscustomobject]@{ name = "Windows 7 SP1 x64 patched"; productType = 1; major = 6; minor = 1; servicePack = 1; architecture = "x64"; platformUpdate = $true; sha2 = $true; expected = "XxSnap-Legacy-x64" },
    [pscustomobject]@{ name = "Windows 7 SP1 x86 patched"; productType = 1; major = 6; minor = 1; servicePack = 1; architecture = "x86"; platformUpdate = $true; sha2 = $true; expected = "XxSnap-Legacy-x86" },
    [pscustomobject]@{ name = "Windows 7 RTM x64"; productType = 1; major = 6; minor = 1; servicePack = 0; architecture = "x64"; platformUpdate = $true; sha2 = $true; expected = $null },
    [pscustomobject]@{ name = "Windows 7 x64 missing Platform Update"; productType = 1; major = 6; minor = 1; servicePack = 1; architecture = "x64"; platformUpdate = $false; sha2 = $true; expected = $null },
    [pscustomobject]@{ name = "Windows 7 x86 missing SHA-2"; productType = 1; major = 6; minor = 1; servicePack = 1; architecture = "x86"; platformUpdate = $true; sha2 = $false; expected = $null },
    [pscustomobject]@{ name = "Windows Server 2022 x64"; productType = 3; major = 10; minor = 0; servicePack = 0; architecture = "x64"; platformUpdate = $true; sha2 = $true; expected = $null },
    [pscustomobject]@{ name = "Windows Server 2008 R2 SP1 x64"; productType = 3; major = 6; minor = 1; servicePack = 1; architecture = "x64"; platformUpdate = $true; sha2 = $true; expected = $null }
)
foreach ($environment in $environments) {
    $accepted = @($packages | Where-Object {
        Test-PackageAcceptance $_ $environment
    })
    if ($environment.expected) {
        Assert-True ($accepted.Count -eq 1 -and $accepted[0].name -eq $environment.expected) `
            "$($environment.name) must accept only $($environment.expected)."
    } else {
        Assert-True ($accepted.Count -eq 0) `
            "$($environment.name) must reject all packages."
    }
}

if ($MatrixOnly) {
    Write-Output "Package matrix validation passed: four identities and ten OS gates."
    return
}

$installerDirectory = (Resolve-Path -LiteralPath $Directory).ProviderPath
$msiFiles = @(Get-ChildItem -LiteralPath $installerDirectory -Filter "*.msi" -File)
Assert-True ($msiFiles.Count -eq 4) `
    "Expected exactly four MSI files in '$installerDirectory', found $($msiFiles.Count)."

$installer = New-Object -ComObject WindowsInstaller.Installer
foreach ($package in $packages) {
    $matching = @($msiFiles | Where-Object {
        $_.Name -match "^$([regex]::Escape($package.name))-\d+\.\d+\.\d+\.msi$"
    })
    Assert-True ($matching.Count -eq 1) "Missing or duplicate MSI for $($package.name)."
    $msi = $matching[0]
    $database = Invoke-ComMethod $installer "OpenDatabase" @($msi.FullName, 0)
    $productName = Read-MsiScalar $database `
        "SELECT ``Value`` FROM ``Property`` WHERE ``Property``='ProductName'"
    $upgradeCode = Read-MsiScalar $database `
        "SELECT ``Value`` FROM ``Property`` WHERE ``Property``='UpgradeCode'"
    $productVersion = Read-MsiScalar $database `
        "SELECT ``Value`` FROM ``Property`` WHERE ``Property``='ProductVersion'"
    $launchCondition = Read-MsiScalar $database `
        "SELECT ``Condition`` FROM ``LaunchCondition`` WHERE ``Description``='$($package.launchMessage.Replace("'", "''"))'"
    Assert-True ($productName -eq $package.productName) "ProductName mismatch in $($msi.Name)."
    Assert-True ($upgradeCode -eq $package.upgradeCode) "UpgradeCode mismatch in $($msi.Name)."
    Assert-True ($msi.BaseName -eq "$($package.name)-$productVersion") `
        "MSI file name and ProductVersion mismatch in $($msi.Name)."
    Assert-True ($launchCondition -eq $package.launchCondition) `
        "LaunchCondition mismatch in $($msi.Name)."

    $summary = Invoke-ComMethod $installer "SummaryInformation" @($msi.FullName, 0)
    $template = [string]$summary.Property(7)
    $expectedTemplate = if ($package.architecture -eq "x64") { "x64" } else { "Intel" }
    Assert-True ($template.StartsWith("$expectedTemplate;")) `
        "MSI architecture mismatch in $($msi.Name): $template"

    $extractRoot = Join-Path $env:TEMP "XxSnap installer extract $([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $extractRoot | Out-Null
    try {
        & msiexec.exe /a $msi.FullName /qn "TARGETDIR=$extractRoot"
        $extractExitCode = $LASTEXITCODE
        Assert-True ($extractExitCode -eq 0) `
            "Administrative extraction failed for $($msi.Name) with code $extractExitCode."
        $manifests = @(Get-ChildItem -LiteralPath $extractRoot -Filter "payload-manifest.json" -File -Recurse)
        Assert-True ($manifests.Count -eq 1) `
            "Expected one payload manifest in $($msi.Name), found $($manifests.Count)."
        $payloadRoot = $manifests[0].Directory.FullName
        $payload = Get-Content -LiteralPath $manifests[0].FullName -Raw | ConvertFrom-Json
        $manifestPaths = @($payload.files.relativePath | Sort-Object)
        $actualPaths = @(
            Get-ChildItem -LiteralPath $payloadRoot -File -Recurse |
                Where-Object { $_.Name -ne "payload-manifest.json" } |
                ForEach-Object { $_.FullName.Substring($payloadRoot.Length).TrimStart([char]'\') } |
                Sort-Object
        )
        Assert-True (($manifestPaths -join "|") -eq ($actualPaths -join "|")) `
            "Payload manifest does not enumerate every installed file in $($msi.Name)."
        foreach ($entry in $payload.files) {
            $path = Join-Path $payloadRoot $entry.relativePath
            Assert-True (Test-Path -LiteralPath $path -PathType Leaf) `
                "Missing payload '$($entry.relativePath)' in $($msi.Name)."
            $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            Assert-True ($actualHash -eq $entry.sha256) `
                "Payload hash mismatch for '$($entry.relativePath)' in $($msi.Name)."
        }
        Assert-True (Test-Path -LiteralPath (Join-Path $payloadRoot "xxsnap_windows.exe")) `
            "Application executable is missing from $($msi.Name)."
        $installedIcon = Join-Path $payloadRoot "Snipory.ico"
        Assert-True (Test-Path -LiteralPath $installedIcon) `
            "Original icon is missing from $($msi.Name)."
        Assert-True ((Get-FileHash -LiteralPath $installedIcon -Algorithm SHA256).Hash -eq $sourceIconHash) `
            "Original icon bytes changed in $($msi.Name)."
        Assert-True (Test-Path -LiteralPath (Join-Path $payloadRoot "License.rtf")) `
            "License is missing from $($msi.Name)."
        foreach ($runtime in @("msvcp140.dll", "vcruntime140.dll")) {
            Assert-True (Test-Path -LiteralPath (Join-Path $payloadRoot $runtime)) `
                "VC runtime '$runtime' is missing from $($msi.Name)."
        }
        if ($package.family -eq "legacy") {
            foreach ($runtime in @("ucrtbase.dll", "api-ms-win-crt-runtime-l1-1-0.dll")) {
                Assert-True (Test-Path -LiteralPath (Join-Path $payloadRoot $runtime)) `
                    "UCRT runtime '$runtime' is missing from $($msi.Name)."
            }
        }
        $expectedMachine = if ($package.architecture -eq "x64") { 0x8664 } else { 0x014C }
        $installedExecutable = Join-Path $payloadRoot "xxsnap_windows.exe"
        $actualMachine = Get-PeMachine $installedExecutable
        Assert-True ($actualMachine -eq $expectedMachine) `
            "Executable architecture mismatch in $($msi.Name): 0x$($actualMachine.ToString('X4'))"
        $versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($installedExecutable)
        Assert-True (
            $versionInfo.FileVersion -eq $productVersion -and
            $versionInfo.ProductVersion -eq $productVersion) `
            "Executable version does not match MSI ProductVersion in $($msi.Name)."
    }
    finally {
        if (Test-Path -LiteralPath $extractRoot) {
            Remove-Item -LiteralPath $extractRoot -Recurse -Force
        }
    }
}

Write-Output "Installer validation passed: four MSI identities, gates, architectures, and payload hashes."
