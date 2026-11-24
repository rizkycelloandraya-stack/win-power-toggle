$projectRoot = Split-Path -Parent $PSScriptRoot
$switchModePath = Join-Path $projectRoot 'src\Switch-Mode.ps1'
$defaultConfigPath = Join-Path $projectRoot 'config.json'

if (Test-Path -LiteralPath $switchModePath) {
    . $switchModePath
}

Describe 'Switch-Mode' {
    Context 'Script availability' {
        It 'exists at src\Switch-Mode.ps1' {
            Test-Path -LiteralPath $switchModePath | Should Be $true
        }
    }

    Context 'Get-PowerToggleConfig' {
        It 'parses the default repository config.json with all expected fields' {
            $cfg = Get-PowerToggleConfig -Path $defaultConfigPath
            $cfg.batteryMode.brightness | Should Be 30
            $cfg.batteryMode.refreshRate | Should Be 60
            $cfg.batteryMode.maxCpuState | Should Be 50
            $cfg.batteryMode.appsToKill.Count | Should Be 4
            $cfg.gamingMode.brightness | Should Be 100
            $cfg.gamingMode.refreshRate | Should Be 144
            $cfg.gamingMode.maxCpuState | Should Be 100
            $cfg.gamingMode.appsToLaunch.Count | Should Be 1
        }

        It 'throws a descriptive error when config file does not exist' {
            { Get-PowerToggleConfig -Path (Join-Path $TestDrive 'nonexistent.json') } | Should Throw 'Configuration file not found'
        }

        It 'throws a descriptive error when config file contains malformed JSON' {
            $badPath = Join-Path $TestDrive 'bad.json'
            Set-Content -LiteralPath $badPath -Value '{ "batteryMode": ' -Encoding UTF8
            { Get-PowerToggleConfig -Path $badPath } | Should Throw 'Invalid JSON'
        }

        It 'throws when batteryMode or gamingMode section is missing' {
            $incompletePath = Join-Path $TestDrive 'incomplete.json'
            Set-Content -LiteralPath $incompletePath -Value '{ "batteryMode": { "brightness": 30 } }' -Encoding UTF8
            { Get-PowerToggleConfig -Path $incompletePath } | Should Throw 'gamingMode'
        }

        It 'throws when brightness or maxCpuState is outside 0..100' {
            $outOfRangePath = Join-Path $TestDrive 'range.json'
            $badJson = '{"batteryMode":{"brightness":150,"refreshRate":60,"maxCpuState":50},"gamingMode":{"brightness":100,"refreshRate":144,"maxCpuState":100}}'
            Set-Content -LiteralPath $outOfRangePath -Value $badJson -Encoding UTF8
            { Get-PowerToggleConfig -Path $outOfRangePath } | Should Throw 'brightness'
        }
    }

    Context 'CPU Power Capping (PROCTHROTTLEMAX)' {
        It 'parses AC and DC percentages from powercfg query output' {
            Mock Invoke-PowerCfg {
                return [PSCustomObject]@{
                    ExitCode = 0
                    Output   = @"
Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)
  Subgroup GUID: 54533251-82be-4824-96c1-47b60b740d00  (Processor power management)
    Power Setting GUID: bc5038f7-23e0-4960-96da-33abaf5935ec  (Maximum processor state)
    Current AC Power Setting Index: 0x00000064
    Current DC Power Setting Index: 0x00000032
"@
                }
            }

            $cpu = Get-CpuMaxState
            $cpu.AcPercent | Should Be 100
            $cpu.DcPercent | Should Be 50
        }

        It 'sets both AC and DC PROCTHROTTLEMAX under SCHEME_CURRENT and activates it' {
            $script:capturedPowerCfgCalls = New-Object System.Collections.ArrayList
            Mock Invoke-PowerCfg {
                [void]$script:capturedPowerCfgCalls.Add(($Arguments -join ' '))
                return [PSCustomObject]@{ ExitCode = 0; Output = '' }
            }

            $res = Set-CpuMaxState -Percent 50

            $res.Status | Should Be 'Changed'
            $res.Percent | Should Be 50
            $script:capturedPowerCfgCalls.Count | Should Be 3
            $script:capturedPowerCfgCalls[0] | Should Be '/setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 50'
            $script:capturedPowerCfgCalls[1] | Should Be '/setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 50'
            $script:capturedPowerCfgCalls[2] | Should Be '/setactive SCHEME_CURRENT'
        }

        It 'skips gracefully when powercfg returns a non-zero exit code' {
            Mock Invoke-PowerCfg {
                return [PSCustomObject]@{ ExitCode = 5; Output = 'Access is denied.' }
            }

            $res = Set-CpuMaxState -Percent 50

            $res.Status | Should Be 'Skipped'
            $res.Message | Should Match 'powercfg'
        }
    }

    Context 'Windows 11 Power Mode Overlay' {
        It 'maps official Windows Power Mode overlay GUIDs to friendly names' {
            Get-PowerOverlayFriendlyName -Guid '961cc777-2547-4f9d-8174-7d86181b8a7a' | Should Be 'Best Power Efficiency'
            Get-PowerOverlayFriendlyName -Guid '00000000-0000-0000-0000-000000000000' | Should Be 'Balanced'
            Get-PowerOverlayFriendlyName -Guid '3af9b8d9-7c97-431d-ad78-34a8bfea439f' | Should Be 'Better Performance'
            Get-PowerOverlayFriendlyName -Guid 'ded574b5-45a0-4f42-8737-46345c09c238' | Should Be 'Best Performance'
        }

        It 'sets Best Power Efficiency overlay GUID for battery mode' {
            Mock Invoke-GetPowerOverlayNative {
                return [PSCustomObject]@{ ReturnCode = 0; Guid = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Invoke-SetPowerOverlayNative { return 0 }

            $res = Set-PowerModeOverlay -Overlay 'BestPowerEfficiency'

            $res.Status | Should Be 'Changed'
            $res.Overlay | Should Be 'Best Power Efficiency'
            Assert-MockCalled Invoke-SetPowerOverlayNative -Scope It -Times 1 -Exactly -ParameterFilter {
                $Guid -eq '961cc777-2547-4f9d-8174-7d86181b8a7a'
            }
        }

        It 'sets Best Performance overlay GUID for gaming mode' {
            Mock Invoke-GetPowerOverlayNative {
                return [PSCustomObject]@{ ReturnCode = 0; Guid = '961cc777-2547-4f9d-8174-7d86181b8a7a' }
            }
            Mock Invoke-SetPowerOverlayNative { return 0 }

            $res = Set-PowerModeOverlay -Overlay 'BestPerformance'

            $res.Status | Should Be 'Changed'
            $res.Overlay | Should Be 'Best Performance'
            Assert-MockCalled Invoke-SetPowerOverlayNative -Scope It -Times 1 -Exactly -ParameterFilter {
                $Guid -eq 'ded574b5-45a0-4f42-8737-46345c09c238'
            }
        }

        It 'returns Unchanged when overlay is already active' {
            Mock Invoke-GetPowerOverlayNative {
                return [PSCustomObject]@{ ReturnCode = 0; Guid = 'ded574b5-45a0-4f42-8737-46345c09c238' }
            }
            Mock Invoke-SetPowerOverlayNative { return 0 }

            $res = Set-PowerModeOverlay -Overlay 'BestPerformance'

            $res.Status | Should Be 'Unchanged'
            Assert-MockCalled Invoke-SetPowerOverlayNative -Scope It -Times 0 -Exactly
        }

        It 'skips gracefully when PowerSetActiveOverlayScheme returns non-zero' {
            Mock Invoke-GetPowerOverlayNative {
                return [PSCustomObject]@{ ReturnCode = 0; Guid = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Invoke-SetPowerOverlayNative { return 87 }

            $res = Set-PowerModeOverlay -Overlay 'BestPerformance'

            $res.Status | Should Be 'Skipped'
            $res.Message | Should Match '87'
        }
    }

    Context 'WMI Display Brightness' {
        It 'sets brightness via WmiSetBrightness when internal display supports WMI' {
            $fakeMonitor = [PSCustomObject]@{ InstanceName = 'DISPLAY\MOCK0001\0' }
            Mock Get-BrightnessMethodsCimInstance { return @($fakeMonitor) }
            Mock Invoke-SetBrightnessCimMethod { return $null }

            $res = Set-DisplayBrightness -Percent 30

            $res.Status | Should Be 'Changed'
            $res.Percent | Should Be 30
            Assert-MockCalled Invoke-SetBrightnessCimMethod -Scope It -Times 1 -Exactly -ParameterFilter { $Percent -eq 30 }
        }

        It 'skips gracefully when no WMI brightness monitor is available (external display)' {
            Mock Get-BrightnessMethodsCimInstance { throw 'Not supported' }
            Mock Invoke-SetBrightnessCimMethod { return $null }

            $res = Set-DisplayBrightness -Percent 30

            $res.Status | Should Be 'Skipped'
            $res.Message | Should Match 'brightness'
            Assert-MockCalled Invoke-SetBrightnessCimMethod -Scope It -Times 0 -Exactly
        }
    }

    Context 'Process Management' {
        It 'terminates running apps, normalizes .exe suffix, and skips non-running apps' {
            Mock Get-RunningProcessByName {
                if ($Name -eq 'Discord') {
                    return @(
                        [PSCustomObject]@{ Id = 101; ProcessName = 'Discord' },
                        [PSCustomObject]@{ Id = 102; ProcessName = 'Discord' }
                    )
                }
                return @()
            }
            Mock Invoke-StopProcessById { return $null }

            $res = Stop-ConfiguredApps -AppNames @('Discord.exe', 'Steam')

            $res.Status | Should Be 'Changed'
            ($res.Stopped -contains 'Discord') | Should Be $true
            ($res.NotRunning -contains 'Steam') | Should Be $true
            Assert-MockCalled Invoke-StopProcessById -Scope It -Times 2 -Exactly
        }

        It 'continues terminating remaining apps when one process throws access denied' {
            Mock Get-RunningProcessByName {
                if ($Name -eq 'ProtectedApp') {
                    return @([PSCustomObject]@{ Id = 201; ProcessName = 'ProtectedApp' })
                }
                if ($Name -eq 'Steam') {
                    return @([PSCustomObject]@{ Id = 202; ProcessName = 'Steam' })
                }
                return @()
            }
            Mock Invoke-StopProcessById {
                if ($Id -eq 201) { throw 'Access is denied' }
            }

            $res = Stop-ConfiguredApps -AppNames @('ProtectedApp', 'Steam')

            ($res.Stopped -contains 'Steam') | Should Be $true
            $res.Failed.Count | Should Be 1
        }

        It 'launches existing gaming apps, skips already-running apps, and skips missing paths' {
            $fakeApp1 = Join-Path $TestDrive 'FakeLauncher.exe'
            $fakeApp2 = Join-Path $TestDrive 'AlreadyOpen.exe'
            $missingApp = Join-Path $TestDrive 'MissingGame.exe'
            Set-Content -LiteralPath $fakeApp1 -Value ''
            Set-Content -LiteralPath $fakeApp2 -Value ''

            Mock Get-RunningProcessByName {
                if ($Name -eq 'AlreadyOpen') {
                    return @([PSCustomObject]@{ Id = 301; ProcessName = 'AlreadyOpen' })
                }
                return @()
            }
            Mock Invoke-StartProcessPath { return $null }

            $res = Start-ConfiguredApps -AppPaths @($fakeApp1, $fakeApp2, $missingApp)

            $res.Status | Should Be 'Changed'
            $res.Launched.Count | Should Be 1
            $res.AlreadyRunning.Count | Should Be 1
            $res.Missing.Count | Should Be 1
            Assert-MockCalled Invoke-StartProcessPath -Scope It -Times 1 -Exactly -ParameterFilter { $FilePath -eq $fakeApp1 }
        }
    }

    Context 'Status Inspection (-Status)' {
        It 'aggregates power source, battery percentage, scheme, overlay, CPU cap, brightness, and refresh rate' {
            Mock Get-BatteryCimInstance {
                return [PSCustomObject]@{ BatteryStatus = 2; EstimatedChargeRemaining = 83 }
            }
            Mock Get-ActivePowerScheme {
                return [PSCustomObject]@{ Guid = '381b4222-f694-41f0-9685-ff5bb260df2e'; Name = 'Balanced' }
            }
            Mock Get-PowerModeOverlay {
                return [PSCustomObject]@{ Guid = 'ded574b5-45a0-4f42-8737-46345c09c238'; Name = 'Best Performance'; Supported = $true }
            }
            Mock Get-CpuMaxState {
                return [PSCustomObject]@{ AcPercent = 100; DcPercent = 50 }
            }
            Mock Get-DisplayBrightness { return 70 }
            Mock Get-DisplayInfo {
                return [PSCustomObject]@{
                    Width                 = 1920
                    Height                = 1080
                    RefreshRate           = 144
                    SupportedRefreshRates = @(60, 144)
                }
            }

            $status = Get-SystemPowerStatus

            $status.PowerSource | Should Be 'AC (Plugged In)'
            $status.BatteryPercent | Should Be 83
            $status.PowerSchemeName | Should Be 'Balanced'
            $status.PowerModeOverlay | Should Be 'Best Performance'
            $status.CpuMaxStateAc | Should Be 100
            $status.CpuMaxStateDc | Should Be 50
            $status.ActiveCpuMaxState | Should Be 100
            $status.BrightnessPercent | Should Be 70
            $status.RefreshRateHz | Should Be 144
        }

        It 'handles desktop systems with no battery and external displays with no WMI brightness' {
            Mock Get-BatteryCimInstance { return $null }
            Mock Get-ActivePowerScheme {
                return [PSCustomObject]@{ Guid = '381b4222-f694-41f0-9685-ff5bb260df2e'; Name = 'Balanced' }
            }
            Mock Get-PowerModeOverlay {
                return [PSCustomObject]@{ Guid = '00000000-0000-0000-0000-000000000000'; Name = 'Balanced'; Supported = $true }
            }
            Mock Get-CpuMaxState {
                return [PSCustomObject]@{ AcPercent = 100; DcPercent = 100 }
            }
            Mock Get-DisplayBrightness { return $null }
            Mock Get-DisplayInfo {
                return [PSCustomObject]@{
                    Width                 = 2560
                    Height                = 1440
                    RefreshRate           = 60
                    SupportedRefreshRates = @(60)
                }
            }

            $status = Get-SystemPowerStatus

            $status.PowerSource | Should Match 'No Battery'
            $status.BatteryPercent | Should Be $null
            $status.BrightnessPercent | Should Be $null
        }
    }

    Context 'End-to-End Orchestration (Invoke-WinPowerToggle)' {
        It 'executes all battery mode steps and continues if brightness is skipped' {
            Mock Set-CpuMaxState { return [PSCustomObject]@{ Status = 'Changed'; Percent = 50; Message = 'CPU 50%' } }
            Mock Set-PowerModeOverlay { return [PSCustomObject]@{ Status = 'Changed'; Overlay = 'Best Power Efficiency'; Message = 'Overlay set' } }
            Mock Set-DisplayBrightness { return [PSCustomObject]@{ Status = 'Skipped'; Percent = $null; Message = 'External monitor' } }
            Mock Set-DisplayRefreshRate { return [PSCustomObject]@{ Status = 'Changed'; CurrentRate = 60; Message = '60Hz' } }
            Mock Stop-ConfiguredApps { return [PSCustomObject]@{ Status = 'Unchanged'; Stopped = @(); NotRunning = @('Discord'); Failed = @(); Message = 'None running' } }

            $result = Invoke-WinPowerToggle -Mode 'battery' -ConfigPath $defaultConfigPath -Quiet

            $result.Mode | Should Be 'battery'
            $result.Steps.Cpu.Status | Should Be 'Changed'
            $result.Steps.PowerMode.Status | Should Be 'Changed'
            $result.Steps.Brightness.Status | Should Be 'Skipped'
            $result.Steps.RefreshRate.Status | Should Be 'Changed'
            Assert-MockCalled Set-CpuMaxState -Scope It -Times 1 -Exactly -ParameterFilter { $Percent -eq 50 }
            Assert-MockCalled Set-PowerModeOverlay -Scope It -Times 1 -Exactly -ParameterFilter { $Overlay -eq 'BestPowerEfficiency' }
            Assert-MockCalled Set-DisplayBrightness -Scope It -Times 1 -Exactly -ParameterFilter { $Percent -eq 30 }
            Assert-MockCalled Set-DisplayRefreshRate -Scope It -Times 1 -Exactly -ParameterFilter { $RefreshRate -eq 60 -and $Fallback -eq 'Lowest' }
            Assert-MockCalled Stop-ConfiguredApps -Scope It -Times 1 -Exactly
        }

        It 'executes all gaming mode steps with Best Performance overlay and Highest refresh-rate fallback' {
            Mock Set-CpuMaxState { return [PSCustomObject]@{ Status = 'Changed'; Percent = 100; Message = 'CPU 100%' } }
            Mock Set-PowerModeOverlay { return [PSCustomObject]@{ Status = 'Changed'; Overlay = 'Best Performance'; Message = 'Overlay set' } }
            Mock Set-DisplayBrightness { return [PSCustomObject]@{ Status = 'Changed'; Percent = 100; Message = '100%' } }
            Mock Set-DisplayRefreshRate { return [PSCustomObject]@{ Status = 'Changed'; CurrentRate = 144; Message = '144Hz' } }
            Mock Start-ConfiguredApps { return [PSCustomObject]@{ Status = 'Changed'; Launched = @('steam.exe'); AlreadyRunning = @(); Missing = @(); Failed = @(); Message = 'Launched' } }

            $result = Invoke-WinPowerToggle -Mode 'gaming' -ConfigPath $defaultConfigPath -Quiet

            $result.Mode | Should Be 'gaming'
            Assert-MockCalled Set-CpuMaxState -Scope It -Times 1 -Exactly -ParameterFilter { $Percent -eq 100 }
            Assert-MockCalled Set-PowerModeOverlay -Scope It -Times 1 -Exactly -ParameterFilter { $Overlay -eq 'BestPerformance' }
            Assert-MockCalled Set-DisplayBrightness -Scope It -Times 1 -Exactly -ParameterFilter { $Percent -eq 100 }
            Assert-MockCalled Set-DisplayRefreshRate -Scope It -Times 1 -Exactly -ParameterFilter { $RefreshRate -eq 144 -and $Fallback -eq 'Highest' }
            Assert-MockCalled Start-ConfiguredApps -Scope It -Times 1 -Exactly
        }

        It 'throws when neither -Mode nor -Status is provided' {
            { Invoke-WinPowerToggle -Quiet } | Should Throw 'Specify either -Mode'
        }

        It 'throws when both -Mode and -Status are provided together' {
            { Invoke-WinPowerToggle -Mode 'battery' -Status -Quiet } | Should Throw 'mutually exclusive'
        }
    }

    Context 'Fresh CLI Invocation (powershell.exe -File)' {
        It 'runs -Status cleanly in a fresh PowerShell 5.1 process without requiring -ConfigPath' {
            $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $switchModePath -Status 2>&1
            $exitCode = $LASTEXITCODE
            $text = ($output | ForEach-Object { "$_" }) -join "`n"

            $exitCode | Should Be 0
            $text | Should Match 'Win-Power-Toggle System Status'
            $text | Should Match 'Power Scheme'
            $text | Should Match 'Windows Power Mode'
            $text | Should Match 'Max CPU State'
        }

        It 'exits non-zero with usage message when invoked with no parameters' {
            $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $switchModePath 2>&1
            $exitCode = $LASTEXITCODE
            $text = ($output | ForEach-Object { "$_" }) -join "`n"

            $exitCode | Should Not Be 0
            $text | Should Match 'Usage:'
        }
    }
}
