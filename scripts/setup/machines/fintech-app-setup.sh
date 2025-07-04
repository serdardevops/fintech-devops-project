#!/bin/bash

# ======================================================================
# 🏦 Fintech Application VM Setup Script (ARM64 optimized)
# ======================================================================
# Bu script fintech-app-1 ve fintech-app-2 VM'lerini kurar
# Hedef: Docker, K8s Worker Node, Application Runtime
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
# 🔧 Parametreler
# ======================================================================
NODE_NAME=${1:-"fintech-app-node"}
MASTER_IP=${2:-""}

if [[ -z "$MASTER_IP" ]]; then
    error "Kullanım: $0 <node-name> <master-ip>"
fi

log "🏦 Fintech Application VM kurulumu başlatılıyor..."
log "📛 Node Name: $NODE_NAME"
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
    redis-tools \
    postgresql-client

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

# kubectl kurulumu (opsiyonel - worker node'da gerekli değil ama debug için faydalı)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# ======================================================================
# 🐍 Python Runtime Environment
# ======================================================================
log "🐍 Python runtime environment hazırlanıyor..."

# Python paketleri
pip3 install --upgrade pip setuptools wheel

# Fintech uygulaması için gerekli Python paketleri
pip3 install \
    fastapi \
    uvicorn \
    redis \
    psycopg2-binary \
    sqlalchemy \
    pydantic \
    python-jose \
    passlib \
    python-multipart \
    websockets \
    aioredis \
    celery \
    prometheus-client \
    structlog \
    httpx \
    asyncpg

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

# cAdvisor kurulumu (Container monitoring)
log "📦 cAdvisor container monitoring kuruluyor..."
docker run \
  --volume=/:/rootfs:ro \
  --volume=/var/run:/var/run:ro \
  --volume=/sys:/sys:ro \
  --volume=/var/lib/docker/:/var/lib/docker:ro \
  --volume=/dev/disk/:/dev/disk:ro \
  --publish=8080:8080 \
  --detach=true \
  --name=cadvisor \
  --privileged \
  --device=/dev/kmsg \
  --restart=unless-stopped \
  gcr.io/cadvisor/cadvisor:v0.47.2

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
ufw allow from $MASTER_IP to any port 10250  # kubelet
ufw allow from $MASTER_IP to any port 8080   # cAdvisor
ufw allow from $MASTER_IP to any port 9100   # node-exporter
ufw --force enable

# Otomatik güvenlik güncellemeleri
apt install -y unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades

# ======================================================================
# 🏦 Fintech Uygulama Dizinleri
# ======================================================================
log "🏦 Fintech uygulama dizinleri oluşturuluyor..."

# Uygulama dizinleri
mkdir -p /opt/fintech/{app,logs,config,data}
mkdir -p /opt/fintech/app/{api,worker,static}
mkdir -p /opt/fintech/logs/{app,nginx,system}

# Dizin izinleri
chown -R ubuntu:ubuntu /opt/fintech
chmod -R 755 /opt/fintech

# Log rotation konfigürasyonu
cat > /etc/logrotate.d/fintech << 'EOF'
/opt/fintech/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 ubuntu ubuntu
    postrotate
        systemctl reload fintech-api || true
    endscript
}
EOF

# ======================================================================
# 🌐 HAProxy Load Balancer (Local)
# ======================================================================
log "🌐 HAProxy load balancer kuruluyor..."

apt install -y haproxy

# HAProxy konfigürasyonu
cat > /etc/haproxy/haproxy.cfg << 'EOF'
global
    daemon
    user haproxy
    group haproxy
    log stdout local0

defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms
    option httplog
    log global

frontend fintech_frontend
    bind *:80
    default_backend fintech_backend

backend fintech_backend
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    
    # Local application instance
    server local_app 127.0.0.1:8000 check
    
    # Diğer node'lar eklenecek
    # server app1 fintech-app-1:8000 check
    # server app2 fintech-app-2:8000 check

listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 5s
EOF

# HAProxy'yi enable et ama henüz başlatma (uygulama henüz yok)
systemctl enable haproxy

