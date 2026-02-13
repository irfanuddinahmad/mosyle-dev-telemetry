# DevLake On-Premises Deployment Guide
## Docker Compose Deployment with Custom Telemetry Plugin

This guide covers deploying Apache DevLake with the custom Developer Telemetry plugin on your organization's on-premises data center servers.

---

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Installation Steps](#installation-steps)
4. [Custom Plugin Integration](#custom-plugin-integration)
5. [Configuration](#configuration)
6. [Security Hardening](#security-hardening)
7. [Monitoring & Maintenance](#monitoring--maintenance)
8. [Backup & Recovery](#backup--recovery)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Server Requirements
- **OS**: Ubuntu 20.04+ / RHEL 8+ / CentOS 8+
- **CPU**: 4 cores minimum (8 cores recommended)
- **RAM**: 8GB minimum (16GB recommended for 100+ developers)
- **Storage**: 100GB SSD (storage grows ~1GB/developer/month)
- **Network**: Static IP address within your data center

### Software Requirements
- Docker 24.0+
- Docker Compose 2.20+
- Git
- Make (for building custom plugin)
- Go 1.21+ (for plugin development)

### Access Requirements
- SSH access to the server
- Sudo/root privileges for initial setup
- Internal DNS or host entry for `devlake.yourcompany.internal`

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Your Data Center                          │
│                                                              │
│  ┌──────────────┐      ┌──────────────┐                    │
│  │   Developer  │──┬──▶│   DevLake    │                    │
│  │   Machines   │  │   │   Server     │                    │
│  └──────────────┘  │   │              │                    │
│                    │   │  ┌────────┐  │                    │
│  ┌──────────────┐  │   │  │ Config │  │                    │
│  │   Developer  │──┼──▶│  │   UI   │  │◀──── Port 4000    │
│  │   Machines   │  │   │  └────────┘  │                    │
│  └──────────────┘  │   │              │                    │
│                    │   │  ┌────────┐  │                    │
│  ┌──────────────┐  │   │  │Telemetry│ │◀──── Port 8080    │
│  │   Developer  │──┘   │  │Webhook │  │                    │
│  │   Machines   │      │  └────────┘  │                    │
│  └──────────────┘      │              │                    │
│                        │  ┌────────┐  │                    │
│                        │  │PostgreSQL│                    │
│                        │  └────────┘  │                    │
│                        └──────────────┘                    │
└─────────────────────────────────────────────────────────────┘
```

**Components:**
- **Config UI** (Port 4000): Web interface for DevLake configuration
- **Telemetry Webhook** (Port 8080): Endpoint for telemetry data collection
- **PostgreSQL**: Database for storing all metrics
- **Grafana** (Optional, Port 3000): Dashboards for visualization

---

## Installation Steps

### 1. Prepare the Server

```bash
# SSH into your data center server
ssh admin@devlake-server.yourcompany.internal

# Update system packages
sudo apt update && sudo apt upgrade -y  # Ubuntu/Debian
# OR
sudo yum update -y                       # RHEL/CentOS

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify installation
docker --version
docker-compose --version
```

### 2. Set Up Directory Structure

```bash
# Create project directory
sudo mkdir -p /opt/devlake
sudo chown $USER:$USER /opt/devlake
cd /opt/devlake

# Create directory structure
mkdir -p {data,logs,plugins,config,ssl}
```

### 3. Clone DevLake Repository

```bash
# Clone official DevLake
git clone https://github.com/apache/incubator-devlake.git devlake-source
cd devlake-source

# Checkout stable version
git checkout v0.20.0  # Use latest stable release
```

---

## Custom Plugin Integration

### 1. Add Telemetry Plugin to DevLake

```bash
cd /opt/devlake/devlake-source/backend/plugins

# Create plugin directory
mkdir -p developer_telemetry

# Copy your plugin code (from development machine or Git repo)
# Option A: Clone from your plugin repo
git clone https://github.com/yourcompany/devlake-telemetry-plugin.git developer_telemetry

# Option B: Copy via SCP
# (Run from your local machine)
scp -r ./plugins/developer_telemetry admin@devlake-server:/opt/devlake/devlake-source/backend/plugins/
```

### 2. Create Custom Dockerfile

Create `/opt/devlake/Dockerfile.custom`:

```dockerfile
FROM apache/devlake:v0.20.0

# Copy custom telemetry plugin
COPY ./devlake-source/backend/plugins/developer_telemetry /app/backend/plugins/developer_telemetry

# Register plugin in the backend
# Note: This requires modifying /app/backend/server/services/init.go to include your plugin
# For now, we'll mount it as a volume and configure via environment

# Set working directory
WORKDIR /app

# Expose ports
EXPOSE 8080 4000

# Start DevLake
CMD ["./bin/lake"]
```

### 3. Create Docker Compose Configuration

Create `/opt/devlake/docker-compose.yml`:

```yaml
version: '3.9'

services:
  # PostgreSQL Database
  postgres:
    image: postgres:15-alpine
    container_name: devlake-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: devlake
      POSTGRES_USER: devlake
      POSTGRES_PASSWORD: ${DB_PASSWORD:-changeme}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - devlake-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U devlake"]
      interval: 10s
      timeout: 5s
      retries: 5

  # DevLake Backend (with custom plugin)
  devlake:
    build:
      context: .
      dockerfile: Dockerfile.custom
    container_name: devlake-backend
    restart: unless-stopped
    ports:
      - "4000:4000"   # Config UI
      - "8080:8080"   # API & Webhook
    environment:
      # Database Configuration
      DB_URL: postgres://devlake:${DB_PASSWORD:-changeme}@postgres:5432/devlake?sslmode=disable
      
      # DevLake Configuration
      PORT: 8080
      MODE: release
      API_TIMEOUT: 120s
      
      # Telemetry Plugin Configuration
      TELEMETRY_ENABLED: "true"
      TELEMETRY_WEBHOOK_SECRET: ${WEBHOOK_SECRET:-your-secret-token}
      
      # Encryption Key (generate with: openssl rand -hex 32)
      ENCRYPTION_SECRET: ${ENCRYPTION_SECRET}
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - ./data:/app/data
      - ./logs:/app/logs
      - ./config:/app/config
    networks:
      - devlake-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/ping"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Grafana (Optional - for dashboards)
  grafana:
    image: grafana/grafana:10.2.0
    container_name: devlake-grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD:-admin}
      GF_DATABASE_TYPE: postgres
      GF_DATABASE_HOST: postgres:5432
      GF_DATABASE_NAME: grafana
      GF_DATABASE_USER: devlake
      GF_DATABASE_PASSWORD: ${DB_PASSWORD:-changeme}
    depends_on:
      - postgres
    volumes:
      - grafana_data:/var/lib/grafana
    networks:
      - devlake-network

  # Nginx Reverse Proxy (for HTTPS)
  nginx:
    image: nginx:alpine
    container_name: devlake-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./config/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
    depends_on:
      - devlake
      - grafana
    networks:
      - devlake-network

volumes:
  postgres_data:
    driver: local
  grafana_data:
    driver: local

networks:
  devlake-network:
    driver: bridge
```

### 4. Create Environment File

Create `/opt/devlake/.env`:

```bash
# Database
DB_PASSWORD=your-strong-database-password

# Webhook Security
WEBHOOK_SECRET=your-webhook-secret-token

# Encryption (generate with: openssl rand -hex 32)
ENCRYPTION_SECRET=your-encryption-secret-key

# Grafana
GRAFANA_PASSWORD=your-grafana-admin-password
```

**Generate secure secrets:**
```bash
# Generate database password
openssl rand -base64 32 > /opt/devlake/.db_password

# Generate webhook secret
openssl rand -hex 32 > /opt/devlake/.webhook_secret

# Generate encryption key
openssl rand -hex 32 > /opt/devlake/.encryption_key

# Update .env file
cat <<EOF > /opt/devlake/.env
DB_PASSWORD=$(cat .db_password)
WEBHOOK_SECRET=$(cat .webhook_secret)
ENCRYPTION_SECRET=$(cat .encryption_key)
GRAFANA_PASSWORD=$(openssl rand -base64 16)
EOF

# Secure the file
chmod 600 /opt/devlake/.env
```

---

## Configuration

### 1. Create Nginx Configuration

Create `/opt/devlake/config/nginx.conf`:

```nginx
events {
    worker_connections 1024;
}

http {
    upstream devlake_backend {
        server devlake:8080;
    }

    upstream grafana_backend {
        server grafana:3000;
    }

    # HTTP to HTTPS redirect
    server {
        listen 80;
        server_name devlake.yourcompany.internal;
        return 301 https://$server_name$request_uri;
    }

    # HTTPS Server
    server {
        listen 443 ssl http2;
        server_name devlake.yourcompany.internal;

        # SSL Configuration
        ssl_certificate /etc/nginx/ssl/devlake.crt;
        ssl_certificate_key /etc/nginx/ssl/devlake.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        # DevLake UI
        location / {
            proxy_pass http://devlake_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Telemetry Webhook Endpoint
        location /api/plugins/developer-telemetry/ {
            proxy_pass http://devlake_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            
            # Rate limiting
            limit_req zone=telemetry burst=20 nodelay;
        }

        # Grafana
        location /grafana/ {
            proxy_pass http://grafana_backend/;
            proxy_set_header Host $host;
        }
    }

    # Rate limiting zone
    limit_req_zone $binary_remote_addr zone=telemetry:10m rate=10r/s;
}
```

### 2. Generate SSL Certificates

For internal data center deployment:

```bash
# Option A: Use your company's CA to issue a certificate
# (Contact your IT/Security team)

# Option B: Generate self-signed certificate (for testing)
cd /opt/devlake/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout devlake.key \
  -out devlake.crt \
  -subj "/CN=devlake.yourcompany.internal"

# Secure the key
chmod 600 devlake.key
```

### 3. Start DevLake

```bash
cd /opt/devlake

# Build custom image
docker-compose build

# Start services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f devlake
```

### 4. Verify Deployment

```bash
# Test Config UI
curl -k https://devlake.yourcompany.internal

# Test Telemetry Webhook
curl -X POST https://devlake.yourcompany.internal/api/plugins/developer-telemetry/1/report \
  -H "Authorization: Bearer $(cat .webhook_secret)" \
  -H "Content-Type: application/json" \
  -d '{
    "developer_id": "test@yourcompany.com",
    "date": "2026-02-13",
    "active_hours": 1,
    "commands": {"git": 5}
  }'
```

---

## Security Hardening

### 1. Firewall Configuration

```bash
# Allow only internal network access
sudo ufw allow from 10.0.0.0/8 to any port 80
sudo ufw allow from 10.0.0.0/8 to any port 443
sudo ufw allow from 10.0.0.0/8 to any port 22

# Enable firewall
sudo ufw enable
```

### 2. Update Telemetry Collector Configuration

On developer machines, update the webhook URL in the collector script:

```bash
# Update DEVLAKE_WEBHOOK_URL in collector config
sed -i 's|DEVLAKE_WEBHOOK_URL=.*|DEVLAKE_WEBHOOK_URL=https://devlake.yourcompany.internal/api/plugins/developer-telemetry/1/report|' \
  ~/.config/devlake-telemetry/config
```

### 3. Set Up Authentication

Add to `/opt/devlake/.env`:

```bash
# API Authentication
API_KEY_ENABLED=true
ADMIN_API_KEY=$(openssl rand -hex 32)
```

---

## Monitoring & Maintenance

### 1. Set Up Health Checks

Create `/opt/devlake/monitoring/healthcheck.sh`:

```bash
#!/bin/bash
# Health check script

WEBHOOK_URL="https://devlake.yourcompany.internal/api/ping"

if curl -sf "$WEBHOOK_URL" > /dev/null; then
  echo "✅ DevLake is healthy"
  exit 0
else
  echo "❌ DevLake is down!"
  # Send alert (email, Slack, etc.)
  exit 1
fi
```

### 2. Log Rotation

Create `/etc/logrotate.d/devlake`:

```
/opt/devlake/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
```

### 3. Resource Monitoring

```bash
# Monitor container resources
docker stats devlake-backend devlake-postgres

# Check disk usage
df -h /opt/devlake
```

---

## Backup & Recovery

### 1. Automated Backups

Create `/opt/devlake/scripts/backup.sh`:

```bash
#!/bin/bash
BACKUP_DIR="/opt/devlake/backups"
DATE=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup PostgreSQL
docker exec devlake-postgres pg_dump -U devlake devlake | \
  gzip > "$BACKUP_DIR/devlake_db_$DATE.sql.gz"

# Backup configuration
tar -czf "$BACKUP_DIR/devlake_config_$DATE.tar.gz" \
  /opt/devlake/config \
  /opt/devlake/.env \
  /opt/devlake/docker-compose.yml

# Keep only last 30 days of backups
find "$BACKUP_DIR" -name "*.gz" -mtime +30 -delete

echo "Backup completed: $DATE"
```

Schedule daily backups:

```bash
# Add to crontab
crontab -e

# Add line:
0 2 * * * /opt/devlake/scripts/backup.sh >> /opt/devlake/logs/backup.log 2>&1
```

### 2. Restore from Backup

```bash
# Stop services
cd /opt/devlake
docker-compose down

# Restore database
gunzip < backups/devlake_db_YYYYMMDD.sql.gz | \
  docker exec -i devlake-postgres psql -U devlake devlake

# Restore configuration
tar -xzf backups/devlake_config_YYYYMMDD.tar.gz -C /

# Restart services
docker-compose up -d
```

---

## Troubleshooting

### Common Issues

#### 1. Plugin Not Loading
```bash
# Check if plugin is in correct directory
docker exec devlake-backend ls -la /app/backend/plugins/developer_telemetry

# Check logs for plugin registration errors
docker logs devlake-backend | grep -i telemetry
```

#### 2. Webhook Not Receiving Data
```bash
# Test webhook endpoint
curl -v https://devlake.yourcompany.internal/api/plugins/developer-telemetry/1/report

# Check nginx logs
docker logs devlake-nginx
```

#### 3. Database Connection Issues
```bash
# Verify PostgreSQL is running
docker exec devlake-postgres pg_isready -U devlake

# Test connection from DevLake container
docker exec devlake-backend nc -zv postgres 5432
```

### Updating the Plugin

```bash
# Pull latest plugin code
cd /opt/devlake/devlake-source/backend/plugins/developer_telemetry
git pull

# Rebuild and restart
cd /opt/devlake
docker-compose build devlake
docker-compose up -d devlake
```

---

## Next Steps

1. **Configure Data Sources**: Add GitHub, Jira, etc. via the Config UI
2. **Set Up Dashboards**: Create Grafana dashboards for telemetry metrics
3. **Deploy Collectors**: Install telemetry collectors on developer machines
4. **Monitor Usage**: Track data ingestion and system health

## Support

For issues or questions:
- Internal DevOps: devops@yourcompany.com
- DevLake Docs: https://devlake.apache.org/docs
- Plugin Issues: Create ticket in your internal tracking system
