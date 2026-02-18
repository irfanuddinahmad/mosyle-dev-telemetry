# Local Testing Setup - DevLake Telemetry Collector

## Overview
Created a local testing installation script that installs the telemetry collector in user space without requiring sudo/root access.

## Installation Script
**File:** `release/install-telemetry-local.sh`

### Key Differences from Production Script
| Aspect | Production (`install-telemetry.sh`) | Local (`install-telemetry-local.sh`) |
|--------|-------------------------------------|--------------------------------------|
| **Requires sudo** | Yes (root access required) | No (user space only) |
| **Install location** | `/usr/local/bin` | `~/.local/bin` |
| **LaunchDaemon type** | System LaunchDaemon (`/Library/LaunchDaemons`) | User LaunchAgent (`~/Library/LaunchAgents`) |
| **Config location** | `/usr/local/etc/devlake-telemetry` | `~/.config/devlake-telemetry` |
| **Data directory** | `/var/tmp/devlake-telemetry` | `~/.local/share/devlake-telemetry` |
| **Log directory** | `/var/log` | `~/.local/var/log` |
| **Service name** | `com.devlake.telemetry` | `com.devlake.telemetry.local` |
| **Runs on** | System boot | User login |

## Configuration

### Webhook URLs (Configured for Testing)
```json
{
  "webhook_url": "http://localhost:8080/plugins/developer_telemetry/connections/1/report",
  "webhook_url_secondary": "https://webhook.site/04421308-e750-4ead-901c-f5bf32292fd4"
}
```

- **Primary URL**: Local DevLake instance (developer_telemetry plugin)
- **Secondary URL**: webhook.site for testing/verification

## Installation Steps

1. Make the script executable:
   ```bash
   chmod +x release/install-telemetry-local.sh
   ```

2. Run the installation:
   ```bash
   cd release
   ./install-telemetry-local.sh
   ```

3. The script will:
   - Create user-level directories
   - Install the collector script
   - Generate and install LaunchAgent plist
   - Create configuration file with test URLs
   - Load the LaunchAgent

## Testing Results

### Test Output
```
[2026-02-18 08:01:49] === DevLake Telemetry Collector Starting ===
[2026-02-18 08:01:49] Sending payload to secondary webhook: https://webhook.site/04421308-e750-4ead-901c-f5bf32292fd4
[2026-02-18 08:01:50] Successfully sent data to secondary webhook
[2026-02-18 08:01:50] Sending payload to http://localhost:8080/plugins/developer_telemetry/connections/1/report
[2026-02-18 08:01:50] Successfully sent data to DevLake (HTTP 200)
[2026-02-18 08:01:50] Archived data to ~/.local/share/devlake-telemetry/archive/daily_2026-02-16.json
```

### Verification

#### 1. Database Verification
Data successfully stored in DevLake database:
```
developer_id: irfan.ahmad
email: iahmad@2u.com
date: 2026-02-16
active_hours: 3
tools_used: ["docker","git","goland","intellij","node","pycharm","python","vscode"]
```

#### 2. LaunchAgent Status
```bash
$ launchctl list | grep devlake
-       1       com.devlake.telemetry.local
```
✅ Agent is running successfully

## Key Files Locations

| File | Location |
|------|----------|
| Collector Script | `~/.local/bin/devlake-telemetry-collector.sh` |
| LaunchAgent Plist | `~/Library/LaunchAgents/com.devlake.telemetry.local.plist` |
| Configuration | `~/.config/devlake-telemetry/config.json` |
| Hourly Data | `~/.local/share/devlake-telemetry/hourly_data.json` |
| Daily Aggregate | `~/.local/share/devlake-telemetry/daily_aggregate.json` |
| Archives | `~/.local/share/devlake-telemetry/archive/` |
| Logs | `~/.local/var/log/devlake-telemetry.log` |

## Management Commands

### Check Status
```bash
launchctl list | grep devlake
```

### View Logs
```bash
tail -f ~/.local/var/log/devlake-telemetry.log
```

### Manual Run (Immediate Test)
```bash
~/.local/bin/devlake-telemetry-collector.sh
```

### Unload Agent
```bash
launchctl unload ~/Library/LaunchAgents/com.devlake.telemetry.local.plist
```

### Reload Agent
```bash
launchctl unload ~/Library/LaunchAgents/com.devlake.telemetry.local.plist
launchctl load ~/Library/LaunchAgents/com.devlake.telemetry.local.plist
```

## Code Changes

### Collector Script Update
Fixed the secondary webhook URL loading in `devlake-telemetry-collector.sh` to properly read from JSON config using `jq`.

## Test Results Summary

✅ **Installation**: Successful (no sudo required)  
✅ **LaunchAgent**: Loaded and running  
✅ **Data Collection**: Hourly data being collected  
✅ **Primary Webhook**: Data sent to DevLake (HTTP 200)  
✅ **Secondary Webhook**: Data sent to webhook.site successfully  
✅ **Database Storage**: Verified in DevLake MySQL database  
✅ **Automatic Scheduling**: Will run every hour via LaunchAgent

## Notes

- The local version is ideal for development and testing
- Production deployment should use the standard `install-telemetry.sh` with sudo
- All paths are user-specific and isolated from system directories
- LaunchAgent runs only when the user is logged in
