<#
.SYNOPSIS
    Switches a Windows laptop between Battery Saver and Gaming Performance profiles.

.DESCRIPTION
    Zero-dependency Windows PowerShell 5.1+ utility designed for Modern Standby (S0)
    laptops. Adjusts PROCTHROTTLEMAX under SCHEME_CURRENT, toggles Windows 11 Power Mode
    overlays (Best Power Efficiency / Best Performance), controls internal WMI display
    brightness, switches display refresh rates via Display-Helper.ps1, and manages
    background or gaming applications from config.json.

.EXAMPLE
    .\src\Switch-Mode.ps1 -Mode battery

.EXAMPLE
    .\src\Switch-Mode.ps1 -Mode gaming

.EXAMPLE
    .\src\Switch-Mode.ps1 -Status
#>

[CmdletBinding()]
param(
    [ValidateSet('battery', 'normal', 'gaming')]
    [string]$Mode,

    [switch]$Status,

    [switch]$Specs,

    [string]$ConfigPath = '',

    [switch]$Quiet,

    [switch]$PassThru
)

$script:ScriptRootDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:DefaultConfigPath = Join-Path (Split-Path -Parent $script:ScriptRootDir) 'config.json'
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = $script:DefaultConfigPath
}

$displayHelperPath = Join-Path $script:ScriptRootDir 'Display-Helper.ps1'
if (Test-Path -LiteralPath $displayHelperPath) {
    . $displayHelperPath
}

$script:PowerOverlayGuids = @{
    BestPowerEfficiency = '961cc777-2547-4f9d-8174-7d86181b8a7a'
    Balanced            = '00000000-0000-0000-0000-000000000000'
    BetterPerformance   = '3af9b8d9-7c97-431d-ad78-34a8bfea439f'
    BestPerformance     = 'ded574b5-45a0-4f42-8737-46345c09c238'
}

function Initialize-PowerOverlayNativeApi {
    if (-not ([System.Management.Automation.PSTypeName]'WinPowerToggle.PowerOverlayNative').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace WinPowerToggle {
    public class OverlayQueryResult {
        public uint ReturnCode { get; set; }
        public string Guid { get; set; }
    }

    public class SystemPowerNativeResult {
        public int AcLineStatus { get; set; }
        public int BatteryFlag { get; set; }
        public int BatteryLifePercent { get; set; }
        public bool HasBattery { get; set; }
        public bool IsCharging { get; set; }
    }

    public static class PowerOverlayNative {
        [StructLayout(LayoutKind.Sequential)]
        private struct SYSTEM_POWER_STATUS {
            public byte ACLineStatus;
            public byte BatteryFlag;
            public byte BatteryLifePercent;
            public byte SystemStatusFlag;
            public int BatteryLifeTime;
            public int BatteryFullLifeTime;
        }

        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern uint PowerGetActualOverlayScheme(out Guid ActualOverlayGuid);

        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern uint PowerGetEffectiveOverlayScheme(out Guid EffectiveOverlayGuid);

        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern uint PowerSetActiveOverlayScheme(Guid OverlaySchemeGuid);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS lpSystemPowerStatus);

        public static OverlayQueryResult GetActiveOverlay() {
            Guid guid = Guid.Empty;
            uint rc = PowerGetActualOverlayScheme(out guid);
            if (rc != 0) {
                rc = PowerGetEffectiveOverlayScheme(out guid);
            }
            return new OverlayQueryResult {
                ReturnCode = rc,
                Guid = guid.ToString("D")
            };
        }

        public static uint SetActiveOverlay(string guidString) {
            Guid guid = new Guid(guidString);
            return PowerSetActiveOverlayScheme(guid);
        }

        public static SystemPowerNativeResult GetSystemPowerInfo() {
            SYSTEM_POWER_STATUS sps;
            if (!GetSystemPowerStatus(out sps)) {
                return null;
            }
            bool noBattery = ((sps.BatteryFlag & 128) != 0) || (sps.BatteryFlag == 255);
            bool charging = !noBattery && ((sps.BatteryFlag & 8) != 0);
            return new SystemPowerNativeResult {
                AcLineStatus = sps.ACLineStatus,
                BatteryFlag = sps.BatteryFlag,
                BatteryLifePercent = sps.BatteryLifePercent,
                HasBattery = !noBattery,
                IsCharging = charging
            };
        }
    }
}
"@
    }
}

function Test-HasProperty {
    param(
        $Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $false
    }
    return ($null -ne $Object.PSObject.Properties[$Name])
}

function ConvertTo-StringArray {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }

    $list = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Value)) {
        if ($null -ne $item) {
            $text = "$item".Trim()
            if ($text.Length -gt 0) {
                $list.Add($text)
            }
        }
    }
    return $list.ToArray()
}

