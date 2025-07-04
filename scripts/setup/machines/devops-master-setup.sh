#!/bin/bash

# ======================================================================
# 🔧 DevOps Master VM Setup Script (ARM64 optimized)
# ======================================================================
# Bu script devops-master VM'ini tamamen kurar ve yapılandırır
# Hedef: Jenkins, GitLab Runner, Ansible, K8s Master Node
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
    iftop

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

# Docker Compose'u kur (ARM64)
log "🐳 Docker Compose ARM64 kuruluyor..."
DOCKER_COMPOSE_VERSION="v2.24.0"
curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-aarch64" \
    -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Ubuntu kullanıcısını docker grubuna ekle
usermod -aG docker ubuntu

# Docker kurulumunu test et
log "🧪 Docker kurulumu test ediliyor..."
docker --version
docker-compose --version

# ======================================================================
# ☸️ Kubernetes (k3s) Master Node Kurulumu
# ======================================================================
log "☸️ Kubernetes (k3s) Master Node kuruluyor..."

# k3s kurulumu (ARM64 otomatik algılanır)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --disable servicelb" sh -

# k3s servisini enable et
systemctl enable k3s

# kubectl yapılandırması
mkdir -p /home/ubuntu/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config
chmod 600 /home/ubuntu/.kube/config

# kubectl bash completion
echo 'source <(kubectl completion bash)' >> /home/ubuntu/.bashrc
echo 'alias k=kubectl' >> /home/ubuntu/.bashrc
echo 'complete -F __start_kubectl k' >> /home/ubuntu/.bashrc

# ======================================================================
# ⛑️ Helm Kurulumu (ARM64)
# ======================================================================
log "⛑️ Helm ARM64 kuruluyor..."

# Helm ARM64 binary'sini indir
HELM_VERSION="v3.14.0"
wget "https://get.helm.sh/helm-${HELM_VERSION}-linux-arm64.tar.gz" -O /tmp/helm.tar.gz
tar -zxvf /tmp/helm.tar.gz -C /tmp
mv /tmp/linux-arm64/helm /usr/local/bin/helm
chmod +x /usr/local/bin/helm
rm -rf /tmp/helm.tar.gz /tmp/linux-arm64

# Helm bash completion
echo 'source <(helm completion bash)' >> /home/ubuntu/.bashrc

# ======================================================================
# 🔧 Jenkins Kurulumu (ARM64)
# ======================================================================
log "🔧 Jenkins ARM64 kuruluyor..."

# Java 17 kurulumu (Jenkins için gerekli)
apt install -y openjdk-17-jdk

# Jenkins GPG anahtarını ekle
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee \
    /usr/share/keyrings/jenkins-keyring.asc > /dev/null

# Jenkins repository'sini ekle
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
    https://pkg.jenkins.io/debian-stable binary/ | tee \
    /etc/apt/sources.list.d/jenkins.list > /dev/null

# Paket listesini güncelle ve Jenkins'i kur
apt update -y
apt install -y jenkins

# Jenkins servisini başlat ve enable et
systemctl start jenkins
systemctl enable jenkins

# Jenkins kullanıcısını docker grubuna ekle
usermod -aG docker jenkins
systemctl restart jenkins

# Firewall ayarları
ufw allow 8080/tcp
ufw allow OpenSSH
ufw --force enable

log "🔑 Jenkins kurulumu tamamlandı!"
log "📍 Jenkins URL: http://$(hostname -I | awk '{print $1}'):8080"
log "🔐 İlk kurulum parolası: $(cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo 'Henüz oluşturulmadı')"

# ======================================================================
# 🦊 GitLab Runner Kurulumu (ARM64)
# ======================================================================
log "🦊 GitLab Runner ARM64 kuruluyor..."

# GitLab Runner repository'sini ekle
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | bash

# GitLab Runner'ı kur
apt install -y gitlab-runner

# GitLab Runner kullanıcısını docker grubuna ekle
usermod -aG docker gitlab-runner

# GitLab Runner servisini başlat
systemctl start gitlab-runner
systemctl enable gitlab-runner

