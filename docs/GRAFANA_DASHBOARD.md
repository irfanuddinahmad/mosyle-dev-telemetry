# Grafana Dashboard Guide

**Dashboard**: Developer Telemetry  
**File**: `DeveloperTelemetry.json` (in DevLake repository)  
**Location**: `incubator-devlake/grafana/dashboards/DeveloperTelemetry.json`  
**Datasource**: MySQL

## Overview

The Developer Telemetry dashboard provides comprehensive visualizations of developer productivity metrics collected by the telemetry system. It includes 13 panels covering active hours, git activity, code churn, testing practices, and productivity summaries.

## Dashboard Panels

### Time Series Visualizations

1. **Active Hours by Developer**
   - Shows daily active hours trends for all developers
   - Useful for identifying productivity patterns and workload distribution

2. **Total Commits by Developer**
   - Tracks commit activity over time
   - Helps identify high-activity periods and code delivery trends

3. **Daily Commits - Top 10 Developers**
   - Focuses on the most active contributors
   - Reduces clutter by showing only top 10 by total commits
   - Good for spotting productivity leaders

4. **Code Churn - Lines Added vs Deleted**
   - Visualizes the balance between additions (green) and deletions (red)
   - Helps understand code evolution and refactoring patterns

5. **Test Runs Detected**
   - Shows testing activity over time
   - Indicates which developers run tests most frequently
   - Useful for assessing testing culture

### Bar Charts

6. **Total Lines Added by Developer**
   - Horizontal bar chart of total lines added
   - Quickly identifies who's writing the most code

7. **Total Active Hours by Developer**
   - Horizontal bar chart of cumulative active hours
   - Shows who's spending the most time coding

8. **Average Active Hours by Day of Week**
   - Reveals team patterns (e.g., lower activity on Fridays)
   - Helps identify optimal meeting days

### Summary Table

9. **Developer Productivity Summary**
   - Comprehensive table with all key metrics per developer
   - Columns: developer_id, name, email, commits, lines added/deleted, avg hours, total hours
   - Sortable by any column
   - Color-coded cells for quick visual scanning

### Stat Panels

10. **Total Commits** - Single number showing team-wide commits
11. **Total Active Hours** - Team-wide active coding hours
12. **Total Lines Added** - Cumulative lines of code added
13. **Active Developers** - Count of unique developers

## Importing the Dashboard

### Method 1: Import via UI

1. **Access Grafana**:
   - Navigate to `https://your-devlake-instance.com/grafana/`
   - Login: `admin` / `admin` (or your configured credentials)

2. **Navigate to Import**:
   - Click **Dashboards** (sidebar)
   - Click **Import**

3. **Upload Dashboard**:
   - Click **Upload JSON file**
   - Select `DeveloperTelemetry.json` from your local copy
   - **OR** paste the JSON content directly into the text area

4. **Configure Options**:
   - **Dashboard Name**: Keep as "Developer Telemetry" or customize
   - **Folder**: Select a folder or leave as "General"
   - **UID**: Keep existing UID (`developer-telemetry`) or let Grafana generate new one
   - **Datasource**: Select your MySQL datasource (usually auto-selected)

5. **Import**:
   - Click **Import**
   - Dashboard will load with your data

### Method 2: Copy-Paste JSON

1. **Copy Dashboard JSON**:
   ```bash
   # From DevLake repository
   cat incubator-devlake/grafana/dashboards/DeveloperTelemetry.json | pbcopy
   ```

2. **Import in Grafana**:
   - Grafana UI → Dashboards → Import
   - Paste JSON into text area
   - Click **Load**
   - Configure datasource (MySQL)
   - Click **Import**

### Method 3: Auto-provisioning (Production)

For production deployments, configure Grafana to auto-load the dashboard on startup:

1. **Edit docker-compose.yml**:
   ```yaml
   grafana:
     image: devlake.docker.scarf.sh/apache/devlake-dashboard:latest
     volumes:
       - grafana-storage:/var/lib/grafana
       - ./grafana/dashboards:/etc/grafana/provisioning/dashboards
       - ./grafana/provisioning:/etc/grafana/provisioning
   ```

