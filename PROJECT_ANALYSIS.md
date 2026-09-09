# Home-Anthill Project Analysis

Last scanned from `docs/` on 2026-06-06 across all sibling folders under `..`.

## Project Overview

**home-anthill** is a multi-repository IoT home automation platform. ESP32 devices publish signed sensor and presence messages over MQTT. Backend services register devices, bridge MQTT into RabbitMQ, persist readings in MongoDB, track online state in Redis, send Firebase Cloud Messaging notifications, and expose user/device management through REST and gRPC APIs. A React web UI and a Kotlin Android app provide the user-facing control surfaces.

## Workspace Inventory

| Folder | Role | Main stack |
|---|---|---|
| `.agents` | Local assistant workflow notes | Markdown |
| `.claude` | Local assistant settings | JSON |
| `.github` | Organization profile repository | Markdown, Git metadata |
| `admission` | Device/sensor registration gateway | Go 1.26.3, Gin, gRPC client, MongoDB |
| `api-devices` | Device registration and command publishing service | Go 1.26.3, gRPC, MongoDB, MQTT |
| `api-server` | Main user-facing API | Go 1.26.3, Gin, MongoDB, GitHub OAuth2, JWT, gRPC client |
| `app` | Android mobile app | Kotlin, Jetpack Compose, Retrofit, Koin, Firebase |
| `consumer` | RabbitMQ to MongoDB ingestion worker | Rust 2024, Tokio, lapin, MongoDB, Redis |
| `deployer` | Kubernetes deployment chart | Helm, Gateway API, Cilium, RabbitMQ Operator |
| `docs` | Architecture and setup documentation | Markdown, diagrams, Bruno collection |
| `esp32-configurator` | Firmware secret/header generator | Python 3.12, Poetry, Jinja2, Pydantic, YAML |
| `firmwares` | ESP32 firmware variants | Arduino/C++ |
| `gui` | Web dashboard | TypeScript, React 19.2, Vite 8.0, Nx 22.6, Redux Toolkit Query, Mantine 9 |
| `k8s-config-reloader` | Sidecar that reloads processes on config file changes | Go 1.26.3, fsnotify, gopsutil |
| `mosquitto` | MQTT broker image entrypoint and examples | Go 1.26.3, Docker, Mosquitto |
| `mqtt-communication-checker` | Local end-to-end MQTT verification CLI | Python 3.12, Poetry, paho-mqtt, PyMongo, Redis |
| `alarm-api` | Online-state REST API and FCM token storage | Rust 2024, Rocket, Redis |
| `alarm-notifier` | Offline-device detector and FCM notifier | Rust 2024, Rocket, Redis, Firebase Cloud Messaging |
| `alarm-receiver` | MQTT presence receiver | Rust 2024, Rocket health endpoint, MQTT, Redis, MongoDB |
| `private-config` | Local deployment override and secret values | YAML, intentionally not analyzed in detail |
| `producer` | MQTT to RabbitMQ bridge | Rust 2024, Tokio, paho-mqtt, lapin |
| `rabbitmq-local` | Local RabbitMQ definitions/config | JSON, RabbitMQ config |
| `register` | Sensor registration and value retrieval API | Rust 2024, Rocket, MongoDB |
| `sharded-mongodb-compose` | Local MongoDB sharded cluster | Docker Compose |

Generated or local-only directories were present in several repos (`coverage`, `target`, `build`, `dist`, `node_modules`, `.venv`, `.gocache`, `.gomodcache`, `.idea`, logs, tmp). They were treated as generated output, not primary source. The `private-config` folder was counted in the workspace inventory but not inspected beyond filenames because it contains local values and secrets.

## High-Level Architecture

