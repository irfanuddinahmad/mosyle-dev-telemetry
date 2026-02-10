# Mosyle Admin Deployment Guide
## DevLake Developer Telemetry System

**For**: Mosyle Administrators  
**Purpose**: Deploy developer telemetry collection to macOS devices  
**Time Required**: 30-45 minutes for initial setup  
**Skill Level**: Intermediate Mosyle administration

---

## 📋 Pre-Deployment Checklist

Before you begin, ensure you have:

- [ ] **Mosyle Admin Access** - Full administrator permissions
- [ ] **DevLake Webhook URL** - Provided by your DevOps/Analytics team
  - Example: `https://devlake.yourcompany.com/api/webhooks/developer-metrics`
- [ ] **Device Group** - List of developer machines to target
- [ ] **Files Package** - The telemetry collector files (provided by development team)
- [ ] **30 minutes** - Time to complete deployment

---

## 🎯 Deployment Overview

**What you'll be doing:**

1. Configure the telemetry collector with your webhook URL
2. Upload files to a hosting location (or embed them)
3. Create a Custom Command in Mosyle
4. Configure network access for the webhook
5. Deploy to test device
6. Roll out to all developer machines
7. Set up monitoring

**After deployment, the system will:**
- Run automatically every hour on each Mac
- Collect privacy-safe developer metrics
- Send daily summaries to DevLake
- Continue running transparently in the background

---

## 📝 Step-by-Step Instructions

### Step 1: Configure the Webhook URL

**Time: 5 minutes**

1. **Locate the config file** in your deployment package:
   - File: `config.json`

2. **Edit the webhook URL**:
   ```json
   {
     "webhook_url": "https://YOUR-DEVLAKE-URL-HERE/api/webhooks/your-id"
   }
   ```

3. **Replace the URL** with the actual DevLake webhook URL provided by your team

4. **Save the file**

> [!IMPORTANT]
> **Get the webhook URL from your DevOps team before proceeding!**  
> Without the correct URL, data won't be sent to DevLake.

---

### Step 2: Choose Your Deployment Method

**Time: 2 minutes**

You have two options:

#### Option A: Upload to File Server (Recommended)

**Pros**: Easy to update later, smaller script  
**Cons**: Requires file hosting

1. **Upload the deployment package** to your company file server:
   - Recommended location: `https://files.yourcompany.com/mosyle/devlake-telemetry/`
   - Upload all files as a `.tar.gz` archive

2. **Note the download URL** - you'll use this in Step 4

#### Option B: Embed in Script

**Pros**: Self-contained, no external dependencies  
**Cons**: Larger script, harder to update

1. You'll embed the files directly in the Mosyle Custom Command
2. Proceed to Step 4 for instructions

---

### Step 3: Configure Network Access

**Time: 5 minutes**

The telemetry needs to reach your DevLake instance.

#### 3.1 Add DevLake Domain to Allowed List

1. **Log into Mosyle Dashboard**
   - Navigate to: **Security** → **Firewall** → **Network Settings**

2. **Add to Allowed Domains**:
   - Click **"+ Add Domain"**
   - Domain: Your DevLake hostname (e.g., `devlake.yourcompany.com`)
   - Protocol: **HTTPS**
   - Action: **Allow**

3. **Save Changes**

#### 3.2 Verify DNS Resolution

If you have custom DNS settings:

1. Navigate to: **Network** → **DNS Settings**
2. Ensure your DevLake domain is resolvable
3. Test from a device if needed: `nslookup devlake.yourcompany.com`

---

### Step 4: Create the Custom Command

**Time: 10 minutes**

#### 4.1 Navigate to Custom Commands

1. **Log into Mosyle Dashboard**
2. Go to: **Devices** → **Custom Commands**
3. Click **"+ New Command"**

#### 4.2 Configure Command Details

**General Settings:**
- **Name**: `Install DevLake Telemetry`
- **Description**: `Deploys developer productivity telemetry collection system`
- **Type**: **Script**
- **Requires Admin**: **Yes** ✓

#### 4.3 Upload Files (If using Option A from Step 2)

If Mosyle supports file attachments:

1. Click **"Upload Files"**
2. Upload these files:
   - `devlake-telemetry-collector.sh`
   - `com.devlake.telemetry.plist`
   - `config.json`
   - `install-telemetry.sh`

#### 4.4 Add the Installation Script

**For Option A (File Server):**

```bash
#!/bin/bash
# DevLake Telemetry - Automatic Installation
set -euo pipefail

echo "Starting DevLake Telemetry installation..."

# Download deployment package
PACKAGE_URL="https://files.yourcompany.com/mosyle/devlake-telemetry-package.tar.gz"
TEMP_DIR=$(mktemp -d)

cd "$TEMP_DIR"
curl -L -o package.tar.gz "$PACKAGE_URL"
tar -xzf package.tar.gz

# Run installation
chmod +x install-telemetry.sh
./install-telemetry.sh

# Cleanup
cd /
rm -rf "$TEMP_DIR"

echo "DevLake Telemetry installed successfully!"
exit 0
```

**For Option B (Embedded Files):**

