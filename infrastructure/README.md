# 🏗️ Infrastructure as Code

Bu klasör, tüm infrastructure yönetimi için gerekli konfigürasyonları içerir.

## 📁 Yapı

```
infrastructure/
├── terraform/                 # Infrastructure provisioning
│   ├── multipass/            # Multipass VM management
│   ├── networking/           # Network configuration
│   └── storage/              # Storage setup
├── ansible/                  # Configuration management
│   ├── playbooks/            # Ansible playbooks
│   ├── roles/                # Reusable roles
│   └── inventory/            # Inventory files
├── kubernetes/               # K8s manifests
│   ├── namespaces/           # Namespace definitions
│   ├── deployments/          # Application deployments
│   ├── services/             # Service definitions
│   ├── ingress/              # Ingress controllers
│   ├── configmaps/           # Configuration maps
│   ├── secrets/              # Secret management
│   └── monitoring/           # Monitoring stack
└── helm/                     # Helm charts
    ├── fintech-app/          # Main application chart
    ├── monitoring/           # Monitoring stack chart
    └── data-services/        # Database stack chart
```

## 🔧 Terraform Modülleri

### Multipass VM Management
- VM oluşturma ve konfigürasyon
- Network setup
- Resource allocation
- SSH key management

### Networking
- VM arası network connectivity
- Load balancer configuration
- Security groups

## ⚙️ Ansible Playbooks

### Setup Playbooks
- `site.yml`: Master playbook
- `k8s-cluster.yml`: Kubernetes cluster setup
- `docker-setup.yml`: Docker installation
- `monitoring-stack.yml`: Monitoring tools

### Roles
- `common`: Temel sistem konfigürasyonu
- `docker`: Docker CE kurulumu
- `kubernetes`: K8s cluster kurulumu
- `monitoring`: Prometheus/Grafana
- `security`: SSL/TLS, firewall

## ☸️ Kubernetes Manifests

### Core Components
- **Namespaces**: Logical separation
- **Deployments**: Application rollouts
- **Services**: Service discovery
- **Ingress**: External access
- **ConfigMaps**: Non-sensitive config
- **Secrets**: Sensitive data

### Applications
- Fintech microservices
- Database clusters
- Message queues
- Cache layers

## 📊 Monitoring Infrastructure

- Prometheus operators
- Grafana dashboards
- Alert manager rules
- Log aggregation (ELK)
- Distributed tracing (Jaeger)

## 🔐 Security

- RBAC policies
- Network policies
- Pod security policies
- Secret encryption
- Certificate management

## 🚀 Deployment Strategy

1. **Infrastructure**: Terraform provisions VMs
2. **Configuration**: Ansible configures systems
3. **Applications**: Kubernetes deploys services
4. **Monitoring**: Observability stack activation 