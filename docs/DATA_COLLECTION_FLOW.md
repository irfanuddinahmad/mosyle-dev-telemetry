# DevLake Telemetry: Data Collection Flow

This document details how the `devlake-telemetry-collector.sh` script collects, aggregates, and transmits data.

## 1. Data Collection (Hourly)
The script `devlake-telemetry-collector.sh` is triggered every hour by the LaunchAgent.

### A. Command Activity (`collect_shell_commands`)
- **Source**: Reads the last 1000 lines of `~/.zsh_history` and `~/.bash_history`.
- **Extraction**:
  - Parses the history format (e.g., zsh's `: timestamp:0;command`).
  - Extracts only the first word (the command name, like `git`, `docker`, `npm`).
  - Removes `sudo` prefix.
- **Privacy Filtering**:
  - Excludes lines starting with non-command characters (`#`, `"`, empty lines).
  - **Crucial**: Filters out code snippets (Python, JS) by ignoring lines with parentheses `()`, brackets `[]`, equals `=`, dots `.`, and keywords like `print`, `import`, `for`, `if`.
- **Aggregation**: Counts the occurrences of each command uniquely (e.g., `git: 45`, `docker: 12`).

### B. Tool Usage (`collect_active_tools`)
- **Method**: Uses `pgrep` to check for running processes of known developer tools.
- **Detected Tools**:
  - **IDEs**: VSCode, IntelliJ, PyCharm, GoLand.
  - **Infrastructure**: Docker.
  - **CLI Processes**: git, go, node/npm, python.
- **Output**: A list of currently active tools (e.g., `["vscode", "docker", "go"]`).

### C. Project Context (`collect_active_projects`)
- **Method**: Scans for `.git` directories in the user's home folder (depth 4).
- **Activity Check**: Checks if any file within a repo was modified in the last 60 minutes (`find ... -mmin -60`).
- **Privacy**: Collects only the **directory name** of the repo (e.g., `mosyle-dev-telemetry`), not the full path or file contents.

### D. Activity Status
- Calculates `is_active`: `true` if *any* commands were run OR *any* developer tools are running.

## 2. Local Aggregation (Daily)
Data is processed entirely on the local machine to ensure privacy and reduce network traffic.

- **Hourly File**: Each hour, the collected metrics are saved to `hourly_data.json`.
- **Daily File**: The script reads `daily_aggregate.json` (or creates it if new).
- **Merging Logic**:
  - **Commands**: Sums up counts from the current hour with the daily total.
  - **Tools**: Merges the lists and keeps unique values (set union).
  - **Projects**: Merges lists and keeps unique values.
  - **Active Hours**: Increments the `active_hours` counter if `is_active` was true for this hour.
  - **Hours Collected**: Appends the current hour to a list to track coverage.

## 3. Transmission (Once per Day)
- **Trigger**: The script checks if it's the first run after midnight.
- **Payload**: Constructs a JSON payload from the `daily_aggregate.json`.
- **Sending**:
  - Sends a POST request to the configured DevLake Webhook URL.
  - **On Success (HTTP 2xx)**:
    - Archives the day's data to `archive/daily_YYYY-MM-DD.json`.
    - Resets `daily_aggregate.json` for the new day.
