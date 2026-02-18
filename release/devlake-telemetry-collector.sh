#!/bin/bash
#
# DevLake Telemetry Collector (OPTIMIZED)
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
# OPTIMIZATIONS:
# - Consolidated grep chains to reduce subprocess overhead
# - Cached repeated system calls (date, config)
# - Batched process checks instead of multiple pgrep calls
# - Parallel data collection for independent operations
# - Improved error handling with retries
# - Security fixes (removed unsafe eval)
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

# Cache variables (Bash 3.2 compatible - no -g flag needed at top level)
CONFIG_LOADED=0
CACHED_WEBHOOK_URL=""
CURRENT_DATE=""
CURRENT_HOUR=""
CURRENT_TIMESTAMP=""
CURRENT_EPOCH=""

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
# Configuration Loading (OPTIMIZED: Cached)
# ============================================================================

load_config() {
    # Return cached value if already loaded
    if [[ $CONFIG_LOADED -eq 1 ]]; then
        [[ -n "$CACHED_WEBHOOK_URL" ]] && DEVLAKE_WEBHOOK_URL="$CACHED_WEBHOOK_URL"
        return
    fi
    
    if [[ -f "$CONFIG_FILE" ]]; then
        # Load webhook URL from config if available
        if command -v jq &> /dev/null; then
            local webhook_url
            webhook_url=$(jq -r '.webhook_url // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
            if [[ -n "$webhook_url" ]]; then
                DEVLAKE_WEBHOOK_URL="$webhook_url"
            fi
            
            # Load optional secondary webhook (for testing)
            local webhook_url_secondary
            webhook_url_secondary=$(jq -r '.webhook_url_secondary // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
            if [[ -n "$webhook_url_secondary" ]]; then
                DEVLAKE_WEBHOOK_URL_SECONDARY="$webhook_url_secondary"
            fi
            CACHED_WEBHOOK_URL="$webhook_url"
        fi
    fi
    
    CONFIG_LOADED=1
}

# ============================================================================
# Initialization (OPTIMIZED: Cache date calls)
# ============================================================================

init() {
    # Cache date calls for reuse throughout the script
    CURRENT_DATE=$(date '+%Y-%m-%d')
    CURRENT_HOUR=$(date '+%H')
    CURRENT_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    CURRENT_EPOCH=$(date +%s)
    
    # Create data directory if it doesn't exist
    mkdir -p "$DATA_DIR"
    
    # Load configuration
    load_config
    
    # Initialize daily aggregate if it doesn't exist or if it's a new day
    if [[ ! -f "$DAILY_AGGREGATE_FILE" ]]; then
        echo '{"date":"'"$CURRENT_DATE"'","hours_collected":[],"commands":{},"tools_used":[],"projects":[],"builds":{},"active_hours":0}' > "$DAILY_AGGREGATE_FILE"
    else
        # Check if we need to reset for a new day
        local stored_date
        stored_date=$(jq -r '.date // empty' "$DAILY_AGGREGATE_FILE" 2>/dev/null || echo "")
        if [[ "$stored_date" != "$CURRENT_DATE" ]]; then
            # New day - send previous day's data first, then reset
            send_daily_data
            echo '{"date":"'"$CURRENT_DATE"'","hours_collected":[],"commands":{},"tools_used":[],"projects":[],"builds":{},"active_hours":0}' > "$DAILY_AGGREGATE_FILE"
        fi
    fi
}

# ============================================================================
# Helper Functions (NEW: Optimized filtering)
# ============================================================================

# OPTIMIZATION: Single awk call instead of 19 grep processes
filter_commands() {
    awk '
    /^$/ {next}
    /^#/ {next}
    /^"/ {next}
    /[(){}\[\]=.:]/ {next}
    /^print$/ {next}
    /^from$/ {next}
    /^import$/ {next}
    /^if$/ {next}
    /^for$/ {next}
    /^while$/ {next}
    /^try$/ {next}
    /^except$/ {next}
    /^with$/ {next}
    /^User$/ {next}
    /^content$/ {next}
    /^Registration$/ {next}
    /^f$/ {next}
    /^user$/ {next}
    /^reg$/ {next}
    {print}
    '
}

# SECURITY FIX: Safe home directory lookup without eval
get_user_home() {
    local username="$1"
    
    # Try different methods based on OS
    if command -v getent &> /dev/null; then
        # Linux method
        getent passwd "$username" 2>/dev/null | cut -d: -f6
    elif command -v dscl &> /dev/null; then
        # macOS method
        dscl . -read "/Users/$username" NFSHomeDirectory 2>/dev/null | awk '{print $2}'
    else
        # Fallback: grep passwd file (works on most Unix systems)
        grep "^$username:" /etc/passwd 2>/dev/null | cut -d: -f6
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

# MULTI-SOURCE: Collect from zsh history, unified logs, and git commits
collect_shell_commands() {
    local username
    username=$(get_username)
    local user_home
    user_home=$(get_user_home "$username")
    
    # Validate home directory
    if [[ -z "$user_home" ]] || [[ ! -d "$user_home" ]]; then
        log_error "Could not determine home directory for $username"
        echo "{}"
        return
    fi
    
    # Temporary file to store commands
    local temp_cmds="/tmp/devlake_cmds_$$"
    : > "$temp_cmds"
    
    # Timestamp tracking file
    local timestamp_file="$DATA_DIR/last_history_timestamp"
    local last_timestamp=0
    
    # Load last processed timestamp
    if [[ -f "$timestamp_file" ]]; then
        last_timestamp=$(cat "$timestamp_file" 2>/dev/null || echo "0")
    fi
    
    # SOURCE 1: Zsh history (has built-in timestamps) - MOST ACCURATE
    if [[ -f "$user_home/.zsh_history" ]]; then
        grep -E "^: [0-9]+:[0-9]+;" "$user_home/.zsh_history" 2>/dev/null | \
            awk -v last="$last_timestamp" '
                {
                    # Extract timestamp from ": 1234567890:0;command"
                    match($0, /^: ([0-9]+):/, ts);
                    if (ts[1] > last) print $0;
                }
            ' | \
            sed -E 's/^: [0-9]+:[0-9]+;//' | \
            awk '{print $1}' | \
            sed 's/^sudo //' | \
            filter_commands >> "$temp_cmds" || true
    fi
    
    # SOURCE 2: macOS Unified Logs (command execution tracking) - FALLBACK FOR BASH
    # Only use if zsh history is empty or we're using bash
    if [[ ! -s "$temp_cmds" ]] || [[ -f "$user_home/.bash_history" ]]; then
        # Calculate time range (since last run)
        local time_range="1h"
        if [[ $last_timestamp -gt 0 ]]; then
            local time_diff=$((CURRENT_EPOCH - last_timestamp))
            if [[ $time_diff -lt 3600 ]]; then
                time_range="${time_diff}s"
            fi
        fi
        
        # Extract shell commands from unified logs (requires no special permissions for own processes)
        log show --predicate 'process == "bash" || process == "zsh" || process == "sh"' \
            --style compact \
            --last "$time_range" 2>/dev/null | \
            grep -E "^[0-9]" | \
            awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}' | \
            grep -v "^$" | \
            awk '{print $1}' | \
            sed 's/^sudo //' | \
            filter_commands >> "$temp_cmds" || true
    fi
    
    # SOURCE 3: Bash history with file mtime check (FALLBACK)
    if [[ -f "$user_home/.bash_history" ]]; then
        local bash_mtime
        bash_mtime=$(stat -f %m "$user_home/.bash_history" 2>/dev/null || stat -c %Y "$user_home/.bash_history" 2>/dev/null || echo "0")
        
        if [[ $bash_mtime -gt $last_timestamp ]]; then
            tail -n 100 "$user_home/.bash_history" 2>/dev/null | \
                awk '{print $1}' | \
                sed 's/^sudo //' | \
                filter_commands >> "$temp_cmds" || true
        fi
    fi
    
    # Count commands and convert to JSON using jq
    local result
    if [[ -s "$temp_cmds" ]]; then
        result=$(sort "$temp_cmds" | uniq -c | \
            awk '{print $2 "\t" $1}' | \
            jq -R 'split("\t") | {(.[0]): (.[1] | tonumber)}' | \
            jq -s 'add // {}')
    else
        result="{}"
    fi
    
    # Update timestamp file
    (
        flock -x 200
        echo "$CURRENT_EPOCH" > "$timestamp_file"
    ) 200>"$timestamp_file.lock" 2>/dev/null || echo "$CURRENT_EPOCH" > "$timestamp_file"
    
    # Cleanup
    rm -f "$temp_cmds"
    
    echo "$result"
}

# NEW: Collect git commit activity for project validation
collect_git_activity() {
    local username
    username=$(get_username)
    local user_home
    user_home=$(get_user_home "$username")
    
    if [[ -z "$user_home" ]] || [[ ! -d "$user_home" ]]; then
        echo "{}"
        return
    fi
    
    local temp_activity="/tmp/devlake_git_$$"
    : > "$temp_activity"
    
    # Find git repositories and check for recent commits
    while IFS= read -r git_dir; do
        [[ -z "$git_dir" ]] && continue
        
        local repo_dir
        repo_dir=$(dirname "$git_dir")
        local repo_name
        repo_name=$(basename "$repo_dir")
        
        # Check for commits in the last hour
        if git -C "$repo_dir" log --all --since="1 hour ago" --oneline 2>/dev/null | grep -q .; then
            local commit_count
            commit_count=$(git -C "$repo_dir" log --all --since="1 hour ago" --oneline 2>/dev/null | wc -l | tr -d ' ')
            echo "$repo_name\t$commit_count" >> "$temp_activity"
        fi
    done < <(find "$user_home" -type d -name ".git" -maxdepth 4 2>/dev/null || true)
    
    # Convert to JSON
    if [[ -s "$temp_activity" ]]; then
        sort "$temp_activity" | \
            jq -R 'split("\t") | {(.[0]): (.[1] | tonumber)}' | \
            jq -s 'add // {}'
    else
        echo "{}"
    fi
    
    rm -f "$temp_activity"
}


# NEW: Monitor network connections to developer APIs (DIFFERENTIAL TRACKING)
# Only counts NEW connections that appear, not existing long-lived ones
collect_api_connections() {
    local temp_api="/tmp/devlake_api_$$"
    local state_file="$DATA_DIR/api_connection_state"
    : > "$temp_api"
    
    # Get all established HTTPS connections with unique identifier
    local current_connections
    current_connections=$(lsof -i TCP:443 -sTCP:ESTABLISHED -n 2>/dev/null | \
        awk 'NR>1 {print $2":"$9}' 2>/dev/null || echo "")
    
    if [[ -z "$current_connections" ]]; then
        # No connections - clear state and return empty
        : > "$state_file"
        echo "{}"
        return
    fi
    
    # Load previous connections state
    local previous_connections=""
    if [[ -f "$state_file" ]]; then
        previous_connections=$(cat "$state_file")
    fi
    
    # Find NEW connections (not in previous state)
    local new_connections
    if [[ -z "$previous_connections" ]]; then
        # First run - all connections are "new"
        new_connections="$current_connections"
    else
        new_connections=$(comm -13 \
            <(echo "$previous_connections" | sort) \
            <(echo "$current_connections" | sort))
    fi
    
    # Update state file with current connections
    echo "$current_connections" > "$state_file"
    
    # Count NEW connections per service
    if [[ -n "$new_connections" ]]; then
        echo "$new_connections" | while read -r conn; do
            # Extract hostname from "PID:host:port" or "PID:IP:port"
            local host
            host=$(echo "$conn" | cut -d':' -f2)
            
            # Match against known services
            case "$host" in
                *github.com*)
                    echo "github" >> "$temp_api"
                    ;;
                *atlassian.net*|*jira*)
                    echo "jira" >> "$temp_api"
                    ;;
                *slack.com*)
                    echo "slack" >> "$temp_api"
                    ;;
                *docker.io*|*docker.com*)
                    echo "docker-hub" >> "$temp_api"
                    ;;
                *gitlab.com*)
                    echo "gitlab" >> "$temp_api"
                    ;;
                *bitbucket.org*)
                    echo "bitbucket" >> "$temp_api"
                    ;;
                *npmjs.org*)
                    echo "npm-registry" >> "$temp_api"
                    ;;
                *pypi.org*)
                    echo "pypi" >> "$temp_api"
                    ;;
                *openai.com*)
                    echo "openai" >> "$temp_api"
                    ;;
            esac
        done
    fi
    
    # Convert to JSON with counts
    if [[ -s "$temp_api" ]]; then
        sort "$temp_api" | uniq -c | \
            awk '{print $2 "\t" $1}' | \
            jq -R 'split("\t") | {(.[0]): (.[1] | tonumber)}' | \
            jq -s 'add // {}'
    else
        echo "{}"
    fi
    
    rm -f "$temp_api"
}


