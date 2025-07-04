# 🚀 ARM64 Kurulum Scriptleri

ARM tabanlı sistemler (Apple Silicon M1/M2/M3) için optimize edilmiş kurulum scriptleri.

## 📁 Script Yapısı

```
scripts/setup/
├── setup-all-vms.sh              # Master kurulum scripti
├── machines/                     # Makine-özel kurulum scriptleri
│   ├── devops-master-setup.sh    # DevOps master node
│   ├── fintech-app-setup.sh      # Fintech uygulama node'ları
│   ├── data-services-setup.sh    # Veritabanı servisleri
│   └── monitoring-setup.sh       # Monitoring stack
└── README.md                     # Bu dosya
```

## 🎯 Tek Komutla Kurulum

### Hızlı Başlangıç
```bash
# Tüm sistemi otomatik olarak kur
./scripts/setup/setup-all-vms.sh
```

Bu script:
- ✅ 5 VM oluşturur (ARM64 optimized)
- ✅ Tüm servisleri kurar ve yapılandırır
- ✅ Kubernetes cluster'ını hazırlar
- ✅ Güvenlik ayarlarını yapar
- ✅ Monitoring stack'ini kurar
- ✅ Credentials'ları güvenli şekilde yönetir

## 🖥️ VM Konfigürasyonları

| VM Adı | CPU | RAM | Disk | Rol |
|--------|-----|-----|------|-----|
| `devops-master` | 2 | 4GB | 30GB | Jenkins, GitLab Runner, K8s Master |
| `fintech-app-1` | 2 | 2GB | 20GB | Fintech App, K8s Worker, HAProxy |
| `fintech-app-2` | 2 | 2GB | 20GB | Fintech App, K8s Worker, HAProxy |
| `data-services` | 2 | 3GB | 30GB | PostgreSQL, Redis, InfluxDB |
| `monitoring` | 2 | 2GB | 20GB | Prometheus, Grafana, ELK Stack |

## 🔧 Makine-Özel Kurulumlar

### DevOps Master (`devops-master-setup.sh`)
```bash
# Manuel kurulum
./scripts/setup/machines/devops-master-setup.sh
```

**Kurduğu Servisler:**
- 🐳 Docker & Docker Compose (ARM64)
- ☸️ Kubernetes (k3s) Master Node
- ⛑️ Helm Package Manager
- 🔧 Jenkins CI/CD Server
- 🦊 GitLab Runner
- 🔧 Ansible Automation
- 📊 Node Exporter
- 🎯 MetalLB Load Balancer
- 🌐 Nginx Ingress Controller

**Port Açılımları:**
- 8080: Jenkins Web UI
- 6443: Kubernetes API
- 9100: Node Exporter
- 22: SSH

### Fintech Apps (`fintech-app-setup.sh`)
```bash
# Manuel kurulum (her iki app node için)
./scripts/setup/machines/fintech-app-setup.sh fintech-app-1 <master-ip>
./scripts/setup/machines/fintech-app-setup.sh fintech-app-2 <master-ip>
```

**Kurduğu Servisler:**
- 🐳 Docker & Container Runtime
- ☸️ Kubernetes (k3s) Worker Node
- 🐍 Python Runtime Environment (FastAPI stack)
- 📊 Node Exporter + cAdvisor
- 🌐 HAProxy Load Balancer
- 📁 Fintech App Directories

**Python Paketleri:**
- FastAPI, Uvicorn
- PostgreSQL & Redis clients
- WebSocket support
- Prometheus metrics
- Async/await libraries

**Port Açılımları:**
- 80: HAProxy Frontend
- 8000: Application Port
- 8080: cAdvisor
- 8404: HAProxy Stats
- 9100: Node Exporter

### Data Services (`data-services-setup.sh`)
```bash
# Manuel kurulum
./scripts/setup/machines/data-services-setup.sh <master-ip> [postgres-pass] [redis-pass]
```

**Kurduğu Servisler:**
- 🐘 PostgreSQL 15 (ARM64)
- 🔴 Redis Server
- 📊 InfluxDB (Time Series)
- 📊 Database Exporters (Prometheus)
- 💾 Otomatik Backup Sistemi
- ☸️ Kubernetes Worker Node

**Database Konfigürasyonları:**
- PostgreSQL: SSL enabled, optimized for fintech
- Redis: Password protected, persistence enabled
- InfluxDB: Fintech database with retention policy

**Backup Sistemi:**
- 📅 Günlük otomatik backup (02:00)
- 🗜️ Sıkıştırma ve rotasyon (7 gün)
- 📊 Tüm veritabanları dahil

**Port Açılımları:**
- 5432: PostgreSQL
- 6379: Redis
- 8086: InfluxDB
- 9100, 9187, 9121: Exporters

### Monitoring (`monitoring-setup.sh`)
```bash
# Manuel kurulum
./scripts/setup/machines/monitoring-setup.sh <master-ip> [grafana-password]
```

