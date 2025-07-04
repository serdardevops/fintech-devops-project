# 🏦 Fintech Uygulamaları

Bu klasör, gerçek zamanlı fintech platformunun tüm uygulamalarını içerir.

## 📁 Uygulama Yapısı

```
apps/
├── auth-service/              # Kimlik doğrulama servisi
├── trading-engine/            # Trading motoru
├── payment-gateway/           # Ödeme geçidi
├── risk-management/           # Risk yönetimi
├── notification-service/      # Bildirim servisi
├── market-data-service/       # Piyasa verisi servisi
├── user-management/           # Kullanıcı yönetimi
├── fraud-detection/           # Sahtekarlık tespit
├── gateway-api/               # API Gateway
└── shared/                    # Ortak kütüphaneler
```

## 🔧 Servis Mimarisi

### Core Services
- **auth-service**: JWT, OAuth2, 2FA
- **trading-engine**: Order matching, execution
- **payment-gateway**: Multi-provider payment processing
- **risk-management**: Real-time risk assessment

### Supporting Services
- **notification-service**: WebSocket, email, SMS
- **market-data-service**: Real-time price feeds
- **user-management**: KYC, profile management
- **fraud-detection**: ML-based fraud detection

### Infrastructure Services
- **gateway-api**: Rate limiting, routing, load balancing
- **shared**: Common utilities, database models

## 🚀 Teknoloji Stack

- **Framework**: FastAPI (Python 3.11+)
- **Database**: PostgreSQL + SQLAlchemy
- **Cache**: Redis
- **Message Queue**: RabbitMQ/Kafka
- **Real-time**: WebSocket + Server-Sent Events
- **Testing**: pytest, coverage
- **Documentation**: OpenAPI/Swagger

## 📊 Real-time Features

- Live market data streaming
- Instant transaction notifications
- Real-time portfolio updates
- Live chat support
- Price alerts and notifications

## 🔐 Güvenlik

- End-to-end encryption
- JWT token management
- Rate limiting per user/IP
- Input validation and sanitization
- SQL injection prevention
- CORS configuration 