2. **Create provisioning config**:
   File: `grafana/provisioning/dashboards/devlake.yaml`
   ```yaml
   apiVersion: 1
   providers:
     - name: 'DevLake Dashboards'
       orgId: 1
       folder: 'DevLake'
       type: file
       disableDeletion: false
       updateIntervalSeconds: 10
       allowUiUpdates: true
       options:
         path: /etc/grafana/provisioning/dashboards
   ```

3. **Restart Grafana**:
   ```bash
   docker-compose restart grafana
   ```

## Customizing the Dashboard

### Changing Time Range

Default: **Last 6 weeks** (`now-6w` to `now`)

To change:
1. Click **Time range picker** (top right)
2. Select preset (Last 7 days, Last 30 days, etc.)
3. **OR** use custom: `now-3M` to `now` for 3 months

To change default:
1. **Dashboard Settings** (gear icon, top right)
2. **General** → **Time options**
3. Set **From**: `now-3M` and **To**: `now`
4. **Save dashboard**

### Filtering by Developer

Add a template variable:

1. **Dashboard Settings** → **Variables**
2. **Add variable**:
   - **Name**: `developer`
   - **Type**: Query
   - **Data source**: MySQL
   - **Query**:
     ```sql
     SELECT DISTINCT developer_id
     FROM _tool_developer_metrics
     WHERE connection_id = 2
     ORDER BY developer_id
     ```
   - **Multi-value**: Yes
   - **Include All option**: Yes

3. **Update panel queries** to use `$developer`:
   ```sql
   WHERE connection_id = 2
     AND $__timeFilter(date)
     AND developer_id IN ($developer)
   ```

4. **Save dashboard**

5. **Use filter**: Dropdown will appear at top of dashboard

### Adjusting Top 10 Limit

For "Daily Commits - Top 10 Developers":

1. **Edit panel** (click title → Edit)
2. **Update query**:
   ```sql
   -- Change LIMIT 10 to desired number
   LIMIT 15  -- Show top 15 instead
   ```
3. **Apply** → **Save**

### Changing Connection ID

If using a different connection:

1. **Dashboard Settings** → **JSON Model**
2. **Search and replace**: `"connection_id = 2"` → `"connection_id = YOUR_ID"`
3. **Save changes**
4. **Save dashboard**

## Common Queries

### Query Structure for Time Series

```sql
SELECT
  UNIX_TIMESTAMP(date) as time_sec,
  developer_id as metric,
  CAST(JSON_EXTRACT(git_activity, '$.total_commits') AS UNSIGNED) as value
FROM _tool_developer_metrics
WHERE connection_id = 2
  AND $__timeFilter(date)
ORDER BY time_sec
```

**Key Points**:
- `UNIX_TIMESTAMP(date) as time_sec` - Required for time series
- `developer_id as metric` - Creates separate series per developer
- `CAST(...AS UNSIGNED)` - Ensures numeric values from JSON
- `$__timeFilter(date)` - Grafana macro for time range filtering

### Query Structure for Bar Charts

```sql
SELECT
  developer_id,
  CAST(SUM(JSON_EXTRACT(git_activity, '$.total_lines_added')) AS UNSIGNED) as lines_added
FROM _tool_developer_metrics
WHERE connection_id = 2
  AND $__timeFilter(date)
GROUP BY developer_id
ORDER BY lines_added DESC
LIMIT 15
```

### Query Structure for Tables

```sql
SELECT
  developer_id,
  name,
  email,
  SUM(CAST(JSON_EXTRACT(git_activity, '$.total_commits') AS UNSIGNED)) as total_commits,
  SUM(CAST(JSON_EXTRACT(git_activity, '$.total_lines_added') AS UNSIGNED)) as total_lines_added,
  SUM(CAST(JSON_EXTRACT(git_activity, '$.total_lines_deleted') AS UNSIGNED)) as total_lines_deleted,
  AVG(active_hours) as avg_active_hours,
  SUM(active_hours) as total_active_hours
FROM _tool_developer_metrics
WHERE connection_id = 2
  AND $__timeFilter(date)
GROUP BY developer_id, name, email
ORDER BY total_commits DESC
```

