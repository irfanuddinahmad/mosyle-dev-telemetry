# API Authentication Guide

**Status**: February 2026  
**Plugin**: developer_telemetry

## Overview

The DevLake Developer Telemetry plugin uses **API Key authentication** via Bearer tokens to secure the webhook endpoint. This guide explains how to obtain API keys, configure them, and troubleshoot authentication issues.

## Prerequisites

- DevLake instance running (v0.21+)
- Developer Telemetry plugin installed
- Access to DevLake UI (admin or developer role)

## 1. Creating a Connection and Getting an API Key

### Step 1: Access Data Connections

1. Log into DevLake UI: `https://your-devlake-instance.com`
2. Navigate to **Data Connections** (sidebar)
3. Find **Developer Telemetry** plugin
4. Click **Add Connection**

### Step 2: Configure Connection

Fill in the connection details:

- **Connection Name**: E.g., "Engineering Team Telemetry"
- **Description**: (Optional) "Telemetry from development machines"

Click **Save** or **Create**.

### Step 3: Get the API Key

After creating the connection:

1. The **Connection ID** will be displayed (e.g., `2`)
2. The **API Key** will be shown **once** - copy it immediately
3. If you miss it, you may need to regenerate or create a new connection

**Example API Key**:
```
G26T9szjBS0rMPoIEODmrgB4Iw5ey3kIqZFPKFpVpLonnGbDr04ZWvx7PqG2WOOIecDuww3QH7n6HJvltqbDJnvrW88Gcl463mh0wJ3MwuTRSx8537U7HMblDzoSEPTH
```

**Security Warning**: Treat API keys like passwords. Do not commit them to public repositories or share them via insecure channels.

## 2. Configuring the Collector

### Configuration File Location

- **System Installation**: `/usr/local/etc/devlake-telemetry/config.json`
- **Local Installation**: `~/.config/devlake-telemetry/config.json`

### Configuration Format

Edit `config.json`:

```json
{
  "webhook_url": "https://devlake.arbisoft.com/api/rest/plugins/developer_telemetry/connections/2/report",
  "api_key": "G26T9szjBS0rMPoIEODmrgB4Iw5ey3kIqZFPKFpVpLonnGbDr04ZWvx7PqG2WOOIecDuww3QH7n6HJvltqbDJnvrW88Gcl463mh0wJ3MwuTRSx8537U7HMblDzoSEPTH",
  "webhook_url_secondary": "https://webhook.site/04421308-e750-4ead-901c-f5bf32292fd4"
}
```

### URL Structure Breakdown

**Critical**: The URL **must** include `/rest/` in the path for API key authentication to work.

```
https://devlake.arbisoft.com/api/rest/plugins/developer_telemetry/connections/2/report
         └────────┬─────────┘  └──┬──┘ └──┬───┘ └──────────┬──────────┘ └───┬────┘ └┬┘ └─┬─┘
              DevLake          /api  /rest      /plugins       Plugin Name    /conns /ID /endpoint
              instance
```

**Components**:
- `https://devlake.arbisoft.com` - Your DevLake instance URL
- `/api/rest` - **Required** prefix for API key authentication
- `/plugins/developer_telemetry` - Plugin route
- `/connections/2` - Connection ID (from step 1)
- `/report` - Endpoint for receiving telemetry

## 3. Why `/rest/` is Required

DevLake's API routing works differently depending on the path:

- **Without `/rest/`**: Routes through UI/proxy layer, expects session auth
- **With `/rest/`**: Routes to API handler, processes Bearer token authentication

**Example Failure** (missing `/rest/`):
```
URL: https://devlake.arbisoft.com/api/plugins/developer_telemetry/...
Result: 401 Unauthorized (API key not processed)
```

**Example Success** (with `/rest/`):
```
URL: https://devlake.arbisoft.com/api/rest/plugins/developer_telemetry/...
Result: 200 OK (API key authenticated)
```

## 4. Testing Authentication

### Using curl

Test the endpoint with your API key:

```bash
curl -v -X POST \
  'https://devlake.arbisoft.com/api/rest/plugins/developer_telemetry/connections/2/report' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer G26T9szjBS0rMPoIEODmrgB4Iw5ey3kIqZFPKFpVpLonnGbDr04ZWvx7PqG2WOOIecDuww3QH7n6HJvltqbDJnvrW88Gcl463mh0wJ3MwuTRSx8537U7HMblDzoSEPTH' \
  -d '{
    "developer_id": "test.user",
    "email": "test@company.com",
    "name": "Test User",
    "hostname": "test-machine",
    "date": "2026-02-19",
    "active_hours": 5,
    "git_activity": {
      "total_commits": 3,
      "total_lines_added": 150,
      "total_lines_deleted": 50,
      "total_files_changed": 5,
      "repositories": []
    },
    "development_activity": {
      "test_runs_detected": 1,
      "build_commands_detected": 2
    },
    "tools_used": ["vscode"],
    "project_context": []
  }'
```

**Expected Response** (Success):
```
HTTP/1.1 200 OK
Content-Type: application/json

{"message":"Data received successfully"}
```

**Expected Response** (Auth Failure):
```
HTTP/1.1 401 Unauthorized
Content-Type: application/json

{"error":"Unauthorized: Invalid or missing API key"}
```