function Validate-ProfileSection {
    param(
        $Section,
        [string]$SectionName
    )

    if ($null -eq $Section) {
        throw "Configuration error: missing required '$SectionName' section."
    }

    if ((Test-HasProperty $Section 'brightness') -and $null -ne $Section.brightness) {
        $b = 0
        if (-not [int]::TryParse("$($Section.brightness)", [ref]$b) -or $b -lt 0 -or $b -gt 100) {
            throw "Configuration error: '$SectionName.brightness' must be an integer between 0 and 100 (got '$($Section.brightness)')."
        }
    }

    if ((Test-HasProperty $Section 'maxCpuState') -and $null -ne $Section.maxCpuState) {
        $cpu = 0
        if (-not [int]::TryParse("$($Section.maxCpuState)", [ref]$cpu) -or $cpu -lt 0 -or $cpu -gt 100) {
            throw "Configuration error: '$SectionName.maxCpuState' must be an integer between 0 and 100 (got '$($Section.maxCpuState)')."
        }
    }

    if ((Test-HasProperty $Section 'refreshRate') -and $null -ne $Section.refreshRate) {
        $rateText = "$($Section.refreshRate)".Trim().ToLowerInvariant()
        if ($rateText -ne 'max' -and $rateText -ne 'min') {
            $hz = 0
            if (-not [int]::TryParse($rateText, [ref]$hz) -or $hz -lt 0) {
                throw "Configuration error: '$SectionName.refreshRate' must be a positive integer, 0, 'max', or 'min' (got '$($Section.refreshRate)')."
            }
        }
    }
}

function Get-PowerToggleConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configuration file not found: $Path"
    }

    $rawJson = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    try {
        $parsed = $rawJson | ConvertFrom-Json
    }
    catch {
        throw "Invalid JSON in configuration file '$Path': $($_.Exception.Message)"
    }

    if (-not (Test-HasProperty $parsed 'batteryMode')) {
        throw "Configuration error: missing required 'batteryMode' section in '$Path'."
    }
    if (-not (Test-HasProperty $parsed 'gamingMode')) {
        throw "Configuration error: missing required 'gamingMode' section in '$Path'."
    }

    Validate-ProfileSection -Section $parsed.batteryMode -SectionName 'batteryMode'
    Validate-ProfileSection -Section $parsed.gamingMode -SectionName 'gamingMode'

    $hasNormal = Test-HasProperty $parsed 'normalMode'
    if ($hasNormal -and $null -ne $parsed.normalMode) {
        Validate-ProfileSection -Section $parsed.normalMode -SectionName 'normalMode'
    }

    $normalBrightness = if ($hasNormal -and (Test-HasProperty $parsed.normalMode 'brightness')) { $parsed.normalMode.brightness } else { 70 }
    $normalRefresh = if ($hasNormal -and (Test-HasProperty $parsed.normalMode 'refreshRate')) { $parsed.normalMode.refreshRate } else { 144 }
    $normalCpu = if ($hasNormal -and (Test-HasProperty $parsed.normalMode 'maxCpuState')) { $parsed.normalMode.maxCpuState } else { 100 }

    return [PSCustomObject]@{
        batteryMode = [PSCustomObject]@{
            brightness        = if (Test-HasProperty $parsed.batteryMode 'brightness') { $parsed.batteryMode.brightness } else { $null }
            refreshRate       = if (Test-HasProperty $parsed.batteryMode 'refreshRate') { $parsed.batteryMode.refreshRate } else { $null }
            maxCpuState       = if (Test-HasProperty $parsed.batteryMode 'maxCpuState') { $parsed.batteryMode.maxCpuState } else { $null }
            forceBatterySaver = if (Test-HasProperty $parsed.batteryMode 'forceBatterySaver') { [bool]$parsed.batteryMode.forceBatterySaver } else { $false }
            appsToKill        = if (Test-HasProperty $parsed.batteryMode 'appsToKill') { ConvertTo-StringArray $parsed.batteryMode.appsToKill } else { @() }
        }
        normalMode = [PSCustomObject]@{
            brightness  = $normalBrightness
            refreshRate = $normalRefresh
            maxCpuState = $normalCpu
        }
        gamingMode = [PSCustomObject]@{
            brightness   = if (Test-HasProperty $parsed.gamingMode 'brightness') { $parsed.gamingMode.brightness } else { $null }
            refreshRate  = if (Test-HasProperty $parsed.gamingMode 'refreshRate') { $parsed.gamingMode.refreshRate } else { $null }
            maxCpuState  = if (Test-HasProperty $parsed.gamingMode 'maxCpuState') { $parsed.gamingMode.maxCpuState } else { $null }
            appsToLaunch = if (Test-HasProperty $parsed.gamingMode 'appsToLaunch') { ConvertTo-StringArray $parsed.gamingMode.appsToLaunch } else { @() }
        }
    }
}

function Invoke-PowerCfg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $outputLines = & powercfg.exe @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output   = (($outputLines | ForEach-Object { "$_" }) -join [Environment]::NewLine)
    }
}

function Get-ActivePowerScheme {
    [CmdletBinding()]
    param()

    try {
        $res = Invoke-PowerCfg -Arguments @('/getactivescheme')
        if ($res.ExitCode -eq 0 -and $res.Output -match 'Power Scheme GUID:\s*([0-9a-fA-F-]+)\s*\(([^)]+)\)') {
            return [PSCustomObject]@{
                Guid = $Matches[1].ToLowerInvariant()
                Name = $Matches[2].Trim()
            }
        }
    }
    catch {
        # Handled below via graceful fallback
    }

    return [PSCustomObject]@{
        Guid = 'Unknown'
        Name = 'Unknown'
    }
}

