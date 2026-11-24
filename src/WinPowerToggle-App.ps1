<#
.SYNOPSIS
    Native Windows desktop and system-tray app for Win-Power-Toggle.

.DESCRIPTION
    Zero-dependency WPF desktop UI built on Windows PowerShell 5.1+. Provides one-click
    Battery Saver and Gaming Performance switching, live hardware telemetry, a visual
    config.json profile editor, Light/Dark theme toggle, and System Tray quick controls.
    Reuses src\Switch-Mode.ps1 and src\Display-Helper.ps1 directly.

.EXAMPLE
    powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .\src\WinPowerToggle-App.ps1

.EXAMPLE
    wscript.exe .\src\Launch-App.vbs
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = '',

    [ValidateSet('Auto', 'Light', 'Dark')]
    [string]$Theme = 'Auto',

    [switch]$StartMinimized
)

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
    [Console]::Error.WriteLine('WinPowerToggle-App.ps1 requires an STA thread. Launch with: powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .\src\WinPowerToggle-App.ps1')
    exit 1
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:ScriptRootDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:SwitchModePath = Join-Path $script:ScriptRootDir 'Switch-Mode.ps1'
$script:AppLogicPath = Join-Path $script:ScriptRootDir 'App-Logic.ps1'
$script:DefaultConfigPath = Join-Path (Split-Path -Parent $script:ScriptRootDir) 'config.json'
$script:ActiveConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $script:DefaultConfigPath } else { $ConfigPath }

. $script:SwitchModePath
. $script:AppLogicPath

if (-not ([System.Management.Automation.PSTypeName]'WinPowerToggle.DwmThemeNative').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace WinPowerToggle {
    public static class DwmThemeNative {
        [DllImport("dwmapi.dll", PreserveSig = true)]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        public static void SetDarkTitleBar(IntPtr hwnd, bool useDark) {
            if (hwnd == IntPtr.Zero) return;
            int val = useDark ? 1 : 0;
            // Attribute 20 works on Windows 10 20H1+ and Windows 11
            DwmSetWindowAttribute(hwnd, 20, ref val, sizeof(int));
        }
    }
}
"@
}

$script:CurrentTheme = if ($Theme -eq 'Auto') { Get-WindowsPreferredAppTheme } else { $Theme }
$script:CurrentConfig = $null
$script:SupportedRates = @(60, 144)
$script:IsBusy = $false
$script:SuppressFormSync = $false
$script:ActivePs = $null
$script:ActiveHandle = $null
$script:ActiveCallback = $null
$script:PollTimer = $null
$script:NotifyIcon = $null

$xaml = Get-AppWindowXaml
$script:Window = [Windows.Markup.XamlReader]::Parse($xaml)

# Resolve named UI controls
$script:TxtDetectedProfile = $script:Window.FindName('TxtDetectedProfile')
$script:BtnThemeToggle     = $script:Window.FindName('BtnThemeToggle')
$script:BtnMinimizeTray    = $script:Window.FindName('BtnMinimizeTray')
$script:BannerLoading      = $script:Window.FindName('BannerLoading')
$script:TxtLoadingMessage  = $script:Window.FindName('TxtLoadingMessage')
$script:BannerError        = $script:Window.FindName('BannerError')
$script:TxtErrorMessage    = $script:Window.FindName('TxtErrorMessage')
$script:BtnDismissError    = $script:Window.FindName('BtnDismissError')
$script:BannerNotice       = $script:Window.FindName('BannerNotice')
$script:TxtNoticeMessage   = $script:Window.FindName('TxtNoticeMessage')

$script:BtnBatteryMode     = $script:Window.FindName('BtnBatteryMode')
$script:TxtBatterySummary  = $script:Window.FindName('TxtBatterySummary')
$script:BtnGamingMode      = $script:Window.FindName('BtnGamingMode')
$script:TxtGamingSummary   = $script:Window.FindName('TxtGamingSummary')

