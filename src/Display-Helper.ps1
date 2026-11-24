<#
.SYNOPSIS
    Native Windows Display API helper for querying and changing display refresh rates.

.DESCRIPTION
    Zero-dependency PowerShell module wrapping user32.dll (EnumDisplaySettingsW and
    ChangeDisplaySettingsExW) to inspect supported refresh rates and switch safely
    between presets (such as 60Hz for battery mode and 144Hz for gaming mode).
#>

function Initialize-DisplayNativeApi {
    if (-not ([System.Management.Automation.PSTypeName]'WinPowerToggle.DisplayNative').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace WinPowerToggle {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODEW {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    public class DisplayInfoResult {
        public string DeviceName { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        public int BitsPerPixel { get; set; }
        public int RefreshRate { get; set; }
        public int[] SupportedRefreshRates { get; set; }
    }

    public static class DisplayNative {
        private const int ENUM_CURRENT_SETTINGS = -1;
        private const int DM_DISPLAYFREQUENCY = 0x00400000;
        private const int CDS_UPDATEREGISTRY = 0x00000001;
        private const int CDS_TEST = 0x00000002;
        private const int DISP_CHANGE_SUCCESSFUL = 0;

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern bool EnumDisplaySettingsW(string lpszDeviceName, int iModeNum, ref DEVMODEW lpDevMode);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int ChangeDisplaySettingsExW(
            string lpszDeviceName,
            ref DEVMODEW lpDevMode,
            IntPtr hwnd,
            int dwflags,
            IntPtr lParam);

        private static string NormalizeDeviceName(string deviceName) {
            return string.IsNullOrWhiteSpace(deviceName) ? null : deviceName;
        }

        public static DisplayInfoResult GetDisplayInfo(string deviceName) {
            string dev = NormalizeDeviceName(deviceName);
            DEVMODEW current = new DEVMODEW();
            current.dmSize = (short)Marshal.SizeOf(typeof(DEVMODEW));

            if (!EnumDisplaySettingsW(dev, ENUM_CURRENT_SETTINGS, ref current)) {
                return null;
            }

            SortedSet<int> rates = new SortedSet<int>();
            DEVMODEW mode = new DEVMODEW();
            mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODEW));
            int modeIndex = 0;

            while (EnumDisplaySettingsW(dev, modeIndex, ref mode)) {
                if (mode.dmPelsWidth == current.dmPelsWidth &&
                    mode.dmPelsHeight == current.dmPelsHeight &&
                    mode.dmBitsPerPel == current.dmBitsPerPel &&
                    mode.dmDisplayFrequency > 1) {
                    rates.Add(mode.dmDisplayFrequency);
                }
                modeIndex++;
            }

            if (current.dmDisplayFrequency > 1) {
                rates.Add(current.dmDisplayFrequency);
            }

            int[] rateArray = new int[rates.Count];
            rates.CopyTo(rateArray);

            return new DisplayInfoResult {
                DeviceName = string.IsNullOrWhiteSpace(dev) ? current.dmDeviceName : dev,
                Width = current.dmPelsWidth,
                Height = current.dmPelsHeight,
                BitsPerPixel = current.dmBitsPerPel,
                RefreshRate = current.dmDisplayFrequency,
                SupportedRefreshRates = rateArray
            };
        }

        public static int SetRefreshRate(string deviceName, int targetFrequency) {
            string dev = NormalizeDeviceName(deviceName);
            DEVMODEW dm = new DEVMODEW();
            dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODEW));

            if (!EnumDisplaySettingsW(dev, ENUM_CURRENT_SETTINGS, ref dm)) {
                return -1;
            }

            dm.dmDisplayFrequency = targetFrequency;
            dm.dmFields = DM_DISPLAYFREQUENCY;

            int testResult = ChangeDisplaySettingsExW(dev, ref dm, IntPtr.Zero, CDS_TEST, IntPtr.Zero);
            if (testResult != DISP_CHANGE_SUCCESSFUL) {
                return testResult;
            }

            return ChangeDisplaySettingsExW(dev, ref dm, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero);
        }
    }
}
"@
    }
}

