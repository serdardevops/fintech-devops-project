#!/bin/bash

# ======================================================================
# 📊 Monitoring VM Setup Script (ARM64 optimized)
# ======================================================================
# Bu script monitoring VM'ini kurar ve yapılandırır
# Hedef: Prometheus, Grafana, ELK Stack, Alertmanager
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
MASTER_IP=${1:-""}
GRAFANA_PASSWORD=${2:-"$(openssl rand -base64 32)"}

if [[ -z "$MASTER_IP" ]]; then
    error "Kullanım: $0 <master-ip> [grafana-admin-password]"
fi

log "📊 Monitoring VM kurulumu başlatılıyor..."
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
    openjdk-11-jdk

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
# 📊 Prometheus Kurulumu (ARM64)
# ======================================================================
log "📊 Prometheus ARM64 kurulumu başlatılıyor..."

# Prometheus kullanıcısı oluştur
useradd --no-create-home --shell /bin/false prometheus

# Prometheus dizinleri oluştur
mkdir -p /etc/prometheus /var/lib/prometheus
chown prometheus:prometheus /var/lib/prometheus

# Prometheus ARM64 binary'sini indir
PROMETHEUS_VERSION="2.48.0"
wget "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-arm64.tar.gz" \
    -O /tmp/prometheus.tar.gz
tar -xzf /tmp/prometheus.tar.gz -C /tmp
mv "/tmp/prometheus-${PROMETHEUS_VERSION}.linux-arm64/prometheus" /usr/local/bin/
mv "/tmp/prometheus-${PROMETHEUS_VERSION}.linux-arm64/promtool" /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
rm -rf /tmp/prometheus*

# Prometheus konfigürasyonu
cat > /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "fintech_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - localhost:9093

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: 
        - '$MASTER_IP:9100'
        - 'localhost:9100'
    # Diğer node'lar eklenecek

  - job_name: 'postgres-exporter'
    static_configs:
      - targets: 
        - 'data-services:9187'

  - job_name: 'redis-exporter'
    static_configs:
      - targets: 
        - 'data-services:9121'

  - job_name: 'cadvisor'
    static_configs:
      - targets:
        - 'fintech-app-1:8080'
        - 'fintech-app-2:8080'

  - job_name: 'jenkins'
    static_configs:
      - targets:
        - '$MASTER_IP:8080'
    metrics_path: '/prometheus'

  - job_name: 'kubernetes-apiservers'
    kubernetes_sd_configs:
    - role: endpoints
    scheme: https
    tls_config:
      ca_file: /var/lib/rancher/k3s/agent/client-ca.crt
      cert_file: /var/lib/rancher/k3s/agent/client-kube-proxy.crt
      key_file: /var/lib/rancher/k3s/agent/client-kube-proxy.key
    relabel_configs:
    - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
      action: keep
      regex: default;kubernetes;https

  - job_name: 'kubernetes-nodes'
    kubernetes_sd_configs:
    - role: node
    scheme: https
    tls_config:
      ca_file: /var/lib/rancher/k3s/agent/client-ca.crt
      cert_file: /var/lib/rancher/k3s/agent/client-kube-proxy.crt
      key_file: /var/lib/rancher/k3s/agent/client-kube-proxy.key
    relabel_configs:
    - action: labelmap
      regex: __meta_kubernetes_node_label_(.+)
EOF