$script:BtnRefreshStatus   = $script:Window.FindName('BtnRefreshStatus')
$script:TxtStatusPower     = $script:Window.FindName('TxtStatusPower')
$script:TxtStatusOverlay   = $script:Window.FindName('TxtStatusOverlay')
$script:TxtStatusCpu       = $script:Window.FindName('TxtStatusCpu')
$script:TxtStatusDisplay   = $script:Window.FindName('TxtStatusDisplay')
$script:TxtLastAction      = $script:Window.FindName('TxtLastAction')

$script:TxtConfigPath      = $script:Window.FindName('TxtConfigPath')
$script:BtnReloadConfig    = $script:Window.FindName('BtnReloadConfig')
$script:BtnSaveConfig      = $script:Window.FindName('BtnSaveConfig')

$script:SliderBatCpu       = $script:Window.FindName('SliderBatCpu')
$script:TxtBatCpuVal       = $script:Window.FindName('TxtBatCpuVal')
$script:SliderBatBright    = $script:Window.FindName('SliderBatBright')
$script:TxtBatBrightVal    = $script:Window.FindName('TxtBatBrightVal')
$script:CboBatRefresh      = $script:Window.FindName('CboBatRefresh')
$script:LstAppsToKill      = $script:Window.FindName('LstAppsToKill')
$script:TxtEmptyKillList   = $script:Window.FindName('TxtEmptyKillList')
$script:TxtAddKillApp      = $script:Window.FindName('TxtAddKillApp')
$script:BtnAddKillApp      = $script:Window.FindName('BtnAddKillApp')
$script:BtnRemoveKillApp   = $script:Window.FindName('BtnRemoveKillApp')

$script:SliderGameCpu      = $script:Window.FindName('SliderGameCpu')
$script:TxtGameCpuVal      = $script:Window.FindName('TxtGameCpuVal')
$script:SliderGameBright   = $script:Window.FindName('SliderGameBright')
$script:TxtGameBrightVal   = $script:Window.FindName('TxtGameBrightVal')
$script:CboGameRefresh     = $script:Window.FindName('CboGameRefresh')
$script:LstAppsToLaunch    = $script:Window.FindName('LstAppsToLaunch')
$script:TxtEmptyLaunchList = $script:Window.FindName('TxtEmptyLaunchList')
$script:TxtAddLaunchApp    = $script:Window.FindName('TxtAddLaunchApp')
$script:BtnBrowseLaunchApp = $script:Window.FindName('BtnBrowseLaunchApp')
$script:BtnAddLaunchApp    = $script:Window.FindName('BtnAddLaunchApp')
$script:BtnRemoveLaunchApp = $script:Window.FindName('BtnRemoveLaunchApp')

$script:TxtConfigPath.Text = $script:ActiveConfigPath

function Show-ErrorBanner {
    param([string]$Message)
    $script:BannerNotice.Visibility = 'Collapsed'
    $script:TxtErrorMessage.Text = "ERROR: $Message"
    $script:BannerError.Visibility = 'Visible'
}

function Hide-ErrorBanner {
    $script:BannerError.Visibility = 'Collapsed'
    $script:TxtErrorMessage.Text = ''
}

function Show-NoticeBanner {
    param([string]$Message)
    Hide-ErrorBanner
    $script:TxtNoticeMessage.Text = $Message
    $script:BannerNotice.Visibility = 'Visible'
}

function Hide-NoticeBanner {
    $script:BannerNotice.Visibility = 'Collapsed'
    $script:TxtNoticeMessage.Text = ''
}