function Get-DisplayInfo {
    [CmdletBinding()]
    param(
        [string]$DeviceName = $null
    )

    try {
        Initialize-DisplayNativeApi
        $nativeInfo = [WinPowerToggle.DisplayNative]::GetDisplayInfo($DeviceName)
        if ($null -eq $nativeInfo) {
            return $null
        }

        return [PSCustomObject]@{
            DeviceName            = $nativeInfo.DeviceName
            Width                 = [int]$nativeInfo.Width
            Height                = [int]$nativeInfo.Height
            BitsPerPixel          = [int]$nativeInfo.BitsPerPixel
            RefreshRate           = [int]$nativeInfo.RefreshRate
            SupportedRefreshRates = [int[]]$nativeInfo.SupportedRefreshRates
        }
    }
    catch {
        return $null
    }
}

function Get-SupportedRefreshRates {
    [CmdletBinding()]
    param(
        [string]$DeviceName = $null
    )

    $info = Get-DisplayInfo -DeviceName $DeviceName
    if ($null -eq $info -or $null -eq $info.SupportedRefreshRates) {
        return @()
    }

    return [int[]]$info.SupportedRefreshRates
}

function Resolve-TargetRefreshRate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $RequestedRate,

        [AllowEmptyCollection()]
        [int[]]$SupportedRates = @(),

        [ValidateSet('None', 'Highest', 'Lowest')]
        [string]$Fallback = 'None'
    )

    if ($null -eq $SupportedRates -or $SupportedRates.Count -eq 0) {
        return [PSCustomObject]@{
            TargetRate   = $null
            UsedFallback = $false
            Reason       = 'No supported refresh rates reported for the current display.'
        }
    }

    $sortedRates = @($SupportedRates | Sort-Object -Unique)
    $rateListText = ($sortedRates | ForEach-Object { "${_}Hz" }) -join ', '
    $minRate = [int]$sortedRates[0]
    $maxRate = [int]$sortedRates[$sortedRates.Count - 1]

    $requestedText = "$RequestedRate".Trim().ToLowerInvariant()
    if ($requestedText -eq 'max' -or $requestedText -eq '0') {
        return [PSCustomObject]@{
            TargetRate   = $maxRate
            UsedFallback = $false
            Reason       = "Selected maximum supported refresh rate (${maxRate}Hz)."
        }
    }

    if ($requestedText -eq 'min') {
        return [PSCustomObject]@{
            TargetRate   = $minRate
            UsedFallback = $false
            Reason       = "Selected minimum supported refresh rate (${minRate}Hz)."
        }
    }

    $parsedRate = 0
    if (-not [int]::TryParse($requestedText, [ref]$parsedRate) -or $parsedRate -le 0) {
        return [PSCustomObject]@{
            TargetRate   = $null
            UsedFallback = $false
            Reason       = "Invalid refresh rate value '$RequestedRate'."
        }
    }

    if ($sortedRates -contains $parsedRate) {
        return [PSCustomObject]@{
            TargetRate   = $parsedRate
            UsedFallback = $false
            Reason       = "Matched supported refresh rate (${parsedRate}Hz)."
        }
    }

    if ($Fallback -eq 'Highest') {
        return [PSCustomObject]@{
            TargetRate   = $maxRate
            UsedFallback = $true
            Reason       = "Requested ${parsedRate}Hz not supported (available: $rateListText); falling back to highest (${maxRate}Hz)."
        }
    }

    if ($Fallback -eq 'Lowest') {
        return [PSCustomObject]@{
            TargetRate   = $minRate
            UsedFallback = $true
            Reason       = "Requested ${parsedRate}Hz not supported (available: $rateListText); falling back to lowest (${minRate}Hz)."
        }
    }

    return [PSCustomObject]@{
        TargetRate   = $null
        UsedFallback = $false
        Reason       = "Requested ${parsedRate}Hz is not supported by this display (supported: $rateListText)."
    }
}

