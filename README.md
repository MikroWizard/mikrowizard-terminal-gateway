# 🖥️ MikroWizard+ Terminal Gateway

[![Docker Image](https://img.shields.io/badge/Docker%20Hub-mikrowizard%2Fterminal--gateway-blue?logo=docker)](https://hub.docker.com/r/mikrowizard/terminal-gateway)
[![Image Version](https://img.shields.io/badge/version-v1.0.0-green)](https://hub.docker.com/r/mikrowizard/terminal-gateway)
[![Architecture](https://img.shields.io/badge/arch-linux%2Famd64%20%7C%20linux%2Farm64-informational)](#system-architecture)
[![License](https://img.shields.io/badge/license-Commercial%20%2F%20Proprietary-red)](#-proprietary-source-code--security-notice)
[![Security Status](https://img.shields.io/badge/security-audited-success)](#-security-model)

**MikroWizard+ Terminal Gateway** is an enterprise-grade, zero-trust web terminal and policy enforcement gateway designed for **MikroWizard**. It securely connects browser sessions to network appliances, servers, and embedded devices (MikroTik RouterOS, Linux, macOS, BSD) with real-time audit logging, multi-user collaboration, and kernel-level command interception.

---

## 📌 Overview

The Terminal Gateway acts as an intelligent intermediary between the **MikroWizard Web Console** and target infrastructure. Instead of granting raw, unrestricted SSH/Telnet sessions, all terminal I/O is parsed, monitored, and mediated in real time.

```
┌─────────────────────────┐
│   MikroWizard Backend   │ (Auth, RBAC, Redis Sessions)
└────────────┬────────────┘
             │ Bearer Token REST API (/health, /agent/*)
             ▼
┌─────────────────────────────────────────────────────────────┐
│             MikroWizard+ Terminal Gateway                   │
│         [ mikrowizard/terminal-gateway:latest ]             │
│                                                             │
│  ┌──────────────────────┐      ┌─────────────────────────┐  │
│  │   WebSocket Bridge   │ ───► │  Policy & Audit Engine  │  │
│  │     (xterm.js)       │      │  (Asciinema .cast logs) │  │
│  └──────────────────────┘      └────────────┬────────────┘  │
└─────────────────────────────────────────────┼───────────────┘
                                              │ SSH / Telnet / Agent PTY
                                              ▼
                                 ┌─────────────────────────┐
                                 │   Target Infrastructure │
                                 │  - MikroTik RouterOS    │
                                 │  - Linux / BSD / macOS  │
                                 └─────────────────────────┘
```

---

## ✨ Features

- 🌐 **Zero-Client Browser Terminal**: Smooth, responsive terminal experience powered by `xterm.js` over secure WebSockets (`wss://`).
- 🛡️ **Dual-Tier Policy Enforcement**:
  - **Kernel Tier (Linux)**: Low-level `ptrace` and `seccomp` system-call interception blocking prohibited `execve` binaries before execution.
  - **Compatible Tier (macOS / BSD / Generic)**: High-speed shell hook traps backed by cryptographic tamper monitoring and heartbeat silence detection.
- 👥 **Real-Time Collaboration**: Shared terminal rooms supporting multi-user sessions with role enforcement (`Owner`, `Collaborator`, `Observer`).
- 📼 **Tamper-Evident Session Recording**: Full session keystrokes and visual output recorded in Asciinema v2 (`.cast`) format.
- 🔑 **Zero-Trust Security**: Three independent credential boundaries (Backend ↔ Gateway, Browser ↔ Gateway, Agent ↔ Gateway) with constant-time token comparison.
- 🐳 **Prebuilt Multi-Architecture Container**: Ready-to-deploy Docker image for `linux/amd64` and `linux/arm64`.

---

## 🚀 Quick Start & Installation

### Prerequisites

- Linux operating system (Ubuntu 20.04+, Debian 11+, RHEL 8+, AlmaLinux, Rocky Linux)
- Docker Engine installed and running
- Root privileges (`sudo`)
- MikroWizard installed (default location: `/opt/mikrowizard`)

---

### Option 1: 1-Line Remote Install (Recommended)

Run this single command on the host running MikroWizard:

```bash
curl -fsSL https://raw.githubusercontent.com/MikroWizard/mikrowizard-terminal-gateway/main/install.sh | sudo bash
```

The installer will:
1. Automatically read the existing `/opt/mikrowizard/server-conf.json` (or prompt if remote).
2. Generate/link a high-entropy API token.
3. Pull the latest official image (`mikrowizard/terminal-gateway:latest`) from Docker Hub.
4. Launch the container with host networking and automatic restart.
5. Verify health check status and signal MikroWizard to reload configuration.

---

### Option 2: Clone & Run Locally

```bash
git clone https://github.com/MikroWizard/mikrowizard-terminal-gateway.git
cd mikrowizard-terminal-gateway
sudo bash install.sh
```

---

### Option 3: Docker Compose

For orchestrations using Docker Compose, use the provided [`docker-compose.yml`](docker-compose.yml):

```bash
# 1. Clone the repository
git clone https://github.com/MikroWizard/mikrowizard-terminal-gateway.git
cd mikrowizard-terminal-gateway

# 2. Copy the sample environment file and adjust variables
cp .env.example .env

# 3. Start the container
docker compose up -d
```

---

## ⚙️ Configuration Reference

### Port & Network Architecture

| Service | Container Port | Default Host Port | Access Scope |
| :--- | :--- | :--- | :--- |
| **Terminal WebSocket / Control** | `8200` | `8200` (or `8201` via nginx) | Loopback (`127.0.0.1`) |
| **Agent Check-in HTTP** | `8201` | `8201` (or `8202` via nginx) | Loopback / Internal Network |

### Environment Variables

| Variable | Default | Description |
| :--- | :--- | :--- |
| `PORT` | `8200` | Gateway WebSocket & HTTP control port |
| `GATEWAY_BIND` | `127.0.0.1` | IP bind address (`0.0.0.0` for separate gateway host) |
| `GATEWAY_TOKEN` | *Auto-generated* | Shared secret for Backend ↔ Gateway authentication |
| `AGENT_PORT` | `8201` | Port used by ephemeral target agents for phone-home check-ins |
| `AGENT_BIND` | `127.0.0.1` | Agent HTTP bind address |
| `PYSRV_CONFIG_PATH` | `/opt/mikrowizard/server-conf.json` | Path to shared MikroWizard configuration |
| `PYSRV_REDIS_HOST` | `127.0.0.1:6379` | Backend Redis address for session verification |
| `PYSRV_DATABASE_HOST` | `127.0.0.1` | Backend PostgreSQL database host |
| `PYSRV_DATABASE_PORT` | `5432` | Backend PostgreSQL port |
| `PYSRV_DATABASE_NAME` | `MIKROMAN` | Backend PostgreSQL database name |
| `PYSRV_TERMINAL_RECORDINGS_DIR` | `/opt/mikrowizard/terminal_recordings` | Directory where session recordings (`.cast`) are saved |

---

## 🔒 Security Model

The gateway is built around a zero-trust credential architecture:

1. **Backend ↔ Gateway (`terminal_gateway_token`)**:
   - Every administrative request (including `/health`) requires an `Authorization: Bearer <token>` header.
   - The gateway will refuse to start if no token is configured.
   - Tokens are validated with `secrets.compare_digest` (constant-time comparison).

2. **Browser ↔ Gateway (`session_token`)**:
   - Short-lived tokens (120-second TTL) are issued by the MikroWizard backend into Redis upon user authorization.
   - The browser connects to `wss://<host>/terminal-ws/?token=<session_token>`. Once consumed, tokens are invalidated.

3. **Agent ↔ Gateway (`agent_token`)**:
   - Each target device session receives an isolated, session-scoped 64-character token.
   - Agent binaries deployed to target devices are signed in memory via Ed25519 cryptography.

---

## 🛡️ Proprietary Source Code & Security Notice

### Why is the source code not publicly published?

The **MikroWizard+ Terminal Gateway** contains proprietary intellectual property and sensitive security mechanics:
- **Kernel-level interception engines** (`ptrace`/`seccomp` system-call analysis).
- **Anti-tamper detection algorithms** and active bypass prevention heuristics.
- **Protocol mediation state machines** for multi-vendor network devices.

To protect these security mechanisms against malicious exploitation and reverse-engineering, the gateway is distributed as a pre-built, obfuscated, and cryptographically verified Docker container on Docker Hub.

---

## 🏢 Pro & Enterprise Customers: Source Code Access under NDA

We recognize that enterprise compliance policies, regulatory standards, and internal security reviews often require access to the underlying source code.

Full source code access (including the Python gateway, Go agent sources, and build toolchains) is available to **MikroWizard Pro and Enterprise customers** under a mutual **Non-Disclosure Agreement (NDA)**.

### How to Request Source Code Access:

1. **Submit a Request**: Email our enterprise security team at [security@mikrowizard.com](mailto:security@mikrowizard.com) or reach out to your designated account manager.
2. **Provide Required Information**:
   - Organization / Company Name
   - Active MikroWizard Pro/Enterprise License Key or Subscription ID
   - Primary security auditor / compliance officer contact
   - Intended scope (e.g., internal security audit, sovereign on-prem deployment, air-gapped integration)
3. **NDA Execution**: Our legal team will provide our mutual standard NDA (or review your corporate agreement).
4. **Repository Access**: Upon completion, designated engineers are invited to the private source code repository and provided with full build verification pipelines.

---

## 🤝 Contributing & Bug Reports

While the core source code is proprietary, we welcome public issue reports, feature requests, and installer improvements!

- **Bug Reports & Issues**: [GitHub Issues](https://github.com/MikroWizard/mikrowizard-terminal-gateway/issues)
- **Security Disclosures**: Please see our [Security Policy](SECURITY.md) before reporting security issues.

---

## 📄 License

The installer, Docker Compose files, and documentation in this repository are licensed under the [MIT License](LICENSE).
The pre-compiled Docker container (`mikrowizard/terminal-gateway`) is proprietary software owned by **MikroWizard**.

---

© 2026 [MikroWizard](https://mikrowizard.com). All rights reserved.
