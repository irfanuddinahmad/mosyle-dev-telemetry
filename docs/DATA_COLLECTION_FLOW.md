# DevLake Telemetry: Data Collection Flow

This document details how the `devlake-telemetry-collector.sh` script collects, aggregates, and transmits data.

## Architecture Diagram

```mermaid
graph TD
    subgraph Hourly["⏰ Hourly Triggers (LaunchAgent)"]
        H1(Cron Trigger) --> S(Collector Script)
        
        subgraph ParallelCollection["1. Parallel Multi-Source Collection"]
            S -->|Parallel| CMD_COLLECT[Command Collection]
            S -->|Parallel| TOOL_COLLECT[Tool Detection]
            S -->|Parallel| PROJ_COLLECT[Project Activity]
            S -->|Parallel| GIT_COLLECT[Git Commits]
            S -->|Parallel| API_COLLECT[API Connections]
            
            subgraph CommandSources["Command Sources (Fallback Chain)"]
                CMD_COLLECT --> ZSH{Zsh History<br/>with timestamps?}
                ZSH -->|Yes| ZSH_PARSE[Parse timestamps<br/>Filter by last run]
                ZSH -->|No/Empty| UNIFIED[macOS Unified Logs<br/>bash/zsh processes]
                UNIFIED --> BASH[Bash History<br/>file mtime check]
                ZSH_PARSE --> CMD_FILTER[Privacy Filter]
                BASH --> CMD_FILTER
                CMD_FILTER --> CMD_COUNTS{Command Counts}
            end
            
            subgraph ToolDetection["Tool Detection"]
                TOOL_COLLECT --> PS[ps aux | grep]
                PS --> TOOLS{Active Tools<br/>vscode, docker, etc.}
            end
            
            subgraph ProjectActivity["Project Activity"]
                PROJ_COLLECT --> FIND_GIT[find .git dirs]
                FIND_GIT --> CHECK_MTIME[Check file mtime<br/>last 60 min]
                CHECK_MTIME --> PROJECTS{Active Projects}
            end
            
            subgraph GitCommits["Git Commit Tracking"]
                GIT_COLLECT --> SCAN_REPOS[Scan .git directories]
                SCAN_REPOS --> GIT_LOG[git log --since 1h]
                GIT_LOG --> GIT_COUNTS{Commit Counts<br/>per repo}
            end
            
            subgraph APIConnections["API Connection Tracking (Differential)"]
                API_COLLECT --> LSOF[lsof -i TCP:443]
                LSOF --> STATE_COMP{Compare with<br/>previous state}
                STATE_COMP --> NEW_CONN[Identify NEW<br/>connections only]
                NEW_CONN --> API_COUNTS{API Connections<br/>github, jira, slack}
                API_COUNTS --> UPDATE_STATE[Update state file]
            end
        end
        
        subgraph ActiveLogic["2. Activity Determination"]
            CMD_COUNTS -->|cmd_count > 0?| IS_ACTIVE{is_active}
            PROJECTS -->|project_count > 0?| IS_ACTIVE
            GIT_COUNTS -->|git_count > 0?| IS_ACTIVE
            IS_ACTIVE -->|true/false| HOURLY_JSON
        end
        
        subgraph HourlyStorage["3. Hourly Data Storage"]
            CMD_COUNTS --> HOURLY_JSON[hourly_data.json]
            TOOLS --> HOURLY_JSON
            PROJECTS --> HOURLY_JSON
            GIT_COUNTS --> HOURLY_JSON
            API_COUNTS --> HOURLY_JSON
        end
    end
    
    subgraph Aggregation["4. Daily Aggregation"]
        HOURLY_JSON --> MERGE[jq merge operation]
        DAILY_FILE[daily_aggregate.json] --> MERGE
        
        subgraph MergeLogic["Merge Operations"]
            MERGE --> SUM_CMD[Sum command counts]
            MERGE --> UNION_TOOLS[Union tools<br/>ONLY if active]
            MERGE --> UNION_PROJ[Union projects]
            MERGE --> SUM_GIT[Sum git commits]
            MERGE --> SUM_API[Sum API connections]
            MERGE --> INC_HOURS[Increment active_hours<br/>if is_active]
        end
        
        SUM_CMD --> UPDATED_DAILY[Updated daily_aggregate.json]
        UNION_TOOLS --> UPDATED_DAILY
        UNION_PROJ --> UPDATED_DAILY
        SUM_GIT --> UPDATED_DAILY
        SUM_API --> UPDATED_DAILY
        INC_HOURS --> UPDATED_DAILY
    end
    
    subgraph Transmission["5. Daily Transmission (Once per Day)"]
        UPDATED_DAILY -->|Check time| TIME{First run<br/>after midnight?}
        TIME -->|Yes| CHECK_SENT{Already sent<br/>today?}
        CHECK_SENT -->|No| SEND[POST to DevLake<br/>Webhook /api/plugins/...]
        SEND -->|HTTP 2xx| SUCCESS[Success]
        SUCCESS --> ARCHIVE[Archive to<br/>archive/daily_YYYY-MM-DD.json]
        SUCCESS --> MARK_SENT[Update last_send_timestamp]
        SUCCESS --> RESET[Reset daily_aggregate.json<br/>for new day]
        
        SEND -->|HTTP 4xx/5xx| RETRY{Retry count<br/>< 3?}
        RETRY -->|Yes| BACKOFF[Exponential backoff<br/>wait]
        BACKOFF --> SEND
        RETRY -->|No| LOG_ERROR[Log error:<br/>retry next hour]
    end
    
    style ParallelCollection fill:#e1f5ff
    style Aggregation fill:#fff4e1
    style Transmission fill:#e8f5e8
    style CommandSources fill:#f0f0f0
    style APIConnections fill:#ffe1f5
```

