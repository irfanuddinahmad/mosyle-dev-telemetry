# DevLake Telemetry Collector for macOS

A transparent, privacy-safe telemetry system that captures developer productivity metrics and sends them to a DevLake webhook. Designed for deployment via Mosyle or direct installation.

## 🎯 What It Collects

### Git Activity
- **Commits**: Total daily commits with repository-level breakdown
- **Code Changes**: Lines added/deleted, files modified
- **Repository Details**: Per-repo activity with branch information
- **Activity Patterns**: When and where code is being written

### Development Activity
- **Test Runs**: Detected via terminal monitoring (pytest, npm test, go test, jest, etc.)
- **Build Commands**: npm run build, cargo build, go build, make, etc.
- **Development Practices**: Indicators of testing culture and build frequency

### Active Hours
- **Hourly Activity Detection**: Based on git commits, file changes, IDE activity, and dev commands
- **Daily Aggregation**: Total active coding hours per day
- **Privacy-Safe**: Measures development activity, not total work time
- **See**: [ACTIVITY_DETECTION.md](docs/ACTIVITY_DETECTION.md) for detailed methodology

### Tools & Context
- **Tools Used**: Running development tools (VSCode, IntelliJ, PyCharm, Docker, etc.)
- **Project Context**: Active git repositories and project names
- **Environment**: Hostname, developer ID, git identity

## ❌ What It Does NOT Collect

- ❌ Command arguments or parameters
- ❌ File paths or contents
- ❌ Code snippets or actual source code
- ❌ URLs or browsing history
- ❌ Personal or confidential data
- ❌ Keystrokes or screen captures

## 📂 Project Structure

- **`release/`**: Production-ready files for deployment
  - `devlake-telemetry-collector.sh`: Core data collection script
  - `install-telemetry.sh`: System installation script (requires sudo)
  - `install-telemetry-local.sh`: Local user installation (no sudo)
  - `uninstall-telemetry.sh`: Cleanup utility
  - `com.devlake.telemetry.plist`: LaunchDaemon configuration
  - `config.json`: Configuration file (webhook URL, API key)

- **`docs/`**: Comprehensive documentation
  - [PLUGIN_SPEC.md](docs/PLUGIN_SPEC.md): DevLake plugin API specification
  - [API_AUTHENTICATION.md](docs/API_AUTHENTICATION.md): How to get and use API keys
  - [GRAFANA_DASHBOARD.md](docs/GRAFANA_DASHBOARD.md): Dashboard import and usage guide
  - [ACTIVITY_DETECTION.md](docs/ACTIVITY_DETECTION.md): How active hours are measured
  - [DATA_COLLECTION_FLOW.md](docs/DATA_COLLECTION_FLOW.md): Internal collection logic
  - [LOCAL_TESTING.md](LOCAL_TESTING.md): Local development and testing setup

- **`generate_fake_data.py`**: Generate realistic test data for dashboard development
  - Creates data for 15 developers with varied productivity levels
  - Supports custom date ranges and developer profiles
  - Useful for testing dashboards without real collector deployment

## 🚀 Quick Start

### System Installation (Requires sudo)

Install collector as a system service (runs on all user accounts):

```bash
cd release
sudo ./install-telemetry.sh
```

**Installed Files**:
- Script: `/usr/local/bin/devlake-telemetry-collector.sh`
- Config: `/usr/local/etc/devlake-telemetry/config.json`
- LaunchDaemon: `/Library/LaunchDaemons/com.devlake.telemetry.plist`
- Data: `/var/tmp/devlake-telemetry/`
- Logs: `/var/log/devlake-telemetry.log` (or `/tmp/devlake-telemetry.log` if no write permission)

### Local Installation (No sudo)

Install collector in user space for testing:

```bash
cd release
./install-telemetry-local.sh
```

**Installed Files**:
- Script: `~/.local/bin/devlake-telemetry-collector.sh`
- Config: `~/.config/devlake-telemetry/config.json`
- LaunchAgent: `~/Library/LaunchAgents/com.devlake.telemetry.local.plist`
- Data: `~/.local/share/devlake-telemetry/`
- Logs: `~/.local/var/log/devlake-telemetry.log`

See [LOCAL_TESTING.md](LOCAL_TESTING.md) for detailed local testing instructions.

## ⚙️ Configuration

Edit the config file after installation:

**System**: `/usr/local/etc/devlake-telemetry/config.json`  
**Local**: `~/.config/devlake-telemetry/config.json`

```json
{
  "webhook_url": "https://devlake.arbisoft.com/api/rest/plugins/developer_telemetry/connections/2/report",
  "api_key": "YOUR_API_KEY_HERE",
  "webhook_url_secondary": "https://webhook.site/YOUR-UUID-HERE"
}
```

### Getting Your API Key

1. Log into DevLake UI: `https://your-devlake-instance.com`
2. Navigate to **Data Connections** → **Developer Telemetry**
3. Click **Add Connection**
4. Copy the **Connection ID** and **API Key**
5. Update `config.json` with your webhook URL and API key

**Critical**: The URL **must** include `/rest/` prefix:
```
https://<instance>/api/rest/plugins/developer_telemetry/connections/<ID>/report
```

See [API_AUTHENTICATION.md](docs/API_AUTHENTICATION.md) for detailed setup instructions.

## 📊 Grafana Dashboard

A comprehensive dashboard is available in the DevLake repository:

**File**: `incubator-devlake/grafana/dashboards/DeveloperTelemetry.json`

