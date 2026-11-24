<#
.SYNOPSIS
    Core UI state, theme palette, config persistence, and XAML definition for Win-Power-Toggle App.

.DESCRIPTION
    Pure PowerShell helper module consumed by WinPowerToggle-App.ps1 and unit tested
    independently via Pester. Keeps UI calculations, WCAG-verified Light/Dark palettes,
    config validation/saving, and XAML markup modular and testable.
#>

function Get-AppThemePalette {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Light', 'Dark')]
        [string]$Theme
    )

    if ($Theme -eq 'Light') {
        return @{
            ThemeName          = 'Light'
            WindowBg           = '#F5F4F0'
            CardBg             = '#FFFFFF'
            RecessedBg         = '#EAE8E1'
            InputBg            = '#FFFFFF'
            TextPrimary        = '#18181B'
            TextMuted          = '#52525B'
            TextOnRecessed     = '#4A4A52'
            BorderSubtle       = '#D6D3CB'
            BorderControl      = '#76736A'
            SecondaryBtnBg     = '#EAE8E1'
            SecondaryBtnHover  = '#DDD9CE'
            SecondaryBtnPress  = '#CFCAC0'
            SecondaryBtnFg     = '#18181B'
            BatteryBtnBg       = '#166534'
            BatteryBtnHover    = '#14532D'
            BatteryBtnPress    = '#0F3F22'
            BatteryBtnFg       = '#FFFFFF'
            BatteryAccentFg    = '#14532D'
            NormalBtnBg        = '#27272A'
            NormalBtnHover     = '#18181B'
            NormalBtnPress     = '#09090B'
            NormalBtnFg        = '#FFFFFF'
            GamingBtnBg        = '#B45309'
            GamingBtnHover     = '#92400E'
            GamingBtnPress     = '#78350F'
            GamingBtnFg        = '#FFFFFF'
            GamingAccentFg     = '#9A3412'
            ErrorBg            = '#FEF2F2'
            ErrorBorder        = '#B91C1C'
            ErrorFg            = '#991B1B'
            NoticeBg           = '#ECFDF5'
            NoticeBorder       = '#166534'
            NoticeFg           = '#14532D'
            LoadingBg          = '#EFF6FF'
            LoadingBorder      = '#1D4ED8'
            LoadingFg          = '#1E3A8A'
            FocusRing          = '#1D4ED8'
            ListSelectedBg     = '#DCE6F8'
            ListSelectedFg     = '#18181B'
        }
    }

    return @{
        ThemeName          = 'Dark'
        WindowBg           = '#121316'
        CardBg             = '#1B1D22'
        RecessedBg         = '#24272F'
        InputBg            = '#15171C'
        TextPrimary        = '#F4F4F5'
        TextMuted          = '#A8ACB8'
        TextOnRecessed     = '#B4B8C5'
        BorderSubtle       = '#2E323D'
        BorderControl      = '#6B7080'
        SecondaryBtnBg     = '#24272F'
        SecondaryBtnHover  = '#2F3340'
        SecondaryBtnPress  = '#393E4D'
        SecondaryBtnFg     = '#F4F4F5'
        BatteryBtnBg       = '#4ADE80'
        BatteryBtnHover    = '#86EFAC'
        BatteryBtnPress    = '#22C55E'
        BatteryBtnFg       = '#052E16'
        BatteryAccentFg    = '#4ADE80'
        NormalBtnBg        = '#E4E4E7'
        NormalBtnHover     = '#F4F4F5'
        NormalBtnPress     = '#D4D4D8'
        NormalBtnFg        = '#18181B'
        GamingBtnBg        = '#F59E0B'
        GamingBtnHover     = '#FBBF24'
        GamingBtnPress     = '#D97706'
        GamingBtnFg        = '#291403'
        GamingAccentFg     = '#FBBF24'
        ErrorBg            = '#2C1215'
        ErrorBorder        = '#F87171'
        ErrorFg            = '#FCA5A5'
        NoticeBg           = '#0D2618'
        NoticeBorder       = '#4ADE80'
        NoticeFg           = '#86EFAC'
        LoadingBg          = '#152238'
        LoadingBorder      = '#93C5FD'
        LoadingFg          = '#BFDBFE'
        FocusRing          = '#93C5FD'
        ListSelectedBg     = '#2D3A54'
        ListSelectedFg     = '#F4F4F5'
    }
}

function Get-WindowsPreferredAppTheme {
    [CmdletBinding()]
    param()

    try {
        $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        $prop = Get-ItemProperty -Path $regPath -Name 'AppsUseLightTheme' -ErrorAction Stop
        if ($prop.AppsUseLightTheme -eq 1) {
            return 'Light'
        }
        return 'Dark'
    }
    catch {
        return 'Dark'
    }
}

function Set-WindowThemePalette {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Light', 'Dark')]
        [string]$Theme
    )

    $palette = Get-AppThemePalette -Theme $Theme
    foreach ($key in $palette.Keys) {
        if ($key -eq 'ThemeName') { continue }
        $color = [System.Windows.Media.ColorConverter]::ConvertFromString($palette[$key])
        $existing = $Window.Resources[$key]
        if ($existing -is [System.Windows.Media.SolidColorBrush] -and -not $existing.IsFrozen) {
            $existing.Color = $color
        }
        else {
            $brush = New-Object System.Windows.Media.SolidColorBrush($color)
            $Window.Resources.Remove($key)
            [void]$Window.Resources.Add($key, $brush)
        }
    }
}

function Get-DetectedProfileState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $StatusObject,

        $Config = $null
    )

    $batCpu = if ($null -ne $Config -and $null -ne $Config.batteryMode.maxCpuState) { [int]$Config.batteryMode.maxCpuState } else { 50 }
    $normalCpu = if ($null -ne $Config -and $null -ne $Config.PSObject.Properties['normalMode'] -and $null -ne $Config.normalMode.maxCpuState) { [int]$Config.normalMode.maxCpuState } else { 100 }
    $gameCpu = if ($null -ne $Config -and $null -ne $Config.gamingMode.maxCpuState) { [int]$Config.gamingMode.maxCpuState } else { 100 }

    $overlay = "$($StatusObject.PowerModeOverlay)"
    $cpuCap = $StatusObject.ActiveCpuMaxState

    if ($overlay -eq 'Best Power Efficiency' -and ($null -eq $cpuCap -or $cpuCap -le $batCpu)) {
        return [PSCustomObject]@{
            Label  = 'Battery Saver'
            Detail = "Overlay: Best Power Efficiency, CPU cap: ${cpuCap}%"
        }
    }

    if ($overlay -eq 'Best Performance' -and ($null -eq $cpuCap -or $cpuCap -ge $gameCpu)) {
        return [PSCustomObject]@{
            Label  = 'Gaming Performance'
            Detail = "Overlay: Best Performance, CPU cap: ${cpuCap}%"
        }
    }

    if ($overlay -eq 'Balanced' -and ($null -eq $cpuCap -or $cpuCap -eq $normalCpu)) {
        return [PSCustomObject]@{
            Label  = 'Normal'
            Detail = "Overlay: Balanced, CPU cap: ${cpuCap}%"
        }
    }

    return [PSCustomObject]@{
        Label  = 'Custom'
        Detail = "Overlay: $overlay, CPU cap: ${cpuCap}%"
    }
}

