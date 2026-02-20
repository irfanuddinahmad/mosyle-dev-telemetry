# Activity Detection and Active Hours Measurement

This document explains how the telemetry collector detects developer activity and measures active hours.

## Activity Detection Methods

### 1. Git Activity Tracking

- Monitors git commits, staging, and branch operations
- Tracks file changes in git repositories
- Records lines added/deleted via git diff analysis

### 2. File System Monitoring

- Watches development directories for file modifications
- Detects saves in code editors
- Tracks creation/deletion of source files

### 3. Process/Command Monitoring

- Monitors terminal commands (test runners, build tools, compilers)
- Tracks IDE process activity (VS Code, IntelliJ, etc.)
- Detects development tool usage (npm, pip, go, cargo, etc.)

### 4. Keyboard/Mouse Activity (in dev tools)

- Optional: Some implementations track input activity specifically in development applications
- Helps distinguish between actual coding vs idle time with tools open

## Hourly Activity Determination

The collector (`devlake-telemetry-collector.sh`) runs **every hour** and checks:

```bash
# Hourly check (simplified logic):
if [ git commits > 0 ] || 
   [ files changed > 0 ] || 
   [ dev commands detected > 0 ] ||
   [ IDE active > 0 ]; then
    HOUR_ACTIVE=1
else
    HOUR_ACTIVE=0
fi
```

### An hour is marked as "active" if ANY of these occur:

- At least 1 git commit
- At least 1 source file modification
- At least 1 development command execution (test, build, run)
- IDE/editor had active file editing sessions

## Daily Aggregation

At the end of each day, the collector:

1. Sums up all active hours: `active_hours = sum(hourly_active_flags)`
2. Creates the daily aggregate record with `active_hours` field
3. Sends to DevLake API endpoint

### Example

If a developer commits code at 9am, edits files at 11am-2pm, and runs tests at 4pm, they would have **5 active hours** for that day (9am, 11am, 12pm, 1pm, 2pm, 4pm).

## Important Notes

- **Active ≠ Working:** Active hours measure development activity, not total work hours
- **Minimum Activity Threshold:** Even small actions (1 commit, 1 file save) count the entire hour as active
- **Privacy:** The collector doesn't track keystrokes or screen content, only development tool activity
- **Granularity:** Hourly collection allows for daily/weekly/monthly aggregation patterns

## Data Structure

The collected data is stored in the `active_hours` field of the daily telemetry record:

```json
{
  "developer_id": "sarah.johnson",
  "date": "2026-02-19",
  "active_hours": 7,
  "git_activity": {
    "total_commits": 8,
    "total_lines_added": 520,
    "total_lines_deleted": 180
  },
  "development_activity": {
    "test_runs_detected": 3,
    "build_commands_detected": 5
  }
}
```

## Visualization

Active hours data can be visualized in Grafana dashboards to show:

- Daily trends per developer
- Team-wide productivity patterns
- Weekday vs weekend activity
- Active hours distribution across developers
- Correlation with commit activity and code changes

See the [DeveloperTelemetry.json](../grafana/dashboards/DeveloperTelemetry.json) dashboard for example visualizations.
