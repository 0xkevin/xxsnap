[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("x64", "x86")]
    [string]$Arch = "x64",

    [Parameter()]
    [ValidateRange(4, 1000)]
    [int]$Iterations = 30,

    [Parameter()]
    [string]$BuildRoot = (Join-Path $env:USERPROFILE "build")
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
if (-not ("XxSnapMeasurementWindows" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class XxSnapMeasurementWindows {
    public delegate bool Callback(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] static extern bool EnumWindows(Callback callback, IntPtr parameter);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder value, int capacity);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam);
    static bool PostTo(uint processId, string className, uint message, UIntPtr wParam) {
        bool posted = false;
        EnumWindows((window, parameter) => {
            uint owner;
            GetWindowThreadProcessId(window, out owner);
            if (owner == processId) {
                var value = new StringBuilder(256);
                GetClassName(window, value, value.Capacity);
                if (value.ToString() == className) {
                    posted = PostMessage(window, message, wParam, IntPtr.Zero) || posted;
                }
            }
            return true;
        }, IntPtr.Zero);
        return posted;
    }
    public static bool Cancel(uint processId) {
        return PostTo(processId, "XxSnapCaptureOverlayWindow", 0x0312, new UIntPtr(0x5853));
    }
    public static bool Close(uint processId) {
        return PostTo(processId, "XxSnap.HiddenTopLevelWindow.v1", 0x0010, UIntPtr.Zero);
    }
}
"@
}

function Get-Percentile([double[]]$Values, [double]$Percentile) {
    $sorted = @($Values | Sort-Object)
    $index = [Math]::Max(0, [Math]::Ceiling($Percentile * $sorted.Count) - 1)
    return $sorted[$index]
}

$binary = Join-Path $BuildRoot "xxsnap-modern-$Arch\platforms\win\xxsnap_windows.exe"
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
    throw "Missing executable: $binary. Run run-modern-matrix.ps1 first."
}

$currentSession = (Get-Process -Id $PID).SessionId
$existing = @(Get-Process xxsnap_windows -ErrorAction SilentlyContinue |
    Where-Object SessionId -eq $currentSession)
if ($existing.Count -ne 0) {
    throw "Close the existing XxSnap process in session $currentSession before measuring."
}

$metricsDirectory = Join-Path $BuildRoot "xxsnap-metrics"
New-Item -ItemType Directory -Path $metricsDirectory -Force | Out-Null
$metricsPath = Join-Path $metricsDirectory "capture-$Arch.csv"
[System.IO.File]::WriteAllText(
    $metricsPath,
    "trigger,backend,milliseconds`r`n",
    [System.Text.UTF8Encoding]::new($false)
)

$previousMetricsPath = $env:XXSNAP_CAPTURE_METRICS_PATH
$env:XXSNAP_CAPTURE_METRICS_PATH = $metricsPath
$application = $null
try {
    $application = Start-Process -FilePath $binary -PassThru
    Start-Sleep -Milliseconds 750
    $application.Refresh()
    if ($application.HasExited) {
        throw "XxSnap exited during measurement startup with code $($application.ExitCode)."
    }

    $startupDeadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 25
        $startupMetricCount = (Get-Content -LiteralPath $metricsPath).Count
    } while ($startupMetricCount -le 1 -and [DateTime]::UtcNow -lt $startupDeadline)
    if ($startupMetricCount -le 1) {
        throw "Initial capture did not open during measurement startup."
    }
    if (-not [XxSnapMeasurementWindows]::Cancel([uint32]$application.Id)) {
        throw "Could not close the initial capture overlay before measurement."
    }
    Start-Sleep -Milliseconds 75
    [System.IO.File]::WriteAllText(
        $metricsPath,
        "trigger,backend,milliseconds`r`n",
        [System.Text.UTF8Encoding]::new($false)
    )

    $shell = New-Object -ComObject WScript.Shell
    for ($iteration = 0; $iteration -lt $Iterations; ++$iteration) {
        $before = (Get-Content -LiteralPath $metricsPath).Count
        $shell.SendKeys("^" + [char]96)

        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        do {
            Start-Sleep -Milliseconds 25
            $after = (Get-Content -LiteralPath $metricsPath).Count
        } while ($after -le $before -and [DateTime]::UtcNow -lt $deadline)
        if ($after -le $before) {
            throw "Capture iteration $($iteration + 1) timed out."
        }

        if (-not [XxSnapMeasurementWindows]::Cancel([uint32]$application.Id)) {
            throw "Could not find the capture overlay after iteration $($iteration + 1)."
        }
        Start-Sleep -Milliseconds 75
    }

    if (-not [XxSnapMeasurementWindows]::Close([uint32]$application.Id)) {
        throw "Could not close XxSnap after measurement."
    }
    if (-not $application.WaitForExit(5000)) {
        throw "XxSnap did not exit within 5 seconds after measurement."
    }
    if ($application.ExitCode -ne 0) {
        throw "XxSnap exited after measurement with code $($application.ExitCode)."
    }
}
finally {
    $env:XXSNAP_CAPTURE_METRICS_PATH = $previousMetricsPath
    if ($application -and -not $application.HasExited) {
        Stop-Process -Id $application.Id -Force -ErrorAction SilentlyContinue
    }
}

$all = @(Import-Csv -LiteralPath $metricsPath)
if ($all.Count -ne $Iterations) {
    throw "Expected $Iterations measurements, found $($all.Count)."
}
$samples = @($all | Select-Object -Skip 3)
$values = [double[]]@($samples | ForEach-Object { [double]$_.milliseconds })
$backendCounts = ($samples | Group-Object backend | ForEach-Object {
    "$($_.Name)=$($_.Count)"
}) -join ","

[pscustomobject]@{
    Architecture = $Arch
    Iterations = $Iterations
    WarmupDiscarded = 3
    Samples = $values.Count
    P50Milliseconds = [Math]::Round((Get-Percentile $values 0.50), 3)
    P95Milliseconds = [Math]::Round((Get-Percentile $values 0.95), 3)
    Backends = $backendCounts
    Metrics = $metricsPath
    Note = "VM results are trend-only; no screen content is recorded."
} | Format-List