# ======================================================================
# 🔧 Sistem Optimizasyonları
# ======================================================================
log "🔧 Sistem optimizasyonları yapılıyor..."

# Kernel parametreleri (Fintech uygulaması için)
cat >> /etc/sysctl.conf << 'EOF'

# Fintech Application Optimizations
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
vm.swappiness = 10
fs.file-max = 1000000
EOF

# Limits konfigürasyonu
cat >> /etc/security/limits.conf << 'EOF'

# Fintech Application Limits
ubuntu soft nofile 65536
ubuntu hard nofile 65536
ubuntu soft nproc 32768
ubuntu hard nproc 32768
EOF

# Sysctl ayarlarını uygula
sysctl -p

# ======================================================================
# 📝 Kurulum Özeti ve Bilgiler
# ======================================================================
log "📝 Kurulum özeti oluşturuluyor..."

cat > /home/ubuntu/fintech-app-info.txt << EOF
🏦 Fintech Application VM Kurulum Özeti
======================================
📅 Kurulum Tarihi: $(date)
🖥️  Hostname: $(hostname)
🌐 IP Adres: $(hostname -I | awk '{print $1}')
💾 Mimari: $(uname -m)
📛 Node Name: $NODE_NAME
🎯 Master IP: $MASTER_IP

🚀 Kurulan Servisler:
-------------------
✅ Docker & Container Runtime
✅ Kubernetes (k3s) Worker Node
✅ Python Runtime Environment
✅ Node Exporter (Monitoring)
✅ cAdvisor (Container Monitoring)
✅ HAProxy Load Balancer

🔗 Monitoring Endpoints:
----------------------
📊 Node Exporter: http://$(hostname -I | awk '{print $1}'):9100
📦 cAdvisor: http://$(hostname -I | awk '{print $1}'):8080
📈 HAProxy Stats: http://$(hostname -I | awk '{print $1}'):8404/stats

🏦 Fintech Directories:
---------------------
📁 App Directory: /opt/fintech/app
📋 Logs Directory: /opt/fintech/logs
⚙️  Config Directory: /opt/fintech/config
💾 Data Directory: /opt/fintech/data

📋 Sonraki Adımlar:
-----------------
1. Master node'dan k3s token'ını kopyalayın
2. Fintech uygulamasını deploy edin
3. HAProxy konfigürasyonunu güncelleyin
4. Load balancing testlerini yapın

🔧 Kubernetes Join Command:
--------------------------
# Master node'da çalıştırın:
sudo cat /var/lib/rancher/k3s/server/node-token

# Bu node'da çalıştırın:
sudo cat > /tmp/k3s-token << 'EOL'
[TOKEN_FROM_MASTER]
EOL

sudo systemctl restart k3s-agent

EOF

chown ubuntu:ubuntu /home/ubuntu/fintech-app-info.txt

# ======================================================================
# ✅ Kurulum Tamamlandı
# ======================================================================
log "✅ Fintech Application VM kurulumu başarıyla tamamlandı!"
log "📄 Detaylı bilgiler: /home/ubuntu/fintech-app-info.txt"
log ""
log "📊 Node Exporter: http://$(hostname -I | awk '{print $1}'):9100"
log "📦 cAdvisor: http://$(hostname -I | awk '{print $1}'):8080"
log "📈 HAProxy Stats: http://$(hostname -I | awk '{print $1}'):8404/stats"
log ""
log "⚠️  K3s token'ını master node'dan kopyalamayı unutmayın!"
log "🎯 Sistem yeniden başlatılması önerilir: sudo reboot"

# ======================================================================
# 🔄 Son Kontroller
# ======================================================================
log "🔄 Servis durumları kontrol ediliyor..."

services=("docker" "node_exporter" "haproxy")
for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        log "✅ $service aktif"
    else
        warn "❌ $service aktif değil"
    fi
done

# cAdvisor container kontrolü
if docker ps | grep -q cadvisor; then
    log "✅ cAdvisor container aktif"
else
    warn "❌ cAdvisor container aktif değil"
fi

log "🎉 Kurulum scripti tamamlandı!" 