function Get-CpuMaxState {
    [CmdletBinding()]
    param()

    $acPercent = $null
    $dcPercent = $null

    try {
        $res = Invoke-PowerCfg -Arguments @('/q', 'SCHEME_CURRENT', 'SUB_PROCESSOR', 'PROCTHROTTLEMAX')
        if ($res.ExitCode -eq 0) {
            if ($res.Output -match 'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)') {
                $acPercent = [Convert]::ToInt32($Matches[1], 16)
            }
            if ($res.Output -match 'Current DC Power Setting Index:\s*0x([0-9a-fA-F]+)') {
                $dcPercent = [Convert]::ToInt32($Matches[1], 16)
            }
        }
    }
    catch {
        # Graceful fallback with null values
    }

    return [PSCustomObject]@{
        AcPercent = $acPercent
        DcPercent = $dcPercent
    }
}

function Set-CpuMaxState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Percent
    )

    if ($Percent -lt 0 -or $Percent -gt 100) {
        return [PSCustomObject]@{
            Status  = 'Skipped'
            Percent = $null
            Message = "Invalid CPU max state percentage '$Percent' (expected 0-100)."
        }
    }

    $commands = @(
        @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_PROCESSOR', 'PROCTHROTTLEMAX', "$Percent"),
        @('/setdcvalueindex', 'SCHEME_CURRENT', 'SUB_PROCESSOR', 'PROCTHROTTLEMAX', "$Percent"),
        @('/setactive', 'SCHEME_CURRENT')
    )

    foreach ($cmdArgs in $commands) {
        try {
            $res = Invoke-PowerCfg -Arguments $cmdArgs
            if ($res.ExitCode -ne 0) {
                $detail = if ([string]::IsNullOrWhiteSpace($res.Output)) { "exit code $($res.ExitCode)" } else { $res.Output.Trim() }
                return [PSCustomObject]@{
                    Status  = 'Skipped'
                    Percent = $null
                    Message = "powercfg failed while running '$($cmdArgs -join ' ')': $detail"
                }
            }
        }
        catch {
            return [PSCustomObject]@{
                Status  = 'Skipped'
                Percent = $null
                Message = "powercfg error while setting CPU max state: $($_.Exception.Message)"
            }
        }
    }

    return [PSCustomObject]@{
        Status  = 'Changed'
        Percent = $Percent
        Message = "Set PROCTHROTTLEMAX (AC/DC) to ${Percent}% on SCHEME_CURRENT."
    }
}

function Get-PowerOverlayFriendlyName {
    [CmdletBinding()]
    param(
        [string]$Guid
    )

    if ([string]::IsNullOrWhiteSpace($Guid)) {
        return 'Unavailable'
    }

    switch ($Guid.Trim().ToLowerInvariant()) {
        '961cc777-2547-4f9d-8174-7d86181b8a7a' { return 'Best Power Efficiency' }
        '00000000-0000-0000-0000-000000000000' { return 'Balanced' }
        '381b4222-f694-41f0-9685-ff5bb260df2e' { return 'Balanced' }
        '3af9b8d9-7c97-431d-ad78-34a8bfea439f' { return 'Better Performance' }
        'ded574b5-45a0-4f42-8737-46345c09c238' { return 'Best Performance' }
        default { return "Custom ($Guid)" }
    }
}

function Invoke-GetPowerOverlayNative {
    [CmdletBinding()]
    param()

    Initialize-PowerOverlayNativeApi
    $res = [WinPowerToggle.PowerOverlayNative]::GetActiveOverlay()
    return [PSCustomObject]@{
        ReturnCode = [uint32]$res.ReturnCode
        Guid       = $res.Guid
    }
}

function Invoke-SetPowerOverlayNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Guid
    )

    Initialize-PowerOverlayNativeApi
    return [uint32][WinPowerToggle.PowerOverlayNative]::SetActiveOverlay($Guid)
}

function Get-PowerModeOverlay {
    [CmdletBinding()]
    param()

    try {
        $res = Invoke-GetPowerOverlayNative
        if ($res.ReturnCode -eq 0) {
            return [PSCustomObject]@{
                Guid      = $res.Guid.ToLowerInvariant()
                Name      = Get-PowerOverlayFriendlyName -Guid $res.Guid
                Supported = $true
            }
        }
    }
    catch {
        # Graceful fallback when overlay API is unavailable
    }

    return [PSCustomObject]@{
        Guid      = $null
        Name      = 'Unavailable'
        Supported = $false
    }
}

