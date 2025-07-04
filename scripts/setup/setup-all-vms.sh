#!/bin/bash

# ======================================================================
# 🚀 Fintech DevOps - Complete VM Setup Script (ARM64)
# ======================================================================
# Bu script tüm VM'leri oluşturur ve yapılandırır
# MacOS Multipass ortamında ARM64 için optimize edilmiştir
# ======================================================================

set -e

# Renkli output için
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

success() {
    echo -e "${CYAN}[SUCCESS] $1${NC}"
}

# ======================================================================
# 🔧 Konfigürasyon
# ======================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# VM konfigürasyonları
declare -A VM_CONFIGS
VM_CONFIGS["devops-master"]="2 4G 30G"
VM_CONFIGS["fintech-app-1"]="2 2G 20G"
VM_CONFIGS["fintech-app-2"]="2 2G 20G"
VM_CONFIGS["data-services"]="2 3G 30G"
VM_CONFIGS["monitoring"]="2 2G 20G"

# Network interface
NETWORK_INTERFACE="en0"

# Credentials (otomatik oluşturulacak)
POSTGRES_PASSWORD=""
REDIS_PASSWORD=""
GRAFANA_PASSWORD=""

log "🚀 Fintech DevOps VM Setup Script başlatılıyor..."
log "📁 Script directory: $SCRIPT_DIR"
log "📁 Project root: $PROJECT_ROOT"

# ======================================================================
# 🔍 Ön Kontroller
# ======================================================================
log "🔍 Ön kontroller yapılıyor..."

# Multipass kontrolü
if ! command -v multipass &> /dev/null; then
    error "Multipass kurulu değil! Lütfen önce Multipass'i kurun: https://multipass.run/"
fi

# ARM64 kontrolü
if [[ "$(uname -m)" != "arm64" ]]; then
    warn "Bu script ARM64 (Apple Silicon) için optimize edilmiştir"
fi

# Script dosyalarının varlığını kontrol et
SETUP_SCRIPTS=(
    "machines/devops-master-setup.sh"
    "machines/fintech-app-setup.sh"
    "machines/data-services-setup.sh"
    "machines/monitoring-setup.sh"
)

for script in "${SETUP_SCRIPTS[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
        error "Setup script bulunamadı: $SCRIPT_DIR/$script"
    fi
done

success "Ön kontroller başarıyla tamamlandı"

# ======================================================================
# 🔐 Credentials Oluştur
# ======================================================================
log "🔐 Güvenlik credentials'ları oluşturuluyor..."

POSTGRES_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
GRAFANA_PASSWORD=$(openssl rand -base64 32)

# Credentials dosyası oluştur
CREDENTIALS_FILE="$PROJECT_ROOT/vm-credentials.txt"
cat > "$CREDENTIALS_FILE" << EOF
🔐 Fintech DevOps VM Credentials
==============================
Generated: $(date)

PostgreSQL (data-services):
---------------------------
Password: $POSTGRES_PASSWORD

Redis (data-services):
---------------------
Password: $REDIS_PASSWORD

Grafana (monitoring):
--------------------
Admin Password: $GRAFANA_PASSWORD

SSH Access:
-----------
All VMs use SSH key authentication
Default user: ubuntu

⚠️  IMPORTANT: Store these credentials securely!
This file will be deleted after successful setup.
EOF

chmod 600 "$CREDENTIALS_FILE"
info "Credentials dosyası oluşturuldu: $CREDENTIALS_FILE"

# ======================================================================
# 🖥️ VM'leri Oluştur
# ======================================================================
log "🖥️ VM'ler oluşturuluyor..."

# Mevcut VM'leri kontrol et
existing_vms=$(multipass list --format csv | tail -n +2 | cut -d, -f1)

for vm_name in "${!VM_CONFIGS[@]}"; do
    if echo "$existing_vms" | grep -q "^$vm_name$"; then
        warn "VM zaten mevcut: $vm_name"
        continue
    fi
    
    config=(${VM_CONFIGS[$vm_name]})
    cpus=${config[0]}
    memory=${config[1]}
    disk=${config[2]}
    
    info "🔨 $vm_name oluşturuluyor (CPU: $cpus, RAM: $memory, Disk: $disk)..."
    
    multipass launch \
        --name "$vm_name" \
        --cpus "$cpus" \
        --memory "$memory" \
        --disk "$disk" \
        --network "$NETWORK_INTERFACE" \
        22.04
    
    success "$vm_name başarıyla oluşturuldu"
done

# VM'lerin hazır olmasını bekle
log "⏳ VM'lerin boot olmasını bekleniyor..."
sleep 30

# ======================================================================
# 📊 VM IP Adreslerini Al
# ======================================================================
log "📊 VM IP adresleri toplanıyor..."

declare -A VM_IPS
for vm_name in "${!VM_CONFIGS[@]}"; do
    vm_ip=$(multipass info "$vm_name" | grep "IPv4" | awk '{print $2}' | head -1)
    VM_IPS[$vm_name]="$vm_ip"
    info "$vm_name IP: $vm_ip"
done

