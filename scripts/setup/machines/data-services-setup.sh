#!/bin/bash

# ======================================================================
# 🗄️ Data Services VM Setup Script (ARM64 optimized)
# ======================================================================
# Bu script data-services VM'ini kurar ve yapılandırır
# Hedef: PostgreSQL, Redis, InfluxDB, Backup Services
# ======================================================================

set -e

# Renkli output için
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# ======================================================================
# 🔧 Parametreler ve Konfigürasyonlar
# ======================================================================
MASTER_IP=${1:-""}
POSTGRES_PASSWORD=${2:-"$(openssl rand -base64 32)"}
REDIS_PASSWORD=${3:-"$(openssl rand -base64 32)"}

if [[ -z "$MASTER_IP" ]]; then
    error "Kullanım: $0 <master-ip> [postgres-password] [redis-password]"
fi

log "🗄️ Data Services VM kurulumu başlatılıyor..."
log "🎯 Master IP: $MASTER_IP"

# ======================================================================
# 🔍 Sistem Kontrolü
# ======================================================================
log "🔍 Sistem bilgileri kontrol ediliyor..."

# ARM64 mimarisi kontrolü
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" && "$ARCH" != "aarch64" ]]; then
    warn "Bu script ARM64 için optimize edilmiştir. Mevcut mimari: $ARCH"
fi

# Ubuntu sürüm kontrolü
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    log "OS: $NAME $VERSION"
    if [[ "$ID" != "ubuntu" ]]; then
        warn "Bu script Ubuntu için optimize edilmiştir"
    fi
fi

log "Mimari: $ARCH"
log "Çekirdek: $(uname -r)"
log "Bellek: $(free -h | awk '/^Mem:/ {print $2}')"

# ======================================================================
# 📦 Sistem Güncellemeleri ve Temel Paketler
# ======================================================================
log "📦 Sistem güncellemeleri yapılıyor..."

# Paket listesini güncelle
apt update -y

# Sistem paketlerini güncelle
apt upgrade -y

# Temel araçları kur
log "🛠️ Temel araçlar kuruluyor..."
apt install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    tree \
    jq \
    unzip \
    zip \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    openssl \
    net-tools \
    telnet \
    nmap \
    stress \
    iotop \
    iftop \
    rsync \
    cron

# ======================================================================
# 🐳 Docker Kurulumu (ARM64)
# ======================================================================
log "🐳 Docker ARM64 kurulumu başlatılıyor..."

# Docker'ın eski sürümlerini kaldır
apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Docker GPG anahtarını ekle
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Docker repository'sini ekle (ARM64)
echo \
  "deb [arch=arm64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Paket listesini güncelle
apt update -y

# Docker CE'yi kur
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Docker servisini başlat ve enable et
systemctl start docker
systemctl enable docker

# Ubuntu kullanıcısını docker grubuna ekle
usermod -aG docker ubuntu

# Docker kurulumunu test et
log "🧪 Docker kurulumu test ediliyor..."
docker --version

# ======================================================================
# ☸️ Kubernetes (k3s) Worker Node Kurulumu
# ======================================================================
log "☸️ Kubernetes (k3s) Worker Node kuruluyor..."

# k3s agent kurulumu
curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN_FILE=/tmp/k3s-token sh -

# Not: Token dosyası master node'dan kopyalanmalı
log "⚠️  Master node'dan token kopyalamayı unutmayın!"
log "🔧 Komut: scp ubuntu@${MASTER_IP}:/var/lib/rancher/k3s/server/node-token /tmp/k3s-token"

# k3s-agent servisini enable et
systemctl enable k3s-agent

# kubectl kurulumu
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# ======================================================================
# 🐘 PostgreSQL Kurulumu ve Konfigürasyonu
# ======================================================================
log "🐘 PostgreSQL ARM64 kurulumu başlatılıyor..."

# PostgreSQL resmi repository'sini ekle
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# Paket listesini güncelle
apt update -y

# PostgreSQL 15'i kur
apt install -y postgresql-15 postgresql-client-15 postgresql-contrib-15

# PostgreSQL servisini başlat ve enable et
systemctl start postgresql
systemctl enable postgresql

# PostgreSQL konfigürasyonu
log "🔧 PostgreSQL konfigürasyonu yapılıyor..."

# postgres kullanıcısı için parola ayarla
sudo -u postgres psql -c "ALTER USER postgres PASSWORD '$POSTGRES_PASSWORD';"

