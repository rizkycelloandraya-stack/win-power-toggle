$projectRoot = Split-Path -Parent $PSScriptRoot
$helperPath = Join-Path $projectRoot 'src\Display-Helper.ps1'

if (Test-Path -LiteralPath $helperPath) {
    . $helperPath
}

Describe 'Display-Helper' {
    Context 'Module availability' {
        It 'exists at src\Display-Helper.ps1' {
            Test-Path -LiteralPath $helperPath | Should Be $true
        }
    }

    Context 'Resolve-TargetRefreshRate' {
        It 'selects exact rate when supported' {
            $res = Resolve-TargetRefreshRate -RequestedRate 60 -SupportedRates @(60, 144)
            $res.TargetRate | Should Be 60
            $res.UsedFallback | Should Be $false
        }

        It 'selects maximum supported rate when requested rate is max' {
            $res = Resolve-TargetRefreshRate -RequestedRate 'max' -SupportedRates @(60, 120, 144)
            $res.TargetRate | Should Be 144
            $res.UsedFallback | Should Be $false
        }

        It 'selects maximum supported rate when requested rate is 0' {
            $res = Resolve-TargetRefreshRate -RequestedRate 0 -SupportedRates @(60, 144)
            $res.TargetRate | Should Be 144
            $res.UsedFallback | Should Be $false
        }

        It 'returns null TargetRate with clear reason when unsupported and Fallback is None' {
            $res = Resolve-TargetRefreshRate -RequestedRate 240 -SupportedRates @(60, 144) -Fallback 'None'
            $res.TargetRate | Should Be $null
            $res.Reason | Should Match '240Hz'
            $res.Reason | Should Match '60Hz, 144Hz'
        }

        It 'falls back to highest supported rate when unsupported and Fallback is Highest' {
            $res = Resolve-TargetRefreshRate -RequestedRate 144 -SupportedRates @(60, 120) -Fallback 'Highest'
            $res.TargetRate | Should Be 120
            $res.UsedFallback | Should Be $true
        }

        It 'falls back to lowest supported rate when unsupported and Fallback is Lowest' {
            $res = Resolve-TargetRefreshRate -RequestedRate 60 -SupportedRates @(48, 120) -Fallback 'Lowest'
            $res.TargetRate | Should Be 48
            $res.UsedFallback | Should Be $true
        }

        It 'returns null TargetRate when supported rates list is empty' {
            $res = Resolve-TargetRefreshRate -RequestedRate 60 -SupportedRates @() -Fallback 'Lowest'
            $res.TargetRate | Should Be $null
            $res.Reason | Should Match 'No supported refresh rates'
        }

        It 'rejects invalid non-numeric rate gracefully' {
            $res = Resolve-TargetRefreshRate -RequestedRate 'fast' -SupportedRates @(60, 144)
            $res.TargetRate | Should Be $null
            $res.Reason | Should Match 'Invalid'
        }
    }

    Context 'Set-DisplayRefreshRate' {
        It 'skips native API call and returns Unchanged when already at target rate' {
            Mock Get-DisplayInfo {
                [PSCustomObject]@{
                    DeviceName            = 'Primary'
                    Width                 = 1920
                    Height                = 1080
                    BitsPerPixel          = 32
                    RefreshRate           = 144
                    SupportedRefreshRates = @(60, 144)
                }
            }
            Mock Invoke-DisplayChangeNative { return 0 }

            $result = Set-DisplayRefreshRate -RefreshRate 144

            $result.Status | Should Be 'Unchanged'
            $result.CurrentRate | Should Be 144
            Assert-MockCalled Invoke-DisplayChangeNative -Scope It -Times 0 -Exactly
        }

        It 'invokes native display change and returns Changed on DISP_CHANGE_SUCCESSFUL (0)' {
            Mock Get-DisplayInfo {
                [PSCustomObject]@{
                    DeviceName            = 'Primary'
                    Width                 = 1920
                    Height                = 1080
                    BitsPerPixel          = 32
                    RefreshRate           = 144
                    SupportedRefreshRates = @(60, 144)
                }
            }
            Mock Invoke-DisplayChangeNative { return 0 }

            $result = Set-DisplayRefreshRate -RefreshRate 60

            $result.Status | Should Be 'Changed'
            $result.PreviousRate | Should Be 144
            $result.CurrentRate | Should Be 60
            Assert-MockCalled Invoke-DisplayChangeNative -Scope It -Times 1 -Exactly -ParameterFilter { $RefreshRate -eq 60 }
        }

        It 'skips gracefully when Get-DisplayInfo returns null' {
            Mock Get-DisplayInfo { return $null }
            Mock Invoke-DisplayChangeNative { return 0 }

            $result = Set-DisplayRefreshRate -RefreshRate 60

            $result.Status | Should Be 'Skipped'
            $result.Message | Should Match 'Unable to query'
            Assert-MockCalled Invoke-DisplayChangeNative -Scope It -Times 0 -Exactly
        }

        It 'skips gracefully when Win32 ChangeDisplaySettings returns DISP_CHANGE_BADMODE (-2)' {
            Mock Get-DisplayInfo {
                [PSCustomObject]@{
                    DeviceName            = 'Primary'
                    Width                 = 1920
                    Height                = 1080
                    BitsPerPixel          = 32
                    RefreshRate           = 144
                    SupportedRefreshRates = @(60, 144)
                }
            }
            Mock Invoke-DisplayChangeNative { return -2 }

            $result = Set-DisplayRefreshRate -RefreshRate 60

            $result.Status | Should Be 'Skipped'
            $result.Message | Should Match 'DISP_CHANGE_BADMODE'
        }

        It 'uses Fallback Highest to switch to 120Hz when 144Hz is configured on a 120Hz panel' {
            Mock Get-DisplayInfo {
                [PSCustomObject]@{
                    DeviceName            = 'Primary'
                    Width                 = 1920
                    Height                = 1080
                    BitsPerPixel          = 32
                    RefreshRate           = 60
                    SupportedRefreshRates = @(60, 120)
                }
            }
            Mock Invoke-DisplayChangeNative { return 0 }

            $result = Set-DisplayRefreshRate -RefreshRate 144 -Fallback 'Highest'

            $result.Status | Should Be 'Changed'
            $result.CurrentRate | Should Be 120
            Assert-MockCalled Invoke-DisplayChangeNative -Scope It -Times 1 -Exactly -ParameterFilter { $RefreshRate -eq 120 }
        }
    }

    Context 'Live read-only host query' {
        It 'returns current display resolution and non-empty supported refresh rates' {
            $info = Get-DisplayInfo
            $info | Should Not BeNullOrEmpty
            $info.Width | Should BeGreaterThan 0
            $info.Height | Should BeGreaterThan 0
            $info.RefreshRate | Should BeGreaterThan 0
            $info.SupportedRefreshRates.Count | Should BeGreaterThan 0
        }
    }
}