```text
ESP32 firmware
  | MQTT signed sensor payloads: sensors/{deviceUuid}/{featureName}
  | MQTT signed presence payloads: online/{deviceUuid}/features/{featureUuid}
  | MQTT signed alarm payloads: alarms/{deviceUuid}/features/{featureUuid}/{alarmType}
  v
Mosquitto
  |--> producer --> RabbitMQ queue ks89 --> consumer --> MongoDB sensors DB
  |--> alarm-receiver -------------------------------> Redis online state + pending alarms

gui / app
  | REST + OAuth/JWT
  v
api-server --> MongoDB api-server DB
  |--> register HTTP for sensor values
  |--> alarm-api HTTP for online state and token rotation
  |--> api-devices gRPC for controller commands

admission REST --> api-devices gRPC + register HTTP
api-devices --> MongoDB controllers DB + MQTT commands: devices/{deviceUuid}/values
alarm-notifier --> Redis offline scan --> Firebase Cloud Messaging --> app
```

## Service Summary

| Service | Runtime | Primary purpose | Stores | Protocols |
|---|---|---|---|---|
| `api-server` | Go/Gin | Homes, rooms, devices, profile, OAuth2, JWT, value access | MongoDB | REST, gRPC client, HTTP clients |
| `api-devices` | Go/gRPC | Controller registration and value commands | MongoDB | gRPC, MQTT publish |
| `admission` | Go/Gin | Public device registration endpoint | MongoDB | REST, gRPC client, HTTP client |
| `register` | Rust/Rocket | Sensor registration and latest value reads | MongoDB | REST |
| `producer` | Rust/Tokio | Subscribe to sensor MQTT topics and publish AMQP messages | None | MQTT, AMQP |
| `consumer` | Rust/Tokio | Validate and persist signed sensor readings | MongoDB, Redis | AMQP |
| `alarm-api` | Rust/Rocket | Read/delete online records, store FCM tokens, alarm preferences, API-token migration, and notification history | Redis DB 0/1/3 | REST |
| `alarm-receiver` | Rust/Tokio/Rocket | Validate signed online/alarm MQTT messages and update Redis | Redis DB 0/2/3, MongoDB | MQTT, REST health |
| `alarm-notifier` | Rust/Tokio/Rocket | Poll offline state and pending alarms, send grouped push notifications, and persist notification history | Redis DB 0/1/3 | REST health, FCM |
| `gui` | React/Vite/Nx | Browser dashboard for homes, devices, profile, values | Browser state | REST |
| `app` | Android/Kotlin | Mobile dashboard, OAuth2 PKCE login, FCM token upload | SecurePrefs | REST, FCM |
| `mosquitto` | Mosquitto + Go entrypoint | MQTT broker with generated password file | Filesystem | MQTT, MQTT/TLS |
| `k8s-config-reloader` | Go | Watch mounted config dirs and signal a named process | None | fsnotify, Unix signals |

## Data Flows

### Sensor Ingestion

```text
ESP32 -> Mosquitto -> producer -> RabbitMQ queue ks89 -> consumer -> MongoDB sensors.sensors
```

The producer subscribes to typed sensor topics and wraps MQTT payloads into AMQP messages. It validates MQTT topic shape, UUIDs, known sensor feature names, and payload size before publishing. AMQP publisher confirms are enabled; a publish only counts as accepted after broker confirmation, and the producer retries once after rebuilding the AMQP connection on publish failure.

The consumer validates:

- AMQP body HMAC in the `x-hmac-sha256` header using `AMQP_HMAC_SECRET`.
- MQTT signed payload HMAC using the feature API token loaded from MongoDB.
- Timestamp freshness with a 300 second skew window.
- Nonce replay protection using Redis keys with a 720 second TTL.
- Topic/device/feature binding before updating MongoDB.

### Online State

```text
ESP32 -> Mosquitto -> alarm-receiver -> Redis
alarm-api -> Redis
alarm-notifier -> Redis -> FCM -> Android app
alarm-notifier -> notifications Redis history -> alarm-api -> api-server -> gui/app
```