**Kurduğu Servisler:**
- 📊 Prometheus (ARM64)
- 🚨 Alertmanager
- 📈 Grafana
- 📋 Elasticsearch
- 📄 Logstash
- 📊 Kibana
- 📊 Node Exporter

**Monitoring Konfigürasyonları:**
- Prometheus: Fintech alert rules, service discovery
- Grafana: Admin user, data sources
- ELK Stack: Log processing, fintech patterns
- Alertmanager: Slack integration ready

**Port Açılımları:**
- 9090: Prometheus
- 9093: Alertmanager
- 3000: Grafana
- 9200: Elasticsearch
- 5601: Kibana
- 5044: Logstash

## 🔐 Güvenlik Özellikleri

### SSH Security
- ✅ Password authentication disabled
- ✅ Root login disabled
- ✅ Key-based authentication only

### Firewall (UFW)
- ✅ Minimal port exposure
- ✅ Service-specific rules
- ✅ Inter-VM communication

### Database Security
- ✅ Strong random passwords
- ✅ SSL/TLS encryption
- ✅ Network access controls
- ✅ User privilege separation

### Container Security
- ✅ Non-root containers
- ✅ Resource limits
- ✅ Security contexts
- ✅ Network policies

## 📊 Monitoring & Observability

### Metrics Collection
- **System**: CPU, memory, disk, network
- **Application**: Response time, throughput, errors
- **Business**: Transaction volume, user activity
- **Database**: Connections, queries, performance

### Log Management
- **Application logs**: Structured JSON logging
- **System logs**: Syslog integration
- **Audit logs**: Security events
- **Performance logs**: Slow queries, timeouts

### Alerting
- **Critical**: Database down, high error rate
- **Warning**: High CPU/memory usage
- **Info**: Deployment notifications

## 🔧 Kullanım Komutları

### VM Yönetimi
```bash
# Tüm VM'leri listele
multipass list

# VM'ye bağlan
multipass shell <vm-name>

# VM'leri durdur
multipass stop devops-master fintech-app-1 fintech-app-2 data-services monitoring

# VM'leri başlat
multipass start devops-master fintech-app-1 fintech-app-2 data-services monitoring

# VM'leri sil (DİKKAT!)
multipass delete devops-master fintech-app-1 fintech-app-2 data-services monitoring
multipass purge
```

### Kubernetes
```bash
# Master node'da
multipass shell devops-master

# Cluster durumu
kubectl get nodes
kubectl get pods --all-namespaces

# Servis durumu
kubectl get services --all-namespaces
```

### Database Bağlantıları
```bash
# PostgreSQL
multipass shell data-services
sudo -u postgres psql -d fintech

# Redis
multipass shell data-services
redis-cli -a <password>
```

### Monitoring
```bash
# Prometheus targets
curl http://<monitoring-ip>:9090/api/v1/targets

# Grafana health
curl http://<monitoring-ip>:3000/api/health

# Elasticsearch status
curl http://<monitoring-ip>:9200/_cluster/health
```

## 🚨 Sorun Giderme

### VM Oluşturma Sorunları
```bash
# Multipass durumu kontrol et
multipass version
multipass list

# VM oluşturma debug
multipass launch --name test-vm --verbose 22.04
```

### Network Sorunları
```bash
# VM IP adreslerini kontrol et
multipass info <vm-name>

# Network connectivity test
multipass shell <vm-name>
ping <other-vm-ip>
```

### Service Sorunları
```bash
# Service durumları
systemctl status docker
systemctl status k3s
systemctl status postgresql

# Logs kontrol et
journalctl -u <service-name> -f
```

### Kubernetes Sorunları
```bash
# Node durumu
kubectl describe node <node-name>

# Pod logs
kubectl logs <pod-name> -n <namespace>

# Events
kubectl get events --sort-by=.metadata.creationTimestamp
```

## 📋 Checklist

### Kurulum Öncesi
- [ ] Multipass kurulumu
- [ ] Yeterli disk alanı (minimum 150GB)
- [ ] RAM (minimum 16GB önerilen)
- [ ] ARM64 macOS

### Kurulum Sonrası
- [ ] Tüm VM'ler çalışıyor
- [ ] Kubernetes cluster aktif
- [ ] Database bağlantıları çalışıyor
- [ ] Monitoring endpoints erişilebilir
- [ ] Credentials güvenli yerde saklandı

### Production Hazırlık
- [ ] SSL sertifikaları
- [ ] Domain yapılandırması
- [ ] Backup testi
- [ ] Disaster recovery planı
- [ ] Security audit

## 🔗 Faydalı Linkler

- [Multipass Documentation](https://multipass.run/docs)
- [K3s Documentation](https://k3s.io/)
- [Prometheus Configuration](https://prometheus.io/docs/prometheus/latest/configuration/)
- [Grafana Documentation](https://grafana.com/docs/)
- [ELK Stack Guide](https://www.elastic.co/guide/)

## 📞 Destek

Script'lerle ilgili sorunlar için:
1. Log dosyalarını kontrol edin
2. Service durumlarını kontrol edin
3. Network bağlantılarını test edin
4. VM resource'larını kontrol edin 