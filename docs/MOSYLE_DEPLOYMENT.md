# Mosyle Deployment Guide

Complete guide for deploying the DevLake Telemetry Collector via Mosyle Custom Commands.

## Prerequisites

1. **Mosyle Dashboard Access**
   - Admin access to your Mosyle instance
   - Permissions to create and deploy Custom Commands

2. **DevLake Webhook URL**
   - Your DevLake webhook endpoint URL
   - Example: `https://devlake.yourcompany.com/api/webhooks/developer-metrics`

3. **Target Devices**
   - macOS 10.14 or later
   - Devices enrolled in Mosyle

## Deployment Steps

### Step 1: Prepare Configuration

1. **Edit the webhook URL** in `config.json`:

```json
{
  "webhook_url": "https://YOUR-ACTUAL-DEVLAKE-URL/api/webhooks/your-id"
}
```

2. **Optional**: Adjust collection settings in the same file

### Step 2: Package Files for Mosyle

Create a deployment package:

```bash
cd mosyle-dev-telemetry

# Create a tar archive
tar -czf devlake-telemetry-package.tar.gz \
  devlake-telemetry-collector.sh \
  com.devlake.telemetry.plist \
  config.json \
  install-telemetry.sh
```

### Step 3: Create Mosyle Custom Command

#### Option A: Single Script Deployment (Recommended)

**This creates a self-contained deployment script that includes all files.**

Create a new Custom Command in Mosyle with the following script:

```bash
#!/bin/bash
# DevLake Telemetry - Mosyle Deployment Script

set -euo pipefail

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download or embed files here
# For Mosyle, you'll typically upload files to a hosted location
# and download them, OR embed them directly in the script using base64

# Example: Download from your file server
DOWNLOAD_URL="https://your-file-server.com/devlake-telemetry-package.tar.gz"
curl -L -o package.tar.gz "$DOWNLOAD_URL"
tar -xzf package.tar.gz

# Run installation
chmod +x install-telemetry.sh
./install-telemetry.sh

# Cleanup
cd /
rm -rf "$TEMP_DIR"

echo "DevLake Telemetry installed successfully"
```

#### Option B: Direct File Upload

If your Mosyle instance supports file attachments:

1. Go to **Devices** → **Custom Commands**
2. Click **+ New Command**
3. Configure:
   - **Name**: `Install DevLake Telemetry`
   - **Type**: Script
   - **Upload Files**:
     - `devlake-telemetry-collector.sh`
     - `com.devlake.telemetry.plist`
     - `config.json`
     - `install-telemetry.sh`
   - **Script**: Reference the uploaded `install-telemetry.sh`

### Step 4: Configure Network Access

Add the DevLake webhook URL to Mosyle's allowed domains:

1. Go to **Security** → **Firewall Settings**
2. Add your DevLake domain to **Allowed Domains**:
   - Example: `devlake.yourcompany.com`

This ensures the telemetry can reach your DevLake instance.

### Step 5: Target Devices

1. **Create a Device Group** (if not already exists):
   - Name: `Developer Machines`
   - Criteria: Tag all developer devices

2. **Apply the Command**:
   - Select your Custom Command
   - Choose target: `Developer Machines` group
   - Execute

### Step 6: Verify Deployment

After deployment, verify on a test machine:

```bash
# Check if daemon is running
ssh user@test-machine.local
sudo launchctl list | grep devlake

# Check logs
sudo tail -f /var/log/devlake-telemetry.log

# Verify first collection
sudo /usr/local/bin/devlake-telemetry-collector.sh
```

## Configuration Management

### Updating Webhook URL After Deployment

If you need to change the webhook URL after deployment:

**Option 1: Via Mosyle Custom Command**

```bash
#!/bin/bash
# Update webhook URL
NEW_URL="https://new-devlake-url.com/api/webhooks/your-id"
sudo jq --arg url "$NEW_URL" '.webhook_url = $url' \
  /usr/local/etc/devlake-telemetry/config.json > /tmp/config.json
sudo mv /tmp/config.json /usr/local/etc/devlake-telemetry/config.json
```