function Set-BusyState {
    param(
        [bool]$Busy,
        [string]$Message = ''
    )

    $script:IsBusy = $Busy
    $script:BtnBatteryMode.IsEnabled = (-not $Busy)
    $script:BtnGamingMode.IsEnabled = (-not $Busy)
    $script:BtnRefreshStatus.IsEnabled = (-not $Busy)
    $script:BtnSaveConfig.IsEnabled = (-not $Busy)
    $script:BtnReloadConfig.IsEnabled = (-not $Busy)

    if ($null -ne $script:TrayBatteryItem) { $script:TrayBatteryItem.Enabled = (-not $Busy) }
    if ($null -ne $script:TrayGamingItem)  { $script:TrayGamingItem.Enabled = (-not $Busy) }

    if ($Busy) {
        $script:TxtLoadingMessage.Text = $Message
        $script:BannerLoading.Visibility = 'Visible'
    }
    else {
        $script:BannerLoading.Visibility = 'Collapsed'
    }
}

function Apply-AppTheme {
    param([ValidateSet('Light', 'Dark')][string]$ThemeName)

    Set-WindowThemePalette -Window $script:Window -Theme $ThemeName
    $script:CurrentTheme = $ThemeName

    $script:BtnThemeToggle.Content = if ($ThemeName -eq 'Dark') { 'Light Theme' } else { 'Dark Theme' }

    try {
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($script:Window)
        if ($helper.Handle -ne [IntPtr]::Zero) {
            [WinPowerToggle.DwmThemeNative]::SetDarkTitleBar($helper.Handle, ($ThemeName -eq 'Dark'))
        }
    }
    catch {
        # Native dark title bar is best-effort on older Windows builds
    }
}

function Update-EmptyListIndicators {
    $script:TxtEmptyKillList.Visibility = if ($script:LstAppsToKill.Items.Count -eq 0) { 'Visible' } else { 'Collapsed' }
    $script:TxtEmptyLaunchList.Visibility = if ($script:LstAppsToLaunch.Items.Count -eq 0) { 'Visible' } else { 'Collapsed' }
    $script:BtnRemoveKillApp.IsEnabled = ($null -ne $script:LstAppsToKill.SelectedItem)
    $script:BtnRemoveLaunchApp.IsEnabled = ($null -ne $script:LstAppsToLaunch.SelectedItem)
}

function Populate-RefreshCombo {
    param(
        $ComboBox,
        [int[]]$SupportedRates,
        $SelectedValue
    )

    $choices = Get-RefreshRateChoices -SupportedRates $SupportedRates -ConfiguredRate $SelectedValue
    $ComboBox.Items.Clear()
    foreach ($choice in $choices) {
        [void]$ComboBox.Items.Add($choice)
    }

    $targetText = if ($null -ne $SelectedValue) { "$SelectedValue".Trim().ToLowerInvariant() } else { '60' }
    $matchedIndex = -1
    for ($i = 0; $i -lt $ComboBox.Items.Count; $i++) {
        if ("$($ComboBox.Items[$i])".ToLowerInvariant() -eq $targetText) {
            $matchedIndex = $i
            break
        }
    }
    if ($matchedIndex -ge 0) {
        $ComboBox.SelectedIndex = $matchedIndex
    }
    elseif ($ComboBox.Items.Count -gt 0) {
        $ComboBox.SelectedIndex = 0
    }
}

function Get-FormConfigObject {
    $killItems = @()
    foreach ($item in $script:LstAppsToKill.Items) { $killItems += "$item" }

    $launchItems = @()
    foreach ($item in $script:LstAppsToLaunch.Items) { $launchItems += "$item" }

    $forceSaver = if ($null -ne $script:CurrentConfig -and $null -ne $script:CurrentConfig.batteryMode.PSObject.Properties['forceBatterySaver']) {
        [bool]$script:CurrentConfig.batteryMode.forceBatterySaver
    }
    else {
        $true
    }

    return [PSCustomObject]@{
        batteryMode = [PSCustomObject]@{
            brightness        = [int][Math]::Round($script:SliderBatBright.Value)
            refreshRate       = if ($null -ne $script:CboBatRefresh.SelectedItem) { "$($script:CboBatRefresh.SelectedItem)" } else { 60 }
            maxCpuState       = [int][Math]::Round($script:SliderBatCpu.Value)
            forceBatterySaver = $forceSaver
            appsToKill        = $killItems
        }
        gamingMode = [PSCustomObject]@{
            brightness   = [int][Math]::Round($script:SliderGameBright.Value)
            refreshRate  = if ($null -ne $script:CboGameRefresh.SelectedItem) { "$($script:CboGameRefresh.SelectedItem)" } else { 144 }
            maxCpuState  = [int][Math]::Round($script:SliderGameCpu.Value)
            appsToLaunch = $launchItems
        }
    }
}