function Set-PowerModeOverlay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('BestPowerEfficiency', 'Balanced', 'BestPerformance')]
        [string]$Overlay
    )

    $targetGuid = $script:PowerOverlayGuids[$Overlay]
    $friendlyName = Get-PowerOverlayFriendlyName -Guid $targetGuid

    try {
        $current = Invoke-GetPowerOverlayNative
        if ($current.ReturnCode -eq 0 -and $current.Guid.ToLowerInvariant() -eq $targetGuid) {
            return [PSCustomObject]@{
                Status  = 'Unchanged'
                Overlay = $friendlyName
                Guid    = $targetGuid
                Message = "Windows Power Mode is already '$friendlyName'."
            }
        }

        $rc = Invoke-SetPowerOverlayNative -Guid $targetGuid
        if ($rc -eq 0) {
            return [PSCustomObject]@{
                Status  = 'Changed'
                Overlay = $friendlyName
                Guid    = $targetGuid
                Message = "Set Windows Power Mode overlay to '$friendlyName'."
            }
        }

        return [PSCustomObject]@{
            Status  = 'Skipped'
            Overlay = $null
            Guid    = $null
            Message = "Windows Power Mode overlay '$friendlyName' was rejected or unsupported (code $rc)."
        }
    }
    catch {
        return [PSCustomObject]@{
            Status  = 'Skipped'
            Overlay = $null
            Guid    = $null
            Message = "Windows Power Mode overlay API unavailable: $($_.Exception.Message)"
        }
    }
}

function Get-BrightnessCimInstance {
    [CmdletBinding()]
    param()

    return Get-CimInstance -Namespace 'root/WMI' -ClassName 'WmiMonitorBrightness' -ErrorAction Stop
}

function Get-BrightnessMethodsCimInstance {
    [CmdletBinding()]
    param()

    return Get-CimInstance -Namespace 'root/WMI' -ClassName 'WmiMonitorBrightnessMethods' -ErrorAction Stop
}

function Invoke-SetBrightnessCimMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Instance,

        [Parameter(Mandatory = $true)]
        [byte]$Percent
    )

    $null = Invoke-CimMethod -InputObject $Instance -MethodName 'WmiSetBrightness' -Arguments @{
        Timeout    = [uint32]1
        Brightness = $Percent
    } -ErrorAction Stop
}

function Get-DisplayBrightness {
    [CmdletBinding()]
    param()

    try {
        $monitor = Get-BrightnessCimInstance | Select-Object -First 1
        if ($null -ne $monitor -and $null -ne $monitor.CurrentBrightness) {
            return [int]$monitor.CurrentBrightness
        }
    }
    catch {
        # External monitor or desktop without WMI brightness
    }

    return $null
}

function Set-DisplayBrightness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Percent
    )

    if ($Percent -lt 0 -or $Percent -gt 100) {
        return [PSCustomObject]@{
            Status  = 'Skipped'
            Percent = $null
            Message = "Invalid brightness percentage '$Percent' (expected 0-100)."
        }
    }

    try {
        $monitors = @(Get-BrightnessMethodsCimInstance)
        if ($monitors.Count -eq 0) {
            return [PSCustomObject]@{
                Status  = 'Skipped'
                Percent = $null
                Message = 'No internal display with WMI brightness control was detected.'
            }
        }

        foreach ($monitor in $monitors) {
            Invoke-SetBrightnessCimMethod -Instance $monitor -Percent ([byte]$Percent)
        }

        return [PSCustomObject]@{
            Status  = 'Changed'
            Percent = $Percent
            Message = "Set internal display brightness to ${Percent}%."
        }
    }
    catch {
        return [PSCustomObject]@{
            Status  = 'Skipped'
            Percent = $null
            Message = "Skipped WMI brightness control (external monitor or unsupported hardware): $($_.Exception.Message)"
        }
    }
}

function Get-RunningProcessByName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
}

function Invoke-StopProcessById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Id
    )

    Stop-Process -Id $Id -Force -ErrorAction Stop
}

function Invoke-StartProcessPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string]$WorkingDirectory
    )

    if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        Start-Process -FilePath $FilePath -ErrorAction Stop
    }
    else {
        Start-Process -FilePath $FilePath -WorkingDirectory $WorkingDirectory -ErrorAction Stop
    }
}

function Stop-ConfiguredApps {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [string[]]$AppNames = @()
    )

    $stopped = New-Object System.Collections.Generic.List[string]
    $notRunning = New-Object System.Collections.Generic.List[string]
    $failed = New-Object System.Collections.Generic.List[string]

    foreach ($rawName in $AppNames) {
        if ([string]::IsNullOrWhiteSpace($rawName)) {
            continue
        }

        $normalized = $rawName.Trim() -replace '\.exe$', ''
        $procs = @(Get-RunningProcessByName -Name $normalized)

        if ($procs.Count -eq 0) {
            $notRunning.Add($normalized)
            continue
        }

        $stoppedAny = $false
        $hadError = $false
        foreach ($proc in $procs) {
            try {
                Invoke-StopProcessById -Id $proc.Id
                $stoppedAny = $true
            }
            catch {
                $errMsg = $_.Exception.Message
                if ($errMsg -match 'Cannot find a process|has exited') {
                    $stoppedAny = $true
                }
                else {
                    $hadError = $true
                    $failed.Add("${normalized} (PID $($proc.Id)): $errMsg")
                }
            }
        }

        if ($stoppedAny -and -not $hadError) {
            $stopped.Add($normalized)
        }
        elseif ($stoppedAny) {
            $stopped.Add($normalized)
        }
    }

    $status = if ($stopped.Count -gt 0) { 'Changed' } elseif ($failed.Count -gt 0) { 'Skipped' } else { 'Unchanged' }
    $parts = New-Object System.Collections.Generic.List[string]
    if ($stopped.Count -gt 0) { $parts.Add("Stopped: $($stopped -join ', ')") }
    if ($notRunning.Count -gt 0) { $parts.Add("Not running: $($notRunning -join ', ')") }
    if ($failed.Count -gt 0) { $parts.Add("Skipped (errors): $($failed -join '; ')") }
    if ($parts.Count -eq 0) { $parts.Add('No apps configured to stop.') }

    return [PSCustomObject]@{
        Status     = $status
        Stopped    = $stopped.ToArray()
        NotRunning = $notRunning.ToArray()
        Failed     = $failed.ToArray()
        Message    = ($parts -join ' | ')
    }
}