`alarm-receiver` subscribes to `online/+/features/+` and `alarms/+/features/+/+`, verifies the signed envelope against the registered MongoDB feature, claims a replay nonce in Redis DB 2, then updates online state in DB 0 or stores a pending alarm in DB 3. `alarm-notifier` scans every 10 seconds, applies DB 3 silence preferences to offline and generic alarms, groups notifications by recipient/type, acknowledges alarms after successful FCM delivery, and stores sent-notification history in DB 1 with a 90 day retention window.

### Commands To Controllers

```text
gui/app -> api-server -> api-devices gRPC -> Mosquitto -> ESP32
```

The command topic is `devices/{deviceUuid}/values`. Controller commands include values such as `on`, `setpoint`, `mode`, `fanSpeed`, and `tolerance`.

### Registration

```text
ESP32 -> admission /admission/register -> api-devices gRPC + register HTTP
```

The registration path creates/updates controller metadata through `api-devices` and sensor metadata through `register`.

## Protocol Details

### MQTT Topics

| Topic | Direction | Purpose |
|---|---|---|
| `sensors/{deviceUuid}/temperature` | ESP32 to producer | Temperature readings |
| `sensors/{deviceUuid}/humidity` | ESP32 to producer | Humidity readings |
| `sensors/{deviceUuid}/light` | ESP32 to producer | Light readings |
| `sensors/{deviceUuid}/motion` | ESP32 to producer | Motion readings |
| `sensors/{deviceUuid}/airquality` | ESP32 to producer | Air quality enum readings |
| `sensors/{deviceUuid}/airpressure` | ESP32 to producer | Air pressure readings |
| `sensors/{deviceUuid}/online` | ESP32 to producer | Online sensor feature readings |
| `online/{deviceUuid}/features/{featureUuid}` | ESP32 to alarm-receiver | Dedicated presence updates |
| `alarms/{deviceUuid}/features/{featureUuid}/motion` | ESP32 to alarm-receiver | Motion alarm (`value=1`) |
| `alarms/{deviceUuid}/features/{featureUuid}/thermostat-mode-error` | ESP32 to alarm-receiver | Thermostat mode fault (`value=-1`) |
| `devices/{deviceUuid}/values` | api-devices to ESP32 | Controller command array |
| `clients/{clientId}/status` | MQTT clients to broker | Last-will status topic configured by MQTT clients |

### Feature Names

Supported sensor features scanned in source and local checker:

- Float/decimal: `temperature`, `humidity`, `light`, `airpressure`
- Integer/enum: `motion`, `airquality`
- Boolean/status: `online`

Controller command features scanned in the local checker:

- `on`
- `setpoint`
- `mode`
- `fanSpeed`
- `tolerance`

### AMQP

| Setting | Value |
|---|---|
| Queue | `ks89` by default |
| Publish exchange | Default exchange (`exchange=""`) |
| Routing key | Queue name (`ks89`) |
| Producer permission | Configure `ks89`, write `amq.default` and `ks89`, read `ks89` |
| Consumer permission | Configure `ks89`, read `ks89`, no write |
| Message integrity | `x-hmac-sha256` header |

RabbitMQ 4.x rejects transient non-exclusive named queues by default, so producer and consumer declare the named queue as durable. Producer channels use publisher confirms and treat returned messages, broker `Nack`s, missing confirm mode, and confirm failures as publish errors.

## Public And Internal APIs

### `api-server` REST

