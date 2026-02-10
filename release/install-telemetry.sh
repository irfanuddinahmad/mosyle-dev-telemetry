#!/bin/bash
#
# DevLake Telemetry Installation Script
# 
# This script installs the DevLake telemetry collector on macOS.
# It can be deployed via Mosyle Custom Commands.
#

set -euo pipefail

echo "================================================"
echo "DevLake Telemetry Collector - Installation"
echo "================================================"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (use sudo)" 
   exit 1
fi

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_NAME="devlake-telemetry-collector.sh"
PLIST_NAME="com.devlake.telemetry.plist"
CONFIG_NAME="config.json"

INSTALL_DIR="/usr/local/bin"
LAUNCHD_DIR="/Library/LaunchDaemons"
CONFIG_DIR="/usr/local/etc/devlake-telemetry"
DATA_DIR="/var/tmp/devlake-telemetry"
LOG_DIR="/var/log"

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

echo "Step 3: Installing LaunchDaemon configuration..."
if [[ -f "$SOURCE_DIR/$PLIST_NAME" ]]; then
    cp "$SOURCE_DIR/$PLIST_NAME" "$PLIST_PATH"
    chmod 644 "$PLIST_PATH"
    chown root:wheel "$PLIST_PATH"
    echo "✓ LaunchDaemon plist installed to $PLIST_PATH"
else
    echo "ERROR: Cannot find $PLIST_NAME in $SOURCE_DIR"
    exit 1
fi
echo ""

echo "Step 4: Installing configuration file..."
if [[ -f "$SOURCE_DIR/$CONFIG_NAME" ]]; then
    if [[ ! -f "$CONFIG_PATH" ]]; then
        # Only install if config doesn't already exist (preserve existing config)
        cp "$SOURCE_DIR/$CONFIG_NAME" "$CONFIG_PATH"
        chmod 644 "$CONFIG_PATH"
        echo "✓ Configuration file installed to $CONFIG_PATH"
    else
        echo "ℹ Configuration file already exists at $CONFIG_PATH (preserving existing)"
    fi
else
    echo "WARNING: Cannot find $CONFIG_NAME in $SOURCE_DIR (skipping)"
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

echo "Step 7: Loading LaunchDaemon..."
# Unload first if it's already loaded
if launchctl list | grep -q "com.devlake.telemetry"; then
    echo "  Unloading existing daemon..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
fi

launchctl load "$PLIST_PATH"
echo "✓ LaunchDaemon loaded and will run every hour"
echo ""

echo "Step 8: Verifying installation..."
if launchctl list | grep -q "com.devlake.telemetry"; then
    echo "✓ Daemon is running"
else
    echo "⚠ Warning: Daemon may not be running properly"
fi
echo ""

echo "================================================"
echo "Installation Complete!"
echo "================================================"
echo ""
echo "The telemetry collector is now installed and will:"
echo "  • Collect data every hour"
echo "  • Send daily summaries to DevLake webhook"
echo "  • Run automatically on system boot"
echo ""
echo "Configuration: $CONFIG_PATH"
echo "Logs: $LOG_DIR/devlake-telemetry.log"
echo "Data: $DATA_DIR"
echo ""
echo "To configure the webhook URL, edit:"
echo "  $CONFIG_PATH"
echo ""
echo "To check status:"
echo "  sudo launchctl list | grep devlake"
echo "  tail -f $LOG_DIR/devlake-telemetry.log"
echo ""