MASTER_IP=${VM_IPS["devops-master"]}
if [[ -z "$MASTER_IP" ]]; then
    error "Master IP alınamadı!"
fi

success "Tüm VM IP adresleri başarıyla alındı"

# ======================================================================
# 🔧 Setup Scriptlerini Kopyala
# ======================================================================
log "🔧 Setup scriptlerini VM'lere kopyalanıyor..."

for vm_name in "${!VM_CONFIGS[@]}"; do
    info "📁 $vm_name'e scriptler kopyalanıyor..."
    
    # Script klasörünü oluştur
    multipass exec "$vm_name" -- mkdir -p /home/ubuntu/setup
    
    # Uygun setup scriptini kopyala
    case $vm_name in
        "devops-master")
            multipass transfer "$SCRIPT_DIR/machines/devops-master-setup.sh" "$vm_name:/home/ubuntu/setup/"
            ;;
        "fintech-app-1"|"fintech-app-2")
            multipass transfer "$SCRIPT_DIR/machines/fintech-app-setup.sh" "$vm_name:/home/ubuntu/setup/"
            ;;
        "data-services")
            multipass transfer "$SCRIPT_DIR/machines/data-services-setup.sh" "$vm_name:/home/ubuntu/setup/"
            ;;
        "monitoring")
            multipass transfer "$SCRIPT_DIR/machines/monitoring-setup.sh" "$vm_name:/home/ubuntu/setup/"
            ;;
    esac
    
    # Script'i executable yap
    multipass exec "$vm_name" -- chmod +x /home/ubuntu/setup/*.sh
    
    success "$vm_name script kopyalama tamamlandı"
done

# ======================================================================
# 🎯 DevOps Master Kurulumu (İlk)
# ======================================================================
log "🎯 DevOps Master VM kurulumu başlatılıyor..."

info "🔧 devops-master setup scripti çalıştırılıyor..."
multipass exec devops-master -- sudo /home/ubuntu/setup/devops-master-setup.sh

# Master'dan k3s token'ını al
log "🔑 K3s token alınıyor..."
sleep 30  # k3s'in tamamen başlatılmasını bekle

k3s_token=$(multipass exec devops-master -- sudo cat /var/lib/rancher/k3s/server/node-token)
if [[ -z "$k3s_token" ]]; then
    error "K3s token alınamadı!"
fi

info "✅ K3s token başarıyla alındı"

success "DevOps Master kurulumu tamamlandı"

# ======================================================================
# 🗄️ Data Services Kurulumu
# ======================================================================
log "🗄️ Data Services VM kurulumu başlatılıyor..."

# K3s token'ını kopyala
echo "$k3s_token" | multipass transfer - data-services:/tmp/k3s-token

info "🔧 data-services setup scripti çalıştırılıyor..."
multipass exec data-services -- sudo /home/ubuntu/setup/data-services-setup.sh "$MASTER_IP" "$POSTGRES_PASSWORD" "$REDIS_PASSWORD"

success "Data Services kurulumu tamamlandı"

# ======================================================================
# 📊 Monitoring Kurulumu
# ======================================================================
log "📊 Monitoring VM kurulumu başlatılıyor..."

# K3s token'ını kopyala
echo "$k3s_token" | multipass transfer - monitoring:/tmp/k3s-token

info "🔧 monitoring setup scripti çalıştırılıyor..."
multipass exec monitoring -- sudo /home/ubuntu/setup/monitoring-setup.sh "$MASTER_IP" "$GRAFANA_PASSWORD"

success "Monitoring kurulumu tamamlandı"

# ======================================================================
# 🏦 Fintech App Kurulumları (Paralel)
# ======================================================================
log "🏦 Fintech Application VM'leri kuruluyor..."

# Fintech app VM'lerini paralel olarak kur
for vm_name in "fintech-app-1" "fintech-app-2"; do
    {
        info "🔧 $vm_name kurulumu başlatılıyor..."
        
        # K3s token'ını kopyala
        echo "$k3s_token" | multipass transfer - "$vm_name:/tmp/k3s-token"
        
        # Setup scriptini çalıştır
        multipass exec "$vm_name" -- sudo /home/ubuntu/setup/fintech-app-setup.sh "$vm_name" "$MASTER_IP"
        
        success "$vm_name kurulumu tamamlandı"
    } &
done

# Paralel işlemlerin bitmesini bekle
wait

success "Tüm Fintech Application VM'leri kuruldu"

# ======================================================================
# 🔄 Kubernetes Cluster Doğrulaması
# ======================================================================
log "🔄 Kubernetes cluster durumu kontrol ediliyor..."

sleep 60  # Node'ların cluster'a katılması için bekle

info "📊 Cluster node'ları kontrol ediliyor..."
multipass exec devops-master -- kubectl get nodes

info "📦 Cluster pod'ları kontrol ediliyor..."
multipass exec devops-master -- kubectl get pods --all-namespaces

success "Kubernetes cluster başarıyla kuruldu"

# ======================================================================
# 🌐 Network Konfigürasyonu
# ======================================================================
log "🌐 Network konfigürasyonu güncelleniyor..."

# /etc/hosts dosyalarını güncelle
HOSTS_CONTENT=""
for vm_name in "${!VM_IPS[@]}"; do
    HOSTS_CONTENT+="${VM_IPS[$vm_name]} $vm_name
"
done

for vm_name in "${!VM_CONFIGS[@]}"; do
    info "📝 $vm_name /etc/hosts güncelleniyor..."
    echo "$HOSTS_CONTENT" | multipass transfer - "$vm_name:/tmp/hosts_append"
    multipass exec "$vm_name" -- sudo bash -c "cat /tmp/hosts_append >> /etc/hosts && rm /tmp/hosts_append"
done

success "Network konfigürasyonu tamamlandı"

# ======================================================================
# 📋 Kurulum Özeti
# ======================================================================
log "📋 Kurulum özeti oluşturuluyor..."

SUMMARY_FILE="$PROJECT_ROOT/deployment-summary.txt"
cat > "$SUMMARY_FILE" << EOF
🏦 Fintech DevOps Platform - Deployment Summary
=============================================
Deployment Date: $(date)
Platform: ARM64 (Apple Silicon)
Environment: Multipass VMs

🖥️ Virtual Machines:
------------------
$(for vm_name in "${!VM_IPS[@]}"; do
    config=(${VM_CONFIGS[$vm_name]})
    echo "✅ $vm_name"
    echo "   IP: ${VM_IPS[$vm_name]}"
    echo "   Specs: ${config[0]} CPUs, ${config[1]} RAM, ${config[2]} disk"
    echo ""
done)

🔗 Service Endpoints:
-------------------
🔧 DevOps Master (${VM_IPS["devops-master"]}):
   - Jenkins: http://${VM_IPS["devops-master"]}:8080
   - Kubernetes API: https://${VM_IPS["devops-master"]}:6443
   - Node Exporter: http://${VM_IPS["devops-master"]}:9100

🏦 Fintech Apps:
   - App 1: http://${VM_IPS["fintech-app-1"]}:80 (HAProxy stats: :8404)
   - App 2: http://${VM_IPS["fintech-app-2"]}:80 (HAProxy stats: :8404)
   - Container Monitoring: :8080 (cAdvisor)

🗄️ Data Services (${VM_IPS["data-services"]}):
   - PostgreSQL: ${VM_IPS["data-services"]}:5432
   - Redis: ${VM_IPS["data-services"]}:6379
   - InfluxDB: http://${VM_IPS["data-services"]}:8086

📊 Monitoring (${VM_IPS["monitoring"]}):
   - Prometheus: http://${VM_IPS["monitoring"]}:9090
   - Grafana: http://${VM_IPS["monitoring"]}:3000
   - Alertmanager: http://${VM_IPS["monitoring"]}:9093
   - Elasticsearch: http://${VM_IPS["monitoring"]}:9200
   - Kibana: http://${VM_IPS["monitoring"]}:5601

🔐 Access Credentials:
--------------------
See: $CREDENTIALS_FILE

📋 Next Steps:
-------------
1. 🔧 Configure Jenkins pipelines
2. 🏦 Deploy fintech applications
3. 📊 Setup Grafana dashboards
4. 🚨 Configure alert notifications
5. 🔒 Implement security policies

🛠️ Useful Commands:
-----------------
# Access VMs:
$(for vm_name in "${!VM_CONFIGS[@]}"; do
    echo "multipass shell $vm_name"
done)

# Stop all VMs:
multipass stop $(echo "${!VM_CONFIGS[@]}")

# Start all VMs:
multipass start $(echo "${!VM_CONFIGS[@]}")

# Delete all VMs (CAREFUL!):
multipass delete $(echo "${!VM_CONFIGS[@]}") && multipass purge

✅ DEPLOYMENT COMPLETED SUCCESSFULLY! ✅
EOF

success "Deployment summary oluşturuldu: $SUMMARY_FILE"

# ======================================================================
# ✅ Kurulum Tamamlandı
# ======================================================================
log "🎉 Fintech DevOps Platform kurulumu başarıyla tamamlandı!"
echo ""
success "📊 Deployment Summary: $SUMMARY_FILE"
success "🔐 Credentials: $CREDENTIALS_FILE"
echo ""
info "🔗 Key URLs:"
info "  🔧 Jenkins: http://${VM_IPS["devops-master"]}:8080"
info "  📊 Grafana: http://${VM_IPS["monitoring"]}:3000"
info "  📈 Prometheus: http://${VM_IPS["monitoring"]}:9090"
info "  📋 Kibana: http://${VM_IPS["monitoring"]}:5601"
echo ""
warn "⚠️  Credentials dosyasını güvenli bir yere kaydedin!"
warn "⚠️  Bu dosya güvenlik nedeniyle 24 saat sonra silinecek!"

# Credentials dosyasını 24 saat sonra sil
(sleep 86400 && rm -f "$CREDENTIALS_FILE" 2>/dev/null) &

log "🚀 Platform kullanıma hazır!"
log "📖 Detaylı dokümantasyon için proje README.md dosyasını inceleyin."

# VM durumunu göster
echo ""
info "🖥️ VM Status:"
multipass list 