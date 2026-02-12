# Command Deduplication Fix

## Problem
The collector was reading the "last 1000 lines" of shell history on every run, causing:
1. **Duplicate Counts**: Same commands counted across multiple days
2. **Static Metrics**: Command counts remained identical (e.g., `cd: 213` for 3 consecutive days)
3. **Privacy Leaks**: Python code snippets like `user.set_password()` were getting through

## Solution

### Timestamp-Based Filtering
- **New File**: `$DATA_DIR/last_history_timestamp` stores the Unix timestamp of the last processing run
- **Zsh History**: Uses built-in timestamps (`: 1234567890:0;command` format) to filter only new entries
- **Bash History**: Checks file modification time; only processes if file changed since last run

### Strengthened Privacy Filters
Added filters for:
- Any line containing `.` (dot) - blocks method calls like `.save()`, `.create()`
- Any line containing `:` (colon) - blocks Python assignments like `user=User.objects.create(...)`
- Specific keywords: `Registration`, `f$` (file handles), `user$`, `reg$`

## Impact
- **Accurate Daily Counts**: Each day now shows only commands executed that day
- **No Duplicates**: Historical commands are not re-counted
- **Better Privacy**: Code snippets are now blocked effectively

## Migration
On first run with this update, the script will create `last_history_timestamp` with the current time, so the first post-update run will show minimal commands (since last hour only). Subsequent runs will accumulate properly.