## Troubleshooting

### Problem: "No Data" in All Panels

**Causes**:
1. No data in database
2. Wrong connection_id
3. Time range doesn't match data dates
4. MySQL datasource not configured

**Solutions**:
1. **Verify data exists**:
   ```sql
   SELECT COUNT(*) FROM _tool_developer_metrics WHERE connection_id = 2;
   ```

2. **Check date range**:
   ```sql
   SELECT MIN(date), MAX(date)
   FROM _tool_developer_metrics
   WHERE connection_id = 2;
   ```

3. **Verify connection_id** in dashboard queries

4. **Check datasource**: Dashboard Settings → Variables → Datasource

### Problem: "Data is missing a number field"

**Cause**: Time series query not returning proper numeric `value` column

**Solution**: Ensure `CAST(...AS UNSIGNED)` is used for JSON extractions:
```sql
CAST(JSON_EXTRACT(git_activity, '$.total_commits') AS UNSIGNED) as value
```

### Problem: Pie Chart Showing Yellow Circle

**Cause**: Grafana pie charts have strict data format requirements

**Solution**: Use horizontal bar chart instead (already implemented in current dashboard)

### Problem: Panel Shows "N/A" or Empty

**Causes**:
1. Query returns NULL values
2. JSON field is empty for all records
3. Time filter excludes all data

**Solutions**:
1. **Add COALESCE** to handle NULLs:
   ```sql
   COALESCE(JSON_EXTRACT(...), 0) as value
   ```

2. **Check raw data**:
   ```sql
   SELECT git_activity FROM _tool_developer_metrics LIMIT 5;
   ```

3. **Widen time range** to "Last 90 days"

### Problem: Too Many Developers, Chart is Cluttered

**Solution**: Use panel filters or create dashboard variables

**Option 1**: Limit in query
```sql
-- Show top 10 by commits
WHERE developer_id IN (
  SELECT developer_id
  FROM _tool_developer_metrics
  WHERE connection_id = 2
  GROUP BY developer_id
  ORDER BY SUM(CAST(JSON_EXTRACT(git_activity, '$.total_commits') AS UNSIGNED)) DESC
  LIMIT 10
)
```

**Option 2**: Add dashboard variable (see Customizing section above)

## Performance Optimization

### For Large Datasets (1000+ records)

1. **Add indexes** to MySQL:
   ```sql
   CREATE INDEX idx_dev_date ON _tool_developer_metrics(developer_id, date);
   CREATE INDEX idx_conn_date ON _tool_developer_metrics(connection_id, date);
   ```

2. **Use sampling** for very long time ranges:
   ```sql
   -- Sample every 7th day for yearly view
   WHERE connection_id = 2
     AND $__timeFilter(date)
     AND DAY(date) % 7 = 0
   ```

3. **Set reasonable default time range**: 6 weeks instead of "All time"

## Exporting and Sharing

### Export Dashboard JSON

1. **Dashboard Settings** → **JSON Model**
2. **Copy to Clipboard**
3. Save to file or share with team

### Share Dashboard Link

1. **Share button** (top right)
2. **Link** tab
3. **Copy Link**
4. **Optional**: Enable "Lock time range" to share specific date range

### Create Dashboard Snapshot

1. **Share button** → **Snapshot**
2. **Local Snapshot** (stores on Grafana instance)
3. **Publish to snapshot.raintank.io** (public sharing)
4. Copy snapshot URL

## See Also

- [PLUGIN_SPEC.md](PLUGIN_SPEC.md) - Data model and API reference
- [ACTIVITY_DETECTION.md](ACTIVITY_DETECTION.md) - How metrics are collected
- [API_AUTHENTICATION.md](API_AUTHENTICATION.md) - Connection and API key setup
- Grafana Documentation: https://grafana.com/docs/grafana/latest/
- Grafana MySQL Datasource: https://grafana.com/docs/grafana/latest/datasources/mysql/