function Update-ModeSummaries {
    if ($null -eq $script:CurrentConfig) { return }
    $script:TxtBatterySummary.Text = Format-ProfileCardSummary -Profile $script:CurrentConfig.batteryMode -Mode 'battery'
    $script:TxtGamingSummary.Text  = Format-ProfileCardSummary -Profile $script:CurrentConfig.gamingMode -Mode 'gaming'
}

function Load-ConfigIntoForm {
    param([switch]$ShowNotice)

    try {
        $cfg = Get-PowerToggleConfig -Path $script:ActiveConfigPath
        $script:CurrentConfig = $cfg
        $script:SuppressFormSync = $true

        $batCpu = if ($null -ne $cfg.batteryMode.maxCpuState) { [int]$cfg.batteryMode.maxCpuState } else { 50 }
        $batBright = if ($null -ne $cfg.batteryMode.brightness) { [int]$cfg.batteryMode.brightness } else { 30 }
        $gameCpu = if ($null -ne $cfg.gamingMode.maxCpuState) { [int]$cfg.gamingMode.maxCpuState } else { 100 }
        $gameBright = if ($null -ne $cfg.gamingMode.brightness) { [int]$cfg.gamingMode.brightness } else { 100 }

        $script:SliderBatCpu.Value = $batCpu
        $script:TxtBatCpuVal.Text = "${batCpu}%"
        $script:SliderBatBright.Value = $batBright
        $script:TxtBatBrightVal.Text = "${batBright}%"

        $script:SliderGameCpu.Value = $gameCpu
        $script:TxtGameCpuVal.Text = "${gameCpu}%"
        $script:SliderGameBright.Value = $gameBright
        $script:TxtGameBrightVal.Text = "${gameBright}%"

        Populate-RefreshCombo -ComboBox $script:CboBatRefresh -SupportedRates $script:SupportedRates -SelectedValue $cfg.batteryMode.refreshRate
        Populate-RefreshCombo -ComboBox $script:CboGameRefresh -SupportedRates $script:SupportedRates -SelectedValue $cfg.gamingMode.refreshRate

        $script:LstAppsToKill.Items.Clear()
        foreach ($app in @($cfg.batteryMode.appsToKill)) {
            [void]$script:LstAppsToKill.Items.Add($app)
        }

        $script:LstAppsToLaunch.Items.Clear()
        foreach ($path in @($cfg.gamingMode.appsToLaunch)) {
            [void]$script:LstAppsToLaunch.Items.Add($path)
        }

        $script:SuppressFormSync = $false
        Update-EmptyListIndicators
        Update-ModeSummaries
        Hide-ErrorBanner

        if ($ShowNotice) {
            Show-NoticeBanner "Reloaded settings from $script:ActiveConfigPath."
        }
    }
    catch {
        $script:SuppressFormSync = $false
        Show-ErrorBanner $_.Exception.Message
    }
}

