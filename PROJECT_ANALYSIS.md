# Home-Anthill Project Analysis

## Project Overview

**home-anthill** is an IoT home automation system where ESP32 microcontrollers send sensor data over MQTT. A Kubernetes-based microservice backend collects, stores, and exposes that data via REST/gRPC APIs. React web UI and Android mobile app let users manage their devices.

---

## 1. Project Structure

```
home-anthill/
├── api-server/          # Go - Central REST API (homes, rooms, devices, profiles, auth)
├── api-devices/         # Go - gRPC service (device registration + MQTT publishing)
├── admission/           # Go - REST + gRPC device/sensor registration gateway
├── register/            # Rust - Sensor registration and data retrieval (MongoDB)
├── producer/            # Rust - MQTT → RabbitMQ bridge
├── consumer/            # Rust - RabbitMQ → MongoDB persistence
├── online/              # Rust - Device online status tracking (Redis)
├── online-receiver/     # Rust - MQTT → Redis (device presence)
├── online-alarm/        # Rust - Offline device detection + FCM push notifications
├── gui/                 # TypeScript - React web dashboard
├── app/                 # Kotlin - Android mobile app
├── esp32-configurator/  # Python - C header generator from YAML for ESP32 firmware
├── deployer/            # Helm - Kubernetes deployment charts
├── mosquitto/           # Go + Docker - MQTT broker with dynamic auth
├── sharded-mongodb-compose/  # Docker Compose - Local MongoDB cluster
├── k8s-config-reloader/ # Go - K8s sidecar for ConfigMap/Secret changes
├── firmwares/           # C++ - ESP32 firmware variants
└── docs/                # Documentation, diagrams, Postman collections
```

---

## 2. Services Summary

| Service | Language | Framework | Database | Protocol |
|---------|----------|-----------|----------|----------|
| api-server | Go 1.26 | Gin | MongoDB | REST, gRPC |
| api-devices | Go 1.26 | gRPC | MongoDB | gRPC, MQTT |
| admission | Go 1.26 | Gin | MongoDB | REST, gRPC |
| register | Rust | Rocket | MongoDB | REST |
| producer | Rust | Tokio | - | MQTT, AMQP |
| consumer | Rust | Tokio | MongoDB | AMQP |
| online | Rust | Rocket | Redis | REST |
| online-receiver | Rust | Tokio | Redis | MQTT |
| online-alarm | Rust | Rocket | Redis | REST, FCM |
| gui | TypeScript | React 19 | - | REST |
| app | Kotlin | Jetpack Compose | - | REST |

---

## 3. Communication Flow & Protocols

### 3.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          ESP32 Devices (IoT)                                  │
│                    Sensors: temperature, humidity, motion                      │
└────────────────────────────┬────────────────────────────────────────────────┘
                             │ MQTT (TLS)
                             ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Mosquitto (MQTT Broker)                              │
│                            Port: 1883 (8883 TLS)                             │
└──────┬─────────────────────────────────┬─────────────────────────────────────┘
       │                                 │
       │ MQTT Subscribe                  │ MQTT Subscribe
       ▼                                 ▼
┌─────────────────────┐         ┌─────────────────────────────────────────────┐
│   online-receiver   │         │              producer                       │
│   (Rust/Tokio)      │         │              (Rust/Tokio)                  │
│                     │         │                                             │
│ Subscribes to:      │         │ Subscribes to: sensors/{deviceId}/{feature}│
│ online/+/features/+ │         │                                             │
└─────────┬───────────┘         └──────────────┬──────────────────────────────┘
          │                                      │
          │                                      │ AMQP Publish
          │                                      ▼
          │                    ┌─────────────────────────────────────────────┐
          │                    │            RabbitMQ                        │
          │                    │            Port: 5672 (5671 TLS)            │
          │                    │            Queue: ks89                       │
          │                    │            Ports: 15672 (Management UI)      │
          │                    │            Port: 15671 (Management TLS)     │
          │                    └────────────────────┬─────────────────────────┘
          │                                         │
          │                                         │ AMQP Consume
          │                                         ▼
          │                    ┌─────────────────────────────────────────────┐
          │                    │              consumer                        │
          │                    │            (Rust/Tokio)                      │
          │                    │                                             │
          │                    │ Persists sensor data to MongoDB              │
          │                    └────────────────────┬─────────────────────────┘
          │                                         │
          │                                         │ Write
          │                                         ▼
          │                    ┌─────────────────────────────────────────────┐
          │                    │         MongoDB (Sensors DB)                │
          │                    │         Port: 27017                         │
          │                    └─────────────────────────────────────────────┘
          │
          │ Write
          ▼