log "🦊 GitLab Runner kuruldu. Token ile kayıt için: gitlab-runner register"

# ======================================================================
# 🔧 Ansible Kurulumu
# ======================================================================
log "🔧 Ansible kuruluyor..."

# Ansible kurulumu
pip3 install ansible ansible-core

# Ansible koleksiyonları
ansible-galaxy collection install kubernetes.core
ansible-galaxy collection install community.docker

# Ansible konfigürasyonu
mkdir -p /home/ubuntu/.ansible
cat > /home/ubuntu/.ansible/ansible.cfg << 'EOF'
[defaults]
inventory = /home/ubuntu/.ansible/inventory
host_key_checking = False
retry_files_enabled = False
gathering = smart

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no
pipelining = True
EOF

chown -R ubuntu:ubuntu /home/ubuntu/.ansible

# ======================================================================
# 📊 Monitoring Araçları (Temel)
# ======================================================================
log "📊 Temel monitoring araçları kuruluyor..."

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

# Otomatik güvenlik güncellemeleri
apt install -y unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades

# ======================================================================
# 🎯 Kubernetes Eklentileri
# ======================================================================
log "🎯 Kubernetes eklentileri kuruluyor..."

# MetalLB (Load Balancer)
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml

# Nginx Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.4/deploy/static/provider/cloud/deploy.yaml

# ======================================================================
# 📝 Kurulum Özeti ve Bilgiler
# ======================================================================
log "📝 Kurulum özeti oluşturuluyor..."

cat > /home/ubuntu/devops-master-info.txt << EOF
🔧 DevOps Master VM Kurulum Özeti
===============================
📅 Kurulum Tarihi: $(date)
🖥️  Hostname: $(hostname)
🌐 IP Adres: $(hostname -I | awk '{print $1}')
💾 Mimari: $(uname -m)

🚀 Kurulan Servisler:
-------------------
✅ Docker & Docker Compose
✅ Kubernetes (k3s) Master Node
✅ Helm Package Manager
✅ Jenkins CI/CD Server
✅ GitLab Runner
✅ Ansible Automation
✅ Node Exporter (Monitoring)

🔗 Erişim Bilgileri:
------------------
🔧 Jenkins: http://$(hostname -I | awk '{print $1}'):8080
📊 Node Exporter: http://$(hostname -I | awk '{print $1}'):9100
☸️  Kubernetes API: https://$(hostname -I | awk '{print $1}'):6443

🔐 Önemli Dosyalar:
-----------------
🔑 Jenkins Admin Password: /var/lib/jenkins/secrets/initialAdminPassword
☸️  Kubeconfig: /home/ubuntu/.kube/config
🔧 Ansible Config: /home/ubuntu/.ansible/ansible.cfg

📋 Sonraki Adımlar:
-----------------
1. Jenkins'e giriş yapın ve plugin'leri kurun
2. GitLab Runner'ı projenize kaydedin
3. Diğer node'ları Kubernetes cluster'ına ekleyin
4. Ansible inventory'sini yapılandırın

EOF

chown ubuntu:ubuntu /home/ubuntu/devops-master-info.txt

# ======================================================================
# ✅ Kurulum Tamamlandı
# ======================================================================
log "✅ DevOps Master VM kurulumu başarıyla tamamlandı!"
log "📄 Detaylı bilgiler: /home/ubuntu/devops-master-info.txt"
log ""
log "🔧 Jenkins: http://$(hostname -I | awk '{print $1}'):8080"
log "🔑 Jenkins Admin Password: $(cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo 'Henüz oluşturulmadı')"
log ""
log "🎯 Sistem yeniden başlatılması önerilir: sudo reboot"

# ======================================================================
# 🔄 Son Kontroller
# ======================================================================
log "🔄 Servis durumları kontrol ediliyor..."

services=("docker" "k3s" "jenkins" "gitlab-runner" "node_exporter")
for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        log "✅ $service aktif"
    else
        warn "❌ $service aktif değil"
    fi
done

log "🎉 Kurulum scripti tamamlandı!" 