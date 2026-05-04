# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is the **documentation repository** for the home-anthill project — an IoT home automation system that uses ESP32 microcontrollers controlled via a Kubernetes-based microservice backend. This repo contains no application code; it holds guides, diagrams, images, and Postman collections.

## Project Architecture

home-anthill is a multi-repo project. The full list of repos is in `download-full-project.sh`. Key components:

- **Backend microservices** (Go, built with `make`): `api-server`, `api-devices`, `admission`
- **Backend services** (Rust, built with `make`): `register`, `producer`, `consumer`, `online`, `online-receiver`, `online-alarm`
- **Frontend**: `gui` (Node.js/npm)
- **Mobile**: `app` (Android/Kotlin)
- **ESP32 firmwares**: `firmwares` repo (Arduino IDE, C++), configured via `esp32-configurator` (Python/Poetry)
- **Infrastructure**: `deployer` (Helm charts), `mosquitto` (MQTT broker config), `sharded-mongodb-compose` (local MongoDB sharded cluster)

**Infrastructure stack**: MongoDB (Atlas for prod, Docker sharded cluster locally), RabbitMQ, Mosquitto (MQTT), Redis, K3s (Kubernetes), NGINX Gateway Fabric, Cilium (CNI, kube-proxy replacement, LoadBalancer IPAM/L2 announcements), cert-manager.

## Key Documentation Files

- `local-development.md` — Full local dev setup (Docker containers, microservices, OAuth2, Bruno)
- `hetzner-install.md` — Production Kubernetes deployment on Hetzner Cloud
- `firmwares-install.md` — Hardware wiring, Arduino IDE setup, firmware flashing
- `diagrams/` — Architecture and sequence diagrams (draw.io source + PNG exports)
- `bruno-collections/home-anthill.yml` — Bruno API collection for testing (covers `api-server`, `admission`, and `online` endpoints)
- `fill-local-db.sh` — Helper script to seed local MongoDB through running `api-server` and `admission` services

## Conventions

- Diagrams are maintained as `.drawio` files with exported `.png` versions in `diagrams/`
- Documentation references raw GitHub URLs for images (e.g., `https://raw.githubusercontent.com/home-anthill/docs/master/...`)
- The project uses `master` as the main branch but active development happens on `develop`

## Local Data Seeding

- `fill-local-db.sh` requires a JWT and the OAuth session cookie as positional parameters:
  `./fill-local-db.sh "<JWT_VALUE>" "oauth_session=<COOKIE_VALUE>"`
- The script defaults to `API_SERVER=http://localhost:8082` and `ADMISSION_SERVER=http://localhost:8099`; override those environment variables before running if needed.
- It regenerates the profile `apiToken`, creates one home with four rooms, registers supported devices through `admission`, leaves one random device unassigned, and assigns all other devices to random rooms. Device names are set to their model during the home/room assignment update.
