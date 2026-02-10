#!/bin/bash
#
# DevLake Telemetry Uninstallation Script
# 
# This script removes the DevLake telemetry collector from macOS.
#

set -euo pipefail

echo "================================================"
echo "DevLake Telemetry Collector - Uninstallation"
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

PLIST_NAME="com.devlake.telemetry.plist"
PLIST_PATH="/Library/LaunchDaemons/$PLIST_NAME"
SCRIPT_PATH="/usr/local/bin/devlake-telemetry-collector.sh"
CONFIG_DIR="/usr/local/etc/devlake-telemetry"
DATA_DIR="/var/tmp/devlake-telemetry"

# ============================================================================
# Uninstallation Steps
# ============================================================================

echo "Step 1: Stopping LaunchDaemon..."
if launchctl list | grep -q "com.devlake.telemetry"; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    echo "✓ Daemon stopped"
else
    echo "ℹ Daemon not running"
fi
echo ""

echo "Step 2: Removing LaunchDaemon plist..."
if [[ -f "$PLIST_PATH" ]]; then
    rm -f "$PLIST_PATH"
    echo "✓ Plist removed"
else
    echo "ℹ Plist not found"
fi
echo ""

echo "Step 3: Removing collector script..."
if [[ -f "$SCRIPT_PATH" ]]; then
    rm -f "$SCRIPT_PATH"
    echo "✓ Script removed"
else
    echo "ℹ Script not found"
fi
echo ""

echo "Step 4: Removing configuration..."
if [[ -d "$CONFIG_DIR" ]]; then
    rm -rf "$CONFIG_DIR"
    echo "✓ Configuration removed"
else
    echo "ℹ Configuration not found"
fi
echo ""

echo "Step 5: Handling data directory..."
if [[ -d "$DATA_DIR" ]]; then
    read -p "Do you want to remove collected data? (y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$DATA_DIR"
        echo "✓ Data removed"
    else
        echo "ℹ Data preserved at $DATA_DIR"
    fi
else
    echo "ℹ Data directory not found"
fi
echo ""

echo "Step 6: Cleaning log files..."
if [[ -f "/var/log/devlake-telemetry.log" ]]; then
    rm -f "/var/log/devlake-telemetry.log"
fi
if [[ -f "/var/log/devlake-telemetry-error.log" ]]; then
    rm -f "/var/log/devlake-telemetry-error.log"
fi
echo "✓ Log files removed"
echo ""

echo "================================================"
echo "Uninstallation Complete!"
echo "================================================"
echo ""