## 1. Data Collection (Hourly)
The script `devlake-telemetry-collector.sh` is triggered every hour by the LaunchAgent. All data sources are collected **in parallel** for performance.

### A. Command Activity (`collect_shell_commands`) - Multi-Source with Fallback

**Priority Order:**

1. **Zsh History** (Most Accurate - Has Built-in Timestamps)
   - **Source**: `~/.zsh_history`
   - **Format**: `: 1707732456:0;git commit -m "fix"`
   - **Extraction**: 
     - Parses timestamp from each entry
     - Only processes commands **newer than last run** (no duplicates!)
     - Extracts first word (command name: `git`, `npm`, `docker`)
     - Removes `sudo` prefix
   - **Privacy Filtering**: 
     - Excludes code snippets (lines with `()`, `[]`, `=`, `.`, keywords like `print`, `for`)
     - Only command names, never arguments

2. **macOS Unified Logs** (Fallback for Bash Users)
   - **Source**: System logs via `log show`
   - **Method**: Queries shell process execution (bash, zsh, sh) for the last hour
   - **Advantage**: Captures actual command execution timestamps
   - **Usage**: Only if zsh history is empty or user is using bash

3. **Bash History** (Final Fallback)
   - **Source**: `~/.bash_history`
   - **Limitation**: No per-command timestamps (uses file modification time)
   - **Method**: Reads last 100 lines if file was modified since last run

### B. Tool Usage (`collect_active_tools`) - Process Snapshot
- **Method**: Single `ps aux` call (faster than multiple `pgrep`)
- **Detected Tools**:
  - **IDEs**: VSCode, IntelliJ, PyCharm, GoLand, Cursor
  - **Infrastructure**: Docker
  - **Languages**: go, node/npm, python, ruby
- **Output**: Array of currently running tools: `["vscode", "docker", "go"]`

### C. Project Context (`collect_active_projects`) - Real-time File Activity
- **Method**: Scans for `.git` directories (depth 4, entire home directory)
- **Activity Check**: Files modified in last 60 minutes (`find ... -mmin -60`)
- **Privacy**: Only collects **directory name** (e.g., `mosyle-dev-telemetry`), not paths or file contents

### D. Git Commit Activity (`collect_git_activity`) - NEW!
- **Method**: For each git repo, runs `git log --all --since="1 hour ago"`
- **Output**: Commit count per repository
- **Purpose**: Cross-validates actual work (commits = meaningful progress)
- **Example**: `{"mosyle-dev-telemetry": 3, "devlake": 1}`

