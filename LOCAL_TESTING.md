# Local Testing Setup - DevLake Telemetry Collector

## Overview
Local testing installation script that installs the telemetry collector in user space without requiring sudo/root access.

## Prerequisites

- macOS (tested on Ventura 13.4+)
- Internet access to DevLake webhook endpoint
- **DevLake Connection ID and API Key** (see [API_AUTHENTICATION.md](docs/API_AUTHENTICATION.md))

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

### Getting Your API Key

Before configuring, you need a DevLake connection and API key:

1. Log into DevLake UI: `https://devlake.arbisoft.com`
2. Navigate to **Data Connections** → **Developer Telemetry**
3. Click **Add Connection**
4. Name it (e.g., "Local Testing")
5. **Copy the Connection ID and API Key** (shown once!)

For detailed instructions, see [API_AUTHENTICATION.md](docs/API_AUTHENTICATION.md).

### Webhook URLs (Production Configuration)
```json
{
  "webhook_url": "https://devlake.arbisoft.com/api/rest/plugins/developer_telemetry/connections/2/report",
  "api_key": "YOUR_API_KEY_HERE",
  "webhook_url_secondary": "https://webhook.site/YOUR-UNIQUE-UUID-HERE"
}
```

**Critical**: The URL **must** include `/rest/` prefix for API key authentication:
```
https://<instance>/api/rest/plugins/developer_telemetry/connections/<ID>/report
                      ^^^^^
                      Required for Bearer token auth
```

**For localhost testing** (if running DevLake locally):
```json
{
  "webhook_url": "http://localhost:8080/api/rest/plugins/developer_telemetry/connections/2/report",
  "api_key": "YOUR_API_KEY_HERE",
  "webhook_url_secondary": "https://webhook.site/YOUR-UNIQUE-UUID-HERE"
}
```

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
   - Create configuration file with default URLs
   - Load the LaunchAgent

4. **Configure your API key**:
   ```bash
   nExpected Test Output (February 2026 Format)
```
[2026-02-18 08:01:49] === DevLake Telemetry Collector Starting ===
[2026-02-18 08:01:49] Sending payload to secondary webhook: https://webhook.site/YOUR-UNIQUE-UUID-HERE
[2026-02-18 08:01:50] Successfully sent data to secondary webhook
[2026-02-18 08:01:50] Sending payload to https://devlake.arbisoft.com/api/rest/plugins/developer_telemetry/connections/2/report
[2026-02-18 08:01:50] Successfully sent data to DevLake (HTTP 200)
[2026-02-18 08:01:50] Archived data to ~/.local/share/devlake-telemetry/archive/daily_2026-02-16.json
```

### Example Payload (Current Data Model)

The collector sends comprehensive metrics including git activity and development activity:

```json
{
  "developer_id": "irfan.ahmad",
  "hostname": "Irfans-MacBook-Pro.local",
  "timestamp": "2026-02-16T12:00:00Z",
  "active_hours": 3.5,
  "tools_used": {
    "vscode": 120,
    "docker": 45,
    "goland": 90,
    "chrome": 200
  },
  "git_activity": {
    "total_commits": 12,
    "total_lines_added": 450,
    "total_lines_deleted": 120,
    "total_files_changed": 28,
    "repositories": [
      {
        "name": "incubator-devlake",
        "commits": 8,
        "lines_added": 350,
        "lines_deleted": 80,
        "files_changed": 20
      },
      {
        "name": "mosyle-dev-telemetry",
        "commits": 4,
        "lines_added": 100,
        "lines_deleted": 40,
        "files_changed": 8
      }
    ]
  },
  "development_activity": {
    "test_runs_detected": 5,
    "build_commands_detected": 3
  },
  "project_context": { (`_tool_developer_metrics` table):
```
developer_id: irfan.ahmad
email: irfan.ahmad@arbisoft.com
date: 2026-02-16
active_hours: 3.5
tools_used: ["docker","git","goland","intellij","node","pycharm","python","vscode"]
git_activity: {"total_commits":12,"total_lines_added":450,"total_lines_deleted":120,...}
development_activity: {"test_runs_detected":5,"build_commands_detected":3}
```

#### 2. LaunchAgent Status
```bash
$ launchctl list | grep devlake
-       1       com.devlake.telemetry.local
```
✅ Agent is running successfully

#### 3. webhook.site Verification
Visit your webhook.site URL to see the exact JSON payload:
- Check all fields are present
- Verify `git_activity` includes `repositories[]` array
- Verify `development_activity` includes `test_runs_detected` and `build_commands_detected`
- Confirm API key header is sent: `Authorization: Bearer YOUR_API_KEY`repository-level stats
- `development_activity`: Detected test runs and build commands via terminal monitoring
- `project_context`: Active git repositories detected
- `connection_id`: Should match your DevLake connection (typically `2` for production)  "webhook_url_secondary": "https://webhook.site/YOUR-UUID"
   }
   ```

5. **Test the webhook**:
   ```bash
   curl -X POST https://devlake.arbisoft.com/api/rest/plugins/developer_telemetry/connections/2/report \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer YOUR_API_KEY_HERE" \
     -d '{
       "developer_id": "test-user",
       "active_hours": 1,
       "timestamp": "2026-02-01T10:00:00Z",
       "git_activity": {
         "total_commits": 5,
         "total_lines_added": 100,
         "total_lines_deleted": 20,
         "total_files_changed": 10,
         "repositories": []
       }
     }'
   ```

   **Expected Responses**:
   - Success: `200 OK` or `{"success": true}`
   - `401 Unauthorized`: Invalid or missing API key
   - `404 Not Found`: Wrong URL (check `/rest/` prefix and connection ID)
   - Connection error: DevLake instance not accessible

## Testing Results

### Test Output
```
[2026-02-18 08:01:49] === DevLake Telemetry Collector Starting ===

**API Key Authentication**: Updated to support Bearer token authentication for API key-based access.

**Data Model**: Enhanced to include:
- `git_activity` with repository-level breakdown
- `development_activity` with test runs and build commands detection
- Hourly activity tracking with daily aggregation

See [PLUGIN_SPEC.md](docs/PLUGIN_SPEC.md) for the complete data model specification.

## Troubleshooting

### 401 Unauthorized
- Check that your API key is correct in `config.json`
- Verify the URL includes `/rest/` prefix
- Ensure `Authorization: Bearer <API_KEY>` header is sent
- See [API_AUTHENTICATION.md](docs/API_AUTHENTICATION.md#troubleshooting)

### 404 Not Found
- Verify connection ID is correct (typically `2` for production)
- Check URL structure: `/api/rest/plugins/developer_telemetry/connections/<ID>/report`
- Confirm `/rest/` prefix is present

### No Data in Database
- Check logs: `tail -f ~/.local/var/log/devlake-telemetry.log`
- Verify webhook test succeeded (see Installation Steps above)
- Confirm LaunchAgent is running: `launchctl list | grep devlake`
- Check hourly data file exists: `cat ~/.local/share/devlake-telemetry/hourly_data.json`

### git_activity is Empty
- Ensure you've made commits during the collection period
- Check git configuration: `git config --global user.email`
- Verify git repositories are in your home directory or common project locations
- Run manual test: `~/.local/bin/devlake-telemetry-collector.sh`
[2026-02-18 08:01:49] Sending payload to secondary webhook: https://webhook.site/YOUR-UNIQUE-UUID-HERE
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
