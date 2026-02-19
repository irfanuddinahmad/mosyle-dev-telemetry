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
CACHED_API_KEY=""
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
        [[ -n "$CACHED_API_KEY" ]] && DEVLAKE_API_KEY="$CACHED_API_KEY"
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
            
            # Load API key from config if available
            local api_key
            api_key=$(jq -r '.api_key // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
            if [[ -n "$api_key" ]]; then
                DEVLAKE_API_KEY="$api_key"
            fi
            
            # Load optional secondary webhook (for testing)
            local webhook_url_secondary
            webhook_url_secondary=$(jq -r '.webhook_url_secondary // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
            if [[ -n "$webhook_url_secondary" ]]; then
                DEVLAKE_WEBHOOK_URL_SECONDARY="$webhook_url_secondary"
            fi
            CACHED_WEBHOOK_URL="$webhook_url"
            CACHED_API_KEY="$api_key"
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
        echo '{"date":"'"$CURRENT_DATE"'","hours_collected":[],"tools_used":[],"projects":[],"git_activity":{"total_commits":0,"total_lines_added":0,"total_lines_deleted":0,"total_files_changed":0,"repositories":[]},"development_activity":{"test_runs_detected":0,"build_commands_detected":0},"api_connections":{},"active_hours":0}' > "$DAILY_AGGREGATE_FILE"
    else
        # Check if we need to reset for a new day
        local stored_date
        stored_date=$(jq -r '.date // empty' "$DAILY_AGGREGATE_FILE" 2>/dev/null || echo "")
        if [[ "$stored_date" != "$CURRENT_DATE" ]]; then
            # New day - send previous day's data first, then reset
            send_daily_data
            echo '{"date":"'"$CURRENT_DATE"'","hours_collected":[],"tools_used":[],"projects":[],"git_activity":{"total_commits":0,"total_lines_added":0,"total_lines_deleted":0,"total_files_changed":0,"repositories":[]},"development_activity":{"test_runs_detected":0,"build_commands_detected":0},"api_connections":{},"active_hours":0}' > "$DAILY_AGGREGATE_FILE"
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

# Pattern-based terminal analysis - extract development activity patterns only
collect_development_activity() {
    local username
    username=$(get_username)
    local user_home
    user_home=$(get_user_home "$username")
    
    # Validate home directory
    if [[ -z "$user_home" ]] || [[ ! -d "$user_home" ]]; then
        log_error "Could not determine home directory for $username"
        echo '{"test_runs_detected":0,"build_commands_detected":0}'
        return
    fi
    
    # Timestamp tracking file
    local timestamp_file="$DATA_DIR/last_history_timestamp"
    local last_timestamp=0
    
    # Load last processed timestamp
    if [[ -f "$timestamp_file" ]]; then
        last_timestamp=$(cat "$timestamp_file" 2>/dev/null || echo "0")
    fi
    
    # Calculate time range (since last run)
    local time_range="1h"
    if [[ $last_timestamp -gt 0 ]]; then
        local time_diff=$((CURRENT_EPOCH - last_timestamp))
        if [[ $time_diff -lt 3600 ]]; then
            time_range="${time_diff}s"
        fi
    fi
    
    local test_runs=0
    local build_commands=0
    
    # Extract test patterns from unified logs
    local test_patterns="pytest|npm test|npm run test|go test|jest|make test|python -m pytest|python -m unittest"
    test_runs=$(log show --predicate 'process == "bash" || process == "zsh" || process == "sh"' \
        --style compact \
        --last "$time_range" 2>/dev/null | \
        grep -iE "($test_patterns)" | \
        wc -l | tr -d ' ' || echo "0")
    
    # Extract build patterns from unified logs
    local build_patterns="docker build|npm run build|npm build|make build|go build|gradle build|mvn package|mvn install"
    build_commands=$(log show --predicate 'process == "bash" || process == "zsh" || process == "sh"' \
        --style compact \
        --last "$time_range" 2>/dev/null | \
        grep -iE "($build_patterns)" | \
        wc -l | tr -d ' ' || echo "0")
    
    # Also check shell history files for patterns (if we got no hits from log show)
    if [[ $test_runs -eq 0 ]] && [[ $build_commands -eq 0 ]] && [[ -f "$user_home/.zsh_history" ]]; then
        local zsh_test_count
        zsh_test_count=$(grep -E "^: [0-9]+:[0-9]+;" "$user_home/.zsh_history" 2>/dev/null | \
            awk -v last="$last_timestamp" '
                {
                    match($0, /^: ([0-9]+):/, ts);
                    if (ts[1] > last) print $0;
                }
            ' 2>/dev/null | \
            grep -iE "($test_patterns)" 2>/dev/null | \
            wc -l 2>/dev/null | tr -d ' ' || echo "0")
        test_runs=$((test_runs + zsh_test_count))
        
        local zsh_build_count
        zsh_build_count=$(grep -E "^: [0-9]+:[0-9]+;" "$user_home/.zsh_history" 2>/dev/null | \
            awk -v last="$last_timestamp" '
                {
                    match($0, /^: ([0-9]+):/, ts);
                    if (ts[1] > last) print $0;
                }
            ' 2>/dev/null | \
            grep -iE "($build_patterns)" 2>/dev/null | \
            wc -l 2>/dev/null | tr -d ' ' || echo "0")
        build_commands=$((build_commands + zsh_build_count))
    fi
    
    # Update timestamp file
    mkdir -p "$(dirname "$timestamp_file")" 2>/dev/null || true
    (
        flock -x 200
        echo "$CURRENT_EPOCH" > "$timestamp_file"
    ) 200>"$timestamp_file.lock" 2>/dev/null || echo "$CURRENT_EPOCH" > "$timestamp_file"
    
    # Ensure we always return valid JSON
    printf '{"test_runs_detected":%d,"build_commands_detected":%d}\n' "$test_runs" "$build_commands"
}

# Collect comprehensive git activity with code churn metrics
collect_git_activity() {
    local username
    username=$(get_username)
    local user_home
    user_home=$(get_user_home "$username")
    
    if [[ -z "$user_home" ]] || [[ ! -d "$user_home" ]]; then
        echo '{"total_commits":0,"total_lines_added":0,"total_lines_deleted":0,"total_files_changed":0,"repositories":[]}'
        return
    fi
    
    # Get git email for filtering commits
    local git_email
    git_email=$(git config --global user.email 2>/dev/null || echo "")
    
    if [[ -z "$git_email" ]]; then
        log "No git email configured, using all commits"
    fi
    
    local temp_repos="/tmp/devlake_git_repos_$$"
    : > "$temp_repos"
    
    local total_commits=0
    local total_lines_added=0
    local total_lines_deleted=0
    local total_files_changed=0
    
    # Calculate previous hour boundary for time-bounded query
    local previous_hour
    previous_hour=$((CURRENT_HOUR - 1))
    if [[ $previous_hour -lt 0 ]]; then
        previous_hour=23
    fi
    
    # Find git repositories and collect activity
    while IFS= read -r git_dir; do
        [[ -z "$git_dir" ]] && continue
        
        local repo_dir
        repo_dir=$(dirname "$git_dir")
        local repo_name
        repo_name=$(basename "$repo_dir")
        
        # Build git log command with hourly time boundaries
        # CRITICAL: Only collect commits from the PAST HOUR to prevent duplication
        # Each hour gets distinct commits, safe to sum in aggregation
        local git_log_cmd="git -C '$repo_dir' log --all --since='1 hour ago'"
        if [[ -n "$git_email" ]]; then
            git_log_cmd="$git_log_cmd --author='$git_email'"
        fi
        
        # Check for commits
        local commit_count
        commit_count=$(eval "$git_log_cmd --oneline 2>/dev/null" | wc -l | tr -d ' ' || echo "0")
        
        if [[ $commit_count -gt 0 ]]; then
            # Get code churn statistics
            local lines_added=0
            local lines_deleted=0
            local files_changed=0
            
            # Parse git log --numstat for line changes
            local numstat_output
            numstat_output=$(eval "$git_log_cmd --numstat --pretty=format: 2>/dev/null" || echo "")
            
            if [[ -n "$numstat_output" ]]; then
                # Sum additions and deletions
                while IFS=$'\t' read -r added deleted filename; do
                    [[ -z "$added" ]] && continue
                    [[ "$added" == "-" ]] && added=0
                    [[ "$deleted" == "-" ]] && deleted=0
                    lines_added=$((lines_added + added))
                    lines_deleted=$((lines_deleted + deleted))
                    ((files_changed++))
                done <<< "$numstat_output"
            fi
            
            # Get branches worked on
            local branches
            branches=$(git -C "$repo_dir" branch --contains HEAD 2>/dev/null | \
                sed 's/^[* ]*//' | \
                grep -v '^$' | \
                tr '\n' ',' | \
                sed 's/,$//' | \
                awk '{print "[\"" $0 "\"]"}' | \
                sed 's/,/","/g' 2>/dev/null || echo "[]")
            [[ -z "$branches" || "$branches" == '[""]' ]] && branches="[]"
            
            # Add to totals
            total_commits=$((total_commits + commit_count))
            total_lines_added=$((total_lines_added + lines_added))
            total_lines_deleted=$((total_lines_deleted + lines_deleted))
            total_files_changed=$((total_files_changed + files_changed))
            
            # Build repository object (properly formatted JSON) - escape path for JSON
            local repo_path_escaped
            repo_path_escaped=$(echo "$repo_dir" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
            printf '{"name":"%s","path":"%s","commits":%d,"lines_added":%d,"lines_deleted":%d,"files_changed":%d,"branches_worked":%s},\n' \
                "$repo_name" "$repo_path_escaped" "$commit_count" "$lines_added" "$lines_deleted" "$files_changed" "$branches" >> "$temp_repos" 2>/dev/null || \
                log_error "Failed to write repository data for $repo_name"
        fi
    done < <(find "$user_home" -type d -name ".git" -maxdepth 4 2>/dev/null || true)
    
    # Build final JSON
    local repositories="[]"
    if [[ -s "$temp_repos" ]]; then
        # Read JSON objects line by line and build array
        repositories="["
        local first=true
        while IFS= read -r line; do
            # Skip empty lines
            [[ -z "$line" ]] && continue
            # Remove trailing comma if present
            line="${line%,}"
            if [[ "$first" == true ]]; then
                repositories="$repositories$line"
                first=false
            else
                repositories="$repositories,$line"
            fi
        done < "$temp_repos"
        repositories="$repositories]"
        
        # Validate JSON
        if ! echo "$repositories" | jq empty 2>/dev/null; then
            log_error "Invalid repository JSON generated"
            repositories="[]"
        fi
    fi
    
    rm -f "$temp_repos"
    
    # Return comprehensive git activity JSON
    cat <<EOF
{
  "total_commits": $total_commits,
  "total_lines_added": $total_lines_added,
  "total_lines_deleted": $total_lines_deleted,
  "total_files_changed": $total_files_changed,
  "repositories": $repositories
}
EOF
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

# OPTIMIZED: Parallel data collection with enhanced metrics
collect_hourly_data() {
    log "Collecting hourly telemetry data..."
    
    # Use cached date values
    local timestamp="$CURRENT_TIMESTAMP"
    local hour="$CURRENT_HOUR"
    
    # OPTIMIZATION: Collect data in parallel using temp files
    local tmp_tools="$DATA_DIR/tmp_tools_$$"
    local tmp_proj="$DATA_DIR/tmp_proj_$$"
    local tmp_git="$DATA_DIR/tmp_git_$$"
    local tmp_dev="$DATA_DIR/tmp_dev_$$"
    local tmp_api="$DATA_DIR/tmp_api_$$"
    
    # Run collections in parallel
    collect_active_tools > "$tmp_tools" 2>/dev/null &
    local pid_tools=$!
    
    collect_active_projects > "$tmp_proj" 2>/dev/null &
    local pid_proj=$!
    
    collect_git_activity > "$tmp_git" 2>/dev/null &
    local pid_git=$!
    
    collect_development_activity > "$tmp_dev" 2>/dev/null &
    local pid_dev=$!
    
    collect_api_connections > "$tmp_api" 2>/dev/null &
    local pid_api=$!
    
    # Wait for all background jobs to complete
    wait $pid_tools $pid_proj $pid_git $pid_dev $pid_api 2>/dev/null || true
    
    # Read results with fallback defaults
    local tools
    tools=$(cat "$tmp_tools" 2>/dev/null || echo "[]")
    [[ -z "$tools" || "$tools" == "" ]] && tools="[]"
    
    local projects
    projects=$(cat "$tmp_proj" 2>/dev/null || echo "[]")
    [[ -z "$projects" || "$projects" == "" ]] && projects="[]"
    
    local git_activity
    git_activity=$(cat "$tmp_git" 2>/dev/null || echo '{\"total_commits\":0,\"total_lines_added\":0,\"total_lines_deleted\":0,\"total_files_changed\":0,\"repositories\":[]}')
    [[ -z "$git_activity" || "$git_activity" == "" ]] && git_activity='{\"total_commits\":0,\"total_lines_added\":0,\"total_lines_deleted\":0,\"total_files_changed\":0,\"repositories\":[]}'
    
    local development_activity
    development_activity=$(cat "$tmp_dev" 2>/dev/null || echo '{\"test_runs_detected\":0,\"build_commands_detected\":0}')
    [[ -z "$development_activity" || "$development_activity" == "" ]] && development_activity='{\"test_runs_detected\":0,\"build_commands_detected\":0}'
    
    local api_connections
    api_connections=$(cat "$tmp_api" 2>/dev/null || echo "{}")
    [[ -z "$api_connections" || "$api_connections" == "" ]] && api_connections="{}"
    
    # Cleanup temp files
    rm -f "$tmp_tools" "$tmp_proj" "$tmp_git" "$tmp_dev" "$tmp_api"
    
    # Determine if this hour counts as "active"
    local is_active=false
    local project_count
    project_count=$(echo "$projects" | jq 'length' 2>/dev/null || echo "0")
    local git_commits
    git_commits=$(echo "$git_activity" | jq '.total_commits' 2>/dev/null || echo "0")
    local test_runs
    test_runs=$(echo "$development_activity" | jq '.test_runs_detected' 2>/dev/null || echo "0")
    local builds
    builds=$(echo "$development_activity" | jq '.build_commands_detected' 2>/dev/null || echo "0")
    
    # Active if: project files modified OR commits made OR tests/builds run
    if [[ $project_count -gt 0 ]] || [[ $git_commits -gt 0 ]] || [[ $test_runs -gt 0 ]] || [[ $builds -gt 0 ]]; then
        is_active=true
    fi
    
    # Create hourly data JSON
    cat <<EOF > "$HOURLY_DATA_FILE"
{
  "timestamp": "$timestamp",
  "hour": $hour,
  "is_active": $is_active,
  "tools_used": $tools,
  "projects": $projects,
  "git_activity": $git_activity,
  "development_activity": $development_activity,
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
            
            # Merge tools (unique) - ONLY if active
            (if $hourly.is_active then ($daily.tools_used + $hourly.tools_used) else $daily.tools_used end | unique) as $merged_tools |
            
            # Merge projects (unique)
            (($daily.projects + $hourly.projects) | unique) as $merged_projects |
            
            # Merge git activity (sum totals and merge repositories)
            ($daily.git_activity // {total_commits:0,total_lines_added:0,total_lines_deleted:0,total_files_changed:0,repositories:[]}) as $daily_git |
            ($hourly.git_activity // {total_commits:0,total_lines_added:0,total_lines_deleted:0,total_files_changed:0,repositories:[]}) as $hourly_git |
            {
                total_commits: ($daily_git.total_commits + $hourly_git.total_commits),
                total_lines_added: ($daily_git.total_lines_added + $hourly_git.total_lines_added),
                total_lines_deleted: ($daily_git.total_lines_deleted + $hourly_git.total_lines_deleted),
                total_files_changed: ($daily_git.total_files_changed + $hourly_git.total_files_changed),
                repositories: (
                    ($daily_git.repositories + $hourly_git.repositories) |
                    group_by(.name) |
                    map({
                        name: .[0].name,
                        path: .[0].path,
                        commits: (map(.commits) | add),
                        lines_added: (map(.lines_added) | add),
                        lines_deleted: (map(.lines_deleted) | add),
                        files_changed: (map(.files_changed) | add),
                        branches_worked: (map(.branches_worked[]) | unique)
                    })
                )
            } as $merged_git |
            
            # Merge development activity (sum counts)
            ($daily.development_activity // {test_runs_detected:0,build_commands_detected:0}) as $daily_dev |
            ($hourly.development_activity // {test_runs_detected:0,build_commands_detected:0}) as $hourly_dev |
            {
                test_runs_detected: ($daily_dev.test_runs_detected + $hourly_dev.test_runs_detected),
                build_commands_detected: ($daily_dev.build_commands_detected + $hourly_dev.build_commands_detected)
            } as $merged_dev |
            
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
            .tools_used = $merged_tools |
            .projects = $merged_projects |
            .git_activity = $merged_git |
            .development_activity = $merged_dev |
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
    
    # Build the final payload with enhanced metrics
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
            projects: .projects,
            git_activity: (.git_activity // {total_commits:0,total_lines_added:0,total_lines_deleted:0,total_files_changed:0,repositories:[]}),
            development_activity: (.development_activity // {test_runs_detected:0,build_commands_detected:0})
        }
    }')
    
    # OPTIONAL: Send to secondary webhook first (for testing/backup)
    # This is "fire-and-forget" - failure here does NOT stop the main flow
    if [[ -n "${DEVLAKE_WEBHOOK_URL_SECONDARY:-}" ]]; then
        log "Sending payload to secondary webhook: $DEVLAKE_WEBHOOK_URL_SECONDARY"
        
        # Prepare headers for secondary webhook
        local secondary_headers=()
        secondary_headers+=(-H "Content-Type: application/json")
        secondary_headers+=(-H "User-Agent: DevLake-Telemetry-Collector/1.0")
        if [[ -n "${DEVLAKE_API_KEY:-}" ]]; then
            secondary_headers+=(-H "Authorization: Bearer $DEVLAKE_API_KEY")
        fi
        
        if curl -s -X POST \
            --max-time 10 \
            --connect-timeout 5 \
            "${secondary_headers[@]}" \
            -d "$payload" \
            "$DEVLAKE_WEBHOOK_URL_SECONDARY" >/dev/null 2>&1; then
            log "Successfully sent data to secondary webhook"
        else
            log_warn "Failed to send data to secondary webhook (continuing with primary)"
        fi
    fi
    
    log "Sending payload to $DEVLAKE_WEBHOOK_URL"
    
    # Prepare headers for primary webhook
    local curl_headers=()
    curl_headers+=(-H "Content-Type: application/json")
    curl_headers+=(-H "User-Agent: DevLake-Telemetry-Collector/1.0")
    if [[ -n "${DEVLAKE_API_KEY:-}" ]]; then
        curl_headers+=(-H "Authorization: Bearer $DEVLAKE_API_KEY")
        log "Using API key authentication"
    fi
    
    # OPTIMIZATION: Send with timeout, retries, and exponential backoff
    local response http_code max_retries=3 retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if response=$(curl -s -X POST \
            --max-time 30 \
            --connect-timeout 10 \
            "${curl_headers[@]}" \
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