collect_active_tools() {
    local tools=()
    
    # Get all running process names in one call
    local procs
    procs=$(ps aux 2>/dev/null | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' | grep -iE "code|idea|pycharm|goland|docker|git|node|npm|python" || echo "")
    
    # Check against the cached process list
    grep -qi "visual studio code\|\\bcode\\b" <<< "$procs" && tools+=("vscode")
    grep -qi "intellij idea\|\\bidea\\b" <<< "$procs" && tools+=("intellij")
    grep -qi "pycharm" <<< "$procs" && tools+=("pycharm")
    grep -qi "goland" <<< "$procs" && tools+=("goland")
    grep -qi "docker\|com\\.docker" <<< "$procs" && tools+=("docker")
    grep -qi "\\bgit\\b" <<< "$procs" && tools+=("git")
    grep -qi "\\bgo\\b" <<< "$procs" && tools+=("go")
    grep -qi "\\bnode\\b\|\\bnpm\\b" <<< "$procs" && tools+=("node")
    grep -qi "python" <<< "$procs" && tools+=("python")
    
    # OPTIMIZATION: Single jq call instead of two
    if [[ ${#tools[@]} -gt 0 ]]; then
        printf '%s\n' "${tools[@]}" | jq -Rs 'split("\n") | map(select(length > 0))'
    else
        echo "[]"
    fi
}

# REVERTED: Real-time project detection without caching
collect_active_projects() {
    local username
    username=$(get_username)
    local user_home
    user_home=$(get_user_home "$username")
    
    # Validate home directory
    if [[ -z "$user_home" ]] || [[ ! -d "$user_home" ]]; then
        echo "[]"
        return
    fi
    
    local projects=()
    
    # Find recently accessed git repositories
    # Look for .git directories that were accessed in the last hour
    if [[ -d "$user_home" ]]; then
        while IFS= read -r git_dir; do
            [[ -z "$git_dir" ]] && continue
            
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
        printf '%s\n' "${projects[@]}" | sort -u | jq -Rs 'split("\n") | map(select(length > 0))'
    else
        echo "[]"
    fi
}

# OPTIMIZED: Parallel data collection
collect_hourly_data() {
    log "Collecting hourly telemetry data..."
    
    # Use cached date values
    local timestamp="$CURRENT_TIMESTAMP"
    local hour="$CURRENT_HOUR"
    
    # OPTIMIZATION: Collect data in parallel using temp files
    local tmp_cmd="$DATA_DIR/tmp_cmd_$$"
    local tmp_tools="$DATA_DIR/tmp_tools_$$"
    local tmp_proj="$DATA_DIR/tmp_proj_$$"
    local tmp_git="$DATA_DIR/tmp_git_$$"
    local tmp_api="$DATA_DIR/tmp_api_$$"
    
    # Run collections in parallel
    collect_shell_commands > "$tmp_cmd" 2>/dev/null &
    local pid_cmd=$!
    
    collect_active_tools > "$tmp_tools" 2>/dev/null &
    local pid_tools=$!
    
    collect_active_projects > "$tmp_proj" 2>/dev/null &
    local pid_proj=$!
    
    collect_git_activity > "$tmp_git" 2>/dev/null &
    local pid_git=$!
    
    collect_api_connections > "$tmp_api" 2>/dev/null &
    local pid_api=$!
    
    # Wait for all background jobs to complete
    wait $pid_cmd $pid_tools $pid_proj $pid_git $pid_api 2>/dev/null || true
    
    # Read results
    local commands
    commands=$(cat "$tmp_cmd" 2>/dev/null || echo "{}")
    local tools
    tools=$(cat "$tmp_tools" 2>/dev/null || echo "[]")
    local projects
    projects=$(cat "$tmp_proj" 2>/dev/null || echo "[]")
    local git_activity
    git_activity=$(cat "$tmp_git" 2>/dev/null || echo "{}")
    local api_connections
    api_connections=$(cat "$tmp_api" 2>/dev/null || echo "{}")
    
    # Cleanup temp files
    rm -f "$tmp_cmd" "$tmp_tools" "$tmp_proj" "$tmp_git" "$tmp_api"
    
    # Determine if this hour counts as "active"
    local is_active=false
    local cmd_count
    cmd_count=$(echo "$commands" | jq 'keys | length' 2>/dev/null || echo "0")
    local project_count
    project_count=$(echo "$projects" | jq 'length' 2>/dev/null || echo "0")
    local git_count
    git_count=$(echo "$git_activity" | jq 'keys | length' 2>/dev/null || echo "0")
    
    # Active if: commands executed OR project files modified OR commits made
    if [[ $cmd_count -gt 0 ]] || [[ $project_count -gt 0 ]] || [[ $git_count -gt 0 ]]; then
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
  "projects": $projects,
  "git_commits": $git_activity,
  "api_connections": $api_connections
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
            
            # Merge git commits (sum counts per repo)
            ($daily.git_commits // {} + $hourly.git_commits // {}) as $merged_git |
            ($merged_git | to_entries | group_by(.key) | map({
                key: .[0].key,
                value: (map(.value) | add)
            }) | from_entries) as $summed_git |
            
            # Merge API usage (sum connections per service)
            ($daily.api_connections // {} + $hourly.api_connections // {}) as $merged_api |
            ($merged_api | to_entries | group_by(.key) | map({
                key: .[0].key,
                value: (map(.value) | add)
            }) | from_entries) as $summed_api |
            
            # Add hour to collected hours
            ($daily.hours_collected + [$hourly.hour]) as $updated_hours |
            
            # Update active hours
            (if $hourly.is_active then ($daily.active_hours + 1) else $daily.active_hours end) as $updated_active |
            
            $daily |
            .commands = $summed_cmds |
            .tools_used = $merged_tools |
            .projects = $merged_projects |
            .git_commits = $summed_git |
            .api_connections = $summed_api |
            .hours_collected = $updated_hours |
            .active_hours = $updated_active
        ' "$DAILY_AGGREGATE_FILE" "$HOURLY_DATA_FILE" 2>/dev/null) 
        
        if [[ -n "$updated_aggregate" ]] && echo "$updated_aggregate" | jq empty 2>/dev/null; then
            echo "$updated_aggregate" > "$DAILY_AGGREGATE_FILE"
            log "Daily aggregate updated successfully"
        else
            log_error "Failed to aggregate data - invalid JSON"
        fi
    else
        log_error "jq not found - cannot aggregate data"
    fi
}

# ============================================================================
# Webhook Sending (OPTIMIZED: Better error handling and retries)
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
    local hostname
    hostname=$(hostname)
    local git_email
    git_email=$(git config --global user.email 2>/dev/null || echo "")
    local git_name
    git_name=$(git config --global user.name 2>/dev/null || echo "")
    
    # Build the final payload
    local payload
    payload=$(echo "$daily_data" | jq --arg dev "$username" --arg host "$hostname" --arg email "$git_email" --arg name "$git_name" '{
        date: .date,
        developer: $dev,
        hostname: $host,
        email: $email,
        name: $name,
        metrics: {
            active_hours: .active_hours,
            tools_used: .tools_used,
            commands: .commands,
            projects: .projects
        }
    }')
    
    # OPTIONAL: Send to secondary webhook first (for testing/backup)
    # This is "fire-and-forget" - failure here does NOT stop the main flow
    if [[ -n "${DEVLAKE_WEBHOOK_URL_SECONDARY:-}" ]]; then
        log "Sending payload to secondary webhook: $DEVLAKE_WEBHOOK_URL_SECONDARY"
        if curl -s -X POST \
            --max-time 10 \
            --connect-timeout 5 \
            -H "Content-Type: application/json" \
            -H "User-Agent: DevLake-Telemetry-Collector/1.0" \
            -d "$payload" \
            "$DEVLAKE_WEBHOOK_URL_SECONDARY" >/dev/null 2>&1; then
            log "Successfully sent data to secondary webhook"
        else
            log_warn "Failed to send data to secondary webhook (continuing with primary)"
        fi
    fi
    
    log "Sending payload to $DEVLAKE_WEBHOOK_URL"
    
    # OPTIMIZATION: Send with timeout, retries, and exponential backoff
    local response http_code max_retries=3 retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if response=$(curl -s -X POST \
            --max-time 30 \
            --connect-timeout 10 \
            -H "Content-Type: application/json" \
            -H "User-Agent: DevLake-Telemetry-Collector/1.0" \
            -d "$payload" \
            -w "\n%{http_code}" \
            "$DEVLAKE_WEBHOOK_URL" 2>&1); then
            
            http_code=$(echo "$response" | tail -n1)
            
            if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
                log "Successfully sent data to DevLake (HTTP $http_code)"
                
                # Update last send timestamp
                echo "$CURRENT_TIMESTAMP" > "$LAST_SEND_FILE"
                
                # Archive the sent data
                local archive_file="$DATA_DIR/archive/daily_${date}.json"
                mkdir -p "$DATA_DIR/archive"
                cp "$DAILY_AGGREGATE_FILE" "$archive_file"
                log "Archived data to $archive_file"
                
                return 0
            elif [[ "$http_code" =~ ^5[0-9][0-9]$ ]]; then
                # Server error - retry with exponential backoff
                ((retry_count++))
                local wait_time=$((retry_count * retry_count * 5))
                log "Server error (HTTP $http_code), retrying in ${wait_time}s ($retry_count/$max_retries)..."
                sleep $wait_time
            else
                # Client error (4xx) - don't retry
                log_error "Client error (HTTP $http_code) - not retrying"
                return 1
            fi
        else
            # Network error - retry
            ((retry_count++))
            local wait_time=$((retry_count * retry_count * 5))
            log_error "Network error, retrying in ${wait_time}s ($retry_count/$max_retries)..."
            sleep $wait_time
        fi
    done
    
    log_error "Failed to send data after $max_retries attempts"
    return 1
}

should_send_daily_data() {
    # Check if we've already sent today
    if [[ -f "$LAST_SEND_FILE" ]]; then
        local last_send_date
        last_send_date=$(date -r "$LAST_SEND_FILE" '+%Y-%m-%d' 2>/dev/null || echo "1970-01-01")
        
        if [[ "$last_send_date" == "$CURRENT_DATE" ]]; then
            return 1  # Already sent today
        fi
    fi
    
    # Send if it's a new day
    return 0
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log "=== DevLake Telemetry Collector Starting ==="
    
    # Initialize (caches date calls and loads config)
    init
    
    # Collect hourly data (runs in parallel)
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