function Apply-StatusToUi {
    param($StatusObj)

    if ($null -eq $StatusObj) {
        Show-ErrorBanner 'Could not read hardware status.'
        return
    }

    $batPart = if ($null -ne $StatusObj.BatteryPercent) { "$($StatusObj.BatteryPercent)%" } else { 'No battery' }
    $script:TxtStatusPower.Text = "$($StatusObj.PowerSource), $batPart"
    $script:TxtStatusOverlay.Text = "$($StatusObj.PowerModeOverlay) ($($StatusObj.PowerSchemeName))"

    $activeCap = if ($null -ne $StatusObj.ActiveCpuMaxState) { "$($StatusObj.ActiveCpuMaxState)%" } else { 'N/A' }
    $acCap = if ($null -ne $StatusObj.CpuMaxStateAc) { "$($StatusObj.CpuMaxStateAc)%" } else { 'N/A' }
    $dcCap = if ($null -ne $StatusObj.CpuMaxStateDc) { "$($StatusObj.CpuMaxStateDc)%" } else { 'N/A' }
    $script:TxtStatusCpu.Text = "$activeCap active (AC $acCap / DC $dcCap)"

    $brightPart = if ($null -ne $StatusObj.BrightnessPercent) { "$($StatusObj.BrightnessPercent)% brightness" } else { 'External / no WMI brightness' }
    $hzPart = if ($null -ne $StatusObj.RefreshRateHz) { "$($StatusObj.DisplayResolution) @ $($StatusObj.RefreshRateHz)Hz" } else { 'Display unavailable' }
    $script:TxtStatusDisplay.Text = "$hzPart, $brightPart"

    $detected = Get-DetectedProfileState -StatusObject $StatusObj -Config $script:CurrentConfig
    $script:TxtDetectedProfile.Text = "Current state: $($detected.Label) ($($detected.Detail))"

    if ($null -ne $script:NotifyIcon) {
        $tip = "Win-Power-Toggle: $($detected.Label)"
        if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
        $script:NotifyIcon.Text = $tip
    }

    if ($null -ne $StatusObj.SupportedRefreshRatesHz -and $StatusObj.SupportedRefreshRatesHz.Count -gt 0) {
        $script:SupportedRates = [int[]]$StatusObj.SupportedRefreshRatesHz
        $batSel = $script:CboBatRefresh.SelectedItem
        $gameSel = $script:CboGameRefresh.SelectedItem
        $script:SuppressFormSync = $true
        Populate-RefreshCombo -ComboBox $script:CboBatRefresh -SupportedRates $script:SupportedRates -SelectedValue $batSel
        Populate-RefreshCombo -ComboBox $script:CboGameRefresh -SupportedRates $script:SupportedRates -SelectedValue $gameSel
        $script:SuppressFormSync = $false
    }
}

function Start-BackgroundOperation {
    param(
        [string]$LoadingMessage,
        [string]$OperationType,
        [string]$TargetMode = '',
        [scriptblock]$OnCompleted
    )

    if ($script:IsBusy) { return }

    Hide-ErrorBanner
    Hide-NoticeBanner
    Set-BusyState -Busy $true -Message $LoadingMessage

    $ps = [PowerShell]::Create()
    $workerCode = {
        param($switchPath, $opType, $modeName, $cfgPath)
        . $switchPath
        if ($opType -eq 'status') {
            return [PSCustomObject]@{
                Kind   = 'status'
                Status = (Invoke-WinPowerToggle -Status -Quiet)
            }
        }
        else {
            $switchRes = Invoke-WinPowerToggle -Mode $modeName -ConfigPath $cfgPath -Quiet
            $formatted = Format-ModeSwitchResult -Result $switchRes
            $freshStatus = Invoke-WinPowerToggle -Status -Quiet
            return [PSCustomObject]@{
                Kind      = 'switch'
                Result    = $switchRes
                Formatted = $formatted
                Status    = $freshStatus
            }
        }
    }

    [void]$ps.AddScript($workerCode).AddArgument($script:SwitchModePath).AddArgument($OperationType).AddArgument($TargetMode).AddArgument($script:ActiveConfigPath)
    $script:ActivePs = $ps
    $script:ActiveHandle = $ps.BeginInvoke()
    $script:ActiveCallback = $OnCompleted

    if ($null -eq $script:PollTimer) {
        $script:PollTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:PollTimer.Interval = [TimeSpan]::FromMilliseconds(60)
        $script:PollTimer.Add_Tick({
            if ($null -eq $script:ActiveHandle -or -not $script:ActiveHandle.IsCompleted) {
                return
            }

            $script:PollTimer.Stop()
            $psInstance = $script:ActivePs
            $handle = $script:ActiveHandle
            $callback = $script:ActiveCallback

            $script:ActivePs = $null
            $script:ActiveHandle = $null
            $script:ActiveCallback = $null

            $payload = $null
            $errMsg = $null
            try {
                $results = $psInstance.EndInvoke($handle)
                if ($psInstance.HadErrors -and $psInstance.Streams.Error.Count -gt 0) {
                    $errMsg = ($psInstance.Streams.Error | ForEach-Object { $_.Exception.Message }) -join '; '
                }
                elseif ($null -ne $results -and $results.Count -gt 0) {
                    $payload = $results[$results.Count - 1]
                }
            }
            catch {
                $errMsg = $_.Exception.Message
                if ($null -ne $_.Exception.InnerException) {
                    $errMsg = $_.Exception.InnerException.Message
                }
            }
            finally {
                try { $psInstance.Dispose() } catch {}
                Set-BusyState -Busy $false
            }

            if ($errMsg) {
                Show-ErrorBanner $errMsg
            }
            elseif ($null -ne $callback) {
                & $callback $payload
            }
        })
    }

    $script:PollTimer.Start()
}