Public routes:

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/keepalive` | Health check |
| `GET` | `/api/oauth/login` | Start web GitHub OAuth2 |
| `GET` | `/api/oauth/callback` | Complete web OAuth2 |
| `GET` | `/api/oauth/app/login` | Start mobile GitHub OAuth2 with PKCE |
| `GET` | `/api/oauth/app/callback` | Complete mobile OAuth2 |
| `POST` | `/api/oauth/app/exchange-code` | Exchange mobile login code |
| `POST` | `/api/oauth/app/refresh` | Refresh mobile token |
| `POST` | `/api/oauth/app/logout` | Logout mobile session |
| `POST` | `/api/oauth/refresh` | Refresh web token |
| `POST` | `/api/oauth/logout` | Logout web session |

JWT-protected routes:

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/homes` | List homes |
| `POST` | `/api/homes` | Create home |
| `PUT` | `/api/homes/:id` | Update home |
| `DELETE` | `/api/homes/:id` | Delete home |
| `GET` | `/api/homes/:id/rooms` | List rooms in home |
| `POST` | `/api/homes/:id/rooms` | Create room |
| `PUT` | `/api/homes/:id/rooms/:rid` | Update room |
| `DELETE` | `/api/homes/:id/rooms/:rid` | Delete room |
| `GET` | `/api/profile` | Current profile |
| `POST` | `/api/profiles/:id/tokens` | Rotate profile API token |
| `POST` | `/api/profiles/:id/fcmTokens` | Store profile FCM token |
| `GET` | `/api/devices` | List devices |
| `PUT` | `/api/devices/:id` | Assign/update device home and room metadata |
| `PUT` | `/api/devices/:id/features/:featureUuid/notifications` | Silence or unsilence notifications for a device feature |
| `DELETE` | `/api/devices/:id` | Delete device |
| `GET` | `/api/devices/:id/values` | Get sensor/controller values |
| `POST` | `/api/devices/:id/values` | Set controller values |
| `POST` | `/api/fcmtoken` | Store FCM token |
| `GET` | `/api/online` | Get online state for all devices in the current profile |
| `GET` | `/api/online/:id` | Get online state for device |
| `GET` | `/api/notifications` | Get notification history for the current profile |

### `admission` REST

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/admission/register` | Public device registration |
| `GET` | `/admission/keepalive` | Health check |

### `register` REST

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/sensors/register/:featureName` | Register a sensor feature |
| `GET` | `/sensors/:deviceUuid/features/:featureUuid/:featureName` | Get latest value for a feature |
| `DELETE` | `/sensors/:deviceUuid/features/:featureUuid` | Delete a sensor feature value |
| `GET` | `/keepalive` | Health check |

