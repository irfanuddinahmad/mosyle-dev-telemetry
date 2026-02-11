# DevLake Plugin Specification: Developer Telemetry

## 1. Overview
This plugin enables DevLake to ingest, store, and analyze developer productivity metrics collected from local environments (e.g., via the [DevLake Telemetry Collector](https://github.com/irfanuddinahmad/mosyle-dev-telemetry)).

**Goal**: Provide visibility into "active development hours," "tool usage," and "context switching" without invasive monitoring.

## 2. Architecture
The plugin operates on a **Push Model** via an HTTP Webhook.

1.  **Collector (Client)**: Runs on developer machines (macOS/Linux), aggregates data daily, and pushes JSON to the plugin.
2.  **Plugin (Server)**: Exposes a REST endpoint to receive the payload.
3.  **Database**: Stores raw and enriched data in DevLake's PostgreSQL/MySQL database.
4.  **Domain Layer**: Maps raw data to DevLake's domain layer (optional, if mapping to existing `cicd_tasks` or creating a new domain).

## 3. Data Models

We will introduce two new tables to store the unique telemetry data.

### 3.1 `raw_developer_telemetry`
Stores the raw JSON payload for audit and debugging.
| Column | Type | Description |
|---|---|---|
| `id` | BIGINT | Auto-increment ID |
| `connection_id` | BIGINT | ID of the plugin connection |
| `payload` | UI/JSON | Full JSON body received |
| `created_at` | TIMESTAMP | Injection time |

### 3.2 `_tool_developer_metrics` (Tool Layer)
Stores the structured daily metrics.
| Column | Type | Description |
|---|---|---|
| `connection_id` | BIGINT | Plugin connection ID |
| `developer_id` | VARCHAR(255) | System username (e.g., `irfan.ahmad`) |
| `email` | VARCHAR(255) | Git email (PRIMARY KEY for linking) |
| `name` | VARCHAR(255) | Git name |
| `hostname` | VARCHAR(255) | Machine hostname |
| `date` | DATE | The date of the metrics (YYYY-MM-DD) |
| `active_hours` | INT | Number of active coding hours |
| `tools_used` | JSON/TEXT | List of tools (e.g., `["vscode", "go"]`) |
| `project_context` | JSON/TEXT | List of active projects |
| `command_counts` | JSON/TEXT | Key-value pairs of command usage |
| `os_info` | VARCHAR | OS version (if available) |

## 4. API Endpoints

### 4.1 Receive Telemetry
**POST** `/api/plugins/developer-telemetry/:connectionId/report`

**Request Body** (Matches our Collector output):
```json
{
  "date": "2026-02-11",
  "developer": "irfan.ahmad",
  "email": "irfan@company.com",
  "name": "Irfan Ahmad",
  "hostname": "irfan-macbook-pro",
  "metrics": {
    "active_hours": 9,
    "tools_used": ["go", "vscode"],
    "commands": {
      "git": 45,
      "docker": 12
    },
    "projects": ["mosyle-dev-telemetry"]
  }
}
```

**Response**:
- `200 OK`: Data accepted.
- `400 Bad Request`: Invalid JSON or missing fields.

## 5. Implementation Plan

### Phase 1: Skeleton & API
1.  Initialize `github.com/apache/incubator-devlake/plugins/developer-telemetry`.
2.  Implement `plugin_main.go` with `impl.PluginImpl`.
3.  Define `ApiResource` to handle the POST route.

### Phase 2: Database Migration
1.  Create migration scripts for `_tool_developer_metrics`.
2.  Implement `Gorm` models for the table.

### Phase 3: Logic
1.  **Validation**: Ensure `developer` and `date` are present.
2.  **Idempotency**: If data for the same `developer` + `date` arrives again, **update** the existing record (or sum it, depending on strategy). *Suggestion: Overwrite is safer for retries.*

### Phase 4: Blueprint (Optional)
If we want to pull historical data or aggregate it further, we can implement a `BlueprintV200` plan, but for a simple webhook push, the API handler is sufficient.

## 6. Configuration
The plugin needs a **Connection** configuration to manage security (e.g., shared secret for the webhook).

**Connection Config**:
- `name`: "Mosyle Fleet 1"
- `endpoint`: (Not active for push, but required field)
- `secret_token`: (Optional) A token the collector must send in `Authorization` header for security.

## 7. Integration with Collector
1.  **Update Collector Config**:
    Set `DEVLAKE_WEBHOOK_URL` to: `https://<devlake-host>/api/plugins/developer-telemetry/1/report`
2.  **Security**:
    If using `secret_token`, update `devlake-telemetry-collector.sh` to include `-H "Authorization: Bearer <token>"`.