function Request-StatusRefresh {
    Start-BackgroundOperation -LoadingMessage 'Working: reading hardware status...' -OperationType 'status' -OnCompleted {
        param($payload)
        if ($null -ne $payload -and $null -ne $payload.Status) {
            Apply-StatusToUi -StatusObj $payload.Status
        }
    }
}

function Request-ModeSwitch {
    param([ValidateSet('battery', 'gaming')][string]$TargetMode)

    $label = if ($TargetMode -eq 'battery') { 'Battery Saver' } else { 'Gaming Performance' }
    Start-BackgroundOperation -LoadingMessage "Working: applying $label profile..." -OperationType 'switch' -TargetMode $TargetMode -OnCompleted {
        param($payload)
        if ($null -ne $payload) {
            if (-not [string]::IsNullOrWhiteSpace($payload.Formatted)) {
                $script:TxtLastAction.Text = $payload.Formatted
                $script:TxtLastAction.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'TextPrimary')
            }
            if ($null -ne $payload.Status) {
                Apply-StatusToUi -StatusObj $payload.Status
            }
        }
    }
}

function Restore-MainWindow {
    $script:Window.Show()
    if ($script:Window.WindowState -eq 'Minimized') {
        $script:Window.WindowState = 'Normal'
    }
    $script:Window.Activate() | Out-Null
}

# Setup System Tray NotifyIcon
$script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Application
$script:NotifyIcon.Text = 'Win-Power-Toggle'
$script:NotifyIcon.Visible = $true

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$trayOpenItem = $trayMenu.Items.Add('Open Win-Power-Toggle')
$trayOpenItem.Add_Click({ Restore-MainWindow })
[void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$script:TrayBatteryItem = $trayMenu.Items.Add('Switch to Battery Saver')
$script:TrayBatteryItem.Add_Click({ Request-ModeSwitch -TargetMode 'battery' })

$script:TrayGamingItem = $trayMenu.Items.Add('Switch to Gaming Performance')
$script:TrayGamingItem.Add_Click({ Request-ModeSwitch -TargetMode 'gaming' })

[void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$trayExitItem = $trayMenu.Items.Add('Exit')
$trayExitItem.Add_Click({ $script:Window.Close() })

$script:NotifyIcon.ContextMenuStrip = $trayMenu
$script:NotifyIcon.Add_DoubleClick({ Restore-MainWindow })

# Wire WPF UI events
$script:Window.Add_SourceInitialized({
    Apply-AppTheme -ThemeName $script:CurrentTheme
})

$script:Window.Add_PreviewKeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
        if ($script:BannerError.Visibility -eq 'Visible' -or $script:BannerNotice.Visibility -eq 'Visible') {
            Hide-ErrorBanner
            Hide-NoticeBanner
            $e.Handled = $true
        }
    }
})

