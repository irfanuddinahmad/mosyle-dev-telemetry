# Cross-Platform Adaptation Strategy

This document outlines how to adapt the `devlake-telemetry-collector.sh` (currently optimized for macOS) for Linux and Windows environments.

## 1. Linux Adaptation

The Linux version can reuse ~90% of the existing Bash script. The main differences are in **scheduling**, **app detection**, and **log sources**.

### Required Changes

| Component | macOS Implementation | Linux Implementation | Complexity |
|-----------|----------------------|----------------------|------------|
| **Scheduling** | `launchd` (.plist) | `systemd` timer or `cron` | Low |
| **App Detection** | `mdls`, `/Applications` | `dpkg`, `rpm`, `flatpak list`, `snap list` | Medium |
| **Process Check** | `pgrep` | `pgrep` (Identical) | N/A |
| **History Logs** | `zsh`/`bash` history + `log show` | `zsh`/`bash` history + `auditd` (optional) | Low |
| **User Home** | `dscl` | `getent passwd` | Low |
| **Open Files** | `lsof` | `lsof` or `/proc/net/tcp` | Low |
| **GUI Dialogs** | AppleScript (`osascript`) | `zenity` or `kdialog` (if needed) | Medium |

### Implementation Strategy
1.  **Unified Script**: Wrap OS-specific logic in functions.
    ```bash
    get_installed_apps() {
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS logic
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            # Linux logic (check apt, dnf, snap, flatpak)
        fi
    }
    ```
2.  **Systemd Service**: Create a user-level systemd service (`~/.config/systemd/user/devlake-telemetry.service`) and timer.
3.  **Dependencies**: Ensure `lsof`, `jq`, `curl`, `git` are installed via package manager.

## 2. Windows Adaptation

Windows requires a complete rewrite in **PowerShell**. Bash via WSL is **not recommended** because it cannot easily track host OS processes (e.g., a browser or IDE running in Windows).

### Architecture Map

| Component | macOS (Bash) | Windows (PowerShell) |
|-----------|--------------|-----------------------|
| **Scripting** | Bash | PowerShell Core (`pwsh`) |
| **Scheduling** | `launchd` | **Task Scheduler** |
| **History** | `.zsh_history` | `(Get-History).CommandLine` or `ConsoleHost_history.txt` |
| **Process Check** | `grep` / `ps aux` | `Get-Process` |
| **File Search** | `find` | `Get-ChildItem -Recurse` |
| **Network** | `lsof` | `Get-NetTCPConnection` |
| **JSON** | `jq` | `ConvertTo-Json` / `ConvertFrom-Json` (Native) |
| **Web Request** | `curl` | `Invoke-RestMethod` |
| **Paths** | `/Users/username` | `$env:USERPROFILE` |

### PowerShell Implementation Plan
1.  **Script**: `DevLake-Telemetry-Collector.ps1`
2.  **Config**: Store in `$env:APPDATA\DevLake-Telemetry\config.json`
3.  **Collection Logic**:
    - **Commands**: Parse `C:\Users\User\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt`.
    - **Git**: `git log` works identically.
    - **API**: `Get-NetTCPConnection -State Established -RemotePort 443`.
4.  **Installer**: A `.bat` file to register the Scheduled Task.

## 3. Recommended Roadmap

1.  **Phase 1: Linux Support**
    - Modify `devlake-telemetry-collector.sh` to handle Linux paths and commands.
    - Create `install_linux.sh` to set up systemd timers.
    
2.  **Phase 2: Windows Support**
    - Develop `DevLake-Telemetry-Collector.ps1` as a standalone script.
    - Ensure feature parity (Git scanning, API monitoring, JSON payload structure).

3.  **Phase 3: Unified Release**
    - Package all scripts in a single repo.
    - Update `README.md` with OS-specific installation instructions.