┌─────────────────────┐
│       Redis         │
│    Port: 6379       │
└─────────┬───────────┘
          │
          │ Read                    ┌─────────────────────────────────────────────┐
          │                         │           api-server                      │
          │                         │              (Go/Gin)                      │
          │                         │                                             │
          │                         │ REST API: homes, rooms, devices, profiles  │
          │                         │ gRPC: device commands                       │
          │                         └──────────────┬──────────────────────────────┘
          │                                    │           │
          │                                    │ REST      │ gRPC
          │                                    ▼           ▼
          │                    ┌─────────────────────────────────────────────┐
          │                    │         MongoDB (Main DB)                   │
          │                    │         Port: 27017                         │
          │                    └─────────────────────────────────────────────┘
          │
          │                    ┌─────────────────────────────────────────────┐
          │                    │          api-devices                        │
          │                    │           (Go/gRPC)                         │
          │                    │                                             │
          │                    │ gRPC Services: Registration, Device, Health │
          │                    │ Publishes commands to MQTT                   │
          │                    └──────────────┬──────────────────────────────┘
          │                                   │
          │                                   │ MQTT Publish
          │                                   ▼
          │                    ┌─────────────────────────────────────────────┐
          │                    │           Mosquitto                          │
          │                    │    Commands to devices/{uuid}/values          │
          │                    └─────────────────────────────────────────────┘
          │                                          │
          │                                          │ MQTT
          │                                          ▼
          │                          ┌─────────────────────────────┐
          │                          │     ESP32 Devices           │
          │                          │    (Receive commands)        │
          │                          └─────────────────────────────┘
          │
          │ Polls every 10s           ┌─────────────────────────────────────────────┐
          │                           │          online-alarm                       │
          │                           │            (Rust/Rocket)                    │
          │                           │                                             │
          │                           │ Polls Redis for offline devices            │
          │                           │ Sends FCM push notifications               │
          │                           └─────────────────────────────────────────────┘
          │                                          │
          │                                          │ FCM Push
          │                                          ▼
          │                    ┌─────────────────────────────────────────────┐
          │                    │          Firebase Cloud Messaging           │
          │                    │              (FCM)                          │
          │                    └────────────────────┬──────────────────────┘
          │                                             │
          │                                             │
          ▼                                             ▼
┌─────────────────────┐                 ┌─────────────────────────────────────┐
│        online       │                 │              app                   │
│    (Rust/Rocket)    │                 │         (Android/Kotlin)            │
│                     │                 │                                      │
│ REST API: online    │                 │ FCM notifications, device management │
│ status, FCM tokens  │                 └─────────────────────────────────────┘
└─────────────────────┘

                        ┌─────────────────────────────────────────────┐
                        │              admission                        │
                        │               (Go/Gin)                       │
                        │                                             │
                        │ REST: device registration                     │
                        │ gRPC: calls api-devices                      │
                        │ HTTP: calls register                          │
                        └─────────────────────────────────────────────┘

                        ┌─────────────────────────────────────────────┐
                        │              register                         │
                        │             (Rust/Rocket)                     │
                        │                                             │
                        │ REST: sensor registration, data retrieval    │
                        └─────────────────────────────────────────────┘