$script:BtnThemeToggle.Add_Click({
    $nextTheme = if ($script:CurrentTheme -eq 'Dark') { 'Light' } else { 'Dark' }
    Apply-AppTheme -ThemeName $nextTheme
})

$script:BtnMinimizeTray.Add_Click({
    $script:Window.Hide()
})

$script:BtnDismissError.Add_Click({
    Hide-ErrorBanner
})

$script:BtnBatteryMode.Add_Click({
    Request-ModeSwitch -TargetMode 'battery'
})

$script:BtnGamingMode.Add_Click({
    Request-ModeSwitch -TargetMode 'gaming'
})

$script:BtnRefreshStatus.Add_Click({
    Request-StatusRefresh
})

$script:SliderBatCpu.Add_ValueChanged({
    $val = [int][Math]::Round($script:SliderBatCpu.Value)
    $script:TxtBatCpuVal.Text = "${val}%"
    if (-not $script:SuppressFormSync) {
        $script:CurrentConfig = Get-FormConfigObject
        Update-ModeSummaries
    }
})

$script:SliderBatBright.Add_ValueChanged({
    $val = [int][Math]::Round($script:SliderBatBright.Value)
    $script:TxtBatBrightVal.Text = "${val}%"
    if (-not $script:SuppressFormSync) {
        $script:CurrentConfig = Get-FormConfigObject
        Update-ModeSummaries
    }
})

$script:SliderGameCpu.Add_ValueChanged({
    $val = [int][Math]::Round($script:SliderGameCpu.Value)
    $script:TxtGameCpuVal.Text = "${val}%"
    if (-not $script:SuppressFormSync) {
        $script:CurrentConfig = Get-FormConfigObject
        Update-ModeSummaries
    }
})

$script:SliderGameBright.Add_ValueChanged({
    $val = [int][Math]::Round($script:SliderGameBright.Value)
    $script:TxtGameBrightVal.Text = "${val}%"
    if (-not $script:SuppressFormSync) {
        $script:CurrentConfig = Get-FormConfigObject
        Update-ModeSummaries
    }
})

$script:CboBatRefresh.Add_SelectionChanged({
    if (-not $script:SuppressFormSync) {
        $script:CurrentConfig = Get-FormConfigObject
        Update-ModeSummaries
    }
})

$script:CboGameRefresh.Add_SelectionChanged({
    if (-not $script:SuppressFormSync) {
        $script:CurrentConfig = Get-FormConfigObject
        Update-ModeSummaries
    }
})

$script:LstAppsToKill.Add_SelectionChanged({ Update-EmptyListIndicators })
$script:LstAppsToLaunch.Add_SelectionChanged({ Update-EmptyListIndicators })

$addKillHandler = {
    $existing = @($script:LstAppsToKill.Items | ForEach-Object { "$_" })
    $res = Add-AppListItem -Items $existing -NewItem $script:TxtAddKillApp.Text -NormalizeProcessName
    if ($res.Added) {
        $script:LstAppsToKill.Items.Clear()
        foreach ($item in $res.Items) { [void]$script:LstAppsToKill.Items.Add($item) }
        $script:TxtAddKillApp.Text = ''
        $script:CurrentConfig = Get-FormConfigObject
        Update-EmptyListIndicators
        Hide-ErrorBanner
    }
    else {
        Show-ErrorBanner $res.Message
    }
}

$script:BtnAddKillApp.Add_Click($addKillHandler)
$script:TxtAddKillApp.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
        & $addKillHandler
        $e.Handled = $true
    }
})

