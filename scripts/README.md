# 🛠️ DevOps Scripts

Deployment, yönetim ve utility scriptleri bu klasörde yer alır.

## 📁 Yapı

```
scripts/
├── setup/                     # Initial setup scripts
│   ├── vm-setup.sh           # VM initialization
│   ├── k8s-setup.sh          # Kubernetes cluster setup
│   ├── docker-setup.sh       # Docker installation
│   └── monitoring-setup.sh   # Monitoring stack setup
├── deployment/               # Deployment scripts
│   ├── deploy-all.sh         # Full deployment
│   ├── deploy-app.sh         # Application deployment
│   ├── deploy-db.sh          # Database deployment
│   └── rollback.sh           # Rollback procedures
├── maintenance/              # Maintenance scripts
│   ├── backup.sh             # Database backup
│   ├── cleanup.sh            # System cleanup
│   ├── health-check.sh       # Health monitoring
│   └── log-rotation.sh       # Log management
├── security/                 # Security scripts
│   ├── cert-renewal.sh       # Certificate renewal
│   ├── security-scan.sh      # Security scanning
│   ├── audit.sh              # Security audit
│   └── compliance-check.sh   # Compliance verification
├── monitoring/               # Monitoring utilities
│   ├── alert-test.sh         # Alert testing
│   ├── dashboard-export.sh   # Dashboard backup
│   └── metric-collector.sh   # Custom metrics
└── utils/                    # Utility scripts
    ├── network-test.sh       # Network connectivity
    ├── performance-test.sh   # Performance testing
    ├── data-migration.sh     # Data migration
    └── config-validator.sh   # Configuration validation
```

## 🚀 Setup Scripts

### VM Setup (`vm-setup.sh`)
```bash
#!/bin/bash
# VM initialization and basic configuration

# Update system
sudo apt update && sudo apt upgrade -y

# Install essential packages
sudo apt install -y curl wget git htop vim

# Configure SSH
sudo systemctl enable ssh
sudo systemctl start ssh

# Set timezone
sudo timedatectl set-timezone Europe/Istanbul

# Configure firewall
sudo ufw enable
sudo ufw allow ssh
```

### Kubernetes Setup (`k8s-setup.sh`)
```bash
#!/bin/bash
# Kubernetes cluster initialization

# Install k3s (lightweight Kubernetes)
curl -sfL https://get.k3s.io | sh -

# Configure kubectl
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# Install Helm
curl https://get.helm.sh/helm-v3.12.0-linux-amd64.tar.gz | tar xz
sudo mv linux-amd64/helm /usr/local/bin/
```

## 🚢 Deployment Scripts

### Full Deployment (`deploy-all.sh`)
```bash
#!/bin/bash
# Complete platform deployment

set -e

echo "🚀 Starting full deployment..."

# Deploy infrastructure
./deploy-infrastructure.sh

# Deploy databases
./deploy-db.sh

# Deploy applications
./deploy-app.sh

# Deploy monitoring
./deploy-monitoring.sh

echo "✅ Deployment completed successfully!"
```

### Application Deployment (`deploy-app.sh`)
```bash
#!/bin/bash
# Application deployment script

NAMESPACE="fintech"
HELM_CHART="./helm/fintech-app"

# Create namespace if not exists
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Deploy with Helm
helm upgrade --install fintech-app $HELM_CHART \
  --namespace $NAMESPACE \
  --values values-production.yaml \
  --wait --timeout 600s

# Verify deployment
kubectl get pods -n $NAMESPACE
kubectl get services -n $NAMESPACE
```

## 🔧 Maintenance Scripts

### Database Backup (`backup.sh`)
```bash
#!/bin/bash
# Automated database backup

BACKUP_DIR="/backup/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# PostgreSQL backup
PGPASSWORD=$DB_PASSWORD pg_dump \
  -h $DB_HOST -U $DB_USER -d fintech \
  > $BACKUP_DIR/fintech_$(date +%Y%m%d_%H%M%S).sql

# Redis backup
redis-cli --rdb $BACKUP_DIR/redis_$(date +%Y%m%d_%H%M%S).rdb

# Compress backups
tar -czf $BACKUP_DIR.tar.gz $BACKUP_DIR
rm -rf $BACKUP_DIR

# Upload to S3 (if configured)
if [ -n "$AWS_S3_BUCKET" ]; then
  aws s3 cp $BACKUP_DIR.tar.gz s3://$AWS_S3_BUCKET/backups/
fi
```

