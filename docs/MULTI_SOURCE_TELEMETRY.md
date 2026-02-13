# Multi-Source Telemetry Collection

## Overview
To improve telemetry accuracy beyond simple bash history file modification timestamps, we now collect data from multiple timestamp-rich sources with a fallback chain.

## Data Sources (Priority Order)

### 1. **Zsh History** (Primary Source - Most Accurate)
**Location**: `~/.zsh_history`  
**Format**: `: 1707732456:0;git commit -m "message"`  
**Advantage**: Built-in Unix timestamps (to the second)  
**Usage**: Direct timestamp filtering - only processes commands newer than last run

```bash
grep -E "^: [0-9]+:[0-9]+;" ~/.zsh_history | awk -v last="$timestamp" '
  match($0, /^: ([0-9]+):/, ts);
  if (ts[1] > last) print $0;
'
```

### 2. **macOS Unified Logs** (Fallback for Bash Users)
**Tool**: `log show`  
**Advantage**: Captures actual command execution timestamps from the system  
**Limitation**: Requires parsing unstructured log output

```bash
log show --predicate 'process == "bash" || process == "zsh"' \
  --style compact --last 1h
```

**When Used**:
- If zsh history is empty (user doesn't use zsh)
- As supplementary data for bash users

### 3. **Bash History with File Modification Time** (Final Fallback)
**Location**: `~/.bash_history`  
**Limitation**: No per-command timestamps - uses file mtime  
**Usage**: Only processes if file was modified since last run

```bash
bash_mtime=$(stat -f %m ~/.bash_history)
if [[ $bash_mtime -gt $last_timestamp ]]; then
  tail -n 100 ~/.bash_history
fi
```

### 4. **Git Commit Logs** (Activity Validation)
**Purpose**: Cross-validate project activity  
**Advantage**: Precise timestamps + measure of meaningful work

```bash
git log --all --since="1 hour ago" --oneline
```

**Usage**:
- Counts commits per repository in the last hour
- Strengthens "active hour" determination
- Provides commit count metrics

## How It Works

### Fallback Chain
```
Try zsh history (has timestamps)
  ↓ (if empty or insufficient)
Try unified logs (system-level tracking)
  ↓ (always run in parallel)
Try bash history (if file modified)
  ↓ (always run in parallel)
Collect git commits (validation)
```

### Parallel Collection
All sources are queried **in parallel** for performance:
```bash
collect_shell_commands > temp1 &
collect_git_activity > temp2 &
wait
```

## Benefits

### Improved Accuracy
- **Zsh users**: Near-perfect accuracy (second-level precision)
- **Bash users**: Significant improvement via unified logs
- **All users**: Git commits provide validation

### Cross-Validation
- Commands executed ≈ git commits made
- If commits > 0 but commands = 0 → flag for investigation

### Active Hour Logic
An hour is "active" if **ANY** of these are true:
- Commands executed (`cmd_count > 0`)
- Project files modified (`project_count > 0`)
- Git commits made (`git_count > 0`)

## Output Format

### Hourly Data
```json
{
  "timestamp": "2026-02-13 08:00:00",
  "hour": 8,
  "is_active": true,
  "commands": {"git": 5, "npm": 3},
  "tools_used": ["vscode", "docker"],
  "projects": ["mosyle-dev-telemetry"],
  "git_commits": {"mosyle-dev-telemetry": 2}
}
```

### Daily Aggregate
```json
{
  "date": "2026-02-13",
  "active_hours": 9,
  "commands": {"git": 45, "npm": 12},
  "tools_used": ["vscode", "docker"],
  "projects": ["mosyle-dev-telemetry", "devlake"],
  "git_commits": {"mosyle-dev-telemetry": 8, "devlake": 3}
}
```

## Future Enhancements

### Mosyle HTTPS Logs
If Mosyle provides access to HTTPS connection logs, we could:
- Track API calls (GitHub, Jira, Slack)
- Infer tool usage from service endpoints
- Detect collaboration patterns

**Status**: Awaiting log location and format details

### Process Accounting
If `accton` is enabled, we could use `lastcomm` for even more precise tracking:
```bash
lastcomm | grep -E "git|npm|docker"
```

## Privacy Notes
All filtering and sanitization rules still apply:
- No command arguments collected
- No file paths or URLs
- Only command names and counts
- Git commit messages are NOT collected (only counts)