function Start-ConfiguredApps {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [string[]]$AppPaths = @()
    )

    $launched = New-Object System.Collections.Generic.List[string]
    $alreadyRunning = New-Object System.Collections.Generic.List[string]
    $missing = New-Object System.Collections.Generic.List[string]
    $failed = New-Object System.Collections.Generic.List[string]

    foreach ($rawPath in $AppPaths) {
        if ([string]::IsNullOrWhiteSpace($rawPath)) {
            continue
        }

        $expandedPath = [Environment]::ExpandEnvironmentVariables($rawPath.Trim())
        if (-not (Test-Path -LiteralPath $expandedPath -PathType Leaf)) {
            $missing.Add($expandedPath)
            continue
        }

        $processName = [System.IO.Path]::GetFileNameWithoutExtension($expandedPath)
        $existing = @(Get-RunningProcessByName -Name $processName)
        if ($existing.Count -gt 0) {
            $alreadyRunning.Add($processName)
            continue
        }

        try {
            $workDir = Split-Path -Parent $expandedPath
            Invoke-StartProcessPath -FilePath $expandedPath -WorkingDirectory $workDir
            $launched.Add($processName)
        }
        catch {
            $failed.Add("${processName}: $($_.Exception.Message)")
        }
    }

    $status = if ($launched.Count -gt 0) { 'Changed' } elseif ($failed.Count -gt 0) { 'Skipped' } else { 'Unchanged' }
    $parts = New-Object System.Collections.Generic.List[string]
    if ($launched.Count -gt 0) { $parts.Add("Launched: $($launched -join ', ')") }
    if ($alreadyRunning.Count -gt 0) { $parts.Add("Already running: $($alreadyRunning -join ', ')") }
    if ($missing.Count -gt 0) { $parts.Add("Not found: $($missing -join ', ')") }
    if ($failed.Count -gt 0) { $parts.Add("Failed: $($failed -join '; ')") }
    if ($parts.Count -eq 0) { $parts.Add('No apps configured to launch.') }

    return [PSCustomObject]@{
        Status         = $status
        Launched       = $launched.ToArray()
        AlreadyRunning = $alreadyRunning.ToArray()
        Missing        = $missing.ToArray()
        Failed         = $failed.ToArray()
        Message        = ($parts -join ' | ')
    }
}

function Get-SystemPowerNativeStatus {
    [CmdletBinding()]
    param()

    try {
        Initialize-PowerOverlayNativeApi
        $native = [WinPowerToggle.PowerOverlayNative]::GetSystemPowerInfo()
        if ($null -eq $native) {
            return $null
        }

        return [PSCustomObject]@{
            AcLineStatus       = [int]$native.AcLineStatus
            BatteryFlag        = [int]$native.BatteryFlag
            BatteryLifePercent = [int]$native.BatteryLifePercent
            HasBattery         = [bool]$native.HasBattery
            IsCharging         = [bool]$native.IsCharging
        }
    }
    catch {
        return $null
    }
}

