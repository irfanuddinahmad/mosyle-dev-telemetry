#!/bin/bash
#
# DevLake Telemetry Local Installation Script
# 
# This script installs the DevLake telemetry collector for local testing.
# It runs in user space without requiring sudo/su access.
#

set -euo pipefail

echo "================================================"
echo "DevLake Telemetry Collector - Local Installation"
echo "================================================"
echo ""

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_NAME="devlake-telemetry-collector.sh"
PLIST_NAME="com.devlake.telemetry.local.plist"
CONFIG_NAME="config.json"

# Local user directories (no sudo required)
INSTALL_DIR="$HOME/.local/bin"
LAUNCHD_DIR="$HOME/Library/LaunchAgents"
CONFIG_DIR="$HOME/.config/devlake-telemetry"
DATA_DIR="$HOME/.local/share/devlake-telemetry"
LOG_DIR="$HOME/.local/var/log"

SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"
PLIST_PATH="$LAUNCHD_DIR/$PLIST_NAME"
CONFIG_PATH="$CONFIG_DIR/$CONFIG_NAME"

# Source directory (where this install script is located)
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# Installation Steps
# ============================================================================

echo "Step 1: Creating directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$LAUNCHD_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "$DATA_DIR/archive"
mkdir -p "$LOG_DIR"
echo "✓ Directories created"
echo ""

echo "Step 2: Installing collector script..."
if [[ -f "$SOURCE_DIR/$SCRIPT_NAME" ]]; then
    cp "$SOURCE_DIR/$SCRIPT_NAME" "$SCRIPT_PATH"
    chmod 755 "$SCRIPT_PATH"
    echo "✓ Collector script installed to $SCRIPT_PATH"
else
    echo "ERROR: Cannot find $SCRIPT_NAME in $SOURCE_DIR"
    exit 1
fi
echo ""

echo "Step 3: Creating LaunchAgent configuration..."
cat > "$PLIST_PATH" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Label - Unique identifier for this agent -->
    <key>Label</key>
    <string>com.devlake.telemetry.local</string>
    
    <!-- Program to run -->
    <key>ProgramArguments</key>
    <array>
        <string>SCRIPT_PATH_PLACEHOLDER</string>
    </array>
    
    <!-- Run every hour (3600 seconds) -->
    <key>StartInterval</key>
    <integer>3600</integer>
    
    <!-- Start on load (user login) -->
    <key>RunAtLoad</key>
    <true/>
    
    <!-- Standard output log -->
    <key>StandardOutPath</key>
    <string>LOG_PATH_PLACEHOLDER/devlake-telemetry.log</string>
    
    <!-- Standard error log -->
    <key>StandardErrorPath</key>
    <string>LOG_PATH_PLACEHOLDER/devlake-telemetry-error.log</string>
    
    <!-- Working directory -->
    <key>WorkingDirectory</key>
    <string>INSTALL_DIR_PLACEHOLDER</string>
    
    <!-- Environment variables -->
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>CONFIG_FILE</key>
        <string>CONFIG_DIR_PLACEHOLDER/config.json</string>
        <key>DATA_DIR</key>
        <string>DATA_DIR_PLACEHOLDER</string>
        <key>LOG_FILE</key>
        <string>LOG_PATH_PLACEHOLDER/devlake-telemetry.log</string>
    </dict>
    
    <!-- Process priority (nice value) - run with low priority -->
    <key>Nice</key>
    <integer>10</integer>
    
    <!-- Throttle interval - prevent rapid restart loops (10 seconds) -->
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
EOF

# Replace placeholders with actual paths
sed -i '' "s|SCRIPT_PATH_PLACEHOLDER|$SCRIPT_PATH|g" "$PLIST_PATH"
sed -i '' "s|LOG_PATH_PLACEHOLDER|$LOG_DIR|g" "$PLIST_PATH"
sed -i '' "s|INSTALL_DIR_PLACEHOLDER|$INSTALL_DIR|g" "$PLIST_PATH"
sed -i '' "s|CONFIG_DIR_PLACEHOLDER|$CONFIG_DIR|g" "$PLIST_PATH"
sed -i '' "s|DATA_DIR_PLACEHOLDER|$DATA_DIR|g" "$PLIST_PATH"

