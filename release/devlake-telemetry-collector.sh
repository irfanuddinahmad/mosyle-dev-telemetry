#!/bin/bash
#
# DevLake Telemetry Collector
# 
# This script collects privacy-safe developer telemetry and sends it to DevLake.
# It runs hourly to collect data and sends a daily summary.
#
# Privacy Policy:
# - No command arguments or parameters are collected
# - No file paths or contents are captured
# - No URLs or browsing data is recorded
# - Only aggregated metrics and command names are sent
#

set -euo pipefail

# Ensure PATH includes standard locations and Homebrew
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-/usr/local/etc/devlake-telemetry/config.json}"
DATA_DIR="${DATA_DIR:-/var/tmp/devlake-telemetry}"
LOG_FILE="${LOG_FILE:-/var/log/devlake-telemetry.log}"

# Default webhook URL (override via config file)
DEVLAKE_WEBHOOK_URL="${DEVLAKE_WEBHOOK_URL:-https://your-devlake-instance.com/api/webhooks/your-id}"

# Data file paths
HOURLY_DATA_FILE="$DATA_DIR/hourly_data.json"
DAILY_AGGREGATE_FILE="$DATA_DIR/daily_aggregate.json"
LAST_SEND_FILE="$DATA_DIR/last_send_timestamp"

# ============================================================================
# Logging
# ============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

# ============================================================================
# Configuration Loading
# ============================================================================

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # Load webhook URL from config if available
        if command -v jq &> /dev/null; then
            local webhook_url
            webhook_url=$(jq -r '.webhook_url // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
            if [[ -n "$webhook_url" ]]; then
                DEVLAKE_WEBHOOK_URL="$webhook_url"
            fi
        fi
    fi
}

# ============================================================================
# Initialization
# ============================================================================

init() {
    # Create data directory if it doesn't exist
    mkdir -p "$DATA_DIR"
    
    # Load configuration
    load_config
    
    # Initialize daily aggregate if it doesn't exist or if it's a new day
    local today
    today=$(date '+%Y-%m-%d')
    
    if [[ ! -f "$DAILY_AGGREGATE_FILE" ]]; then
        echo '{"date":"'$today'","hours_collected":[],"commands":{},"tools_used":[],"projects":[],"builds":{},"active_hours":0}' > "$DAILY_AGGREGATE_FILE"
    else
        # Check if we need to reset for a new day
        local stored_date
        stored_date=$(jq -r '.date // empty' "$DAILY_AGGREGATE_FILE" 2>/dev/null || echo "")
        if [[ "$stored_date" != "$today" ]]; then
            # New day - send previous day's data first, then reset
            send_daily_data
            echo '{"date":"'$today'","hours_collected":[],"commands":{},"tools_used":[],"projects":[],"builds":{},"active_hours":0}' > "$DAILY_AGGREGATE_FILE"
        fi
    fi
}

# ============================================================================
# Data Collection
# ============================================================================

get_username() {
    # Get the current user (not root, even if running as root)
    if [[ -n "${SUDO_USER:-}" ]]; then
        echo "$SUDO_USER"
    else
        whoami
    fi
}

collect_shell_commands() {
    local username
    username=$(get_username)
    local user_home
    user_home=$(eval echo "~$username")
    
    # Temporary file to store commands
    local temp_cmds="/tmp/devlake_cmds_$$"
    : > "$temp_cmds"
    
    # Check zsh history
    if [[ -f "$user_home/.zsh_history" ]]; then
        # Extract commands from zsh history (format: : timestamp:0;command)
        tail -n 1000 "$user_home/.zsh_history" 2>/dev/null | \
            grep -E "^: [0-9]+:[0-9]+;" | \
            sed -E 's/^: [0-9]+:[0-9]+;//' | \
            awk '{print $1}' | \
            sed 's/^sudo //' | \
            grep -v '^$' | \
            grep -v '^#' | \
            grep -v '^"' | \
            grep -v "(" | \
            grep -v ")" | \
            grep -v "\[" | \
            grep -v "\]" | \
            grep -v "=" | \
            grep -v "\.objects\." | \
            grep -v "^print" | \
            grep -v "^from" | \
            grep -v "^import" | \
            grep -v "^if" | \
            grep -v "^for" | \
            grep -v "^while" | \
            grep -v "^try" | \
            grep -v "^except" | \
            grep -v "^with" | \
            grep -v "^User" | \
            grep -v "^content" >> "$temp_cmds" || true
    fi
    
    # Check bash history
    if [[ -f "$user_home/.bash_history" ]]; then
        tail -n 1000 "$user_home/.bash_history" 2>/dev/null | \
            awk '{print $1}' | \
            sed 's/^sudo //' | \
            grep -v '^$' | \
            grep -v '^#' | \
            grep -v '^"' | \
            grep -v "(" | \
            grep -v ")" | \
            grep -v "\[" | \
            grep -v "\]" | \
            grep -v "=" | \
            grep -v "^print" | \
            grep -v "^from" | \
            grep -v "^import" | \
            grep -v "^if" | \
            grep -v "^for" | \
            grep -v "^while" | \
            grep -v "^try" | \
            grep -v "^except" | \
            grep -v "^with" >> "$temp_cmds" || true
    fi
    
    # Count commands and convert to JSON using jq
    if [[ -s "$temp_cmds" ]]; then
        sort "$temp_cmds" | uniq -c | \
            awk '{print $2 "\t" $1}' | \
            jq -R 'split("\t") | {(.[0]): (.[1] | tonumber)}' | \
            jq -s 'add // {}'
    else
        echo "{}"
    fi
    
    # Cleanup
    rm -f "$temp_cmds"
}