### `alarm-api` REST

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/online/:deviceUuid/features/:featureUuid` | Get online state |
| `DELETE` | `/online/:deviceUuid/features/:featureUuid` | Delete online state |
| `POST` | `/fcmtoken` | Initialize/store FCM token |
| `PUT` | `/alarms/:deviceUuid/features/:featureUuid/notifications` | Update per-feature alarm notification silence flag |
| `PUT` | `/api-token` | Update API token references in Redis |
| `GET` | `/notifications/:apiToken` | List sent notification history for a profile API token |
| `GET` | `/keepalive` | Health check |

### `alarm-receiver` and `alarm-notifier`

Both expose Rocket health endpoints through `/keepalive`. Their main work happens in background loops:

- `alarm-receiver`: MQTT event loop.
- `alarm-notifier`: Redis scan, FCM notification, and notification-history persistence loop.

### `api-devices` gRPC

Registered gRPC services:

- Standard `grpc.health.v1.Health`.
- `Registration` service from `api/register/register.proto`.
- `Device` service from `api/device/device.proto`.

Responsibilities found in source:

- Register or update controllers.
- Get controller values.
- Set device/controller values by signing requested feature values and publishing MQTT messages to `devices/{deviceUuid}/values`.
- Delete controller metadata and publish cleanup/delete state as part of device deletion flows.
- Cap `SetValues` requests at 100 values and update MongoDB command status only after MQTT publish succeeds.
- Use optional gRPC TLS when `GRPC_TLS=true`.

## Ports

| Component | Local/debug port | Production/chart port | Notes |
|---|---:|---:|---|
| `api-server` | `8082` commonly used in tests/docs | `80` | Gin HTTP |
| `admission` | `8099` commonly used in tests/docs | `80` | Gin HTTP |
| `api-devices` | `50051` | `50051` | gRPC |
| `register` | Rocket debug default or `8000` in docs/tests | `80` | Rocket release chart exposes 80 |
| `alarm-api` | `8089` | `80` | Rocket debug port is configured |
| `alarm-receiver` | `8088` | `80` | Health endpoint plus MQTT background loop |
| `alarm-notifier` | `8091` | `80` | Health endpoint plus notification loop |
| `gui` | Vite/Nx dev server | `80` | Built assets served by standalone GUI image or copied to `api-server/public` for dev |
| `Mosquitto` | `1883`, `8883`, `9001` historically | `1883`/`8883` | MQTT, optional TLS |
| `RabbitMQ` | `5672`, `15672` | `5672`, `15672` | AMQP and management |
| `Redis` | `6379` | `6379` | Authenticated in chart |
| `MongoDB` | `27017`, `27018` via local compose | External Atlas URL in chart | Main and sensors DBs |

## Authentication And Security

- User auth uses GitHub OAuth2.
- Web auth uses sessions, cookies, access JWTs, refresh tokens, and CSRF/PKCE-like OAuth state handling.
- Android auth uses OAuth2 app routes, PKCE, secure preferences, and token refresh.
- API routes under `/api` are protected by JWT middleware except OAuth and keepalive routes.
- Device/API tokens are hashed with `API_TOKEN_HASH_SECRET`; some services also require `API_TOKEN_ENCRYPTION_KEY` for encrypted token storage/lookup.
- MQTT sensor and online payloads are signed with HMAC and include timestamp, nonce, device UUID, feature UUID, feature name/payload, and signature.
- Redis is used for replay protection of signed MQTT nonces.
- Redis DB assignments are fixed: DB 0 online/FCM lookups, DB 1 notification history, DB 2 signed replay claims, and DB 3 alarm settings/pending events. DB 15 is test-only.
- AMQP messages from producer to consumer are signed with an HMAC header.
- The Helm chart creates separate MQTT users for device, producer, alarm-receiver, and api-devices roles.
- The Helm chart includes network policies, dedicated service accounts, disabled service account token automounts for workloads, Gateway security headers, optional TLS certificates, and egress policies for GitHub, MongoDB Atlas, and Google/FCM.

## Deployment

`deployer/home-anthill` is a Helm application chart:

- Chart version: `6.1.0`.
- App version: `5.1.0`.
- Namespace default: `home-anthill`.
- Uses NGINX Gateway Fabric Gateway API routes for web HTTP/HTTPS and MQTT TCP routing.
- Uses cert-manager Issuers/Certificates for web and MQTT TLS.
- Uses Cilium LB-IPAM/L2 announcement and Cilium network policies for selected egress.
- Uses RabbitMQ Cluster Operator resources for RabbitMQ users and permissions.
- Deploys Redis, Mosquitto, GUI, admission, api-server, api-devices, register, producer, consumer, alarm-api, alarm-receiver, and alarm-notifier.
- Uses Redis DB 1 as the default notifications Redis store for sent-notification history.
- Uses Redis DB 3 for alarm notification settings and pending generic alarm events.
- Includes smoke tests for GUI, API, alarm-api, Redis, Mosquitto, and RabbitMQ.
- Uses external MongoDB through `mongodbUrl`, typically MongoDB Atlas.

Important deployment sidecars/helpers:

- `admission-nginx` is deployed in front of `admission` for the public registration path.
- `k8s-config-reloader` can watch mounted config/secret directories and send `SIGHUP` or another configured signal to a named process.
- `mosquitto` image entrypoint generates `/mosquitto/passwd/password_file` from `MOSQUITTO_USERS` or `MOSQUITTO_USERNAME`/`MOSQUITTO_PASSWORD`, validates credentials, clears secret env vars, then `exec`s Mosquitto.

## Local Infrastructure

### MongoDB

`sharded-mongodb-compose` runs a local sharded MongoDB cluster:

- Shard0: `shard0-replica0`, `shard0-replica1`.
- ConfigDB: `configdb-replica0`, `configdb-replica1`.
- Routers: `mongos-router0` on `127.0.0.1:27017`, `mongos-router1` on `127.0.0.1:27018`.

### RabbitMQ

`rabbitmq-local` contains:

- `guest` administrator.
- `produceruser` with configure permission on `ks89`, write permission on `amq.default` and `ks89`, read permission on `ks89`.
- `consumeruser` with configure/read permission on `ks89` and no write permission.
- `management.load_definitions = /etc/rabbitmq/definitions.json`.

### MQTT Checker

`mqtt-communication-checker` is the main local end-to-end verification tool. It:

- Checks Mosquitto, RabbitMQ, MongoDB, Redis, producer, consumer, and alarm-receiver readiness.
- Reads profiles/devices from the `api-server` MongoDB database.
- Joins registered feature metadata from `sensors.sensors` and controller metadata from `controllers.controllers`.
- Generates signed MQTT payloads and verifies resulting MongoDB/Redis state.
- Publishes controller command messages to `devices/{deviceUuid}/values`.

## Frontends

### Web GUI

The `gui` repository is a React 19.2 app using Vite 8.0, Nx 22.6, Mantine 9, Redux Toolkit Query, React Router 7, and MSW/Vitest tests. Main screens found:

- Login and post-login OAuth handling.
- Devices list and device details.
- Sensor values, online status, and controller value controls.
- Homes and rooms management.
- Profile display, logout, and API token rotation.
- Notification history and per-feature notification mute controls.

REST API calls are centralized through RTK Query services under `src/services`, with `/api` as the base path.

### Android App

The Android app uses Jetpack Compose, Material 3, Navigation Compose, Retrofit, OkHttp, Koin, WorkManager, Firebase Messaging, Firebase Analytics, and secure preferences. Main scanned capabilities:

- GitHub OAuth2 app login with PKCE.
- Token refresh and logout.
- Homes, rooms, devices, sensor values, controller values, and online state screens.
- FCM token worker/scheduler.
- Firebase messaging service and in-app notification bus.
- Notification history and per-feature notification mute state support.

Build config:

- Namespace/application id: `eu.homeanthill`.
- `minSdk = 33`, `targetSdk = 36`, `compileSdk = 37`.
- Build types: `debug`, `staging`, `release`.

## Firmware And Device Types

Firmware variants present:

- `ac-beko`: Beko air-conditioner controller, IR handling, MQTT, registration, storage, Wi-Fi.
- `ac-lg`: LG air-conditioner controller, IR handling, MQTT, registration, storage, Wi-Fi.
- `airquality-motion`: Air quality plus motion sensor.
- `barometer`: Air pressure sensor.
- `dht-light`: Temperature/humidity plus light sensor.
- `thermostat`: Controller, display, temperature sensor, MQTT, registration, storage, Wi-Fi.

Each firmware folder has source files plus tests. Shared patterns include:

- Wi-Fi handling.
- Registration with backend.
- MQTT publishing/handling.
- Local storage of identifiers/secrets.
- Signed payload generation expected by backend services.

`esp32-configurator` generates ESP32 header files from YAML using Jinja2 templates, including `templates/secrets.h`.

## Documentation Assets

`docs` contains:

- `README.md`, local development, Hetzner install, and firmware install guides.
- Architecture and workflow diagrams in Draw.io and PNG form.
- Hardware images and ESP32 pinout images.
- A Beko RG52A9/BGEF remote control PDF reference.
- Logo/icon assets.
- Bruno API collection.
- Helper scripts such as `download-full-project.sh` and `fill-local-db.sh`.

The organization profile in `.github/profile/README.md` contains a concise public-facing architecture summary and service table.