**Option 2: Via Environment Variable**

Add to the LaunchDaemon plist via Mosyle:

```xml
<key>EnvironmentVariables</key>
<dict>
    <key>DEVLAKE_WEBHOOK_URL</key>
    <string>https://your-new-url.com</string>
</dict>
```

## Monitoring & Maintenance

### Health Check Command

Create a Mosyle Custom Command for health checks:

```bash
#!/bin/bash
# DevLake Telemetry Health Check

echo "=== DevLake Telemetry Status ==="

# Check daemon status
if launchctl list | grep -q "com.devlake.telemetry"; then
    echo "✓ Daemon is running"
else
    echo "✗ Daemon is NOT running"
    exit 1
fi

# Check last collection
if [[ -f /var/tmp/devlake-telemetry/hourly_data.json ]]; then
    LAST_COLLECTION=$(stat -f %Sm -t "%Y-%m-%d %H:%M:%S" /var/tmp/devlake-telemetry/hourly_data.json)
    echo "✓ Last collection: $LAST_COLLECTION"
else
    echo "⚠ No data collected yet"
fi

# Check last webhook send
if [[ -f /var/tmp/devlake-telemetry/last_send_timestamp ]]; then
    LAST_SEND=$(cat /var/tmp/devlake-telemetry/last_send_timestamp)
    echo "✓ Last webhook send: $LAST_SEND"
else
    echo "ℹ No data sent yet (waiting for first daily send)"
fi

echo "=== End Status ==="
```

### Log Collection

Create a command to collect logs for troubleshooting:

```bash
#!/bin/bash
# Collect DevLake Telemetry logs

LOG_ARCHIVE="/tmp/devlake-telemetry-logs-$(hostname)-$(date +%Y%m%d).tar.gz"

tar -czf "$LOG_ARCHIVE" \
  /var/log/devlake-telemetry.log \
  /var/log/devlake-telemetry-error.log \
  /var/tmp/devlake-telemetry/daily_aggregate.json \
  /var/tmp/devlake-telemetry/hourly_data.json

echo "Logs archived to: $LOG_ARCHIVE"
```

## Undeployment

To remove from all devices:

```bash
#!/bin/bash
# DevLake Telemetry Removal Script

if [[ -f /usr/local/bin/devlake-telemetry-collector.sh ]]; then
    # Download and run uninstall script
    curl -L https://your-server.com/uninstall-telemetry.sh | sudo bash
else
    echo "DevLake Telemetry not installed"
fi
```

## Troubleshooting

### Common Issues

**1. Daemon not starting**
- Check permissions on files
- Verify plist syntax
- Check system logs: `sudo log show --predicate 'process == "launchd"' --last 1h`

**2. No data being collected**
- Verify `jq` is installed: `which jq`
- Check file permissions on data directory
- Review error logs

**3. Webhook failures**
- Verify network connectivity
- Check firewall settings in Mosyle
- Test webhook manually with curl

### Support

For issues with deployment:
1. Check device-specific logs via Mosyle Dashboard
2. Run health check command remotely
3. Collect logs using log collection command
4. Review with DevOps team

## Security Considerations

### Certificate Pinning (Optional)

For enhanced security, configure the webhook to use certificate pinning:

```bash
# Add to collector script
CERT_PATH="/path/to/devlake-cert.pem"
curl --cacert "$CERT_PATH" -X POST ...
```

Deploy the certificate via Mosyle's Certificate Management.

### Audit Compliance

The telemetry system:
- ✅ Logs all collection activities
- ✅ Never collects sensitive data
- ✅ Provides transparent operation
- ✅ Can be audited via log files
- ✅ Respects user privacy

---

**Next Steps**: After successful deployment, monitor the DevLake dashboard for incoming metrics!