# Fintech database oluştur
sudo -u postgres createdb fintech
sudo -u postgres psql -d fintech -c "CREATE EXTENSION IF NOT EXISTS uuid-ossp;"
sudo -u postgres psql -d fintech -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"

# PostgreSQL konfigürasyon dosyalarını düzenle
PG_VERSION="15"
PG_CONFIG_DIR="/etc/postgresql/$PG_VERSION/main"

# postgresql.conf optimizasyonları
cat >> "$PG_CONFIG_DIR/postgresql.conf" << 'EOF'

# Fintech Optimizations
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 4MB
maintenance_work_mem = 64MB
wal_buffers = 16MB
checkpoint_completion_target = 0.9
random_page_cost = 1.1
effective_io_concurrency = 200

# Connection settings
max_connections = 200
listen_addresses = '*'
port = 5432

# Logging
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_statement = 'mod'
log_min_duration_statement = 1000

# SSL
ssl = on
ssl_cert_file = '/etc/ssl/certs/ssl-cert-snakeoil.pem'
ssl_key_file = '/etc/ssl/private/ssl-cert-snakeoil.key'
EOF

# pg_hba.conf güvenlik ayarları
cp "$PG_CONFIG_DIR/pg_hba.conf" "$PG_CONFIG_DIR/pg_hba.conf.backup"
cat > "$PG_CONFIG_DIR/pg_hba.conf" << 'EOF'
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections
local   all             postgres                                peer
local   all             all                                     md5

# IPv4 local connections
host    all             all             127.0.0.1/32            md5

# Fintech application connections
host    fintech         fintech         10.0.0.0/8              md5
host    fintech         fintech         172.16.0.0/12           md5
host    fintech         fintech         192.168.0.0/16          md5

# SSL connections
hostssl all             all             0.0.0.0/0               md5
EOF

# PostgreSQL'i yeniden başlat
systemctl restart postgresql

# Fintech kullanıcısı oluştur
sudo -u postgres psql -c "CREATE USER fintech WITH PASSWORD '$POSTGRES_PASSWORD';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE fintech TO fintech;"
sudo -u postgres psql -d fintech -c "GRANT ALL ON SCHEMA public TO fintech;"

# ======================================================================
# 🔴 Redis Kurulumu ve Konfigürasyonu
# ======================================================================
log "🔴 Redis ARM64 kurulumu başlatılıyor..."

# Redis kurulumu
apt install -y redis-server

# Redis konfigürasyonu
log "🔧 Redis konfigürasyonu yapılıyor..."

# Redis konfigürasyon dosyasını backup al
cp /etc/redis/redis.conf /etc/redis/redis.conf.backup

# Redis konfigürasyonunu düzenle
cat > /etc/redis/redis.conf << EOF
# Network
bind 0.0.0.0
port 6379
protected-mode yes
requirepass $REDIS_PASSWORD

# General
daemonize yes
supervised systemd
pidfile /run/redis/redis-server.pid
loglevel notice
logfile /var/log/redis/redis-server.log

# Snapshotting
save 900 1
save 300 10
save 60 10000
dir /var/lib/redis
dbfilename dump.rdb

# Memory management
maxmemory 512mb
maxmemory-policy allkeys-lru

# Append only file
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Security
rename-command FLUSHALL ""
rename-command FLUSHDB ""
rename-command DEBUG ""

# Performance
tcp-keepalive 300
timeout 0
tcp-backlog 511
databases 16
EOF

# Redis servisini yeniden başlat
systemctl restart redis-server
systemctl enable redis-server

# ======================================================================
# 📊 InfluxDB Kurulumu (Time Series Database)
# ======================================================================
log "📊 InfluxDB ARM64 kurulumu başlatılıyor..."

# InfluxDB repository'sini ekle
wget -qO- https://repos.influxdata.com/influxdb.key | apt-key add -
echo "deb https://repos.influxdata.com/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/influxdb.list

# Paket listesini güncelle
apt update -y

# InfluxDB kurulumu
apt install -y influxdb

# InfluxDB konfigürasyonu
cat > /etc/influxdb/influxdb.conf << 'EOF'
[meta]
  dir = "/var/lib/influxdb/meta"

[data]
  dir = "/var/lib/influxdb/data"
  wal-dir = "/var/lib/influxdb/wal"
  series-id-set-cache-size = 100

[coordinator]
  write-timeout = "10s"
  max-concurrent-queries = 0
  query-timeout = "0s"

