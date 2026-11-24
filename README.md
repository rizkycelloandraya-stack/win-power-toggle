# Win-Power-Toggle

A zero-dependency Windows PowerShell CLI and silent desktop shortcut utility for switching high-performance Windows 10/11 laptops between **Battery Saver** and **Gaming Performance** profiles in under 2 seconds.

Built entirely on native Windows APIs (`powercfg`, `powrprof.dll`, WMI, `user32.dll`, and Windows Script Host), with no third-party modules, installers, or background daemons.

## Features (v1.0)

- **Single-command profile switching (`-Mode battery` / `-Mode gaming`)** driven by a central `config.json`.
- **Modern Standby (S0) CPU & Power Mode control**: updates `PROCTHROTTLEMAX` directly on `SCHEME_CURRENT` (`Balanced`) for both AC and DC, and switches Windows 11's native Power Mode overlay (`Best Power Efficiency` for battery, `Best Performance` for gaming).
- **WMI internal display dimming**: sets laptop panel brightness via `WmiMonitorBrightnessMethods`, skipping cleanly if an external monitor does not support WMI brightness.
- **Native refresh-rate switching (`src/Display-Helper.ps1`)**: queries panel modes via `EnumDisplaySettingsW` and switches refresh rates (e.g., 60Hz for battery, 144Hz or panel max for gaming) via `ChangeDisplaySettingsExW`, with automatic fallback if a configured rate is not supported by the active monitor.
- **Background & gaming app management**: terminates configured launcher processes (`appsToKill`) in battery mode and launches configured gaming utilities (`appsToLaunch`) in gaming mode, skipping missing paths, already-running apps, or processes that are not running.
- **Real-time status inspection (`-Status`)**: displays power source (AC/DC), battery percentage, active power scheme, Windows Power Mode overlay, AC/DC `PROCTHROTTLEMAX`, brightness, and display refresh rate.
- **Desktop and System Tray App (`src/WinPowerToggle-App.ps1` + `src/Launch-App.vbs`)**: native zero-dependency WPF control window for one-click profile switching, live hardware telemetry, visual `config.json` profile editing (CPU cap, brightness, panel refresh rate, app lists with file browser), Light/Dark theme toggle, and a System Tray right-click menu.
- **Silent desktop shortcut wrapper (`src/Run-Hidden.vbs`)**: triggers direct CLI mode switches with zero console window flash.

## Directory Structure

```text
win-power-toggle/
├── src/
│   ├── Switch-Mode.ps1        # Core CLI for power, overlay, brightness, and processes
│   ├── Display-Helper.ps1     # Win32 Display API refresh-rate helper
│   ├── App-Logic.ps1          # Theme palette, config editor logic, and WPF XAML layout
│   ├── WinPowerToggle-App.ps1 # Native WPF desktop and system-tray GUI app
│   ├── Launch-App.vbs         # Silent GUI launcher (double-click, no console window)
│   └── Run-Hidden.vbs         # Silent CLI wrapper for one-click mode shortcuts
├── tests/
│   ├── Display-Helper.Tests.ps1
│   ├── Switch-Mode.Tests.ps1
│   ├── Run-Hidden.Tests.ps1
│   ├── App-Logic.Tests.ps1
│   └── Launch-App.Tests.ps1
├── config.json                # User-editable profile settings
├── LICENSE                    # MIT License
└── README.md
```

## Requirements

- Windows 10 or Windows 11 (x64)
- Windows PowerShell 5.1+ (built into Windows)
- Standard user permissions (no administrator elevation required for `SCHEME_CURRENT` CPU cap, Power Mode overlay, WMI brightness, or refresh rate changes)

## Configuration (`config.json`)

Edit `config.json` in the repository root to match your laptop's panel and installed apps:

```json
{
  "batteryMode": {
    "brightness": 30,
    "refreshRate": 60,
    "maxCpuState": 50,
    "forceBatterySaver": true,
    "appsToKill": [
      "Discord",
      "Steam",
      "EpicGamesLauncher",
      "RiotClientServices"
    ]
  },
  "gamingMode": {
    "brightness": 100,
    "refreshRate": 144,
    "maxCpuState": 100,
    "appsToLaunch": [
      "C:\\Program Files (x86)\\Steam\\steam.exe"
    ]
  }
}
```

### Configuration Notes

- `brightness`: integer `0` to `100` (set to `null` to leave brightness unchanged).
- `refreshRate`: positive integer in Hz (e.g., `60`, `144`), or `"max"` / `0` to select the current display's highest supported refresh rate, or `"min"` for the lowest. If a numeric rate is not supported by the active panel, battery mode falls back to the lowest supported rate and gaming mode falls back to the highest supported rate.
- `maxCpuState`: integer `0` to `100` applied to `PROCTHROTTLEMAX` on `SCHEME_CURRENT` (both AC and DC).
- `forceBatterySaver`: preserved in the schema for v1.1 compatibility.
- `appsToKill`: process names with or without `.exe` (case-insensitive). Non-running processes are skipped gracefully.
- `appsToLaunch`: executable paths (Windows environment variables like `%LOCALAPPDATA%` are expanded). Missing paths and already-running apps are skipped gracefully.