### E. API Connection Tracking (`collect_api_connections`) - NEW! (Differential)
- **Method**: Uses `lsof -i TCP:443 -sTCP:ESTABLISHED` to capture HTTPS connections
- **Differential Tracking**: 
  - Stores current connections in state file
  - Compares to previous state using `comm` command
  - Only counts **NEW** connections (prevents double-counting long-lived connections like Slack)
- **Tracked Services**:
  - `github.com` → GitHub API/git operations
  - `*.atlassian.net` → Jira
  - `slack.com` → Slack
  - `docker.io` → Docker Hub
  - `npmjs.org`, `pypi.org` → Package registries
  - `openai.com` → AI services
- **Example**: `{"github": 5, "slack": 1, "docker-hub": 2}`

### F. Activity Status Determination
Calculates `is_active`: `true` ONLY if:
- Commands were executed (`cmd_count > 0`)
- **OR** Project files were modified (`project_count > 0`)
- **OR** Git commits were made (`git_count > 0`)

**Important**: Merely having tools open (like VS Code) does **not** count as active.

## 2. Local Aggregation (Daily)
Data is processed entirely on the local machine to ensure privacy and reduce network traffic.

- **Hourly File**: `hourly_data.json` (overwritten each hour)
- **Daily File**: `daily_aggregate.json` (accumulated throughout the day)
- **Merging Logic** (using `jq`):
  - **Commands**: Sums counts: `{"git": 45 + 5} → {"git": 50}`
  - **Tools**: Union of arrays, **ONLY if hour was active** (prevents passive tool counting)
  - **Projects**: Union of arrays (unique project names)
  - **Git Commits**: Sums counts per repository
  - **API Connections**: Sums new connection counts per service
  - **Active Hours**: Increments counter if `is_active` was `true`
  - **Hours Collected**: Appends current hour to track coverage

### Example Hourly Data:
```json
{
  "timestamp": "2026-02-13 15:00:00",
  "hour": 15,
  "is_active": true,
  "commands": {"git": 5, "npm": 2},
  "tools_used": ["vscode", "docker"],
  "projects": ["mosyle-dev-telemetry"],
  "git_commits": {"mosyle-dev-telemetry": 2},
  "api_connections": {"github": 3, "slack": 1}
}
```

## 3. Transmission (Once per Day)
- **Trigger**: First run after midnight (checked via timestamp comparison)
- **Duplicate Prevention**: Checks `last_send_timestamp` to avoid sending twice
- **Payload**: Constructs JSON from `daily_aggregate.json`
- **Sending**:
  - POST request to DevLake Webhook: `/api/plugins/developer-telemetry/1/report`
  - **Headers**: `Authorization: Bearer <token>`, `Content-Type: application/json`
  - **Retry Logic**: 
    - Exponential backoff (2s, 4s, 8s)
    - Max 3 retries
    - Logs errors for manual review
  - **On Success (HTTP 2xx)**:
    - Archives data: `archive/daily_YYYY-MM-DD.json`
    - Updates `last_send_timestamp`
    - Resets `daily_aggregate.json` for new day

## Performance Optimizations

1. **Parallel Collection**: All 5 data sources run simultaneously (~3s total vs ~15s sequential)
2. **Cached Date Values**: Date/time calculated once per run, reused
3. **Consolidated Process Queries**: Single `ps aux` instead of multiple `pgrep`
4. **File Locking**: Uses `flock` to prevent race conditions
5. **Timestamp Filtering**: Zsh history only processes new entries since last run
6. **Differential API Tracking**: State file prevents re-counting same connections

## Privacy & Security

- ✅ **No command arguments** collected (only command names)
- ✅ **No file paths** (only project directory names)
- ✅ **No git commit messages** (only counts)
- ✅ **No API request data** (only connection counts)
- ✅ **Local processing** (aggregation happens on-device)
- ✅ **Encrypted transmission** (HTTPS webhook)
- ✅ **Authenticated endpoint** (Bearer token)