[retention]
  enabled = true
  check-interval = "30m"

[shard-precreation]
  enabled = true
  check-interval = "10m"
  advance-period = "30m"

[admin]
  enabled = false

[monitor]
  store-enabled = true
  store-database = "_internal"
  store-interval = "10s"

[http]
  enabled = true
  bind-address = ":8086"
  auth-enabled = false
  log-enabled = true
  write-tracing = false
  pprof-enabled = true
  debug-pprof-enabled = false
  https-enabled = false

[logging]
  format = "auto"
  level = "info"
  suppress-logo = false

[subscriber]
  enabled = true
  http-timeout = "30s"

[[graphite]]
  enabled = false

[[collectd]]
  enabled = false

[[opentsdb]]
  enabled = false

[[udp]]
  enabled = false

[continuous_queries]
  enabled = true
  log-enabled = true
  run-interval = "1s"
EOF

# InfluxDB servisini başlat ve enable et
systemctl start influxdb
systemctl enable influxdb

# InfluxDB'de fintech database oluştur
sleep 5
influx -execute "CREATE DATABASE fintech"
influx -execute "CREATE RETENTION POLICY \"one_year\" ON \"fintech\" DURATION 52w REPLICATION 1 DEFAULT"

# ======================================================================
# 📊 Monitoring Araçları
# ======================================================================
log "📊 Monitoring araçları kuruluyor..."

# Node Exporter kurulumu (ARM64)
NODE_EXPORTER_VERSION="1.7.0"
wget "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-arm64.tar.gz" \
    -O /tmp/node_exporter.tar.gz
tar -xzf /tmp/node_exporter.tar.gz -C /tmp
mv "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-arm64/node_exporter" /usr/local/bin/
rm -rf /tmp/node_exporter*

# Node Exporter systemd service
cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=nobody
Group=nogroup
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start node_exporter
systemctl enable node_exporter

# PostgreSQL Exporter kurulumu
POSTGRES_EXPORTER_VERSION="0.15.0"
wget "https://github.com/prometheus-community/postgres_exporter/releases/download/v${POSTGRES_EXPORTER_VERSION}/postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-arm64.tar.gz" \
    -O /tmp/postgres_exporter.tar.gz
tar -xzf /tmp/postgres_exporter.tar.gz -C /tmp
mv "/tmp/postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-arm64/postgres_exporter" /usr/local/bin/
rm -rf /tmp/postgres_exporter*

# PostgreSQL Exporter service
cat > /etc/systemd/system/postgres_exporter.service << EOF
[Unit]
Description=PostgreSQL Exporter
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
Environment=DATA_SOURCE_NAME=postgresql://fintech:$POSTGRES_PASSWORD@localhost:5432/fintech?sslmode=disable
ExecStart=/usr/local/bin/postgres_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start postgres_exporter
systemctl enable postgres_exporter

# Redis Exporter kurulumu
REDIS_EXPORTER_VERSION="1.55.0"
wget "https://github.com/oliver006/redis_exporter/releases/download/v${REDIS_EXPORTER_VERSION}/redis_exporter-v${REDIS_EXPORTER_VERSION}.linux-arm64.tar.gz" \
    -O /tmp/redis_exporter.tar.gz
tar -xzf /tmp/redis_exporter.tar.gz -C /tmp
mv "/tmp/redis_exporter-v${REDIS_EXPORTER_VERSION}.linux-arm64/redis_exporter" /usr/local/bin/
rm -rf /tmp/redis_exporter*

# Redis Exporter service
cat > /etc/systemd/system/redis_exporter.service << EOF
[Unit]
Description=Redis Exporter
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
Environment=REDIS_ADDR=redis://localhost:6379
Environment=REDIS_PASSWORD=$REDIS_PASSWORD
ExecStart=/usr/local/bin/redis_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start redis_exporter
systemctl enable redis_exporter

# ======================================================================
# 💾 Backup Sistemi
# ======================================================================
log "💾 Backup sistemi kuruluyor..."

# Backup dizinleri oluştur
mkdir -p /backup/{postgres,redis,influxdb}
mkdir -p /backup/scripts

# PostgreSQL backup scripti
cat > /backup/scripts/postgres-backup.sh << EOF
#!/bin/bash
BACKUP_DIR="/backup/postgres"
DATE=\$(date +%Y%m%d_%H%M%S)
PGPASSWORD="$POSTGRES_PASSWORD"