## Desktop & System Tray App

Launch the graphical control app without a console window by double-clicking `src\Launch-App.vbs`, or run from PowerShell:

```powershell
# Launch silently via Windows Script Host
wscript.exe .\src\Launch-App.vbs

# Launch directly via PowerShell
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .\src\WinPowerToggle-App.ps1

# Optional flags: -Theme Light | Dark | Auto, -StartMinimized, -ConfigPath "<path>"
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .\src\WinPowerToggle-App.ps1 -Theme Dark
```

Inside the app you can:
- Switch between **Battery Saver** and **Gaming Performance** in one click and view each step's result and timing.
- Inspect live power source, battery percentage, Windows Power Mode overlay, CPU cap, resolution, refresh rate, and brightness.
- Edit and save `config.json` profiles visually (CPU cap and brightness sliders, refresh-rate dropdown populated from your display's supported rates, and add/browse/remove lists for stopped and launched apps).
- Toggle between **Light** and **Dark** themes at any time.
- Click **Send to Tray** to keep quick-switch controls accessible from the Windows system tray right-click menu.

## CLI Usage

To run scripts without permanently altering Windows' system-wide PowerShell execution policy, pass `-ExecutionPolicy Bypass` per invocation:

```powershell
# Inspect current power, CPU cap, Power Mode overlay, brightness, and refresh rate
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Switch-Mode.ps1 -Status

# Switch to Battery Saver profile
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Switch-Mode.ps1 -Mode battery

# Switch to Gaming Performance profile
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Switch-Mode.ps1 -Mode gaming

# Use an alternate configuration file
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Switch-Mode.ps1 -Mode battery -ConfigPath "D:\custom-config.json"

# Return structured PowerShell objects instead of formatted text
.\src\Switch-Mode.ps1 -Status -PassThru
```

## One-Click Desktop Shortcuts (No Terminal Flash)

Use `src\Run-Hidden.vbs` so Windows launches `Switch-Mode.ps1` with `-ExecutionPolicy Bypass` and a hidden window (`0`):

1. Right-click your Desktop and select **New > Shortcut**.
2. Set the shortcut **Location** (replace `C:\path\to\win-power-toggle` with your actual folder path):
   - **Battery Mode shortcut**:
     ```text
     wscript.exe "C:\path\to\win-power-toggle\src\Run-Hidden.vbs" -Mode battery
     ```
     *(Shorthand also works: `wscript.exe "C:\path\to\win-power-toggle\src\Run-Hidden.vbs" battery`)*
   - **Gaming Mode shortcut**:
     ```text
     wscript.exe "C:\path\to\win-power-toggle\src\Run-Hidden.vbs" -Mode gaming
     ```
3. Give the shortcut a clear name (for example, `Battery Mode` or `Gaming Mode`) and click **Finish**.
4. *(Optional)* Right-click the shortcut > **Properties** to assign a custom **Shortcut key** (e.g., `Ctrl+Alt+B` / `Ctrl+Alt+G`) or **Change Icon** (`%SystemRoot%\System32\shell32.dll`).

## Modern Standby (S0) Behavior

Modern Windows 11 laptops with Modern Standby (`S0 Low Power Idle`) typically expose only the `Balanced` power plan (`381b4222-f694-41f0-9685-ff5bb260df2e`) and hide legacy `High Performance` and `Power Saver` schemes. `Switch-Mode.ps1` works cleanly on these systems by:

1. Modifying `SUB_PROCESSOR / PROCTHROTTLEMAX` directly under `SCHEME_CURRENT` (`powercfg /setacvalueindex`, `/setdcvalueindex`, and `/setactive`).
2. Calling `powrprof.dll` (`PowerSetActiveOverlayScheme`) to switch Windows 11's native Power Mode overlay:
   - Battery mode: **Best Power Efficiency** (`961cc777-2547-4f9d-8174-7d86181b8a7a`)
   - Gaming mode: **Best Performance** (`ded574b5-45a0-4f42-8737-46345c09c238`)

If an older Windows build or custom power plan rejects overlay changes, the step is skipped cleanly without interrupting the remaining actions.

## Running Tests

The repository includes automated Pester tests compatible with the Pester 3.4 module built into Windows PowerShell (no external installs required):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path .\tests -EnableExit"
```

## License

MIT License. See [LICENSE](LICENSE).