Use the contents of `install-telemetry.sh` directly, but you'll need to embed the other files as base64. Contact your development team for the embedded version.

#### 4.5 Configure Execution Settings

- **Run as**: **root** ✓
- **Timeout**: **300 seconds** (5 minutes)
- **On Failure**: **Report error, don't retry**
- **On Success**: **Mark as completed**

#### 4.6 Save the Command

Click **"Save"** at the bottom of the page.

---

### Step 5: Create Health Check Command (Optional but Recommended)

**Time: 5 minutes**

This lets you verify the telemetry is running on devices.

1. **Create another Custom Command**:
   - **Name**: `DevLake Telemetry - Health Check`
   - **Type**: Script
   - **Script**:

```bash
#!/bin/bash
echo "=== DevLake Telemetry Status ==="

# Check if daemon is running
if launchctl list | grep -q "com.devlake.telemetry"; then
    echo "✓ Daemon is running"
    STATUS=0
else
    echo "✗ Daemon is NOT running"
    STATUS=1
fi

# Check last collection
if [[ -f /var/tmp/devlake-telemetry/hourly_data.json ]]; then
    LAST=$(stat -f %Sm -t "%Y-%m-%d %H:%M:%S" /var/tmp/devlake-telemetry/hourly_data.json)
    echo "✓ Last collection: $LAST"
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

exit $STATUS
```

2. **Save** the command

---

### Step 6: Test on a Single Device

**Time: 10 minutes**

**DO NOT deploy to all devices yet!** Test on one device first.

#### 6.1 Select a Test Device

1. Go to: **Devices** → **All Devices**
2. **Search** for a developer's Mac (preferably your own or a volunteer's)
3. Click on the device to open its details

#### 6.2 Deploy the Command

1. In the device details, click **"Commands"** tab
2. Click **"+ Run Command"**
3. Select: **"Install DevLake Telemetry"**
4. Click **"Execute"**

#### 6.3 Monitor Execution

1. Wait for the command to complete (~30 seconds)
2. Check the **Output** in Mosyle:
   - Look for: `"DevLake Telemetry installed successfully!"`
   - If errors appear, see **Troubleshooting** section below

#### 6.4 Verify Installation

1. Run the **Health Check** command on the same device
2. Check the output:
   - Should show: `"✓ Daemon is running"`
   - Should show recent collection time

#### 6.5 Wait for First Data

1. **Wait 1 hour** for the first collection to run
2. Run **Health Check** again
3. Verify: `"✓ Last collection: [recent timestamp]"`

#### 6.6 Verify Webhook (Next Day)

1. **Ask your DevOps team** to check if data arrived in DevLake
2. They should see a payload from the test device's username
3. Confirm the data looks correct

---

### Step 7: Roll Out to All Developers

**Time: 5 minutes**

Once testing is successful:

#### 7.1 Create Device Group (If Not Already Created)

1. Go to: **Devices** → **Groups**
2. Click **"+ New Group"**
3. **Name**: `Developers`
4. **Criteria**: Tag-based or manual selection
5. **Add all developer machines** to this group
6. **Save**

#### 7.2 Deploy to Group

1. Go to: **Devices** → **Custom Commands**
2. Find: **"Install DevLake Telemetry"**
3. Click **"Deploy"**
4. **Target**: Select **"Developers"** group
5. **Execution**: 
   - **When**: Immediately (or schedule for off-hours)
   - **Force**: Yes (to ensure installation even if already run)
6. Click **"Deploy"**

#### 7.3 Monitor Deployment

1. Go to: **Reports** → **Command Execution**
2. Filter by: **"Install DevLake Telemetry"**
3. Monitor the **Success Rate**
   - Target: 95%+ success rate
   - If lower, investigate failures (see Troubleshooting)

---

### Step 8: Set Up Ongoing Monitoring

**Time: 5 minutes**

#### 8.1 Schedule Weekly Health Checks

1. Go to: **Automation** → **Scheduled Tasks**
2. Click **"+ New Task"**
3. Configure:
   - **Name**: `Weekly DevLake Telemetry Check`
   - **Command**: **"DevLake Telemetry - Health Check"**
   - **Target**: **"Developers"** group
   - **Schedule**: **Every Monday at 9 AM**
   - **Notify on failure**: **Yes** (to your email)

#### 8.2 Create Dashboard Widget (If Available)

1. Go to: **Dashboard** → **Customize**
2. Add widget: **"Command Success Rate"**
3. Filter to: **"DevLake Telemetry"** commands
4. This shows ongoing health at a glance

---

## 🔍 Verification

After full deployment, verify success:

### Check Mosyle Dashboard

- [ ] Command execution shows 95%+ success rate
- [ ] Health checks passing on most devices
- [ ] No recurring errors in logs

### Check with DevOps Team

- [ ] DevLake is receiving daily data from developer machines
- [ ] Data quality is good (realistic command counts, tool usage)
- [ ] No errors in DevLake ingestion logs

---

## 🐛 Troubleshooting

### Common Issues

#### Issue: "Permission Denied" during installation

**Symptoms**: Installation fails with permission errors