### Health Check (`health-check.sh`)
```bash
#!/bin/bash
# System health monitoring

echo "🏥 Health Check Report - $(date)"
echo "=================================="

# Check system resources
echo "📊 System Resources:"
echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')"
echo "Memory Usage: $(free | grep Mem | awk '{printf("%.2f%%", $3/$2 * 100.0)}')"
echo "Disk Usage: $(df -h / | tail -1 | awk '{print $5}')"

# Check services
echo "🔧 Service Status:"
kubectl get pods -A --field-selector=status.phase!=Running

# Check database connections
echo "🗄️ Database Status:"
nc -z postgres 5432 && echo "PostgreSQL: ✅" || echo "PostgreSQL: ❌"
nc -z redis 6379 && echo "Redis: ✅" || echo "Redis: ❌"

# Check external APIs
echo "🌐 External Services:"
curl -s -o /dev/null -w "%{http_code}" https://api.exchange.com/health
```

## 🔐 Security Scripts

### Certificate Renewal (`cert-renewal.sh`)
```bash
#!/bin/bash
# Automated SSL certificate renewal

CERT_DIR="/etc/ssl/certs"
KEY_DIR="/etc/ssl/private"

# Check certificate expiration
check_cert_expiry() {
  local cert_file=$1
  local expiry_date=$(openssl x509 -enddate -noout -in $cert_file | cut -d= -f2)
  local expiry_epoch=$(date -d "$expiry_date" +%s)
  local current_epoch=$(date +%s)
  local days_left=$(( ($expiry_epoch - $current_epoch) / 86400 ))
  
  echo $days_left
}

# Renew certificates if needed
for cert in $CERT_DIR/*.crt; do
  days_left=$(check_cert_expiry $cert)
  if [ $days_left -lt 30 ]; then
    echo "Renewing certificate: $cert"
    # Certificate renewal logic here
  fi
done
```

### Security Scan (`security-scan.sh`)
```bash
#!/bin/bash
# Security vulnerability scanning

echo "🔍 Security Scan Report - $(date)"
echo "================================="

# Container image scanning
echo "📦 Container Security:"
for image in $(kubectl get pods -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n' | sort -u); do
  echo "Scanning: $image"
  trivy image $image --severity HIGH,CRITICAL
done

# Network port scanning
echo "🌐 Network Security:"
nmap -sS -O localhost

# File system permissions
echo "📁 File Permissions:"
find /etc -perm /o+w -type f 2>/dev/null
```

## 📊 Monitoring Scripts

### Alert Testing (`alert-test.sh`)
```bash
#!/bin/bash
# Test alerting system

echo "🚨 Testing Alert System..."

# Test high CPU alert
stress --cpu 8 --timeout 60s &

# Test high memory alert
stress --vm 1 --vm-bytes 1G --timeout 60s &

# Test disk space alert
dd if=/dev/zero of=/tmp/testfile bs=1M count=1000

# Test service down alert
kubectl scale deployment fintech-api --replicas=0

sleep 120

# Cleanup
kubectl scale deployment fintech-api --replicas=3
rm -f /tmp/testfile
```

### Performance Test (`performance-test.sh`)
```bash
#!/bin/bash
# API performance testing

API_BASE_URL="https://api.fintech.local"
CONCURRENT_USERS=100
TEST_DURATION=300

echo "🏎️ Performance Test Starting..."
echo "Target: $API_BASE_URL"
echo "Users: $CONCURRENT_USERS"
echo "Duration: ${TEST_DURATION}s"

# Load testing with wrk
wrk -t12 -c$CONCURRENT_USERS -d${TEST_DURATION}s \
  --script=./load-test.lua \
  $API_BASE_URL/api/v1/health

# Database performance test
echo "📊 Database Performance:"
sysbench --test=oltp prepare --mysql-user=test --mysql-password=test
sysbench --test=oltp run --mysql-user=test --mysql-password=test
```

## 🔧 Utility Scripts

### Network Test (`network-test.sh`)
```bash
#!/bin/bash
# Network connectivity testing

SERVICES=(
  "postgres:5432"
  "redis:6379"
  "kafka:9092"
  "elasticsearch:9200"
  "prometheus:9090"
  "grafana:3000"
)

echo "🌐 Network Connectivity Test"
echo "============================"

for service in "${SERVICES[@]}"; do
  host=$(echo $service | cut -d: -f1)
  port=$(echo $service | cut -d: -f2)
  
  if nc -z $host $port 2>/dev/null; then
    echo "✅ $service"
  else
    echo "❌ $service"
  fi
done

# Internet connectivity
if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
  echo "✅ Internet connectivity"
else
  echo "❌ Internet connectivity"
fi
```

## 📋 Script Usage

### Environment Variables
```bash
# Common environment variables
export NAMESPACE="fintech"
export REGISTRY="registry.fintech.local"
export DB_HOST="postgres.fintech.local"
export MONITORING_NAMESPACE="monitoring"
```

### Execution Permissions
```bash
# Make scripts executable
chmod +x scripts/**/*.sh

# Run setup
./scripts/setup/vm-setup.sh

# Deploy application
./scripts/deployment/deploy-app.sh

# Run health check
./scripts/maintenance/health-check.sh
``` 