$script:BtnRemoveKillApp.Add_Click({
    if ($null -eq $script:LstAppsToKill.SelectedItem) { return }
    $existing = @($script:LstAppsToKill.Items | ForEach-Object { "$_" })
    $updated = Remove-AppListItem -Items $existing -ItemToRemove "$($script:LstAppsToKill.SelectedItem)"
    $script:LstAppsToKill.Items.Clear()
    foreach ($item in $updated) { [void]$script:LstAppsToKill.Items.Add($item) }
    $script:CurrentConfig = Get-FormConfigObject
    Update-EmptyListIndicators
})

$addLaunchHandler = {
    $existing = @($script:LstAppsToLaunch.Items | ForEach-Object { "$_" })
    $res = Add-AppListItem -Items $existing -NewItem $script:TxtAddLaunchApp.Text
    if ($res.Added) {
        $script:LstAppsToLaunch.Items.Clear()
        foreach ($item in $res.Items) { [void]$script:LstAppsToLaunch.Items.Add($item) }
        $script:TxtAddLaunchApp.Text = ''
        $script:CurrentConfig = Get-FormConfigObject
        Update-EmptyListIndicators
        Hide-ErrorBanner
    }
    else {
        Show-ErrorBanner $res.Message
    }
}

$script:BtnAddLaunchApp.Add_Click($addLaunchHandler)
$script:TxtAddLaunchApp.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
        & $addLaunchHandler
        $e.Handled = $true
    }
})

$script:BtnBrowseLaunchApp.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = 'Select Gaming Application Executable'
    $dlg.Filter = 'Executable files (*.exe)|*.exe|All files (*.*)|*.*'
    $dlg.CheckFileExists = $true
    if ($dlg.ShowDialog() -eq $true) {
        $script:TxtAddLaunchApp.Text = $dlg.FileName
    }
})

$script:BtnRemoveLaunchApp.Add_Click({
    if ($null -eq $script:LstAppsToLaunch.SelectedItem) { return }
    $existing = @($script:LstAppsToLaunch.Items | ForEach-Object { "$_" })
    $updated = Remove-AppListItem -Items $existing -ItemToRemove "$($script:LstAppsToLaunch.SelectedItem)"
    $script:LstAppsToLaunch.Items.Clear()
    foreach ($item in $updated) { [void]$script:LstAppsToLaunch.Items.Add($item) }
    $script:CurrentConfig = Get-FormConfigObject
    Update-EmptyListIndicators
})

$script:BtnSaveConfig.Add_Click({
    try {
        $toSave = Get-FormConfigObject
        $saveRes = Save-PowerToggleConfig -Config $toSave -Path $script:ActiveConfigPath
        $script:CurrentConfig = Get-PowerToggleConfig -Path $script:ActiveConfigPath
        Update-ModeSummaries
        Show-NoticeBanner $saveRes.Message
    }
    catch {
        Show-ErrorBanner $_.Exception.Message
    }
})

$script:BtnReloadConfig.Add_Click({
    Load-ConfigIntoForm -ShowNotice
})

$script:Window.Add_Loaded({
    Load-ConfigIntoForm
    Request-StatusRefresh
})

$script:Window.Add_Closed({
    if ($null -ne $script:PollTimer) {
        try { $script:PollTimer.Stop() } catch {}
    }
    if ($null -ne $script:ActivePs) {
        try { $script:ActivePs.Dispose() } catch {}
    }
    if ($null -ne $script:NotifyIcon) {
        try {
            $script:NotifyIcon.Visible = $false
            $script:NotifyIcon.Dispose()
        } catch {}
    }
})

Apply-AppTheme -ThemeName $script:CurrentTheme

if ($StartMinimized) {
    Load-ConfigIntoForm
    Request-StatusRefresh
    $script:Window.ShowInTaskbar = $true
    $app = New-Object System.Windows.Application
    $app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
    $script:Window.Add_Closed({ $app.Shutdown() })
    [void]$app.Run()
}
else {
    [void]$script:Window.ShowDialog()
}
