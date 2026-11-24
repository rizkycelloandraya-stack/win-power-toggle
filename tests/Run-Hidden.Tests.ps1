$projectRoot = Split-Path -Parent $PSScriptRoot
$vbsPath = Join-Path $projectRoot 'src\Run-Hidden.vbs'

Describe 'Run-Hidden.vbs' {
    Context 'File availability' {
        It 'exists at src\Run-Hidden.vbs' {
            Test-Path -LiteralPath $vbsPath | Should Be $true
        }
    }

    Context 'Argument forwarding and path handling' {
        It 'exits non-zero when called with no arguments' {
            Test-Path -LiteralPath $vbsPath | Should Be $true
            & cscript.exe //Nologo $vbsPath 2>$null
            $LASTEXITCODE | Should Not Be 0
        }

        It 'translates shorthand mode argument (battery) and works from a path containing spaces' {
            Test-Path -LiteralPath $vbsPath | Should Be $true
            $sandbox = Join-Path $TestDrive 'Folder With Spaces'
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

            $marker = Join-Path $sandbox 'captured.txt'
            $stubScript = Join-Path $sandbox 'Switch-Mode.ps1'
            $copiedVbs = Join-Path $sandbox 'Run-Hidden.vbs'

            Copy-Item -LiteralPath $vbsPath -Destination $copiedVbs -Force
            Set-Content -LiteralPath $stubScript -Value "param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$AllArgs)`n(`$AllArgs -join '|') | Set-Content -LiteralPath '$marker' -Encoding UTF8" -Encoding UTF8

            & cscript.exe //Nologo $copiedVbs battery
            $LASTEXITCODE | Should Be 0

            $deadline = (Get-Date).AddSeconds(5)
            while (-not (Test-Path -LiteralPath $marker) -and (Get-Date) -lt $deadline) {
                Start-Sleep -Milliseconds 100
            }

            Test-Path -LiteralPath $marker | Should Be $true
            (Get-Content -LiteralPath $marker -Raw).Trim() | Should Be '-Mode|battery'
        }

        It 'forwards explicit flags including quoted paths with spaces' {
            Test-Path -LiteralPath $vbsPath | Should Be $true
            $sandbox = Join-Path $TestDrive 'Second Sandbox'
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

            $marker = Join-Path $sandbox 'captured-explicit.txt'
            $stubScript = Join-Path $sandbox 'Switch-Mode.ps1'
            $copiedVbs = Join-Path $sandbox 'Run-Hidden.vbs'

            Copy-Item -LiteralPath $vbsPath -Destination $copiedVbs -Force
            Set-Content -LiteralPath $stubScript -Value "param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$AllArgs)`n(`$AllArgs -join '|') | Set-Content -LiteralPath '$marker' -Encoding UTF8" -Encoding UTF8

            & cscript.exe //Nologo $copiedVbs -Mode gaming -ConfigPath 'C:\My Config\custom.json'
            $LASTEXITCODE | Should Be 0

            $deadline = (Get-Date).AddSeconds(5)
            while (-not (Test-Path -LiteralPath $marker) -and (Get-Date) -lt $deadline) {
                Start-Sleep -Milliseconds 100
            }

            Test-Path -LiteralPath $marker | Should Be $true
            (Get-Content -LiteralPath $marker -Raw).Trim() | Should Be '-Mode|gaming|-ConfigPath|C:\My Config\custom.json'
        }
    }
}