```

### 3.2 Data Flow Paths

#### Path 1: Sensor Data Ingestion (Write Path)
```
ESP32 → Mosquitto → producer → RabbitMQ → consumer → MongoDB (sensors)
```

#### Path 2: Device Online Status
```
ESP32 → Mosquitto → online-receiver → Redis
```

#### Path 3: Offline Detection & Notifications
```
Redis → online-alarm (polls every 10s) → FCM → app (Android)
```

#### Path 4: Device Command (Write Path)
```
gui/app → api-server → api-devices (gRPC) → Mosquitto → ESP32
```

#### Path 5: Device Registration
```
ESP32 → admission (REST) → api-devices (gRPC) + register (HTTP) → MongoDB
```

---

## 4. Services & Ports

### 4.1 Infrastructure Services

| Service | Image | Port(s) | Purpose |
|---------|-------|---------|---------|
| MongoDB | sharded-mongodb-compose | 27017 | Main + Sensors DB |
| Redis | redis:alpine | 6379 | Device online status |
| RabbitMQ | rabbitmq:management | 5672, 15672, 15671 | Message queue |
| Mosquitto | ks89/mosquitto | 1883, 9001 | MQTT broker |

### 4.2 Application Services

| Service | Language | HTTP/REST Port | gRPC Port | Other Ports | Database |
|---------|----------|----------------|-----------|-------------|----------|
| api-server | Go | 8082 | - | - | MongoDB :27017 |
| api-devices | Go | - | 50051 | - | MongoDB :27017 |
| admission | Go | 8099 | - | - | MongoDB :27017 |
| register | Rust | 8000 (dev) / 80 (prod) | - | - | MongoDB :27017 |
| producer | Rust | - | - | - | - |
| consumer | Rust | - | - | - | MongoDB :27017 |
| online | Rust | 8089 (dev) / 80 (prod) | - | - | Redis :6379 |
| online-receiver | Rust | - | - | - | Redis :6379 |
| online-alarm | Rust | 8088 (dev) / 80 (prod) | - | - | Redis :6379 |
| gui | TypeScript | 4200 (dev) / served by api-server | - | - | - |
| app | Kotlin | - | - | - | - |

---

## 5. Protocol Details

### 5.1 MQTT Topics

| Topic Pattern | Direction | Purpose |
|--------------|-----------|---------|
| `sensors/{deviceId}/{featureName}` | ESP32 → producer | Sensor data (temperature, humidity, etc.) |
| `online/{deviceId}/features/{featureId}` | ESP32 → online-receiver | Device online status |
| `devices/{deviceId}/values` | api-devices → ESP32 | Device command values |

**Supported Feature Names:**
- Float: `temperature`, `humidity`, `light`, `airpressure`
- Integer: `motion`, `airquality`
- Boolean: `online`

### 5.2 REST API Endpoints

#### api-server (Port 8082)
- `POST /api/callback` - GitHub OAuth2 callback (web)
- `POST /api/app_callback` - GitHub OAuth2 callback (mobile)
- `GET /api/profiles` - List profiles
- `GET /api/profiles/:id` - Get profile
- `POST /api/profiles` - Create profile
- `PUT /api/profiles/:id` - Update profile
- `GET /api/profiles/:id/tokens` - Regenerate API token
- `GET /api/homes` - List homes
- `POST /api/homes` - Create home
- `GET /api/homes/:id` - Get home
- `PUT /api/homes/:id` - Update home
- `DELETE /api/homes/:id` - Delete home
- `GET /api/rooms` - List rooms
- `POST /api/rooms` - Create room
- `GET /api/rooms/:id` - Get room
- `PUT /api/rooms/:id` - Update room
- `DELETE /api/rooms/:id` - Delete room
- `GET /api/devices` - List devices
- `POST /api/devices` - Create device
- `GET /api/devices/:id` - Get device
- `PUT /api/devices/:id` - Update device
- `DELETE /api/devices/:id` - Delete device
- `POST /api/devices/:id/features` - Add feature to device
- `GET /api/devices/:id/features/:featureId/values` - Get feature value

#### admission (Port 8099)
- `POST /admission/register` - Register device
- `POST /admission/keepalive` - Device keepalive
- `GET /admission/keepalive` - Health check

#### register (Port 8000/80)
- `POST /sensors/register/:featureName` - Register sensor
- `GET /sensors/:deviceUuid/features/:featureUuid/:featureName` - Get sensor value
- `GET /keepalive` - Health check

#### online (Port 8089/80)
- `GET /online/:deviceUuid/features/:featureUuid` - Get online status
- `DELETE /online/:deviceUuid/features/:featureUuid` - Delete online record
- `POST /fcmtoken` - Set FCM token
- `GET /keepalive` - Health check

#### online-alarm (Port 8088/80)
- `GET /keepalive` - Health check

### 5.3 gRPC Services

#### api-devices (Port 50051)

**Registration Service:**
- `RegisterController(Controller) returns (RegistrationResponse)`
- `UpdateController(Controller) returns (RegistrationResponse)`

**Device Service:**
- `GetValue(DeviceRequest) returns (DeviceResponse)`
- `SetValues(DeviceValuesRequest) returns (DeviceValuesResponse)`
- `HealthCheck(HealthCheckRequest) returns (HealthCheckResponse)`

#### admission → api-devices
- Calls `Registration.Register()` via gRPC

---

## 6. Authentication & Security

### 6.1 Authentication Flow
```
gui/app → GitHub OAuth2 → api-server → JWT token
```

### 6.2 API Security
- **GitHub OAuth2**: Web and mobile app authentication
- **JWT**: Session tokens for API requests
- **apiToken**: UUIDv4 for device authentication
  - Stored in plain text in register service
  - SHA-256 hashed in register MongoDB storage
  - Stored in plain text in consumer

### 6.3 Transport Security
| Protocol | TLS Support | Default |
|----------|-------------|---------|
| MQTT | ✅ | Disabled |
| gRPC | ✅ | Disabled |
| REST/HTTP | ❌ | Plaintext |
| AMQP | ❌ | Plaintext (no amqps://) |
| Redis | ❌ | Plaintext |
| MongoDB | ❌ | Plaintext |

---

## 7. External Integrations

| Service | Protocol | Purpose |
|---------|----------|---------|
| GitHub OAuth2 | HTTPS | User authentication |
| Firebase Cloud Messaging (FCM) | HTTPS | Push notifications |
| MongoDB Atlas | mongodb:// | Production database |

---

## 8. Kubernetes Deployment

### 8.1 Cluster Setup
- **K3s** cluster on Hetzner Cloud
- **NGINX Gateway Fabric** for ingress
- **MetalLB** for bare-metal load balancing
- **cert-manager** for TLS certificates

### 8.2 Service Discovery
Internal DNS: `<service-name>.home-anthill.svc.cluster.local`

| K8s Service | Internal DNS |
|-------------|--------------|
| api-server | api-server-svc.home-anthill.svc.cluster.local |
| admission | admission-svc.home-anthill.svc.cluster.local |

---

## 9. Development Ports Quick Reference

```
┌─────────────────────────────────────────────────────────────────┐
│                        localhost                                │
├──────────────┬──────────────┬───────────────────────────────────┤
│ Service      │ Port         │ Protocol                          │
├──────────────┼──────────────┼───────────────────────────────────┤
│ api-server   │ 8082         │ REST (HTTP)                       │
│ admission    │ 8099         │ REST (HTTP)                       │
│ register     │ 8000         │ REST (HTTP) - Debug               │
│ online       │ 8089         │ REST (HTTP) - Debug               │
│ online-alarm │ 8088         │ REST (HTTP) - Debug               │
│ gui          │ 4200         │ REST (HTTP) - Dev Server          │
├──────────────┼──────────────┼───────────────────────────────────┤
│ api-devices  │ 50051        │ gRPC                              │
├──────────────┼──────────────┼───────────────────────────────────┤
│ MongoDB      │ 27017        │ MongoDB Wire Protocol             │
│ Redis        │ 6379         │ Redis Protocol                    │
│ RabbitMQ     │ 5672         │ AMQP 0-9-1                        │
│ RabbitMQ UI  │ 15672        │ HTTP (Management)                  │
│ Mosquitto    │ 1883         │ MQTT                              │
│ Mosquitto WS │ 9001         │ MQTT over WebSocket               │
└──────────────┴──────────────┴───────────────────────────────────┘
```

---

## 10. Technology Stack Summary

| Layer | Technologies |
|-------|-------------|
| Go Services | Go 1.26, Gin, gRPC/Protobuf, MongoDB driver v2 |
| Rust Services | Rust 2024, Rocket, lapin (AMQP), paho-mqtt, redis, tokio |
| Frontend | React 19, Material UI 7, Redux Toolkit, Vite |
| Mobile | Kotlin, Jetpack Compose, Koin, Retrofit, Firebase FCM |
| Infrastructure | Kubernetes (K3s), Helm, NGINX Gateway Fabric, MetalLB |
| Messaging | RabbitMQ (AMQP), Mosquitto (MQTT) |
| Data | MongoDB, Redis |