# Prometheus alert rules
cat > /etc/prometheus/fintech_rules.yml << 'EOF'
groups:
- name: fintech.rules
  rules:
  - alert: HighErrorRate
    expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.1
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High error rate detected"
      description: "Error rate is {{ $value }} errors per second"

  - alert: DatabaseDown
    expr: up{job="postgres-exporter"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "PostgreSQL is down"
      description: "PostgreSQL database is not responding"

  - alert: RedisDown
    expr: up{job="redis-exporter"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Redis is down"
      description: "Redis cache is not responding"

  - alert: HighCPUUsage
    expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High CPU usage"
      description: "CPU usage is above 80%"

  - alert: HighMemoryUsage
    expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "High memory usage"
      description: "Memory usage is above 90%"

  - alert: DiskSpaceLow
    expr: (1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)) * 100 > 85
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Low disk space"
      description: "Disk usage is above 85%"
EOF

chown -R prometheus:prometheus /etc/prometheus

# Prometheus systemd service
cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.listen-address=0.0.0.0:9090 \
    --web.enable-lifecycle

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start prometheus
systemctl enable prometheus

# ======================================================================
# 🚨 Alertmanager Kurulumu (ARM64)
# ======================================================================
log "🚨 Alertmanager ARM64 kurulumu başlatılıyor..."

# Alertmanager kullanıcısı
useradd --no-create-home --shell /bin/false alertmanager

# Alertmanager dizinleri
mkdir -p /etc/alertmanager /var/lib/alertmanager
chown alertmanager:alertmanager /var/lib/alertmanager

# Alertmanager ARM64 binary'sini indir
ALERTMANAGER_VERSION="0.26.0"
wget "https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-arm64.tar.gz" \
    -O /tmp/alertmanager.tar.gz
tar -xzf /tmp/alertmanager.tar.gz -C /tmp
mv "/tmp/alertmanager-${ALERTMANAGER_VERSION}.linux-arm64/alertmanager" /usr/local/bin/
mv "/tmp/alertmanager-${ALERTMANAGER_VERSION}.linux-arm64/amtool" /usr/local/bin/
chown alertmanager:alertmanager /usr/local/bin/alertmanager /usr/local/bin/amtool
rm -rf /tmp/alertmanager*

# Alertmanager konfigürasyonu
cat > /etc/alertmanager/alertmanager.yml << 'EOF'
global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'alertmanager@fintech.local'

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'
  routes:
  - match:
      severity: critical
    receiver: critical-alerts
  - match:
      severity: warning
    receiver: warning-alerts

receivers:
- name: 'web.hook'
  webhook_configs:
  - url: 'http://127.0.0.1:5001/'

- name: 'critical-alerts'
  slack_configs:
  - api_url: 'YOUR_SLACK_WEBHOOK_URL'
    channel: '#critical-alerts'
    title: 'Fintech Critical Alert'
    text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'

- name: 'warning-alerts'
  slack_configs:
  - api_url: 'YOUR_SLACK_WEBHOOK_URL'
    channel: '#alerts'
    title: 'Fintech Warning Alert'
    text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
EOF

chown -R alertmanager:alertmanager /etc/alertmanager

# Alertmanager systemd service
cat > /etc/systemd/system/alertmanager.service << 'EOF'
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/local/bin/alertmanager \
    --config.file=/etc/alertmanager/alertmanager.yml \
    --storage.path=/var/lib/alertmanager/ \
    --web.listen-address=0.0.0.0:9093

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start alertmanager
systemctl enable alertmanager

# ======================================================================
# 📈 Grafana Kurulumu (ARM64)
# ======================================================================
log "📈 Grafana ARM64 kurulumu başlatılıyor..."

# Grafana repository'sini ekle
wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" > /etc/apt/sources.list.d/grafana.list

# Paket listesini güncelle
apt update -y

# Grafana kurulumu
apt install -y grafana

# Grafana konfigürasyonu
cat > /etc/grafana/grafana.ini << EOF
[server]
http_addr = 0.0.0.0
http_port = 3000
domain = $(hostname -I | awk '{print $1}')
root_url = http://$(hostname -I | awk '{print $1}'):3000/

[security]
admin_user = admin
admin_password = $GRAFANA_PASSWORD
secret_key = $(openssl rand -base64 32)

[database]
type = sqlite3
path = grafana.db

[session]
provider = file

[analytics]
reporting_enabled = false
check_for_updates = false

[log]
mode = console file
level = info

[log.console]
level = info

[log.file]
level = info
log_rotate = true
max_lines = 1000000
max_size_shift = 28
daily_rotate = true
max_days = 7

[alerting]
enabled = true
execute_alerts = true

[unified_alerting]
enabled = true
EOF

# Grafana servisini başlat ve enable et
systemctl start grafana-server
systemctl enable grafana-server

# ======================================================================
# 📋 Elasticsearch Kurulumu (ARM64)
# ======================================================================
log "📋 Elasticsearch ARM64 kurulumu başlatılıyor..."

# Elasticsearch repository'sini ekle
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
echo "deb https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list

# Paket listesini güncelle
apt update -y

# Elasticsearch kurulumu
apt install -y elasticsearch

# Elasticsearch konfigürasyonu
cat > /etc/elasticsearch/elasticsearch.yml << 'EOF'
cluster.name: fintech-logs
node.name: monitoring-node
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node

# Disable security for single node
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false

# JVM settings
bootstrap.memory_lock: true
EOF

# Elasticsearch JVM ayarları
cat > /etc/elasticsearch/jvm.options.d/heap.options << 'EOF'
-Xms512m
-Xmx512m
EOF

# Elasticsearch servisini başlat ve enable et
systemctl start elasticsearch
systemctl enable elasticsearch

# ======================================================================
# 📄 Logstash Kurulumu (ARM64)
# ======================================================================
log "📄 Logstash ARM64 kurulumu başlatılıyor..."

# Logstash kurulumu
apt install -y logstash

# Logstash konfigürasyonu
cat > /etc/logstash/conf.d/fintech.conf << 'EOF'
input {
  beats {
    port => 5044
  }
  
  syslog {
    port => 514
  }
}

filter {
  if [fields][logtype] == "fintech" {
    grok {
      match => { "message" => "%{TIMESTAMP_ISO8601:timestamp} %{LOGLEVEL:level} %{DATA:service} %{GREEDYDATA:message_content}" }
    }
    
    date {
      match => [ "timestamp", "ISO8601" ]
    }
    
    if [level] == "ERROR" {
      mutate {
        add_tag => [ "error" ]
      }
    }
  }
  
  if [fields][logtype] == "access" {
    grok {
      match => { "message" => "%{COMBINEDAPACHELOG}" }
    }
  }
}

output {
  elasticsearch {
    hosts => ["localhost:9200"]
    index => "fintech-logs-%{+YYYY.MM.dd}"
  }
  
  if "error" in [tags] {
    email {
      to => "admin@fintech.local"
      subject => "Fintech Error Alert"
      body => "Error detected: %{message}"
    }
  }
}
EOF

# Logstash JVM ayarları
cat > /etc/logstash/jvm.options.d/heap.options << 'EOF'
-Xms256m
-Xmx256m
EOF

# Logstash servisini başlat ve enable et
systemctl start logstash
systemctl enable logstash

# ======================================================================
# 📊 Kibana Kurulumu (ARM64)
# ======================================================================
log "📊 Kibana ARM64 kurulumu başlatılıyor..."

# Kibana kurulumu
apt install -y kibana

# Kibana konfigürasyonu
cat > /etc/kibana/kibana.yml << EOF
server.port: 5601
server.host: "0.0.0.0"
server.publicBaseUrl: "http://$(hostname -I | awk '{print $1}'):5601"
elasticsearch.hosts: ["http://localhost:9200"]
logging.appenders.file.type: file
logging.appenders.file.fileName: /var/log/kibana/kibana.log
logging.appenders.file.layout.type: json
logging.root.appenders: [default, file]
pid.file: /run/kibana/kibana.pid
EOF

# Kibana log dizini
mkdir -p /var/log/kibana
chown kibana:kibana /var/log/kibana

# Kibana servisini başlat ve enable et
systemctl start kibana
systemctl enable kibana

# ======================================================================
# 📊 Node Exporter (Local)
# ======================================================================
log "📊 Node Exporter kuruluyor..."

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
ufw allow from $MASTER_IP to any port 9090    # Prometheus
ufw allow from $MASTER_IP to any port 9093    # Alertmanager
ufw allow from $MASTER_IP to any port 3000    # Grafana
ufw allow from $MASTER_IP to any port 9200    # Elasticsearch
ufw allow from $MASTER_IP to any port 5601    # Kibana
ufw allow from $MASTER_IP to any port 5044    # Logstash beats
ufw allow from $MASTER_IP to any port 9100    # Node Exporter
ufw allow from $MASTER_IP to any port 10250   # Kubelet
ufw --force enable

# Otomatik güvenlik güncellemeleri
apt install -y unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades

# ======================================================================
# 📝 Kurulum Özeti ve Bilgiler
# ======================================================================
log "📝 Kurulum özeti oluşturuluyor..."

cat > /home/ubuntu/monitoring-info.txt << EOF
📊 Monitoring VM Kurulum Özeti
=============================
📅 Kurulum Tarihi: $(date)
🖥️  Hostname: $(hostname)
🌐 IP Adres: $(hostname -I | awk '{print $1}')
💾 Mimari: $(uname -m)
🎯 Master IP: $MASTER_IP

🚀 Kurulan Servisler:
-------------------
✅ Docker & Container Runtime
✅ Kubernetes (k3s) Worker Node
✅ Prometheus (Metrics Collection)
✅ Alertmanager (Alert Management)
✅ Grafana (Visualization)
✅ Elasticsearch (Log Storage)
✅ Logstash (Log Processing)
✅ Kibana (Log Visualization)
✅ Node Exporter (System Metrics)

🔗 Monitoring Endpoints:
----------------------
📊 Prometheus: http://$(hostname -I | awk '{print $1}'):9090
🚨 Alertmanager: http://$(hostname -I | awk '{print $1}'):9093
📈 Grafana: http://$(hostname -I | awk '{print $1}'):3000
📋 Elasticsearch: http://$(hostname -I | awk '{print $1}'):9200
📊 Kibana: http://$(hostname -I | awk '{print $1}'):5601
📊 Node Exporter: http://$(hostname -I | awk '{print $1}'):9100

🔐 Login Credentials:
-------------------
📈 Grafana:
   URL: http://$(hostname -I | awk '{print $1}'):3000
   Username: admin
   Password: [Check credentials file]

📊 Kibana:
   URL: http://$(hostname -I | awk '{print $1}'):5601
   (No authentication configured)

📋 Sonraki Adımlar:
-----------------
1. Master node'dan k3s token'ını kopyalayın
2. Grafana'ya giriş yapın ve dashboard'ları import edin
3. Prometheus target'larını güncelleyin
4. Alertmanager notification'larını konfigüre edin
5. Kibana'da log index pattern'lerini oluşturun

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

# Credentials dosyası oluştur
cat > /home/ubuntu/monitoring-credentials.txt << EOF
🔐 Monitoring Credentials
========================

Grafana Admin:
--------------
URL: http://$(hostname -I | awk '{print $1}'):3000
Username: admin
Password: $GRAFANA_PASSWORD

Service URLs:
-------------
Prometheus: http://$(hostname -I | awk '{print $1}'):9090
Alertmanager: http://$(hostname -I | awk '{print $1}'):9093
Grafana: http://$(hostname -I | awk '{print $1}'):3000
Elasticsearch: http://$(hostname -I | awk '{print $1}'):9200
Kibana: http://$(hostname -I | awk '{print $1}'):5601

Configuration Files:
-------------------
Prometheus: /etc/prometheus/prometheus.yml
Alertmanager: /etc/alertmanager/alertmanager.yml
Grafana: /etc/grafana/grafana.ini
Elasticsearch: /etc/elasticsearch/elasticsearch.yml
Logstash: /etc/logstash/conf.d/fintech.conf
Kibana: /etc/kibana/kibana.yml

EOF

# Dosya izinleri
chown ubuntu:ubuntu /home/ubuntu/monitoring-info.txt
chown ubuntu:ubuntu /home/ubuntu/monitoring-credentials.txt
chmod 600 /home/ubuntu/monitoring-credentials.txt

# ======================================================================
# ✅ Kurulum Tamamlandı
# ======================================================================
log "✅ Monitoring VM kurulumu başarıyla tamamlandı!"
log "📄 Detaylı bilgiler: /home/ubuntu/monitoring-info.txt"
log "🔐 Credentials: /home/ubuntu/monitoring-credentials.txt"
log ""
log "🔗 Monitoring endpoints:"
log "  📊 Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
log "  🚨 Alertmanager: http://$(hostname -I | awk '{print $1}'):9093"
log "  📈 Grafana: http://$(hostname -I | awk '{print $1}'):3000"
log "  📋 Elasticsearch: http://$(hostname -I | awk '{print $1}'):9200"
log "  📊 Kibana: http://$(hostname -I | awk '{print $1}'):5601"
log ""
log "🔐 Grafana Login:"
log "  Username: admin"
log "  Password: $GRAFANA_PASSWORD"
log ""
log "⚠️  K3s token'ını master node'dan kopyalamayı unutmayın!"
log "🎯 Sistem yeniden başlatılması önerilir: sudo reboot"

# ======================================================================
# 🔄 Son Kontroller
# ======================================================================
log "🔄 Servis durumları kontrol ediliyor..."

services=("docker" "prometheus" "alertmanager" "grafana-server" "elasticsearch" "logstash" "kibana" "node_exporter")
for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        log "✅ $service aktif"
    else
        warn "❌ $service aktif değil"
    fi
done

# Service endpoint testleri
log "🔍 Service endpoint testleri..."

endpoints=(
    "http://localhost:9090/-/healthy:Prometheus"
    "http://localhost:9093/-/healthy:Alertmanager"
    "http://localhost:3000/api/health:Grafana"
    "http://localhost:9200:Elasticsearch"
    "http://localhost:5601/api/status:Kibana"
    "http://localhost:9100/metrics:NodeExporter"
)

for endpoint_info in "${endpoints[@]}"; do
    endpoint=$(echo $endpoint_info | cut -d: -f1)
    service_name=$(echo $endpoint_info | cut -d: -f2)
    
    if curl -s "$endpoint" > /dev/null; then
        log "✅ $service_name endpoint erişilebilir"
    else
        warn "❌ $service_name endpoint erişilemez"
    fi
done

log "🎉 Kurulum scripti tamamlandı!" 