chmod 644 "$PLIST_PATH"
echo "✓ LaunchAgent plist created at $PLIST_PATH"
echo ""

echo "Step 4: Installing configuration file..."
if [[ -f "$CONFIG_PATH" ]]; then
    echo "ℹ Configuration file already exists at $CONFIG_PATH (preserving existing)"
else
    # Create default config with test URLs
    cat > "$CONFIG_PATH" << 'EOF'
{
  "webhook_url": "http://localhost:8080/plugins/developer_telemetry/connections/1/report",
  "webhook_url_secondary": "https://webhook.site/04421308-e750-4ead-901c-f5bf32292fd4",
  "collection_interval_seconds": 3600,
  "data_retention_days": 30,
  "privacy": {
    "collect_command_arguments": false,
    "collect_file_paths": false,
    "collect_urls": false,
    "exclude_commands": []
  },
  "developer_tools": [
    "vscode",
    "code",
    "intellij",
    "pycharm",
    "goland",
    "webstorm",
    "docker",
    "git",
    "go",
    "node",
    "npm",
    "python",
    "java",
    "make",
    "gradle",
    "maven",
    "curl",
    "brew"
  ]
}
EOF
    chmod 644 "$CONFIG_PATH"
    echo "✓ Configuration file created at $CONFIG_PATH"
fi
echo ""

echo "Step 5: Creating log files..."
touch "$LOG_DIR/devlake-telemetry.log"
touch "$LOG_DIR/devlake-telemetry-error.log"
chmod 644 "$LOG_DIR/devlake-telemetry.log"
chmod 644 "$LOG_DIR/devlake-telemetry-error.log"
echo "✓ Log files created"
echo ""

echo "Step 6: Setting permissions..."
chmod 755 "$DATA_DIR"
chmod 755 "$DATA_DIR/archive"
echo "✓ Permissions set"
echo ""

echo "Step 7: Loading LaunchAgent..."
# Unload first if it's already loaded
if launchctl list | grep -q "com.devlake.telemetry.local"; then
    echo "  Unloading existing agent..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
fi

launchctl load "$PLIST_PATH"
echo "✓ LaunchAgent loaded and will run every hour"
echo ""

echo "Step 8: Verifying installation..."
if launchctl list | grep -q "com.devlake.telemetry.local"; then
    echo "✓ Agent is running"
else
    echo "⚠ Warning: Agent may not be running properly"
fi
echo ""

echo "================================================"
echo "Installation Complete!"
echo "================================================"
echo ""
echo "The telemetry collector is now installed and will:"
echo "  • Collect data every hour"
echo "  • Send to Primary URL: http://localhost:8080/plugins/developer_telemetry/connections/1/report"
echo "  • Send to Secondary URL: https://webhook.site/04421308-e750-4ead-901c-f5bf32292fd4"
echo "  • Run automatically on user login"
echo ""
echo "Configuration: $CONFIG_PATH"
echo "Logs: $LOG_DIR/devlake-telemetry.log"
echo "Data: $DATA_DIR"
echo ""
echo "To test immediately (without waiting for scheduled run):"
echo "  $SCRIPT_PATH"
echo ""
echo "To check status:"
echo "  launchctl list | grep devlake"
echo "  tail -f $LOG_DIR/devlake-telemetry.log"
echo ""
echo "To unload:"
echo "  launchctl unload $PLIST_PATH"
echo ""

# Add to PATH if not already there
if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
    echo "Note: You may want to add $INSTALL_DIR to your PATH"
    echo "Add this to your ~/.zshrc or ~/.bashrc:"
    echo '  export PATH="$HOME/.local/bin:$PATH"'
    echo ""
fi
