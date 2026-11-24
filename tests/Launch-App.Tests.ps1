$projectRoot = Split-Path -Parent $PSScriptRoot
$launcherPath = Join-Path $projectRoot 'src\Launch-App.vbs'

Describe 'Launch-App.vbs' {
    Context 'File availability' {
        It 'exists at src\Launch-App.vbs' {
            Test-Path -LiteralPath $launcherPath | Should Be $true
        }
    }

    Context 'Silent launch and argument forwarding' {
        It 'launches sibling WinPowerToggle-App.ps1 with -STA from a folder containing spaces' {
            Test-Path -LiteralPath $launcherPath | Should Be $true
            $sandbox = Join-Path $TestDrive 'App Launch Folder'
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

            $marker = Join-Path $sandbox 'launched.txt'
            $stubApp = Join-Path $sandbox 'WinPowerToggle-App.ps1'
            $copiedVbs = Join-Path $sandbox 'Launch-App.vbs'

            Copy-Item -LiteralPath $launcherPath -Destination $copiedVbs -Force
            Set-Content -LiteralPath $stubApp -Value "param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$AllArgs)`n`$apt = [System.Threading.Thread]::CurrentThread.ApartmentState.ToString()`n(`"`$apt|`" + (`$AllArgs -join '|')) | Set-Content -LiteralPath '$marker' -Encoding UTF8" -Encoding UTF8

            & cscript.exe //Nologo $copiedVbs -Theme Dark -ConfigPath 'C:\My Dir\config.json'
            $LASTEXITCODE | Should Be 0

            $deadline = (Get-Date).AddSeconds(5)
            while (-not (Test-Path -LiteralPath $marker) -and (Get-Date) -lt $deadline) {
                Start-Sleep -Milliseconds 100
            }

            Test-Path -LiteralPath $marker | Should Be $true
            (Get-Content -LiteralPath $marker -Raw).Trim() | Should Be 'STA|-Theme|Dark|-ConfigPath|C:\My Dir\config.json'
        }
    }
}