**Includes**:
- Active Hours by Developer (time series)
- Total Commits by Developer (time series)
- Total Lines Added (horizontal bar chart)
- Code Churn - Lines Added vs Deleted (time series)
- Test Runs Detected (time series)
- Developer Productivity Summary (table)
- Daily Commits - Top 10 Developers
- Summary stat panels

**Import Instructions**: See [GRAFANA_DASHBOARD.md](docs/GRAFANA_DASHBOARD.md)

## 🧪 Testing

### Generate Fake Data

Use the included script to generate realistic test data:

```bash
cd /path/to/mosyle-dev-telemetry
python3 generate_fake_data.py
```

**Features**:
- Generates data for 15 developers over 6 weeks (customizable)
- Varied productivity levels (senior/mid/junior)
- Weekend activity reduction (30% of weekday levels)
- Random days off (10% probability)
- Realistic commit patterns and test/build activity

**Use Cases**:
- Testing dashboards without deploying collector
- Demonstrating metrics to stakeholders
- Validating database schema changes

### Test with webhook.site

Add a secondary webhook to `config.json` to inspect payloads:

1. Visit https://webhook.site
2. Copy your unique URL
3. Add to config:
   ```json
   {
     "webhook_url": "https://devlake.arbisoft.com/api/rest/...",
     "webhook_url_secondary": "https://webhook.site/YOUR-UUID"
   }
   ```

The collector sends to both URLs. View the exact JSON payload at webhook.site.

## 🔧 Management Commands

### Check Status

```bash
# System installation
launchctl list | grep devlake
sudo launchctl print system/com.devlake.telemetry

# Local installation
launchctl list | grep devlake
launchctl print gui/$(id -u)/com.devlake.telemetry.local
```

### View Logs

```bash
# System
tail -f /var/log/devlake-telemetry.log
# or
tail -f /tmp/devlake-telemetry.log

# Local
tail -f ~/.local/var/log/devlake-telemetry.log
```

### Manual Run

```bash
# System
sudo /usr/local/bin/devlake-telemetry-collector.sh

# Local
~/.local/bin/devlake-telemetry-collector.sh
```

### Uninstall

```bash
# System
cd release
sudo ./uninstall-telemetry.sh

# Local
launchctl unload ~/Library/LaunchAgents/com.devlake.telemetry.local.plist
rm ~/Library/LaunchAgents/com.devlake.telemetry.local.plist
rm -rf ~/.local/bin/devlake-telemetry-collector.sh
rm -rf ~/.local/share/devlake-telemetry
rm -rf ~/.config/devlake-telemetry
```

## 📚 Documentation

- **[PLUGIN_SPEC.md](docs/PLUGIN_SPEC.md)** - DevLake plugin API specification and data model
- **[API_AUTHENTICATION.md](docs/API_AUTHENTICATION.md)** - How to obtain and use API keys
- **[GRAFANA_DASHBOARD.md](docs/GRAFANA_DASHBOARD.md)** - Dashboard import, customization, and troubleshooting
- **[ACTIVITY_DETECTION.md](docs/ACTIVITY_DETECTION.md)** - How active hours are detected and measured
- **[DATA_COLLECTION_FLOW.md](docs/DATA_COLLECTION_FLOW.md)** - Internal collection logic and architecture
- **[LOCAL_TESTING.md](LOCAL_TESTING.md)** - Local development and testing setup
- **[DOCUMENTATION_AUDIT.md](DOCUMENTATION_AUDIT.md)** - Documentation health and update status

## 🔒 Privacy & Security

- **No Sensitive Data**: Only command names and aggregated counts are collected
- **Privacy Filters**: Command arguments, file paths, and code content are stripped
- **Secure Storage**: API keys stored in restricted config files (chmod 600)
- **Transparent**: All source code is open and auditable
- **User Control**: Can be uninstalled anytime

## 🚀 Deployment Options

### 1. Mosyle Deployment (Enterprise)

Deploy via Mosyle Custom Commands to entire fleet:
- See [MOSYLE_DEPLOYMENT.md](docs/MOSYLE_DEPLOYMENT.md)
- See [ADMIN_DEPLOYMENT_GUIDE.md](docs/ADMIN_DEPLOYMENT_GUIDE.md)

### 2. Manual Installation

Install directly on developer machines:
```bash
cd release
sudo ./install-telemetry.sh
```

### 3. Configuration Management

Deploy via Ansible, Puppet, Chef, or other CM tools:
- Copy files to appropriate locations
- Set config.json with team API key
- Load LaunchDaemon

## 📈 Data Flow

```
1. Hourly Collection
   - Monitor git commits, file changes, running processes
   - Store hourly snapshot

2. Daily Aggregation
   - Merge hourly data into daily summary
   - Calculate total active hours

3. Daily Transmission (Once per day)
   - Send JSON payload to DevLake webhook
   - Archive to local file
   - Reset for new day

4. DevLake Storage
   - Store in _tool_developer_metrics table
   - Make available for Grafana queries

5. Visualization
   - Grafana dashboards show trends and patterns
   - Team-wide productivity insights
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes with tests
4. Submit a pull request

## 📝 License

See LICENSE file for details.

## 🔗 Links

- **DevLake**: https://devlake.apache.org
- **Repository**: https://github.com/irfanuddinahmad/mosyle-dev-telemetry
- **Issues**: https://github.com/irfanuddinahmad/mosyle-dev-telemetry/issues