function Format-ProfileCardSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Profile,

        [Parameter(Mandatory = $true)]
        [ValidateSet('battery', 'normal', 'gaming')]
        [string]$Mode
    )

    $parts = New-Object System.Collections.Generic.List[string]

    if ($null -ne $Profile.maxCpuState) {
        $parts.Add("$($Profile.maxCpuState)% CPU")
    }
    if ($null -ne $Profile.brightness) {
        $parts.Add("$($Profile.brightness)% brightness")
    }
    if ($null -ne $Profile.refreshRate) {
        $rateStr = "$($Profile.refreshRate)".Trim().ToLowerInvariant()
        if ($rateStr -eq 'max' -or $rateStr -eq '0') {
            $parts.Add('Max Hz')
        }
        elseif ($rateStr -eq 'min') {
            $parts.Add('Min Hz')
        }
        else {
            $parts.Add("${rateStr}Hz")
        }
    }

    switch ($Mode) {
        'battery' { $parts.Add('Best Power Efficiency') }
        'normal'  { $parts.Add('Balanced') }
        default   { $parts.Add('Best Performance') }
    }

    return ($parts -join ', ')
}

function Get-RefreshRateChoices {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [int[]]$SupportedRates = @(),

        $ConfiguredRate = $null
    )

    $numericSet = New-Object System.Collections.Generic.SortedSet[int]
    foreach ($rate in $SupportedRates) {
        if ($rate -gt 1) {
            [void]$numericSet.Add([int]$rate)
        }
    }

    if ($null -ne $ConfiguredRate) {
        $parsed = 0
        if ([int]::TryParse("$ConfiguredRate".Trim(), [ref]$parsed) -and $parsed -gt 1) {
            [void]$numericSet.Add($parsed)
        }
    }

    if ($numericSet.Count -eq 0) {
        [void]$numericSet.Add(60)
        [void]$numericSet.Add(144)
    }

    $result = New-Object System.Collections.Generic.List[string]
    foreach ($num in $numericSet) {
        $result.Add("$num")
    }
    $result.Add('max')
    $result.Add('min')

    return $result.ToArray()
}

function Test-RefreshRatesChanged {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [int[]]$Current = @(),

        [AllowEmptyCollection()]
        [int[]]$Incoming = @()
    )

    $a = @($Current | Sort-Object -Unique)
    $b = @($Incoming | Sort-Object -Unique)
    if ($a.Count -ne $b.Count) {
        return $true
    }

    for ($i = 0; $i -lt $a.Count; $i++) {
        if ($a[$i] -ne $b[$i]) {
            return $true
        }
    }

    return $false
}

function Add-AppListItem {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [string[]]$Items = @(),

        [AllowEmptyString()]
        [string]$NewItem = '',

        [switch]$NormalizeProcessName
    )

    $cleaned = "$NewItem".Trim()
    if ($NormalizeProcessName) {
        $cleaned = $cleaned -replace '\.exe$', ''
    }

    if ([string]::IsNullOrWhiteSpace($cleaned)) {
        return [PSCustomObject]@{
            Added   = $false
            Items   = @($Items)
            Message = 'Enter an application name or path before clicking Add.'
        }
    }

    foreach ($existing in @($Items)) {
        if ("$existing".Equals($cleaned, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [PSCustomObject]@{
                Added   = $false
                Items   = @($Items)
                Message = "'$cleaned' is already in the list."
            }
        }
    }

    $list = New-Object System.Collections.Generic.List[string]
    foreach ($existing in @($Items)) {
        if (-not [string]::IsNullOrWhiteSpace($existing)) {
            $list.Add($existing)
        }
    }
    $list.Add($cleaned)

    return [PSCustomObject]@{
        Added   = $true
        Items   = $list.ToArray()
        Message = "Added '$cleaned'."
    }
}

function Remove-AppListItem {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [string[]]$Items = @(),

        [AllowEmptyString()]
        [string]$ItemToRemove = ''
    )

    $list = New-Object System.Collections.Generic.List[string]
    foreach ($existing in @($Items)) {
        if (-not "$existing".Equals($ItemToRemove, [System.StringComparison]::OrdinalIgnoreCase)) {
            $list.Add($existing)
        }
    }
    return $list.ToArray()
}

function ConvertTo-RateJsonValue {
    param($RateValue)

    if ($null -eq $RateValue) {
        return $null
    }

    $text = "$RateValue".Trim().ToLowerInvariant()
    if ($text -eq 'max' -or $text -eq 'min') {
        return $text
    }

    $parsed = 0
    if ([int]::TryParse($text, [ref]$parsed) -and $parsed -ge 0) {
        return $parsed
    }

    throw "Configuration error: refreshRate '$RateValue' must be a positive integer, 0, 'max', or 'min'."
}