# Full backup
pg_dump -h localhost -U fintech -d fintech > "\$BACKUP_DIR/fintech_\$DATE.sql"

# Compress backup
gzip "\$BACKUP_DIR/fintech_\$DATE.sql"

# Keep only last 7 days
find \$BACKUP_DIR -name "*.gz" -mtime +7 -delete

echo "PostgreSQL backup completed: fintech_\$DATE.sql.gz"
EOF

# Redis backup scripti
cat > /backup/scripts/redis-backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/redis"
DATE=$(date +%Y%m%d_%H%M%S)

# Copy RDB file
cp /var/lib/redis/dump.rdb "$BACKUP_DIR/redis_$DATE.rdb"

# Copy AOF file
cp /var/lib/redis/appendonly.aof "$BACKUP_DIR/redis_$DATE.aof"

# Compress backups
gzip "$BACKUP_DIR/redis_$DATE.rdb"
gzip "$BACKUP_DIR/redis_$DATE.aof"

# Keep only last 7 days
find $BACKUP_DIR -name "*.gz" -mtime +7 -delete

echo "Redis backup completed: redis_$DATE"
EOF

# InfluxDB backup scripti
cat > /backup/scripts/influxdb-backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/influxdb"
DATE=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p "$BACKUP_DIR/$DATE"

# Backup database
influxd backup -portable "$BACKUP_DIR/$DATE"

# Compress backup
tar -czf "$BACKUP_DIR/influxdb_$DATE.tar.gz" -C "$BACKUP_DIR" "$DATE"
rm -rf "$BACKUP_DIR/$DATE"

# Keep only last 7 days
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete

echo "InfluxDB backup completed: influxdb_$DATE.tar.gz"
EOF

# Master backup scripti
cat > /backup/scripts/backup-all.sh << 'EOF'
#!/bin/bash
echo "Starting database backups - $(date)"

# Run all backup scripts
/backup/scripts/postgres-backup.sh
/backup/scripts/redis-backup.sh
/backup/scripts/influxdb-backup.sh

echo "All backups completed - $(date)"
EOF