collect_active_tools() {
    local tools=()
    
    # Check for running developer applications
    if pgrep -x "Visual Studio Code" > /dev/null || pgrep -x "Code" > /dev/null; then
        tools+=("vscode")
    fi
    
    if pgrep -x "IntelliJ IDEA" > /dev/null || pgrep -x "idea" > /dev/null; then
        tools+=("intellij")
    fi
    
    if pgrep -x "PyCharm" > /dev/null || pgrep -x "pycharm" > /dev/null; then
        tools+=("pycharm")
    fi
    
    if pgrep -x "GoLand" > /dev/null || pgrep -x "goland" > /dev/null; then
        tools+=("goland")
    fi
    
    if pgrep -x "Docker" > /dev/null || pgrep -f "com.docker" > /dev/null; then
        tools+=("docker")
    fi
    
    # Check for CLI tools in use
    if pgrep -x "git" > /dev/null; then
        tools+=("git")
    fi
    
    if pgrep -x "go" > /dev/null; then
        tools+=("go")
    fi
    
    if pgrep -x "node" > /dev/null || pgrep -x "npm" > /dev/null; then
        tools+=("node")
    fi
    
    if pgrep -x "python" > /dev/null || pgrep -x "python3" > /dev/null; then
        tools+=("python")
    fi
    
    # Output as JSON array
    # Output as JSON array
    if [[ ${#tools[@]} -gt 0 ]]; then
        printf '%s\n' "${tools[@]}" | jq -R . | jq -s .
    else
        echo "[]"
    fi
}

collect_active_projects() {
    local username
    username=$(get_username)
    local user_home
    user_home=$(eval echo "~$username")
    
    local projects=()
    
    # Find recently accessed git repositories
    # Look for .git directories that were accessed in the last hour
    if [[ -d "$user_home" ]]; then
        while IFS= read -r git_dir; do
            local project_dir
            project_dir=$(dirname "$git_dir")
            local project_name
            project_name=$(basename "$project_dir")
            
            # Check if there was recent activity (files modified in last hour)
            if find "$project_dir" -type f -mmin -60 2>/dev/null | grep -q .; then
                projects+=("$project_name")
            fi
        done < <(find "$user_home" -type d -name ".git" -maxdepth 4 2>/dev/null || true)
    fi
    
    # Output as JSON array (unique values)
    if [[ ${#projects[@]} -gt 0 ]]; then
        printf '%s\n' "${projects[@]}" | sort -u | jq -R . | jq -s .
    else
        echo "[]"
    fi
}

collect_hourly_data() {
    log "Collecting hourly telemetry data..."
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hour
    hour=$(date '+%H')
    
    local commands
    commands=$(collect_shell_commands)
    
    local tools
    tools=$(collect_active_tools)
    
    local projects
    projects=$(collect_active_projects)
    
    # Determine if this hour counts as "active" (only if commands executed or file activity detected)
    local is_active=false
    local cmd_count
    cmd_count=$(echo "$commands" | jq 'keys | length')
    local project_count
    project_count=$(echo "$projects" | jq 'length')
    
    if [[ $cmd_count -gt 0 ]] || [[ $project_count -gt 0 ]]; then
        is_active=true
    fi
    
    # Create hourly data JSON
    cat <<EOF > "$HOURLY_DATA_FILE"
{
  "timestamp": "$timestamp",
  "hour": $hour,
  "is_active": $is_active,
  "commands": $commands,
  "tools_used": $tools,
  "projects": $projects
}
EOF
    
    log "Hourly data collected and saved to $HOURLY_DATA_FILE"
}

# ============================================================================
# Data Aggregation
# ============================================================================

aggregate_hourly_to_daily() {
    if [[ ! -f "$HOURLY_DATA_FILE" ]]; then
        log "No hourly data to aggregate"
        return
    fi
    
    if [[ ! -f "$DAILY_AGGREGATE_FILE" ]]; then
        log_error "Daily aggregate file not found"
        return
    fi
    
    log "Aggregating hourly data into daily summary..."
    
    # Use jq to merge hourly data into daily aggregate
    if command -v jq &> /dev/null; then
        local hourly_data
        hourly_data=$(cat "$HOURLY_DATA_FILE")
        
        local updated_aggregate
        updated_aggregate=$(jq -s '
            .[0] as $daily |
            .[1] as $hourly |
            
            # Merge commands
            ($daily.commands + $hourly.commands) as $merged_cmds |
            ($merged_cmds | to_entries | group_by(.key) | map({
                key: .[0].key,
                value: (map(.value) | add)
            }) | from_entries) as $summed_cmds |
            
            # Merge tools (unique) - ONLY if active
            (if $hourly.is_active then ($daily.tools_used + $hourly.tools_used) else $daily.tools_used end | unique) as $merged_tools |
            
            # Merge projects (unique)
            (($daily.projects + $hourly.projects) | unique) as $merged_projects |
            
            # Add hour to collected hours
            ($daily.hours_collected + [$hourly.hour]) as $updated_hours |
            
            # Update active hours
            (if $hourly.is_active then ($daily.active_hours + 1) else $daily.active_hours end) as $updated_active |
            
            $daily |
            .commands = $summed_cmds |
            .tools_used = $merged_tools |
            .projects = $merged_projects |
            .hours_collected = $updated_hours |
            .active_hours = $updated_active
        ' "$DAILY_AGGREGATE_FILE" "$HOURLY_DATA_FILE") 
        
        echo "$updated_aggregate" > "$DAILY_AGGREGATE_FILE"
        log "Daily aggregate updated successfully"
    else
        log_error "jq not found - cannot aggregate data"
    fi
}

# ============================================================================
# Webhook Sending
# ============================================================================

send_daily_data() {
    if [[ ! -f "$DAILY_AGGREGATE_FILE" ]]; then
        log "No daily data to send"
        return
    fi
    
    log "Preparing to send daily data to DevLake webhook..."
    
    local daily_data
    daily_data=$(cat "$DAILY_AGGREGATE_FILE")
    
    # Extract key metrics for the payload
    local date
    date=$(echo "$daily_data" | jq -r '.date')
    local username
    username=$(get_username)
    
    # Build the final payload
    local payload
    payload=$(echo "$daily_data" | jq --arg dev "$username" '{
        date: .date,
        developer: $dev,
        metrics: {
            active_hours: .active_hours,
            tools_used: .tools_used,
            commands: .commands,
            projects: .projects
        }
    }')
    
    log "Sending payload to $DEVLAKE_WEBHOOK_URL"
    
    # Send to webhook
    local response
    if response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        -w "\n%{http_code}" \
        "$DEVLAKE_WEBHOOK_URL" 2>&1); then
        
        local http_code
        http_code=$(echo "$response" | tail -n1)
        
        if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            log "Successfully sent data to DevLake (HTTP $http_code)"
            
            # Update last send timestamp
            date '+%Y-%m-%d %H:%M:%S' > "$LAST_SEND_FILE"
            
            # Archive the sent data
            local archive_file="$DATA_DIR/archive/daily_${date}.json"
            mkdir -p "$DATA_DIR/archive"
            cp "$DAILY_AGGREGATE_FILE" "$archive_file"
            log "Archived data to $archive_file"
        else
            log_error "Failed to send data to DevLake (HTTP $http_code)"
        fi
    else
        log_error "Failed to send data to DevLake: $response"
    fi
}

should_send_daily_data() {
    # Send once per day at the first collection after midnight
    local current_hour
    current_hour=$(date '+%H')
    
    # Check if we've already sent today
    if [[ -f "$LAST_SEND_FILE" ]]; then
        local last_send_date
        last_send_date=$(date -r "$LAST_SEND_FILE" '+%Y-%m-%d' 2>/dev/null || echo "1970-01-01")
        local today
        today=$(date '+%Y-%m-%d')
        
        if [[ "$last_send_date" == "$today" ]]; then
            return 1  # Already sent today
        fi
    fi
    
    # Send if it's past midnight (first run of new day)
    return 0
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log "=== DevLake Telemetry Collector Starting ==="
    
    # Initialize
    init
    
    # Collect hourly data
    collect_hourly_data
    
    # Aggregate into daily summary
    aggregate_hourly_to_daily
    
    # Check if we should send daily data
    if should_send_daily_data; then
        send_daily_data
    else
        log "Daily data already sent today, skipping webhook call"
    fi
    
    log "=== DevLake Telemetry Collector Finished ==="
}

# Run main function
main "$@"
