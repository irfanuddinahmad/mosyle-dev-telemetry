# DevLake Plugin Specification: Developer Telemetry

**Status**: ✅ Updated February 2026  
**Plugin Name**: `developer_telemetry`  
**Repository**: [mosyle-dev-telemetry](https://github.com/irfanuddinahmad/mosyle-dev-telemetry)

## 1. Overview

This plugin enables DevLake to ingest, store, and analyze developer productivity metrics collected from local development environments via the [DevLake Telemetry Collector](https://github.com/irfanuddinahmad/mosyle-dev-telemetry).

**Goal**: Provide visibility into:
- Active development hours (based on git commits, file changes, IDE activity)
- Git activity (commits, lines changed, repository-level breakdowns)
- Development practices (test runs, build commands)
- Tool usage and project context

**Privacy-First Design**: No command arguments, file paths, code content, or sensitive data is collected.

## 2. Architecture

The plugin operates on a **Push Model** via HTTP REST API.

```
┌─────────────────┐                    ┌──────────────────┐
│  Collector      │  POST /api/rest/   │  DevLake Plugin  │
│  (Client)       ├───────────────────►│  (Server)        │
│  macOS/Linux    │  JSON Payload      │                  │
└─────────────────┘                    └────────┬─────────┘
                                                │
                                                ▼
                                    ┌──────────────────────┐
                                    │  MySQL Database      │
                                    │  _tool_developer_    │
                                    │       _metrics       │
                                    └──────────────────────┘
```

**Components**:
1. **Collector (Client)**: Runs on developer machines, collects hourly data, aggregates daily, pushes to plugin
2. **Plugin (Server)**: Exposes REST endpoint `/api/rest/plugins/developer_telemetry/connections/:id/report`
3. **Database**: Stores daily metrics in `_tool_developer_metrics` table
4. **Grafana**: Visualizes metrics via pre-built dashboards

## 3. Data Model

### 3.1 `_tool_developer_metrics` Table

Stores structured daily developer metrics.

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `connection_id` | BIGINT | Plugin connection ID | `2` |
| `developer_id` | VARCHAR(255) | System username | `sarah.johnson` |
| `email` | VARCHAR(255) | Git email | `sarah@company.com` |
| `name` | VARCHAR(255) | Developer full name | `Sarah Johnson` |
| `hostname` | VARCHAR(255) | Machine hostname | `sarah-macbook` |
| `date` | DATE | Metrics date (YYYY-MM-DD) | `2026-02-19` |
| `active_hours` | INT | Active coding hours | `7` |
| `git_activity` | JSON | Git commits and changes | See below |
| `development_activity` | JSON | Test runs, builds | See below |
| `tools_used` | JSON | Development tools array | `["vscode","docker","python"]` |
| `project_context` | JSON | Active projects array | `[{"name":"backend-api",...}]` |

**Composite Primary Key**: (`connection_id`, `developer_id`, `date`)

### 3.2 JSON Field Structures

#### `git_activity` (JSON)

```json
{
  "total_commits": 8,
  "total_lines_added": 520,
  "total_lines_deleted": 180,
  "total_files_changed": 12,
  "repositories": [
    {
      "name": "backend-api",
      "path": "/home/sarah/projects/backend-api",
      "commits": 5,
      "lines_added": 320,
      "lines_deleted": 100,
      "files_changed": 7,
      "branches_worked": ["feature/api-enhancement", "main"]
    },
    {
      "name": "frontend-web",
      "path": "/home/sarah/projects/frontend-web",
      "commits": 3,
      "lines_added": 200,
      "lines_deleted": 80,
      "files_changed": 5,
      "branches_worked": ["feature/ui-update"]
    }
  ]
}
```

#### `development_activity` (JSON)

```json
{
  "test_runs_detected": 3,
  "build_commands_detected": 5
}
```

**Test Detection**: Monitors terminal commands for `pytest`, `npm test`, `go test`, `cargo test`, `jest`, etc.  
**Build Detection**: Monitors for `npm run build`, `cargo build`, `go build`, `make`, etc.

#### `tools_used` (JSON Array)

```json
["vscode", "docker", "python", "go", "node", "git"]
```

Detected via running process monitoring.

#### `project_context` (JSON Array)

```json
[
  {
    "name": "backend-api",
    "path": "/home/sarah/projects/backend-api",
    "last_activity": "2026-02-19T15:30:00Z"
  }
]
```

## 4. API Endpoints

### 4.1 Receive Telemetry Report

**POST** `/api/rest/plugins/developer_telemetry/connections/:connectionId/report`

**Important**: The `/rest/` prefix is **required** for API key authentication to work properly.

**Authentication**:
```
Authorization: Bearer <API_KEY>
```

**Request Headers**:
```
Content-Type: application/json
Authorization: Bearer G26T9szjBS0rMPoIEODmrgB4Iw5ey3kI...
```

**Request Body**:
```json
{
  "developer_id": "sarah.johnson",
  "email": "sarah.johnson@company.com",
  "name": "Sarah Johnson",
  "hostname": "sarah-macbook-pro",
  "date": "2026-02-19",
  "active_hours": 7,
  "git_activity": {
    "total_commits": 8,
    "total_lines_added": 520,
    "total_lines_deleted": 180,
    "total_files_changed": 12,
    "repositories": [
      {
        "name": "backend-api",
        "path": "/home/sarah/projects/backend-api",
        "commits": 5,
        "lines_added": 320,
        "lines_deleted": 100,
        "files_changed": 7,
        "branches_worked": ["feature/api-enhancement"]
      }
    ]
  },
  "development_activity": {
    "test_runs_detected": 3,
    "build_commands_detected": 5
  },
  "tools_used": ["vscode", "docker", "python", "go"],
  "project_context": [
    {
      "name": "backend-api",
      "path": "/home/sarah/projects/backend-api",
      "last_activity": "2026-02-19T15:30:00Z"
    }
  ]
}
```

**Response**:
- `200 OK`: Data accepted and stored
- `400 Bad Request`: Invalid JSON, missing required fields
- `401 Unauthorized`: Invalid or missing API key
- `500 Internal Server Error`: Database or server error

**Idempotency**: Sending the same `developer_id` + `date` combination multiple times will **UPDATE** the existing record (last write wins).

## 5. Configuration

### 5.1 Creating a Connection

In DevLake UI:

1. Navigate to **Data Connections** → **Developer Telemetry**
2. Click **Add Connection**
3. Configure:
   - **Name**: e.g., "Engineering Team Telemetry"
   - **API Key**: Generate or copy from connection details
4. Save and note the **Connection ID** (e.g., `2`)

### 5.2 API Key Management

- Each connection has a unique API key
- API keys are displayed once during connection creation
- Keys are used for Bearer token authentication
- **Security**: Store keys securely (e.g., in config.json with restrictive permissions)

### 5.3 Collector Configuration

Edit `/usr/local/etc/devlake-telemetry/config.json`:

```json
{
  "webhook_url": "https://devlake.arbisoft.com/api/rest/plugins/developer_telemetry/connections/2/report",
  "api_key": "G26T9szjBS0rMPoIEODmrgB4Iw5ey3kIqZFPKFpVpLonnGbDr04ZWvx7PqG2WOOIecDuww3QH7n6HJvltqbDJnvrW88Gcl463mh0wJ3MwuTRSx8537U7HMblDzoSEPTH",
  "webhook_url_secondary": "https://webhook.site/YOUR-UUID-HERE"
}
```

**Critical**: The URL **must** include `/rest/` in the path: `/api/rest/plugins/...`

## 6. Integration Guide

### 6.1 Collector Setup

```bash
# Install collector on macOS
cd mosyle-dev-telemetry/release
sudo ./install-telemetry.sh

# Configure
sudo nano /usr/local/etc/devlake-telemetry/config.json
# Add webhook_url and api_key from DevLake connection

# Verify installation
launchctl list | grep devlake
tail -f /var/log/devlake-telemetry.log
```

### 6.2 Testing

Use curl to test the endpoint:

```bash
curl -X POST \
  'https://devlake.arbisoft.com/api/rest/plugins/developer_telemetry/connections/2/report' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer YOUR_API_KEY' \
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

### 6.3 Verification

Check MySQL database:

```sql
SELECT 
  developer_id, 
  date, 
  active_hours,
  JSON_EXTRACT(git_activity, '$.total_commits') as commits
FROM _tool_developer_metrics
WHERE connection_id = 2
ORDER BY date DESC
LIMIT 10;
```

## 7. Grafana Dashboards

A pre-built dashboard is available at `grafana/dashboards/DeveloperTelemetry.json` in the DevLake repository.

**Visualizations Include**:
- Active Hours by Developer (time series)
- Total Commits by Developer (time series)
- Total Lines Added (horizontal bar chart)
- Total Active Hours by Developer (horizontal bar chart)
- Average Active Hours by Day of Week (bar chart)
- Daily Commits - Top 10 Developers (time series)
- Code Churn - Lines Added vs Deleted (time series)
- Test Runs Detected (time series)
- Developer Productivity Summary (table)
- Summary stat panels (Total Commits, Hours, Lines, Active Developers)

**Import Instructions**: See [GRAFANA_DASHBOARD.md](GRAFANA_DASHBOARD.md) for details.

## 8. Development Activity Detection

See [ACTIVITY_DETECTION.md](ACTIVITY_DETECTION.md) for comprehensive documentation on how active hours are measured.

**Summary**:
- **Git Activity**: Tracks commits, staging, file changes
- **File Monitoring**: Watches development directories for modifications
- **Process Monitoring**: Detects running IDEs and dev tools
- **Hourly Collection**: Marks each hour as active/inactive
- **Daily Aggregation**: Sums active hours and sends daily report

## 9. Implementation Status

**Status**: ✅ **Production Ready** (February 2026)

- [x] Plugin API endpoint implemented
- [x] Database migration created
- [x] API key authentication working
- [x] Collector tested on macOS and Linux
- [x] Production deployment verified
- [x] Grafana dashboard created
- [x] Fake data generator for testing
- [x] Documentation complete

## 10. See Also

- [ACTIVITY_DETECTION.md](ACTIVITY_DETECTION.md) - How active hours are collected
- [API_AUTHENTICATION.md](API_AUTHENTICATION.md) - API key setup guide
- [GRAFANA_DASHBOARD.md](GRAFANA_DASHBOARD.md) - Dashboard import and usage
- [LOCAL_TESTING.md](../LOCAL_TESTING.md) - Local development setup
- [DOCUMENTATION_AUDIT.md](../DOCUMENTATION_AUDIT.md) - Documentation status