function Invoke-DisplayChangeNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$RefreshRate,

        [string]$DeviceName = $null
    )

    Initialize-DisplayNativeApi
    return [int][WinPowerToggle.DisplayNative]::SetRefreshRate($DeviceName, $RefreshRate)
}

function Get-DisplayChangeStatusText {
    param([int]$Code)

    switch ($Code) {
        0  { return 'DISP_CHANGE_SUCCESSFUL' }
        1  { return 'DISP_CHANGE_RESTART' }
        -1 { return 'DISP_CHANGE_FAILED' }
        -2 { return 'DISP_CHANGE_BADMODE' }
        -3 { return 'DISP_CHANGE_NOTUPDATED' }
        -4 { return 'DISP_CHANGE_BADFLAGS' }
        -5 { return 'DISP_CHANGE_BADPARAM' }
        -6 { return 'DISP_CHANGE_BADDUALVIEW' }
        default { return "DISP_CHANGE_UNKNOWN ($Code)" }
    }
}

function Set-DisplayRefreshRate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $RefreshRate,

        [ValidateSet('None', 'Highest', 'Lowest')]
        [string]$Fallback = 'None',

        [string]$DeviceName = $null
    )

    $info = Get-DisplayInfo -DeviceName $DeviceName
    if ($null -eq $info) {
        return [PSCustomObject]@{
            Status       = 'Skipped'
            PreviousRate = $null
            CurrentRate  = $null
            Message      = 'Unable to query current display settings.'
        }
    }

    $resolved = Resolve-TargetRefreshRate -RequestedRate $RefreshRate -SupportedRates $info.SupportedRefreshRates -Fallback $Fallback
    if ($null -eq $resolved.TargetRate) {
        return [PSCustomObject]@{
            Status       = 'Skipped'
            PreviousRate = $info.RefreshRate
            CurrentRate  = $info.RefreshRate
            Message      = $resolved.Reason
        }
    }

    $targetRate = [int]$resolved.TargetRate
    if ($info.RefreshRate -eq $targetRate) {
        $unchangedMsg = "Already at ${targetRate}Hz."
        if ($resolved.UsedFallback) {
            $unchangedMsg = "$($resolved.Reason) Already at ${targetRate}Hz."
        }
        return [PSCustomObject]@{
            Status       = 'Unchanged'
            PreviousRate = $info.RefreshRate
            CurrentRate  = $targetRate
            Message      = $unchangedMsg
        }
    }

    try {
        $resultCode = Invoke-DisplayChangeNative -RefreshRate $targetRate -DeviceName $DeviceName
    }
    catch {
        return [PSCustomObject]@{
            Status       = 'Skipped'
            PreviousRate = $info.RefreshRate
            CurrentRate  = $info.RefreshRate
            Message      = "Display API error while setting ${targetRate}Hz: $($_.Exception.Message)"
        }
    }

    if ($resultCode -eq 0 -or $resultCode -eq 1) {
        $msg = "Changed refresh rate from $($info.RefreshRate)Hz to ${targetRate}Hz."
        if ($resolved.UsedFallback) {
            $msg = "$($resolved.Reason) $msg"
        }
        if ($resultCode -eq 1) {
            $msg = "$msg (Windows requested a restart to complete the change.)"
        }
        return [PSCustomObject]@{
            Status       = 'Changed'
            PreviousRate = $info.RefreshRate
            CurrentRate  = $targetRate
            Message      = $msg
        }
    }

    $codeText = Get-DisplayChangeStatusText -Code $resultCode
    return [PSCustomObject]@{
        Status       = 'Skipped'
        PreviousRate = $info.RefreshRate
        CurrentRate  = $info.RefreshRate
        Message      = "Could not switch refresh rate to ${targetRate}Hz ($codeText)."
    }
}