function Get-BatteryCimInstance {
    [CmdletBinding()]
    param()

    return Get-CimInstance -ClassName 'Win32_Battery' -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Get-SystemPowerStatus {
    [CmdletBinding()]
    param()

    $isOnAc = $true
    $powerSource = 'AC (No Battery Detected)'
    $batteryPercent = $null

    $nativePower = Get-SystemPowerNativeStatus
    if ($null -ne $nativePower) {
        if (-not $nativePower.HasBattery) {
            $isOnAc = $true
            $powerSource = 'AC (No Battery Detected)'
            $batteryPercent = $null
        }
        else {
            if ($nativePower.BatteryLifePercent -ge 0 -and $nativePower.BatteryLifePercent -le 100) {
                $batteryPercent = [int]$nativePower.BatteryLifePercent
            }

            if ($nativePower.AcLineStatus -eq 0) {
                $isOnAc = $false
                $powerSource = 'DC (On Battery)'
            }
            elseif ($nativePower.IsCharging) {
                $isOnAc = $true
                $powerSource = 'AC (Charging)'
            }
            else {
                $isOnAc = $true
                $powerSource = 'AC (Plugged In)'
            }
        }
    }
    else {
        $battery = Get-BatteryCimInstance
        if ($null -ne $battery) {
            $batteryPercent = [int]$battery.EstimatedChargeRemaining
            # Win32_Battery.BatteryStatus: 1,4,5 = Discharging/Low/Critical (DC); 2,3,6,7,8,9 = AC/Charging
            $statusCode = [int]$battery.BatteryStatus
            if ($statusCode -in @(1, 4, 5)) {
                $isOnAc = $false
                $powerSource = 'DC (On Battery)'
            }
            else {
                $isOnAc = $true
                $powerSource = 'AC (Plugged In)'
            }
        }
    }

    $scheme = Get-ActivePowerScheme
    $overlay = Get-PowerModeOverlay
    $cpu = Get-CpuMaxState
    $activeCpuCap = if ($isOnAc) { $cpu.AcPercent } else { $cpu.DcPercent }
    $brightness = Get-DisplayBrightness
    $display = Get-DisplayInfo

    $resolution = if ($null -ne $display) { "$($display.Width)x$($display.Height)" } else { 'Unavailable' }
    $refreshHz = if ($null -ne $display) { $display.RefreshRate } else { $null }
    $supportedHz = if ($null -ne $display -and $null -ne $display.SupportedRefreshRates) { $display.SupportedRefreshRates } else { @() }

    return [PSCustomObject]@{
        PowerSource             = $powerSource
        BatteryPercent          = $batteryPercent
        PowerSchemeName         = $scheme.Name
        PowerSchemeGuid         = $scheme.Guid
        PowerModeOverlay        = $overlay.Name
        CpuMaxStateAc           = $cpu.AcPercent
        CpuMaxStateDc           = $cpu.DcPercent
        ActiveCpuMaxState       = $activeCpuCap
        BrightnessPercent       = $brightness
        DisplayResolution       = $resolution
        RefreshRateHz           = $refreshHz
        SupportedRefreshRatesHz = $supportedHz
    }
}

function Format-SystemPowerStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $StatusObject
    )

    $batteryText = if ($null -ne $StatusObject.BatteryPercent) { "$($StatusObject.BatteryPercent)%" } else { 'N/A' }
    $acCapText = if ($null -ne $StatusObject.CpuMaxStateAc) { "$($StatusObject.CpuMaxStateAc)%" } else { 'N/A' }
    $dcCapText = if ($null -ne $StatusObject.CpuMaxStateDc) { "$($StatusObject.CpuMaxStateDc)%" } else { 'N/A' }
    $activeCapText = if ($null -ne $StatusObject.ActiveCpuMaxState) { "$($StatusObject.ActiveCpuMaxState)%" } else { 'N/A' }
    $brightnessText = if ($null -ne $StatusObject.BrightnessPercent) { "$($StatusObject.BrightnessPercent)%" } else { 'Unsupported / External Display' }
    $refreshText = if ($null -ne $StatusObject.RefreshRateHz) {
        $supportedList = ($StatusObject.SupportedRefreshRatesHz | ForEach-Object { "${_}Hz" }) -join ', '
        if ($supportedList) {
            "$($StatusObject.DisplayResolution) @ $($StatusObject.RefreshRateHz)Hz (Supported: $supportedList)"
        }
        else {
            "$($StatusObject.DisplayResolution) @ $($StatusObject.RefreshRateHz)Hz"
        }
    }
    else {
        'Unavailable'
    }

    return @(
        '=== Win-Power-Toggle System Status ==='
        ("Power Source       : {0}" -f $StatusObject.PowerSource)
        ("Battery Charge     : {0}" -f $batteryText)
        ("Power Scheme       : {0} ({1})" -f $StatusObject.PowerSchemeName, $StatusObject.PowerSchemeGuid)
        ("Windows Power Mode : {0}" -f $StatusObject.PowerModeOverlay)
        ("Max CPU State      : {0} active (AC: {1}, DC: {2})" -f $activeCapText, $acCapText, $dcCapText)
        ("Display Brightness : {0}" -f $brightnessText)
        ("Display Output     : {0}" -f $refreshText)
    ) -join [Environment]::NewLine
}

function Get-HardwareSpecsRaw {
    [CmdletBinding()]
    param()

    try {
        $cpuName = $null
        try {
            $cpuReg = Get-ItemProperty -Path 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -Name 'ProcessorNameString' -ErrorAction Stop
            $cpuName = "$($cpuReg.ProcessorNameString)".Trim() -replace '\s+', ' '
        }
        catch {
            $cpuCim = Get-CimInstance -ClassName 'Win32_Processor' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $cpuCim) {
                $cpuName = "$($cpuCim.Name)".Trim() -replace '\s+', ' '
            }
        }

        $logicalThreads = [Environment]::ProcessorCount
        $gpus = @(Get-CimInstance -ClassName 'Win32_VideoController' -ErrorAction SilentlyContinue |
            ForEach-Object { "$($_.Name)".Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique)

        $cs = Get-CimInstance -ClassName 'Win32_ComputerSystem' -ErrorAction SilentlyContinue | Select-Object -First 1
        $totalMem = if ($null -ne $cs -and $null -ne $cs.TotalPhysicalMemory) { [double]$cs.TotalPhysicalMemory } else { 0 }

        $os = Get-CimInstance -ClassName 'Win32_OperatingSystem' -ErrorAction SilentlyContinue | Select-Object -First 1
        $osCaption = if ($null -ne $os) { "$($os.Caption)".Trim() } else { $null }
        $osBuild = if ($null -ne $os) { "$($os.BuildNumber)".Trim() } else { $null }

        return [PSCustomObject]@{
            CpuName          = $cpuName
            LogicalThreads   = $logicalThreads
            GpuNames         = $gpus
            TotalMemoryBytes = $totalMem
            OsCaption        = $osCaption
            OsBuild          = $osBuild
        }
    }
    catch {
        return $null
    }
}