### Using Collector Test

Run the collector manually to test:

```bash
# System installation
sudo /usr/local/bin/devlake-telemetry-collector.sh

# Local installation
~/.local/bin/devlake-telemetry-collector.sh

# Check logs
tail -f /var/log/devlake-telemetry.log
# or
tail -f ~/.local/var/log/devlake-telemetry.log
```

**Success Output**:
```
[2026-02-19 14:30:15] === DevLake Telemetry Collector Starting ===
[2026-02-19 14:30:16] Sending payload to https://devlake.arbisoft.com/api/rest/plugins/developer_telemetry/connections/2/report
[2026-02-19 14:30:17] Successfully sent data to DevLake (HTTP 200)
```

**Failure Output**:
```
[2026-02-19 14:30:15] === DevLake Telemetry Collector Starting ===
[2026-02-19 14:30:16] Sending payload to https://devlake.arbisoft.com/api/rest/plugins/developer_telemetry/connections/2/report
[2026-02-19 14:30:17] ERROR: Failed to send data (HTTP 401)
```

## 5. Troubleshooting

### Problem: 401 Unauthorized

**Symptoms**:
- HTTP 401 response
- Log shows "Unauthorized" or "Invalid API key"

**Solutions**:
1. **Check URL has `/rest/` prefix**:
   ```
   ❌ /api/plugins/...
   ✅ /api/rest/plugins/...
   ```

2. **Verify API key in config.json**:
   ```bash
   sudo cat /usr/local/etc/devlake-telemetry/config.json
   # or
   cat ~/.config/devlake-telemetry/config.json
   ```

3. **Check Authorization header format**:
   - Must be: `Authorization: Bearer <API_KEY>`
   - No quotes around API key
   - No extra spaces

4. **Regenerate API key**:
   - Create a new connection in DevLake UI
   - Copy new API key
   - Update config.json

### Problem: 404 Not Found

**Symptoms**:
- HTTP 404 response
- "Route not found" error

**Solutions**:
1. **Verify connection ID**:
   - Check DevLake UI for correct connection ID
   - Update URL: `/connections/<ID>/report`

2. **Check plugin is installed**:
   - DevLake UI → Plugins → Developer Telemetry should be enabled

3. **Verify URL structure**:
   ```
   https://<instance>/api/rest/plugins/developer_telemetry/connections/<ID>/report
   ```

### Problem: Connection Timeout

**Symptoms**:
- Request hangs or times out
- No response from server

**Solutions**:
1. **Check DevLake instance is running**:
   ```bash
   curl https://devlake.arbisoft.com/api/ping
   ```

2. **Verify network connectivity**:
   ```bash
   ping devlake.arbisoft.com
   ```

3. **Check firewall rules** (if applicable)

### Problem: Invalid JSON

**Symptoms**:
- HTTP 400 Bad Request
- "Invalid JSON" or "Parse error"

**Solutions**:
1. **Validate JSON payload**:
   ```bash
   # Copy payload from logs and test
   echo '<payload>' | jq .
   ```

2. **Check collector logs** for malformed data

3. **Ensure all required fields are present**:
   - `developer_id`
   - `date`
   - `email`
   - `name`
   - `hostname`
   - `active_hours`
   - `git_activity`
   - `development_activity`

## 6. Security Best Practices

### 1. Restrict Config File Permissions

```bash
# System installation
sudo chmod 600 /usr/local/etc/devlake-telemetry/config.json
sudo chown root:wheel /usr/local/etc/devlake-telemetry/config.json

# Local installation
chmod 600 ~/.config/devlake-telemetry/config.json
```

### 2. Use Environment Variables (Alternative)

Instead of storing in config.json, use environment variables:

```bash
# In LaunchDaemon plist or shell
export DEVLAKE_WEBHOOK_URL="https://..."
export DEVLAKE_API_KEY="G26T9sz..."
```

Update collector script to read from environment if `config.json` is not desired.

### 3. Rotate API Keys Regularly

- Create new connections periodically
- Update config.json with new keys
- Delete old connections in DevLake UI

### 4. Monitor for Unauthorized Access

- Check DevLake logs for failed authentication attempts
- Review MySQL `_tool_developer_metrics` for unexpected data

## 7. Testing with Secondary Webhook

For testing without affecting production, use webhook.site:

1. Go to https://webhook.site
2. Copy your unique URL (e.g., `https://webhook.site/04421308-e750-4ead-901c-f5bf32292fd4`)
3. Add to `config.json`:
   ```json
   {
     "webhook_url": "https://devlake.arbisoft.com/api/rest/...",
     "webhook_url_secondary": "https://webhook.site/YOUR-UUID",
     "api_key": "..."
   }
   ```

The collector will send to both URLs. You can inspect the exact payload at webhook.site.

## 8. See Also

- [PLUGIN_SPEC.md](PLUGIN_SPEC.md) - Full API specification
- [LOCAL_TESTING.md](../LOCAL_TESTING.md) - Local testing setup
- [ACTIVITY_DETECTION.md](ACTIVITY_DETECTION.md) - How telemetry data is collected
- DevLake API Documentation: https://devlake.apache.org/docs/api-reference