# Script izinleri
chmod +x /backup/scripts/*.sh
chown -R ubuntu:ubuntu /backup

# Crontab ile otomatik backup (her gün 02:00)
(crontab -l 2>/dev/null; echo "0 2 * * * /backup/scripts/backup-all.sh >> /var/log/backup.log 2>&1") | crontab -

# ======================================================================
# 🔒 Güvenlik Konfigürasyonları
# ======================================================================
log "🔒 Güvenlik konfigürasyonları yapılıyor..."

# SSH güvenlik ayarları
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart ssh

# Firewall ayarları
ufw allow OpenSSH
ufw allow from $MASTER_IP to any port 5432   # PostgreSQL
ufw allow from $MASTER_IP to any port 6379   # Redis
ufw allow from $MASTER_IP to any port 8086   # InfluxDB
ufw allow from $MASTER_IP to any port 9100   # Node Exporter
ufw allow from $MASTER_IP to any port 9187   # PostgreSQL Exporter
ufw allow from $MASTER_IP to any port 9121   # Redis Exporter
ufw allow from $MASTER_IP to any port 10250  # Kubelet
ufw --force enable

# Otomatik güvenlik güncellemeleri
apt install -y unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades

# ======================================================================
# 📝 Kurulum Özeti ve Bilgiler
# ======================================================================
log "📝 Kurulum özeti oluşturuluyor..."

cat > /home/ubuntu/data-services-info.txt << EOF
🗄️ Data Services VM Kurulum Özeti
=================================
📅 Kurulum Tarihi: $(date)
🖥️  Hostname: $(hostname)
🌐 IP Adres: $(hostname -I | awk '{print $1}')
💾 Mimari: $(uname -m)
🎯 Master IP: $MASTER_IP

🚀 Kurulan Servisler:
-------------------
✅ Docker & Container Runtime
✅ Kubernetes (k3s) Worker Node
✅ PostgreSQL 15 Database
✅ Redis Cache & Pub/Sub
✅ InfluxDB Time Series DB
✅ Node Exporter (Monitoring)
✅ PostgreSQL Exporter
✅ Redis Exporter
✅ Automated Backup System

🔗 Database Connections:
----------------------
🐘 PostgreSQL: $(hostname -I | awk '{print $1}'):5432
   Database: fintech
   User: fintech
   Password: [Check credentials file]

🔴 Redis: $(hostname -I | awk '{print $1}'):6379
   Password: [Check credentials file]

📊 InfluxDB: $(hostname -I | awk '{print $1}'):8086
   Database: fintech

🔗 Monitoring Endpoints:
----------------------
📊 Node Exporter: http://$(hostname -I | awk '{print $1}'):9100
🐘 PostgreSQL Exporter: http://$(hostname -I | awk '{print $1}'):9187
🔴 Redis Exporter: http://$(hostname -I | awk '{print $1}'):9121

💾 Backup Configuration:
-----------------------
📁 Backup Directory: /backup/
🕐 Schedule: Daily at 02:00 AM
📋 Retention: 7 days

📋 Sonraki Adımlar:
-----------------
1. Master node'dan k3s token'ını kopyalayın
2. Database connection'ları test edin
3. Backup sistemini test edin
4. Monitoring dashboard'larını kurun

EOF

# Credentials dosyası oluştur
cat > /home/ubuntu/database-credentials.txt << EOF
🔐 Database Credentials
======================

PostgreSQL:
-----------
Host: $(hostname -I | awk '{print $1}')
Port: 5432
Database: fintech
Username: fintech
Password: $POSTGRES_PASSWORD

Redis:
------
Host: $(hostname -I | awk '{print $1}')
Port: 6379
Password: $REDIS_PASSWORD

InfluxDB:
---------
Host: $(hostname -I | awk '{print $1}')
Port: 8086
Database: fintech
(No authentication configured)

Connection Strings:
------------------
PostgreSQL: postgresql://fintech:$POSTGRES_PASSWORD@$(hostname -I | awk '{print $1}'):5432/fintech
Redis: redis://:$REDIS_PASSWORD@$(hostname -I | awk '{print $1}'):6379
InfluxDB: http://$(hostname -I | awk '{print $1}'):8086

EOF

# Dosya izinleri
chown ubuntu:ubuntu /home/ubuntu/data-services-info.txt
chown ubuntu:ubuntu /home/ubuntu/database-credentials.txt
chmod 600 /home/ubuntu/database-credentials.txt

# ======================================================================
# ✅ Kurulum Tamamlandı
# ======================================================================
log "✅ Data Services VM kurulumu başarıyla tamamlandı!"
log "📄 Detaylı bilgiler: /home/ubuntu/data-services-info.txt"
log "🔐 Database credentials: /home/ubuntu/database-credentials.txt"
log ""
log "🗄️ Database endpoints:"
log "  🐘 PostgreSQL: $(hostname -I | awk '{print $1}'):5432"
log "  🔴 Redis: $(hostname -I | awk '{print $1}'):6379"
log "  📊 InfluxDB: $(hostname -I | awk '{print $1}'):8086"
log ""
log "📊 Monitoring:"
log "  📊 Node Exporter: http://$(hostname -I | awk '{print $1}'):9100"
log "  🐘 PostgreSQL Exporter: http://$(hostname -I | awk '{print $1}'):9187"
log "  🔴 Redis Exporter: http://$(hostname -I | awk '{print $1}'):9121"
log ""
log "⚠️  K3s token'ını master node'dan kopyalamayı unutmayın!"
log "🎯 Sistem yeniden başlatılması önerilir: sudo reboot"

# ======================================================================
# 🔄 Son Kontroller
# ======================================================================
log "🔄 Servis durumları kontrol ediliyor..."

services=("docker" "postgresql" "redis-server" "influxdb" "node_exporter" "postgres_exporter" "redis_exporter")
for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        log "✅ $service aktif"
    else
        warn "❌ $service aktif değil"
    fi
done

# Database bağlantı testleri
log "🔍 Database bağlantı testleri..."

# PostgreSQL test
if sudo -u postgres psql -c '\l' > /dev/null 2>&1; then
    log "✅ PostgreSQL bağlantısı başarılı"
else
    warn "❌ PostgreSQL bağlantı sorunu"
fi

# Redis test
if redis-cli -a "$REDIS_PASSWORD" ping | grep -q PONG; then
    log "✅ Redis bağlantısı başarılı"
else
    warn "❌ Redis bağlantı sorunu"
fi

# InfluxDB test
if curl -s "http://localhost:8086/ping" > /dev/null; then
    log "✅ InfluxDB bağlantısı başarılı"
else
    warn "❌ InfluxDB bağlantı sorunu"
fi

log "🎉 Kurulum scripti tamamlandı!" 