function Get-ComputerSpecs {
    [CmdletBinding()]
    param()

    $raw = Get-HardwareSpecsRaw
    if ($null -eq $raw) {
        return [PSCustomObject]@{
            Cpu    = 'Unavailable'
            Gpu    = 'Unavailable'
            Memory = 'Unavailable'
            Os     = 'Unavailable'
        }
    }

    $cpuText = if (-not [string]::IsNullOrWhiteSpace($raw.CpuName)) {
        if ($raw.LogicalThreads -gt 0) {
            "$($raw.CpuName) ($($raw.LogicalThreads) threads)"
        }
        else {
            "$($raw.CpuName)"
        }
    }
    else {
        'Unavailable'
    }

    $gpuList = @($raw.GpuNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $gpuText = if ($gpuList.Count -gt 0) { $gpuList -join ' + ' } else { 'Unavailable' }

    $memText = if ($null -ne $raw.TotalMemoryBytes -and [double]$raw.TotalMemoryBytes -gt 0) {
        $gb = [Math]::Round(([double]$raw.TotalMemoryBytes) / 1GB)
        "${gb} GB RAM"
    }
    else {
        'Unavailable'
    }

    $osText = if (-not [string]::IsNullOrWhiteSpace($raw.OsCaption)) {
        $cleanCaption = "$($raw.OsCaption)".Trim() -replace '^Microsoft\s+', ''
        if (-not [string]::IsNullOrWhiteSpace($raw.OsBuild)) {
            "$cleanCaption (Build $($raw.OsBuild))"
        }
        else {
            $cleanCaption
        }
    }
    else {
        'Unavailable'
    }

    return [PSCustomObject]@{
        Cpu    = $cpuText
        Gpu    = $gpuText
        Memory = $memText
        Os     = $osText
    }
}

function Format-ComputerSpecs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $SpecsObject
    )

    return @(
        '=== Win-Power-Toggle Computer Specs ==='
        ("Processor : {0}" -f $SpecsObject.Cpu)
        ("Graphics  : {0}" -f $SpecsObject.Gpu)
        ("Memory    : {0}" -f $SpecsObject.Memory)
        ("OS        : {0}" -f $SpecsObject.Os)
    ) -join [Environment]::NewLine
}

function Format-ModeSwitchResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Result
    )

    $modeTitle = switch ($Result.Mode) {
        'battery' { 'Battery Saver' }
        'normal'  { 'Normal (Balanced)' }
        default   { 'Gaming Performance' }
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("=== Win-Power-Toggle: $modeTitle Mode ===")

    $orderedSteps = @(
        @{ Label = 'CPU Cap     '; Step = $Result.Steps.Cpu },
        @{ Label = 'Power Mode  '; Step = $Result.Steps.PowerMode },
        @{ Label = 'Brightness  '; Step = $Result.Steps.Brightness },
        @{ Label = 'Refresh Rate'; Step = $Result.Steps.RefreshRate },
        @{ Label = 'Applications'; Step = $Result.Steps.Apps }
    )

    foreach ($entry in $orderedSteps) {
        $step = $entry.Step
        $tag = switch ($step.Status) {
            'Changed'   { '[OK]  ' }
            'Unchanged' { '[SAME]' }
            default     { '[SKIP]' }
        }
        $lines.Add(("{0} {1}: {2}" -f $tag, $entry.Label, $step.Message))
    }

    $lines.Add(("Completed in {0} ms." -f $Result.ElapsedMs))
    return ($lines -join [Environment]::NewLine)
}

