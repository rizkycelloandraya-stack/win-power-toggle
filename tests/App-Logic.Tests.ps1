$projectRoot = Split-Path -Parent $PSScriptRoot
$appLogicPath = Join-Path $projectRoot 'src\App-Logic.ps1'
$switchModePath = Join-Path $projectRoot 'src\Switch-Mode.ps1'

if (Test-Path -LiteralPath $switchModePath) {
    . $switchModePath
}
if (Test-Path -LiteralPath $appLogicPath) {
    . $appLogicPath
}

Describe 'App-Logic' {
    Context 'Module availability' {
        It 'exists at src\App-Logic.ps1' {
            Test-Path -LiteralPath $appLogicPath | Should Be $true
        }
    }

    Context 'Get-AppThemePalette' {
        It 'returns complete Light theme brushes with verified hex colors' {
            $light = Get-AppThemePalette -Theme 'Light'
            $light.WindowBg | Should Be '#F5F4F0'
            $light.CardBg | Should Be '#FFFFFF'
            $light.TextPrimary | Should Be '#18181B'
            $light.TextMuted | Should Be '#52525B'
            $light.BatteryBtnBg | Should Be '#166534'
            $light.GamingBtnBg | Should Be '#B45309'
            $light.FocusRing | Should Be '#1D4ED8'
        }

        It 'returns complete Dark theme brushes with verified hex colors' {
            $dark = Get-AppThemePalette -Theme 'Dark'
            $dark.WindowBg | Should Be '#121316'
            $dark.CardBg | Should Be '#1B1D22'
            $dark.TextPrimary | Should Be '#F4F4F5'
            $dark.TextMuted | Should Be '#A8ACB8'
            $dark.BatteryBtnBg | Should Be '#4ADE80'
            $dark.GamingBtnBg | Should Be '#F59E0B'
            $dark.FocusRing | Should Be '#93C5FD'
        }
    }

    Context 'Get-DetectedProfileState' {
        It 'detects Battery Saver when overlay is Best Power Efficiency and CPU cap matches battery profile' {
            $status = [PSCustomObject]@{
                PowerModeOverlay  = 'Best Power Efficiency'
                ActiveCpuMaxState = 50
                RefreshRateHz     = 60
            }
            $cfg = [PSCustomObject]@{
                batteryMode = [PSCustomObject]@{ maxCpuState = 50; refreshRate = 60 }
                gamingMode  = [PSCustomObject]@{ maxCpuState = 100; refreshRate = 144 }
            }

            $detected = Get-DetectedProfileState -StatusObject $status -Config $cfg
            $detected.Label | Should Be 'Battery Saver'
        }

        It 'detects Gaming Performance when overlay is Best Performance and CPU cap matches gaming profile' {
            $status = [PSCustomObject]@{
                PowerModeOverlay  = 'Best Performance'
                ActiveCpuMaxState = 100
                RefreshRateHz     = 144
            }
            $cfg = [PSCustomObject]@{
                batteryMode = [PSCustomObject]@{ maxCpuState = 50; refreshRate = 60 }
                gamingMode  = [PSCustomObject]@{ maxCpuState = 100; refreshRate = 144 }
            }

            $detected = Get-DetectedProfileState -StatusObject $status -Config $cfg
            $detected.Label | Should Be 'Gaming Performance'
        }

        It 'detects Custom / Mixed when live state does not match either preset' {
            $status = [PSCustomObject]@{
                PowerModeOverlay  = 'Balanced'
                ActiveCpuMaxState = 100
                RefreshRateHz     = 144
            }
            $cfg = [PSCustomObject]@{
                batteryMode = [PSCustomObject]@{ maxCpuState = 50; refreshRate = 60 }
                gamingMode  = [PSCustomObject]@{ maxCpuState = 100; refreshRate = 144 }
            }

            $detected = Get-DetectedProfileState -StatusObject $status -Config $cfg
            $detected.Label | Should Be 'Custom'
        }
    }

    Context 'Format-ProfileCardSummary' {
        It 'formats concise battery mode summary without em dashes or buzzwords' {
            $profile = [PSCustomObject]@{
                maxCpuState = 50
                brightness  = 30
                refreshRate = 60
            }
            $text = Format-ProfileCardSummary -Profile $profile -Mode 'battery'
            $text | Should Match '50% CPU'
            $text | Should Match '30% brightness'
            $text | Should Match '60Hz'
            $text | Should Match 'Best Power Efficiency'
            ($text.Contains([char]0x2014)) | Should Be $false
        }

        It 'formats concise gaming mode summary with max keyword cleanly' {
            $profile = [PSCustomObject]@{
                maxCpuState = 100
                brightness  = 100
                refreshRate = 'max'
            }
            $text = Format-ProfileCardSummary -Profile $profile -Mode 'gaming'
            $text | Should Match '100% CPU'
            $text | Should Match '100% brightness'
            $text | Should Match 'Max Hz'
            $text | Should Match 'Best Performance'
        }
    }

    Context 'Get-RefreshRateChoices' {
        It 'combines panel supported rates with max, min, and configured custom rate without duplicates' {
            $choices = Get-RefreshRateChoices -SupportedRates @(60, 144) -ConfiguredRate 120
            ($choices -contains '60') | Should Be $true
            ($choices -contains '120') | Should Be $true
            ($choices -contains '144') | Should Be $true
            ($choices -contains 'max') | Should Be $true
            ($choices -contains 'min') | Should Be $true
            $choices.Count | Should Be 5
        }
    }

    Context 'App list editing helpers' {
        It 'adds a normalized process name and rejects duplicates' {
            $res1 = Add-AppListItem -Items @('Discord') -NewItem ' Steam.exe ' -NormalizeProcessName
            $res1.Added | Should Be $true
            $res1.Items.Count | Should Be 2
            ($res1.Items -contains 'Steam') | Should Be $true

            $res2 = Add-AppListItem -Items $res1.Items -NewItem 'steam' -NormalizeProcessName
            $res2.Added | Should Be $false
            $res2.Items.Count | Should Be 2
        }

        It 'rejects blank app entries gracefully' {
            $res = Add-AppListItem -Items @('Discord') -NewItem '   ' -NormalizeProcessName
            $res.Added | Should Be $false
            $res.Items.Count | Should Be 1
        }

        It 'removes the selected item cleanly' {
            $updated = Remove-AppListItem -Items @('Discord', 'Steam', 'EpicGamesLauncher') -ItemToRemove 'Steam'
            $updated.Count | Should Be 2
            ($updated -contains 'Steam') | Should Be $false
            ($updated -contains 'Discord') | Should Be $true
        }
    }

    Context 'Save-PowerToggleConfig' {
        It 'writes valid UTF-8 JSON without BOM that reloads cleanly via Get-PowerToggleConfig' {
            $target = Join-Path $TestDrive 'saved-config.json'
            $cfg = [PSCustomObject]@{
                batteryMode = [PSCustomObject]@{
                    brightness        = 25
                    refreshRate       = 60
                    maxCpuState       = 45
                    forceBatterySaver = $true
                    appsToKill        = @('Discord', 'Steam')
                }
                gamingMode = [PSCustomObject]@{
                    brightness   = 95
                    refreshRate  = 144
                    maxCpuState  = 100
                    appsToLaunch = @('C:\Games\Launcher.exe')
                }
            }

            $saveRes = Save-PowerToggleConfig -Config $cfg -Path $target
            $saveRes.Success | Should Be $true
            Test-Path -LiteralPath $target | Should Be $true

            $bytes = [System.IO.File]::ReadAllBytes($target)
            # Confirm no UTF-8 BOM (EF BB BF)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should Be $false

            $reloaded = Get-PowerToggleConfig -Path $target
            $reloaded.batteryMode.brightness | Should Be 25
            $reloaded.batteryMode.maxCpuState | Should Be 45
            $reloaded.gamingMode.brightness | Should Be 95
            $reloaded.gamingMode.appsToLaunch.Count | Should Be 1
        }

        It 'rejects invalid out-of-range values and does not overwrite the file' {
            $target = Join-Path $TestDrive 'protected-config.json'
            Set-Content -LiteralPath $target -Value '{"original":true}' -Encoding UTF8

            $badCfg = [PSCustomObject]@{
                batteryMode = [PSCustomObject]@{
                    brightness  = 150
                    refreshRate = 60
                    maxCpuState = 50
                    appsToKill  = @()
                }
                gamingMode = [PSCustomObject]@{
                    brightness   = 100
                    refreshRate  = 144
                    maxCpuState  = 100
                    appsToLaunch = @()
                }
            }

            { Save-PowerToggleConfig -Config $badCfg -Path $target } | Should Throw 'brightness'
            (Get-Content -LiteralPath $target -Raw) | Should Match 'original'
        }
    }

    Context 'Get-AppWindowXaml' {
        It 'returns valid WPF XAML that parses cleanly with all named controls and no em dashes' {
            Add-Type -AssemblyName PresentationFramework
            $xaml = Get-AppWindowXaml
            $xaml | Should Not BeNullOrEmpty
            ($xaml.Contains([char]0x2014)) | Should Be $false

            $window = [Windows.Markup.XamlReader]::Parse($xaml)
            $window | Should Not BeNullOrEmpty
            $window.FindName('BtnBatteryMode') | Should Not BeNullOrEmpty
            $window.FindName('BtnGamingMode') | Should Not BeNullOrEmpty
            $window.FindName('BtnRefreshStatus') | Should Not BeNullOrEmpty
            $window.FindName('BtnThemeToggle') | Should Not BeNullOrEmpty
            $window.FindName('BtnMinimizeTray') | Should Not BeNullOrEmpty
            $window.FindName('BtnSaveConfig') | Should Not BeNullOrEmpty
            $window.FindName('BtnReloadConfig') | Should Not BeNullOrEmpty
            $window.FindName('TabProfiles') | Should Not BeNullOrEmpty
            $window.FindName('BannerError') | Should Not BeNullOrEmpty
            $window.FindName('BannerLoading') | Should Not BeNullOrEmpty
        }

        It 'applies Dark and Light themes cleanly via Set-WindowThemePalette without PSObject brush wrapping' {
            Add-Type -AssemblyName PresentationFramework
            $window = [Windows.Markup.XamlReader]::Parse((Get-AppWindowXaml))

            Set-WindowThemePalette -Window $window -Theme 'Dark'
            ($window.Resources['WindowBg'] -is [System.Windows.Media.SolidColorBrush]) | Should Be $true
            $window.Resources['WindowBg'].Color.ToString() | Should Be '#FF121316'
            $window.Resources['TextPrimary'].Color.ToString() | Should Be '#FFF4F4F5'

            Set-WindowThemePalette -Window $window -Theme 'Light'
            ($window.Resources['WindowBg'] -is [System.Windows.Media.SolidColorBrush]) | Should Be $true
            $window.Resources['WindowBg'].Color.ToString() | Should Be '#FFF5F4F0'
            $window.Resources['TextPrimary'].Color.ToString() | Should Be '#FF18181B'
        }
    }
}