**Solution**:
1. Verify the command is set to **"Run as root"**
2. Check device MDM enrollment status
3. Ensure device isn't in recovery mode

---

#### Issue: "Cannot download package.tar.gz"

**Symptoms**: Installation fails when downloading files

**Solution**:
1. Verify the file server URL is correct and accessible
2. Check if the file server requires authentication
3. Verify DNS resolution from the device
4. Try Option B (embedded files) instead

---

#### Issue: Daemon not running on device

**Symptoms**: Health check shows "Daemon is NOT running"

**Solution**:
1. SSH to the device (or ask user to run):
   ```bash
   sudo launchctl load /Library/LaunchDaemons/com.devlake.telemetry.plist
   sudo launchctl list | grep devlake
   ```
2. Check for errors:
   ```bash
   tail -50 /var/log/devlake-telemetry-error.log
   ```
3. Verify plist syntax:
   ```bash
   plutil -lint /Library/LaunchDaemons/com.devlake.telemetry.plist
   ```

---

#### Issue: No data being sent to DevLake

**Symptoms**: Daemon runs but DevLake receives no data

**Solution**:
1. Verify webhook URL is correct in config:
   ```bash
   cat /usr/local/etc/devlake-telemetry/config.json
   ```
2. Test webhook manually:
   ```bash
   curl -X POST https://your-devlake-url.com/api/webhooks/your-id \
     -H "Content-Type: application/json" \
     -d '{"test": "data"}'
   ```
3. Check firewall settings in Mosyle (Step 3)
4. Verify device has internet connectivity

---

#### Issue: High failure rate on Apple Silicon Macs

**Symptoms**: Intel Macs work fine, M1/M2 Macs fail

**Solution**:
1. Verify scripts don't use Intel-specific binaries
2. Check Rosetta 2 compatibility if needed
3. Test manually on M1/M2 Mac first

---

## 🔄 Updating the System

If you need to update the telemetry collector:

### Update Configuration Only

**To change webhook URL:**

1. Create a new Custom Command:
   ```bash
   #!/bin/bash
   NEW_URL="https://new-devlake-url.com"
   sudo jq --arg url "$NEW_URL" '.webhook_url = $url' \
     /usr/local/etc/devlake-telemetry/config.json > /tmp/config.json.new
   sudo mv /tmp/config.json.new /usr/local/etc/devlake-telemetry/config.json
   echo "Webhook URL updated to: $NEW_URL"
   ```

2. Deploy to **"Developers"** group

### Update Entire System

**To deploy new version:**

1. Get updated files from development team
2. Update your file server with new version
3. Create new Custom Command: **"Update DevLake Telemetry"**
4. Use same script as installation (it will overwrite old version)
5. Deploy to **"Developers"** group

---

## 🗑️ Uninstalling (If Needed)

If you need to remove the telemetry:

1. **Create Uninstall Command**:
   - Name: `Uninstall DevLake Telemetry`
   - Script: Upload the provided `uninstall-telemetry.sh`

2. **Deploy to devices** that need removal

3. **Remove from firewall whitelist** if no longer needed

---

## 📊 Success Metrics

**Within 1 week of deployment, you should see:**

- ✅ 95%+ of developer devices reporting
- ✅ Daily data arriving in DevLake
- ✅ No recurring errors in Mosyle logs
- ✅ DevOps team confirms good data quality

**If metrics are lower:**
- Review failed devices individually
- Check common error patterns
- Consider extending testing period before full rollout

---

## 📞 Support Contacts

**For issues with:**

- **Mosyle deployment**: Your IT support team
- **DevLake webhook**: DevOps/Analytics team
- **Script errors**: Development team (provided the scripts)
- **Privacy concerns**: Security team

---

## 📝 Quick Reference Commands

### Check if installed on a device:
```bash
sudo launchctl list | grep devlake
```

### View recent logs:
```bash
sudo tail -50 /var/log/devlake-telemetry.log
```

### Manually trigger collection (for testing):
```bash
sudo /usr/local/bin/devlake-telemetry-collector.sh
```

### View collected data:
```bash
cat /var/tmp/devlake-telemetry/daily_aggregate.json | jq .
```

---

## ✅ Deployment Checklist

Use this checklist to track your progress:

- [ ] Obtained DevLake webhook URL from DevOps team
- [ ] Configured `config.json` with webhook URL
- [ ] Uploaded files to hosting location (or prepared embedded version)
- [ ] Added DevLake domain to Mosyle firewall whitelist
- [ ] Created "Install DevLake Telemetry" Custom Command
- [ ] Created "Health Check" Custom Command
- [ ] Tested installation on single device
- [ ] Verified daemon running on test device
- [ ] Confirmed first data collection
- [ ] Confirmed DevOps team received test data
- [ ] Created "Developers" device group
- [ ] Deployed to all developer machines
- [ ] Monitored deployment success rate (95%+ target)
- [ ] Set up weekly health check automation
- [ ] Added dashboard monitoring widget
- [ ] Documented any issues encountered
- [ ] Notified team that telemetry is live

---

**Deployment Complete!** 🎉

The telemetry system is now collecting privacy-safe developer productivity metrics and sending them to DevLake automatically.
