# DevLake Telemetry Collector for macOS

A transparent, privacy-safe telemetry system that captures developer productivity metrics and sends them to a DevLake webhook. Designed for deployment via Mosyle.

## 📂 Project Structure

- **`release/`**: Contains the production-ready files for deployment.
  - `devlake-telemetry-collector.sh`: The core data collection script.
  - `install-telemetry.sh`: Sudo-based installation script for administrators.
  - `uninstall-telemetry.sh`: Cleanup utility.
  - `com.devlake.telemetry.plist`: LaunchDaemon configuration.
  - `config.json`: Default configuration file.

- **`docs/`**: Detailed documentation.
  - [Full README](docs/FULL_README.md): Comprehensive system overview and usage.
  - [Mosyle Deployment Guide](docs/MOSYLE_DEPLOYMENT.md): Technical guide for creating Custom Commands.
  - [Admin Guide](docs/ADMIN_DEPLOYMENT_GUIDE.md): Step-by-step UI walkthrough for Mosyle admins.
  - [Data Collection Flow](docs/DATA_COLLECTION_FLOW.md): Deep dive into internal logic and privacy filters.


## 🚀 Quick Start (Local Install)

To install on a single machine for testing (requires sudo):

1. Navigate to the release folder:
   ```bash
   cd release
   ```
2. Run the installer:
   ```bash
   sudo ./install-telemetry.sh
   ```

For detailed deployment instructions, see [docs/FULL_README.md](docs/FULL_README.md).