function Invoke-WinPowerToggle {
    [CmdletBinding()]
    param(
        [ValidateSet('', 'battery', 'normal', 'gaming')]
        [string]$Mode,

        [switch]$Status,

        [switch]$Specs,

        [string]$ConfigPath = '',

        [switch]$Quiet
    )

    if (-not $Status -and -not $Specs -and [string]::IsNullOrWhiteSpace($Mode)) {
        throw "Specify either -Mode battery, -Mode normal, -Mode gaming, -Status, or -Specs."
    }

    $selectedActions = 0
    if (-not [string]::IsNullOrWhiteSpace($Mode)) { $selectedActions++ }
    if ($Status) { $selectedActions++ }
    if ($Specs) { $selectedActions++ }
    if ($selectedActions -gt 1) {
        throw "Parameters -Mode, -Status, and -Specs are mutually exclusive."
    }

    if ($Status) {
        return Get-SystemPowerStatus
    }

    if ($Specs) {
        return Get-ComputerSpecs
    }

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = $script:DefaultConfigPath
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $config = Get-PowerToggleConfig -Path $ConfigPath

    if ($Mode -eq 'battery') {
        $profile = $config.batteryMode

        $cpuStep = if ($null -ne $profile.maxCpuState) {
            Set-CpuMaxState -Percent ([int]$profile.maxCpuState)
        }
        else {
            [PSCustomObject]@{ Status = 'Skipped'; Percent = $null; Message = 'maxCpuState not configured.' }
        }

        $powerModeStep = Set-PowerModeOverlay -Overlay 'BestPowerEfficiency'

        $brightnessStep = if ($null -ne $profile.brightness) {
            Set-DisplayBrightness -Percent ([int]$profile.brightness)
        }
        else {
            [PSCustomObject]@{ Status = 'Skipped'; Percent = $null; Message = 'brightness not configured.' }
        }

        $refreshStep = if ($null -ne $profile.refreshRate) {
            Set-DisplayRefreshRate -RefreshRate $profile.refreshRate -Fallback 'Lowest'
        }
        else {
            [PSCustomObject]@{ Status = 'Skipped'; CurrentRate = $null; Message = 'refreshRate not configured.' }
        }

        $appsStep = Stop-ConfiguredApps -AppNames $profile.appsToKill
    }
    elseif ($Mode -eq 'normal') {
        $profile = $config.normalMode

        $cpuStep = if ($null -ne $profile.maxCpuState) {
            Set-CpuMaxState -Percent ([int]$profile.maxCpuState)
        }
        else {
            [PSCustomObject]@{ Status = 'Skipped'; Percent = $null; Message = 'maxCpuState not configured.' }
        }

        $powerModeStep = Set-PowerModeOverlay -Overlay 'Balanced'

        $brightnessStep = if ($null -ne $profile.brightness) {
            Set-DisplayBrightness -Percent ([int]$profile.brightness)
        }
        else {
            [PSCustomObject]@{ Status = 'Skipped'; Percent = $null; Message = 'brightness not configured.' }
        }

        $refreshStep = if ($null -ne $profile.refreshRate) {
            Set-DisplayRefreshRate -RefreshRate $profile.refreshRate -Fallback 'Highest'
        }
        else {
            [PSCustomObject]@{ Status = 'Skipped'; CurrentRate = $null; Message = 'refreshRate not configured.' }
        }

        $appsStep = [PSCustomObject]@{
            Status  = 'Unchanged'
            Message = 'Normal mode leaves running apps unchanged.'
        }
    }
    else {
        $profile = $config.gamingMode

        $cpuStep = if ($null -ne $profile.maxCpuState) {
            Set-CpuMaxState -Percent ([int]$profile.maxCpuState)
        }
        else {
            [PSCustomObject]@{ Status = 'Skipped'; Percent = $null; Message = 'maxCpuState not configured.' }
        }

        $powerModeStep = Set-PowerModeOverlay -Overlay 'BestPerformance'

        $brightnessStep = if ($null -ne $profile.brightness) {
            Set-DisplayBrightness -Percent ([int]$profile.brightness)
        }
        else {
            [PSCustomObject]@{ Status = 'Skipped'; Percent = $null; Message = 'brightness not configured.' }
        }

        $refreshStep = if ($null -ne $profile.refreshRate) {
            Set-DisplayRefreshRate -RefreshRate $profile.refreshRate -Fallback 'Highest'
        }
        else {
            [PSCustomObject]@{ Status = 'Skipped'; CurrentRate = $null; Message = 'refreshRate not configured.' }
        }

        $appsStep = Start-ConfiguredApps -AppPaths $profile.appsToLaunch
    }

    $stopwatch.Stop()

    return [PSCustomObject]@{
        Mode      = $Mode
        ElapsedMs = $stopwatch.ElapsedMilliseconds
        Steps     = [PSCustomObject]@{
            Cpu         = $cpuStep
            PowerMode   = $powerModeStep
            Brightness  = $brightnessStep
            RefreshRate = $refreshStep
            Apps        = $appsStep
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $result = Invoke-WinPowerToggle -Mode $Mode -Status:$Status -Specs:$Specs -ConfigPath $ConfigPath -Quiet:$Quiet
        if ($PassThru) {
            Write-Output $result
        }
        elseif (-not $Quiet) {
            if ($Status) {
                Write-Output (Format-SystemPowerStatus -StatusObject $result)
            }
            elseif ($Specs) {
                Write-Output (Format-ComputerSpecs -SpecsObject $result)
            }
            else {
                Write-Output (Format-ModeSwitchResult -Result $result)
            }
        }
    }
    catch {
        [Console]::Error.WriteLine("Error: $($_.Exception.Message)")
        [Console]::Error.WriteLine("Usage: Switch-Mode.ps1 -Mode <battery|normal|gaming> [-ConfigPath <path>] | -Status | -Specs")
        exit 1
    }
}