function Save-PowerToggleConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Config,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($null -eq $Config.batteryMode -or $null -eq $Config.gamingMode) {
        throw "Configuration error: both 'batteryMode' and 'gamingMode' sections are required."
    }

    $batBrightness = if ($null -ne $Config.batteryMode.brightness) { [int]$Config.batteryMode.brightness } else { $null }
    $batCpu = if ($null -ne $Config.batteryMode.maxCpuState) { [int]$Config.batteryMode.maxCpuState } else { $null }
    $hasNormal = ($null -ne $Config.PSObject.Properties['normalMode'] -and $null -ne $Config.normalMode)
    $normalBrightness = if ($hasNormal -and $null -ne $Config.normalMode.brightness) { [int]$Config.normalMode.brightness } else { 70 }
    $normalCpu = if ($hasNormal -and $null -ne $Config.normalMode.maxCpuState) { [int]$Config.normalMode.maxCpuState } else { 100 }
    $normalRateInput = if ($hasNormal -and $null -ne $Config.normalMode.refreshRate) { $Config.normalMode.refreshRate } else { 144 }
    $gameBrightness = if ($null -ne $Config.gamingMode.brightness) { [int]$Config.gamingMode.brightness } else { $null }
    $gameCpu = if ($null -ne $Config.gamingMode.maxCpuState) { [int]$Config.gamingMode.maxCpuState } else { $null }

    if ($null -ne $batBrightness -and ($batBrightness -lt 0 -or $batBrightness -gt 100)) {
        throw "Configuration error: batteryMode.brightness must be between 0 and 100 (got $batBrightness)."
    }
    if ($null -ne $batCpu -and ($batCpu -lt 0 -or $batCpu -gt 100)) {
        throw "Configuration error: batteryMode.maxCpuState must be between 0 and 100 (got $batCpu)."
    }
    if ($null -ne $normalBrightness -and ($normalBrightness -lt 0 -or $normalBrightness -gt 100)) {
        throw "Configuration error: normalMode.brightness must be between 0 and 100 (got $normalBrightness)."
    }
    if ($null -ne $normalCpu -and ($normalCpu -lt 0 -or $normalCpu -gt 100)) {
        throw "Configuration error: normalMode.maxCpuState must be between 0 and 100 (got $normalCpu)."
    }
    if ($null -ne $gameBrightness -and ($gameBrightness -lt 0 -or $gameBrightness -gt 100)) {
        throw "Configuration error: gamingMode.brightness must be between 0 and 100 (got $gameBrightness)."
    }
    if ($null -ne $gameCpu -and ($gameCpu -lt 0 -or $gameCpu -gt 100)) {
        throw "Configuration error: gamingMode.maxCpuState must be between 0 and 100 (got $gameCpu)."
    }

    $batRate = ConvertTo-RateJsonValue $Config.batteryMode.refreshRate
    $normalRate = ConvertTo-RateJsonValue $normalRateInput
    $gameRate = ConvertTo-RateJsonValue $Config.gamingMode.refreshRate

    $forceSaver = if ($null -ne $Config.batteryMode.PSObject.Properties['forceBatterySaver']) {
        [bool]$Config.batteryMode.forceBatterySaver
    }
    else {
        $true
    }

    $orderedPayload = [ordered]@{
        batteryMode = [ordered]@{
            brightness        = $batBrightness
            refreshRate       = $batRate
            maxCpuState       = $batCpu
            forceBatterySaver = $forceSaver
            appsToKill        = @($Config.batteryMode.appsToKill | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
        normalMode = [ordered]@{
            brightness  = $normalBrightness
            refreshRate = $normalRate
            maxCpuState = $normalCpu
        }
        gamingMode = [ordered]@{
            brightness   = $gameBrightness
            refreshRate  = $gameRate
            maxCpuState  = $gameCpu
            appsToLaunch = @($Config.gamingMode.appsToLaunch | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    }

    $json = ($orderedPayload | ConvertTo-Json -Depth 4) + [Environment]::NewLine
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)

    return [PSCustomObject]@{
        Success = $true
        Path    = $Path
        Message = "Saved configuration to $Path."
    }
}

function Get-AppWindowXaml {
    [CmdletBinding()]
    param()

    return @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Win-Power-Toggle"
        Width="720"
        Height="800"
        MinWidth="580"
        MinHeight="560"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResize"
        FontFamily="Segoe UI"
        FontSize="13"
        UseLayoutRounding="True"
        SnapsToDevicePixels="True"
        Background="{DynamicResource WindowBg}"
        Foreground="{DynamicResource TextPrimary}">
    <Window.Resources>
        <SolidColorBrush x:Key="WindowBg" Color="#F5F4F0"/>
        <SolidColorBrush x:Key="CardBg" Color="#FFFFFF"/>
        <SolidColorBrush x:Key="RecessedBg" Color="#EAE8E1"/>
        <SolidColorBrush x:Key="InputBg" Color="#FFFFFF"/>
        <SolidColorBrush x:Key="TextPrimary" Color="#18181B"/>
        <SolidColorBrush x:Key="TextMuted" Color="#52525B"/>
        <SolidColorBrush x:Key="TextOnRecessed" Color="#4A4A52"/>
        <SolidColorBrush x:Key="BorderSubtle" Color="#D6D3CB"/>
        <SolidColorBrush x:Key="BorderControl" Color="#76736A"/>
        <SolidColorBrush x:Key="SecondaryBtnBg" Color="#EAE8E1"/>
        <SolidColorBrush x:Key="SecondaryBtnHover" Color="#DDD9CE"/>
        <SolidColorBrush x:Key="SecondaryBtnPress" Color="#CFCAC0"/>
        <SolidColorBrush x:Key="SecondaryBtnFg" Color="#18181B"/>
        <SolidColorBrush x:Key="BatteryBtnBg" Color="#166534"/>
        <SolidColorBrush x:Key="BatteryBtnHover" Color="#14532D"/>
        <SolidColorBrush x:Key="BatteryBtnPress" Color="#0F3F22"/>
        <SolidColorBrush x:Key="BatteryBtnFg" Color="#FFFFFF"/>
        <SolidColorBrush x:Key="BatteryAccentFg" Color="#14532D"/>
        <SolidColorBrush x:Key="NormalBtnBg" Color="#27272A"/>
        <SolidColorBrush x:Key="NormalBtnHover" Color="#18181B"/>
        <SolidColorBrush x:Key="NormalBtnPress" Color="#09090B"/>
        <SolidColorBrush x:Key="NormalBtnFg" Color="#FFFFFF"/>
        <SolidColorBrush x:Key="GamingBtnBg" Color="#B45309"/>
        <SolidColorBrush x:Key="GamingBtnHover" Color="#92400E"/>
        <SolidColorBrush x:Key="GamingBtnPress" Color="#78350F"/>
        <SolidColorBrush x:Key="GamingBtnFg" Color="#FFFFFF"/>
        <SolidColorBrush x:Key="GamingAccentFg" Color="#9A3412"/>
        <SolidColorBrush x:Key="ErrorBg" Color="#FEF2F2"/>
        <SolidColorBrush x:Key="ErrorBorder" Color="#B91C1C"/>
        <SolidColorBrush x:Key="ErrorFg" Color="#991B1B"/>
        <SolidColorBrush x:Key="NoticeBg" Color="#ECFDF5"/>
        <SolidColorBrush x:Key="NoticeBorder" Color="#166534"/>
        <SolidColorBrush x:Key="NoticeFg" Color="#14532D"/>
        <SolidColorBrush x:Key="LoadingBg" Color="#EFF6FF"/>
        <SolidColorBrush x:Key="LoadingBorder" Color="#1D4ED8"/>
        <SolidColorBrush x:Key="LoadingFg" Color="#1E3A8A"/>
        <SolidColorBrush x:Key="FocusRing" Color="#1D4ED8"/>
        <SolidColorBrush x:Key="ListSelectedBg" Color="#DCE6F8"/>
        <SolidColorBrush x:Key="ListSelectedFg" Color="#18181B"/>

        <Style x:Key="HighContrastFocusVisual">
            <Setter Property="Control.Template">
                <Setter.Value>
                    <ControlTemplate>
                        <Rectangle Margin="-3"
                                   StrokeThickness="2"
                                   Stroke="{DynamicResource FocusRing}"
                                   RadiusX="6"
                                   RadiusY="6"
                                   SnapsToDevicePixels="True"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ModeActionButton" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="MinHeight" Value="74"/>
            <Setter Property="Padding" Value="16,14"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FocusVisualStyle" Value="{StaticResource HighContrastFocusVisual}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                              VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.52"/>
                                <Setter Property="Cursor" Value="Arrow"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="BatteryModeButton" TargetType="Button" BasedOn="{StaticResource ModeActionButton}">
            <Setter Property="Background" Value="{DynamicResource BatteryBtnBg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BatteryBtnBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource BatteryBtnFg}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource BatteryBtnHover}"/>
                    <Setter Property="BorderBrush" Value="{DynamicResource BatteryBtnHover}"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="Background" Value="{DynamicResource BatteryBtnPress}"/>
                    <Setter Property="BorderBrush" Value="{DynamicResource BatteryBtnPress}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="NormalModeButton" TargetType="Button" BasedOn="{StaticResource ModeActionButton}">
            <Setter Property="Background" Value="{DynamicResource NormalBtnBg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource NormalBtnBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource NormalBtnFg}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource NormalBtnHover}"/>
                    <Setter Property="BorderBrush" Value="{DynamicResource NormalBtnHover}"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="Background" Value="{DynamicResource NormalBtnPress}"/>
                    <Setter Property="BorderBrush" Value="{DynamicResource NormalBtnPress}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="GamingModeButton" TargetType="Button" BasedOn="{StaticResource ModeActionButton}">
            <Setter Property="Background" Value="{DynamicResource GamingBtnBg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource GamingBtnBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource GamingBtnFg}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource GamingBtnHover}"/>
                    <Setter Property="BorderBrush" Value="{DynamicResource GamingBtnHover}"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="Background" Value="{DynamicResource GamingBtnPress}"/>
                    <Setter Property="BorderBrush" Value="{DynamicResource GamingBtnPress}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="SecondaryButton" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="MinHeight" Value="34"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="Background" Value="{DynamicResource SecondaryBtnBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource SecondaryBtnFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderControl}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FocusVisualStyle" Value="{StaticResource HighContrastFocusVisual}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="5"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource SecondaryBtnHover}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource SecondaryBtnPress}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.48"/>
                                <Setter Property="Cursor" Value="Arrow"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="PrimarySaveButton" TargetType="Button" BasedOn="{StaticResource SecondaryButton}">
            <Setter Property="Background" Value="{DynamicResource BatteryBtnBg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BatteryBtnBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource BatteryBtnFg}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="5"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BatteryBtnHover}"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource BatteryBtnHover}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BatteryBtnPress}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.48"/>
                                <Setter Property="Cursor" Value="Arrow"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="TextBox">
            <Setter Property="MinHeight" Value="34"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Background" Value="{DynamicResource InputBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="CaretBrush" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderControl}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FocusVisualStyle" Value="{StaticResource HighContrastFocusVisual}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="Bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="4">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="2,0"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource FocusRing}"/>
                                <Setter TargetName="Bd" Property="BorderThickness" Value="2"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="ComboBoxItem">
            <Setter Property="Padding" Value="10,7"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="Background" Value="{DynamicResource CardBg}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource ListSelectedBg}"/>
                                <Setter Property="Foreground" Value="{DynamicResource ListSelectedFg}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="ComboBox">
            <Setter Property="MinHeight" Value="34"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="Background" Value="{DynamicResource InputBg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderControl}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FocusVisualStyle" Value="{StaticResource HighContrastFocusVisual}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton x:Name="ToggleButton"
                                          Cursor="Hand"
                                          Focusable="False"
                                          IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"
                                          ClickMode="Press">
                                <ToggleButton.Template>
                                    <ControlTemplate TargetType="ToggleButton">
                                        <Border x:Name="Bd"
                                                Background="{DynamicResource InputBg}"
                                                BorderBrush="{DynamicResource BorderControl}"
                                                BorderThickness="1"
                                                CornerRadius="4">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="28"/>
                                                </Grid.ColumnDefinitions>
                                                <Path Grid.Column="1"
                                                      HorizontalAlignment="Center"
                                                      VerticalAlignment="Center"
                                                      Data="M 0 0 L 4 4 L 8 0 Z"
                                                      Fill="{DynamicResource TextPrimary}"/>
                                            </Grid>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource FocusRing}"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </ToggleButton.Template>
                            </ToggleButton>
                            <ContentPresenter x:Name="ContentSite"
                                              IsHitTestVisible="False"
                                              Content="{TemplateBinding SelectionBoxItem}"
                                              ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                              Margin="10,4,30,4"
                                              VerticalAlignment="Center"
                                              HorizontalAlignment="Left"/>
                            <Popup x:Name="Popup"
                                   Placement="Bottom"
                                   IsOpen="{TemplateBinding IsDropDownOpen}"
                                   AllowsTransparency="True"
                                   Focusable="False"
                                   PopupAnimation="None">
                                <Border MinWidth="{TemplateBinding ActualWidth}"
                                        MaxHeight="220"
                                        Background="{DynamicResource CardBg}"
                                        BorderBrush="{DynamicResource BorderControl}"
                                        BorderThickness="1"
                                        CornerRadius="4"
                                        Margin="0,2,0,0">
                                    <ScrollViewer SnapsToDevicePixels="True">
                                        <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/>
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="ListBox">
            <Setter Property="Background" Value="{DynamicResource InputBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderControl}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="2"/>
            <Setter Property="FocusVisualStyle" Value="{StaticResource HighContrastFocusVisual}"/>
            <Setter Property="ItemContainerStyle">
                <Setter.Value>
                    <Style TargetType="ListBoxItem">
                        <Setter Property="Cursor" Value="Hand"/>
                        <Setter Property="Padding" Value="8,6"/>
                        <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
                        <Setter Property="FocusVisualStyle" Value="{StaticResource HighContrastFocusVisual}"/>
                        <Setter Property="Template">
                            <Setter.Value>
                                <ControlTemplate TargetType="ListBoxItem">
                                    <Border x:Name="Bd" Background="Transparent" CornerRadius="3" Padding="{TemplateBinding Padding}">
                                        <ContentPresenter/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True">
                                            <Setter TargetName="Bd" Property="Background" Value="{DynamicResource RecessedBg}"/>
                                        </Trigger>
                                        <Trigger Property="IsSelected" Value="True">
                                            <Setter TargetName="Bd" Property="Background" Value="{DynamicResource ListSelectedBg}"/>
                                            <Setter Property="Foreground" Value="{DynamicResource ListSelectedFg}"/>
                                            <Setter Property="FontWeight" Value="SemiBold"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                    </Style>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="TabItem">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="{DynamicResource TextMuted}"/>
            <Setter Property="FocusVisualStyle" Value="{StaticResource HighContrastFocusVisual}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="Bd"
                                Background="Transparent"
                                BorderBrush="Transparent"
                                BorderThickness="0,0,0,2"
                                Padding="{TemplateBinding Padding}"
                                Margin="0,0,6,0">
                            <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource FocusRing}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="Slider">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="IsMoveToPointEnabled" Value="True"/>
            <Setter Property="FocusVisualStyle" Value="{StaticResource HighContrastFocusVisual}"/>
        </Style>
    </Window.Resources>

    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="20,18,20,22">
            <!-- Header Bar -->
            <Grid Margin="0,0,0,16">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0" VerticalAlignment="Center">
                    <TextBlock Text="Win-Power-Toggle"
                               FontSize="20"
                               FontWeight="SemiBold"
                               Foreground="{DynamicResource TextPrimary}"/>
                    <TextBlock x:Name="TxtDetectedProfile"
                               Text="Reading current power state..."
                               Margin="0,2,12,0"
                               FontSize="12"
                               TextWrapping="Wrap"
                               Foreground="{DynamicResource TextMuted}"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button x:Name="BtnThemeToggle"
                            Style="{StaticResource SecondaryButton}"
                            Content="Dark Theme"
                            Margin="0,0,8,0"
                            AutomationProperties.Name="Toggle Light and Dark Theme"/>
                    <Button x:Name="BtnMinimizeTray"
                            Style="{StaticResource SecondaryButton}"
                            Content="Send to Tray"
                            AutomationProperties.Name="Minimize Window to System Tray"/>
                </StackPanel>
            </Grid>

            <!-- Loading Banner (R-27) -->
            <Border x:Name="BannerLoading"
                    Visibility="Collapsed"
                    Background="{DynamicResource LoadingBg}"
                    BorderBrush="{DynamicResource LoadingBorder}"
                    BorderThickness="1"
                    CornerRadius="6"
                    Padding="12,10"
                    Margin="0,0,0,12">
                <TextBlock x:Name="TxtLoadingMessage"
                           Text="Working: reading hardware status..."
                           Foreground="{DynamicResource LoadingFg}"
                           FontWeight="SemiBold"
                           TextWrapping="Wrap"/>
            </Border>

            <!-- Error Banner (R-27) -->
            <Border x:Name="BannerError"
                    Visibility="Collapsed"
                    Background="{DynamicResource ErrorBg}"
                    BorderBrush="{DynamicResource ErrorBorder}"
                    BorderThickness="1"
                    CornerRadius="6"
                    Padding="12,10"
                    Margin="0,0,0,12">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock x:Name="TxtErrorMessage"
                               Grid.Column="0"
                               Foreground="{DynamicResource ErrorFg}"
                               FontWeight="SemiBold"
                               VerticalAlignment="Center"
                               TextWrapping="Wrap"
                               Margin="0,0,10,0"/>
                    <Button x:Name="BtnDismissError"
                            Grid.Column="1"
                            Style="{StaticResource SecondaryButton}"
                            Content="Dismiss"
                            MinHeight="28"
                            Padding="10,4"
                            AutomationProperties.Name="Dismiss Error Message"/>
                </Grid>
            </Border>

            <!-- Notice Banner -->
            <Border x:Name="BannerNotice"
                    Visibility="Collapsed"
                    Background="{DynamicResource NoticeBg}"
                    BorderBrush="{DynamicResource NoticeBorder}"
                    BorderThickness="1"
                    CornerRadius="6"
                    Padding="12,10"
                    Margin="0,0,0,12">
                <TextBlock x:Name="TxtNoticeMessage"
                           Foreground="{DynamicResource NoticeFg}"
                           FontWeight="SemiBold"
                           TextWrapping="Wrap"/>
            </Border>

            <!-- Focal Point: Mode Switch Deck -->
            <Border Background="{DynamicResource CardBg}"
                    BorderBrush="{DynamicResource BorderSubtle}"
                    BorderThickness="1"
                    CornerRadius="6"
                    Padding="16"
                    Margin="0,0,0,16">
                <StackPanel>
                    <TextBlock Text="Switch Power Profile"
                               FontSize="14"
                               FontWeight="SemiBold"
                               Foreground="{DynamicResource TextPrimary}"
                               Margin="0,0,0,12"/>
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="10"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="10"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <Button x:Name="BtnBatteryMode"
                                Grid.Column="0"
                                Style="{StaticResource BatteryModeButton}"
                                AutomationProperties.Name="Switch to Battery Saver Profile">
                            <StackPanel>
                                <TextBlock Text="Battery Saver"
                                           FontSize="15"
                                           FontWeight="SemiBold"/>
                                <TextBlock x:Name="TxtBatterySummary"
                                           Text="50% CPU, 30% brightness, 60Hz, Best Power Efficiency"
                                           FontSize="12"
                                           Margin="0,4,0,0"
                                           TextWrapping="Wrap"/>
                            </StackPanel>
                        </Button>

                        <Button x:Name="BtnNormalMode"
                                Grid.Column="2"
                                Style="{StaticResource NormalModeButton}"
                                AutomationProperties.Name="Switch to Normal Balanced Profile">
                            <StackPanel>
                                <TextBlock Text="Normal"
                                           FontSize="15"
                                           FontWeight="SemiBold"/>
                                <TextBlock x:Name="TxtNormalSummary"
                                           Text="100% CPU, 70% brightness, 144Hz, Balanced"
                                           FontSize="12"
                                           Margin="0,4,0,0"
                                           TextWrapping="Wrap"/>
                            </StackPanel>
                        </Button>

                        <Button x:Name="BtnGamingMode"
                                Grid.Column="4"
                                Style="{StaticResource GamingModeButton}"
                                AutomationProperties.Name="Switch to Gaming Performance Profile">
                            <StackPanel>
                                <TextBlock Text="Gaming Performance"
                                           FontSize="15"
                                           FontWeight="SemiBold"/>
                                <TextBlock x:Name="TxtGamingSummary"
                                           Text="100% CPU, 100% brightness, 144Hz, Best Performance"
                                           FontSize="12"
                                           Margin="0,4,0,0"
                                           TextWrapping="Wrap"/>
                            </StackPanel>
                        </Button>
                    </Grid>
                </StackPanel>
            </Border>

            <!-- Live Hardware Telemetry -->
            <Border Background="{DynamicResource CardBg}"
                    BorderBrush="{DynamicResource BorderSubtle}"
                    BorderThickness="1"
                    CornerRadius="6"
                    Padding="16"
                    Margin="0,0,0,16">
                <StackPanel>
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0" VerticalAlignment="Center">
                            <TextBlock Text="Live Hardware Status"
                                       FontSize="14"
                                       FontWeight="SemiBold"
                                       Foreground="{DynamicResource TextPrimary}"/>
                            <TextBlock x:Name="TxtStatusUpdated"
                                       Text="Live (2s) | Reading hardware..."
                                       FontSize="11"
                                       Margin="0,2,12,0"
                                       Foreground="{DynamicResource TextMuted}"/>
                        </StackPanel>
                        <Button x:Name="BtnRefreshStatus"
                                Grid.Column="1"
                                Style="{StaticResource SecondaryButton}"
                                Content="Refresh Status"
                                VerticalAlignment="Center"
                                AutomationProperties.Name="Refresh Live Hardware Status"/>
                    </Grid>

                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="10"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="10"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <Border Grid.Row="0" Grid.Column="0" Background="{DynamicResource RecessedBg}" CornerRadius="5" Padding="12,10">
                            <StackPanel>
                                <TextBlock Text="Power Source &amp; Battery" FontSize="12" Foreground="{DynamicResource TextOnRecessed}"/>
                                <TextBlock x:Name="TxtStatusPower" Text="--" FontFamily="Consolas" FontSize="14" FontWeight="SemiBold" Margin="0,4,0,0" Foreground="{DynamicResource TextPrimary}" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>

                        <Border Grid.Row="0" Grid.Column="2" Background="{DynamicResource RecessedBg}" CornerRadius="5" Padding="12,10">
                            <StackPanel>
                                <TextBlock Text="Windows Power Mode" FontSize="12" Foreground="{DynamicResource TextOnRecessed}"/>
                                <TextBlock x:Name="TxtStatusOverlay" Text="--" FontFamily="Consolas" FontSize="14" FontWeight="SemiBold" Margin="0,4,0,0" Foreground="{DynamicResource TextPrimary}" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>

                        <Border Grid.Row="2" Grid.Column="0" Background="{DynamicResource RecessedBg}" CornerRadius="5" Padding="12,10">
                            <StackPanel>
                                <TextBlock Text="Max Processor State" FontSize="12" Foreground="{DynamicResource TextOnRecessed}"/>
                                <TextBlock x:Name="TxtStatusCpu" Text="--" FontFamily="Consolas" FontSize="14" FontWeight="SemiBold" Margin="0,4,0,0" Foreground="{DynamicResource TextPrimary}" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>

                        <Border Grid.Row="2" Grid.Column="2" Background="{DynamicResource RecessedBg}" CornerRadius="5" Padding="12,10">
                            <StackPanel>
                                <TextBlock Text="Display Output &amp; Brightness" FontSize="12" Foreground="{DynamicResource TextOnRecessed}"/>
                                <TextBlock x:Name="TxtStatusDisplay" Text="--" FontFamily="Consolas" FontSize="14" FontWeight="SemiBold" Margin="0,4,0,0" Foreground="{DynamicResource TextPrimary}" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>
                    </Grid>
                </StackPanel>
            </Border>

            <!-- Computer Specs -->
            <Border Background="{DynamicResource CardBg}"
                    BorderBrush="{DynamicResource BorderSubtle}"
                    BorderThickness="1"
                    CornerRadius="6"
                    Padding="16"
                    Margin="0,0,0,16">
                <StackPanel>
                    <TextBlock Text="Computer Specs"
                               FontSize="14"
                               FontWeight="SemiBold"
                               Foreground="{DynamicResource TextPrimary}"
                               Margin="0,0,0,12"/>
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="10"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="10"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <Border Grid.Row="0" Grid.Column="0" Background="{DynamicResource RecessedBg}" CornerRadius="5" Padding="12,10">
                            <StackPanel>
                                <TextBlock Text="Processor" FontSize="12" Foreground="{DynamicResource TextOnRecessed}"/>
                                <TextBlock x:Name="TxtSpecCpu" Text="Reading system hardware..." FontFamily="Consolas" FontSize="12" FontWeight="SemiBold" Margin="0,4,0,0" Foreground="{DynamicResource TextPrimary}" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>

                        <Border Grid.Row="0" Grid.Column="2" Background="{DynamicResource RecessedBg}" CornerRadius="5" Padding="12,10">
                            <StackPanel>
                                <TextBlock Text="Graphics" FontSize="12" Foreground="{DynamicResource TextOnRecessed}"/>
                                <TextBlock x:Name="TxtSpecGpu" Text="Reading system hardware..." FontFamily="Consolas" FontSize="12" FontWeight="SemiBold" Margin="0,4,0,0" Foreground="{DynamicResource TextPrimary}" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>

                        <Border Grid.Row="2" Grid.Column="0" Background="{DynamicResource RecessedBg}" CornerRadius="5" Padding="12,10">
                            <StackPanel>
                                <TextBlock Text="Memory" FontSize="12" Foreground="{DynamicResource TextOnRecessed}"/>
                                <TextBlock x:Name="TxtSpecRam" Text="Reading system hardware..." FontFamily="Consolas" FontSize="12" FontWeight="SemiBold" Margin="0,4,0,0" Foreground="{DynamicResource TextPrimary}" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>

                        <Border Grid.Row="2" Grid.Column="2" Background="{DynamicResource RecessedBg}" CornerRadius="5" Padding="12,10">
                            <StackPanel>
                                <TextBlock Text="Operating System" FontSize="12" Foreground="{DynamicResource TextOnRecessed}"/>
                                <TextBlock x:Name="TxtSpecOs" Text="Reading system hardware..." FontFamily="Consolas" FontSize="12" FontWeight="SemiBold" Margin="0,4,0,0" Foreground="{DynamicResource TextPrimary}" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>
                    </Grid>
                </StackPanel>
            </Border>

            <!-- Last Action Readout -->
            <Border Background="{DynamicResource CardBg}"
                    BorderBrush="{DynamicResource BorderSubtle}"
                    BorderThickness="1"
                    CornerRadius="6"
                    Padding="16"
                    Margin="0,0,0,16">
                <StackPanel>
                    <TextBlock Text="Last Switch Output"
                               FontSize="14"
                               FontWeight="SemiBold"
                               Foreground="{DynamicResource TextPrimary}"
                               Margin="0,0,0,8"/>
                    <TextBlock x:Name="TxtLastAction"
                               Text="No mode switch run in this session yet. Choose Battery Saver, Normal, or Gaming Performance above."
                               FontFamily="Consolas"
                               FontSize="12"
                               Foreground="{DynamicResource TextMuted}"
                               TextWrapping="Wrap"/>
                </StackPanel>
            </Border>

            <!-- Profile Configuration Editor -->
            <Border Background="{DynamicResource CardBg}"
                    BorderBrush="{DynamicResource BorderSubtle}"
                    BorderThickness="1"
                    CornerRadius="6"
                    Padding="16">
                <StackPanel>
                    <Grid Margin="0,0,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0" VerticalAlignment="Center">
                            <TextBlock Text="Profile Settings (config.json)"
                                       FontSize="14"
                                       FontWeight="SemiBold"
                                       Foreground="{DynamicResource TextPrimary}"/>
                            <TextBlock x:Name="TxtConfigPath"
                                       Text="config.json"
                                       FontSize="11"
                                       Margin="0,2,12,0"
                                       Foreground="{DynamicResource TextMuted}"
                                       TextTrimming="CharacterEllipsis"/>
                        </StackPanel>
                        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                            <Button x:Name="BtnReloadConfig"
                                    Style="{StaticResource SecondaryButton}"
                                    Content="Reload"
                                    Margin="0,0,8,0"
                                    AutomationProperties.Name="Reload Settings from config.json"/>
                            <Button x:Name="BtnSaveConfig"
                                    Style="{StaticResource PrimarySaveButton}"
                                    Content="Save Settings"
                                    AutomationProperties.Name="Save Profile Settings to config.json"/>
                        </StackPanel>
                    </Grid>

                    <TabControl x:Name="TabProfiles"
                                Background="Transparent"
                                BorderThickness="0,1,0,0"
                                BorderBrush="{DynamicResource BorderSubtle}"
                                Padding="0,12,0,0">
                        <!-- Battery Profile Tab -->
                        <TabItem Header="Battery Profile">
                            <StackPanel>
                                <Grid Margin="0,0,0,12">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="155"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="52"/>
                                    </Grid.ColumnDefinitions>
                                    <Label Grid.Column="0" Content="Max CPU State" Target="{Binding ElementName=SliderBatCpu}" Foreground="{DynamicResource TextPrimary}" VerticalAlignment="Center" Padding="0"/>
                                    <Slider x:Name="SliderBatCpu" Grid.Column="1" Minimum="5" Maximum="100" TickFrequency="5" IsSnapToTickEnabled="True" VerticalAlignment="Center" AutomationProperties.Name="Battery Mode Max CPU State Percentage"/>
                                    <TextBlock x:Name="TxtBatCpuVal" Grid.Column="2" Text="50%" FontFamily="Consolas" FontWeight="SemiBold" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="{DynamicResource TextPrimary}"/>
                                </Grid>

                                <Grid Margin="0,0,0,12">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="155"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="52"/>
                                    </Grid.ColumnDefinitions>
                                    <Label Grid.Column="0" Content="Display Brightness" Target="{Binding ElementName=SliderBatBright}" Foreground="{DynamicResource TextPrimary}" VerticalAlignment="Center" Padding="0"/>
                                    <Slider x:Name="SliderBatBright" Grid.Column="1" Minimum="0" Maximum="100" TickFrequency="5" IsSnapToTickEnabled="True" VerticalAlignment="Center" AutomationProperties.Name="Battery Mode Display Brightness Percentage"/>
                                    <TextBlock x:Name="TxtBatBrightVal" Grid.Column="2" Text="30%" FontFamily="Consolas" FontWeight="SemiBold" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="{DynamicResource TextPrimary}"/>
                                </Grid>

                                <Grid Margin="0,0,0,14">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="155"/>
                                        <ColumnDefinition Width="140"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Label Grid.Column="0" Content="Refresh Rate (Hz)" Target="{Binding ElementName=CboBatRefresh}" Foreground="{DynamicResource TextPrimary}" VerticalAlignment="Center" Padding="0"/>
                                    <ComboBox x:Name="CboBatRefresh" Grid.Column="1" AutomationProperties.Name="Battery Mode Refresh Rate"/>
                                </Grid>

                                <Label Content="Background Apps to Stop" Target="{Binding ElementName=TxtAddKillApp}" Foreground="{DynamicResource TextPrimary}" FontWeight="SemiBold" Padding="0" Margin="0,0,0,6"/>
                                <Grid MinHeight="88" Margin="0,0,0,8">
                                    <ListBox x:Name="LstAppsToKill" Height="96" AutomationProperties.Name="Background Apps to Stop List"/>
                                    <TextBlock x:Name="TxtEmptyKillList"
                                               Text="No background apps configured to stop. Enter a process name below and click Add."
                                               Visibility="Collapsed"
                                               IsHitTestVisible="False"
                                               Foreground="{DynamicResource TextMuted}"
                                               VerticalAlignment="Center"
                                               HorizontalAlignment="Center"
                                               TextAlignment="Center"
                                               TextWrapping="Wrap"
                                               Margin="16,0"/>
                                </Grid>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="TxtAddKillApp" Grid.Column="0" Margin="0,0,8,0" AutomationProperties.Name="Process Name to Stop"/>
                                    <Button x:Name="BtnAddKillApp" Grid.Column="1" Style="{StaticResource SecondaryButton}" Content="Add" Margin="0,0,8,0" AutomationProperties.Name="Add Process to Stop List"/>
                                    <Button x:Name="BtnRemoveKillApp" Grid.Column="2" Style="{StaticResource SecondaryButton}" Content="Remove Selected" IsEnabled="False" AutomationProperties.Name="Remove Selected Process from Stop List"/>
                                </Grid>
                            </StackPanel>
                        </TabItem>

                        <!-- Normal Profile Tab -->
                        <TabItem Header="Normal Profile">
                            <StackPanel>
                                <Grid Margin="0,0,0,12">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="155"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="52"/>
                                    </Grid.ColumnDefinitions>
                                    <Label Grid.Column="0" Content="Max CPU State" Target="{Binding ElementName=SliderNormalCpu}" Foreground="{DynamicResource TextPrimary}" VerticalAlignment="Center" Padding="0"/>
                                    <Slider x:Name="SliderNormalCpu" Grid.Column="1" Minimum="5" Maximum="100" TickFrequency="5" IsSnapToTickEnabled="True" VerticalAlignment="Center" AutomationProperties.Name="Normal Mode Max CPU State Percentage"/>
                                    <TextBlock x:Name="TxtNormalCpuVal" Grid.Column="2" Text="100%" FontFamily="Consolas" FontWeight="SemiBold" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="{DynamicResource TextPrimary}"/>
                                </Grid>

                                <Grid Margin="0,0,0,12">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="155"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="52"/>
                                    </Grid.ColumnDefinitions>
                                    <Label Grid.Column="0" Content="Display Brightness" Target="{Binding ElementName=SliderNormalBright}" Foreground="{DynamicResource TextPrimary}" VerticalAlignment="Center" Padding="0"/>
                                    <Slider x:Name="SliderNormalBright" Grid.Column="1" Minimum="0" Maximum="100" TickFrequency="5" IsSnapToTickEnabled="True" VerticalAlignment="Center" AutomationProperties.Name="Normal Mode Display Brightness Percentage"/>
                                    <TextBlock x:Name="TxtNormalBrightVal" Grid.Column="2" Text="70%" FontFamily="Consolas" FontWeight="SemiBold" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="{DynamicResource TextPrimary}"/>
                                </Grid>

                                <Grid Margin="0,0,0,12">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="155"/>
                                        <ColumnDefinition Width="140"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Label Grid.Column="0" Content="Refresh Rate (Hz)" Target="{Binding ElementName=CboNormalRefresh}" Foreground="{DynamicResource TextPrimary}" VerticalAlignment="Center" Padding="0"/>
                                    <ComboBox x:Name="CboNormalRefresh" Grid.Column="1" AutomationProperties.Name="Normal Mode Refresh Rate"/>
                                </Grid>

                                <TextBlock Text="Normal mode applies Windows Balanced Power Mode and keeps all currently open applications running."
                                           FontSize="12"
                                           Foreground="{DynamicResource TextMuted}"
                                           TextWrapping="Wrap"/>
                            </StackPanel>
                        </TabItem>

                        <!-- Gaming Profile Tab -->
                        <TabItem Header="Gaming Profile">
                            <StackPanel>
                                <Grid Margin="0,0,0,12">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="155"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="52"/>
                                    </Grid.ColumnDefinitions>
                                    <Label Grid.Column="0" Content="Max CPU State" Target="{Binding ElementName=SliderGameCpu}" Foreground="{DynamicResource TextPrimary}" VerticalAlignment="Center" Padding="0"/>
                                    <Slider x:Name="SliderGameCpu" Grid.Column="1" Minimum="5" Maximum="100" TickFrequency="5" IsSnapToTickEnabled="True" VerticalAlignment="Center" AutomationProperties.Name="Gaming Mode Max CPU State Percentage"/>
                                    <TextBlock x:Name="TxtGameCpuVal" Grid.Column="2" Text="100%" FontFamily="Consolas" FontWeight="SemiBold" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="{DynamicResource TextPrimary}"/>
                                </Grid>

                                <Grid Margin="0,0,0,12">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="155"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="52"/>
                                    </Grid.ColumnDefinitions>
                                    <Label Grid.Column="0" Content="Display Brightness" Target="{Binding ElementName=SliderGameBright}" Foreground="{DynamicResource TextPrimary}" VerticalAlignment="Center" Padding="0"/>
                                    <Slider x:Name="SliderGameBright" Grid.Column="1" Minimum="0" Maximum="100" TickFrequency="5" IsSnapToTickEnabled="True" VerticalAlignment="Center" AutomationProperties.Name="Gaming Mode Display Brightness Percentage"/>
                                    <TextBlock x:Name="TxtGameBrightVal" Grid.Column="2" Text="100%" FontFamily="Consolas" FontWeight="SemiBold" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="{DynamicResource TextPrimary}"/>
                                </Grid>

                                <Grid Margin="0,0,0,14">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="155"/>
                                        <ColumnDefinition Width="140"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Label Grid.Column="0" Content="Refresh Rate (Hz)" Target="{Binding ElementName=CboGameRefresh}" Foreground="{DynamicResource TextPrimary}" VerticalAlignment="Center" Padding="0"/>
                                    <ComboBox x:Name="CboGameRefresh" Grid.Column="1" AutomationProperties.Name="Gaming Mode Refresh Rate"/>
                                </Grid>

                                <Label Content="Gaming Apps to Launch" Target="{Binding ElementName=TxtAddLaunchApp}" Foreground="{DynamicResource TextPrimary}" FontWeight="SemiBold" Padding="0" Margin="0,0,0,6"/>
                                <Grid MinHeight="88" Margin="0,0,0,8">
                                    <ListBox x:Name="LstAppsToLaunch" Height="96" AutomationProperties.Name="Gaming Apps to Launch List"/>
                                    <TextBlock x:Name="TxtEmptyLaunchList"
                                               Text="No gaming apps configured to launch. Enter an executable path below or click Browse."
                                               Visibility="Collapsed"
                                               IsHitTestVisible="False"
                                               Foreground="{DynamicResource TextMuted}"
                                               VerticalAlignment="Center"
                                               HorizontalAlignment="Center"
                                               TextAlignment="Center"
                                               TextWrapping="Wrap"
                                               Margin="16,0"/>
                                </Grid>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="TxtAddLaunchApp" Grid.Column="0" Margin="0,0,8,0" AutomationProperties.Name="Executable Path to Launch"/>
                                    <Button x:Name="BtnBrowseLaunchApp" Grid.Column="1" Style="{StaticResource SecondaryButton}" Content="Browse..." Margin="0,0,8,0" AutomationProperties.Name="Browse for Gaming Executable"/>
                                    <Button x:Name="BtnAddLaunchApp" Grid.Column="2" Style="{StaticResource SecondaryButton}" Content="Add" Margin="0,0,8,0" AutomationProperties.Name="Add Executable to Launch List"/>
                                    <Button x:Name="BtnRemoveLaunchApp" Grid.Column="3" Style="{StaticResource SecondaryButton}" Content="Remove Selected" IsEnabled="False" AutomationProperties.Name="Remove Selected Executable from Launch List"/>
                                </Grid>
                            </StackPanel>
                        </TabItem>
                    </TabControl>
                </StackPanel>
            </Border>
        </StackPanel>
    </ScrollViewer>
</Window>
'@
}
