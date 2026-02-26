#!/bin/bash
#
# DevLake Telemetry Local Uninstallation Script
# 
# This script removes the DevLake telemetry collector installed in user space.
# No sudo required.
#

set -euo pipefail

echo "================================================"
echo "DevLake Telemetry Collector - Local Uninstallation"
echo "================================================"
echo ""

# ============================================================================
# Configuration (must match install-telemetry-local.sh)
# ============================================================================

PLIST_NAME="com.devlake.telemetry.local.plist"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME"
SCRIPT_PATH="$HOME/.local/bin/devlake-telemetry-collector.sh"
CONFIG_DIR="$HOME/.config/devlake-telemetry"
DATA_DIR="$HOME/.local/share/devlake-telemetry"
LOG_DIR="$HOME/.local/var/log"

# ============================================================================
# Uninstallation Steps
# ============================================================================

echo "Step 1: Stopping LaunchAgent..."
if launchctl list | grep -q "com.devlake.telemetry.local"; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    echo "✓ Agent stopped"
else
    echo "ℹ Agent not running"
fi
echo ""

echo "Step 2: Removing LaunchAgent plist..."
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
if [[ -f "$LOG_DIR/devlake-telemetry.log" ]]; then
    rm -f "$LOG_DIR/devlake-telemetry.log"
fi
if [[ -f "$LOG_DIR/devlake-telemetry-error.log" ]]; then
    rm -f "$LOG_DIR/devlake-telemetry-error.log"
fi
echo "✓ Log files removed"
echo ""

echo "================================================"
echo "Uninstallation Complete!"
echo "================================================"
echo ""
