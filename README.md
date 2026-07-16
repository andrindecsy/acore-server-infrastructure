# Self-Hosted Game Server Infrastructure

Setup, operation, and automation of a Linux-based multiplayer server — including network troubleshooting, monitoring, and CI-like automation — built as a personal learning project.

📖 **Detailed documentation:**
- [Setup Guide](docs/SETUP.md) — database fixes, automation scripts, monitoring
- [Tunneling & Networking](docs/TUNNELING.md) — CGNAT/DS-Lite diagnosis, evaluated approaches, final configuration

## Overview

This project covers the complete setup of a persistent application server (AzerothCore, an open-source emulator for a well-known MMO client) on a self-managed Linux VM, including:

- Database setup and troubleshooting (MySQL)
- Network diagnosis and resolution (CGNAT/DS-Lite issues, NAT traversal via tunneling)
- Fully automated operations (scheduled restarts, crash recovery, monitoring)
- External notifications via REST API integration (Discord Webhooks)

The focus of this repo is **not** the server application itself (which is open source, see [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk)), but the **independently developed infrastructure and automation layer** built on top of it.

## Architecture

```
Player Client
      │
      ▼
Tunnel Service (public IP)
      │
      ▼
Linux VM (behind CGNAT/DS-Lite, no native public IPv4)
      │
      ├── authserver / worldserver (C++ application server)
      ├── MySQL (account, character, and world databases)
      ├── systemd services (tunnel clients, auto-start)
      ├── Cron jobs (scheduled restarts, watchdog, memory logging)
      └── Bash automation (status checks, deployment scripts)
                │
                ▼
        Discord Webhooks (status, monitoring, and warning alerts)
```

For details on the network architecture (why a tunnel was needed and which alternatives were evaluated), see [docs/TUNNELING.md](docs/TUNNELING.md).

## Highlights

- **CGNAT/DS-Lite diagnosis**: systematically narrowed down a network issue across multiple layers (router configuration → ISP connection type → cloud firewall → `tcpdump` packet analysis), see [docs/TUNNELING.md](docs/TUNNELING.md)
- **Database root-cause analysis**: traced a schema constraint error that was silently breaking player logins, from application logs down to the exact cause, see [docs/SETUP.md](docs/SETUP.md)
- **Long-term monitoring**: logged and analyzed memory usage across multiple test runs (up to 48h) to distinguish normal caching behavior from genuine resource growth
- **Fully automated operations**: scheduled restarts with staggered player warnings, automatic crash detection and recovery, real-time Discord notifications

## Tech Stack

- **Scripting:** Bash
- **Database:** MySQL (schema adjustments, data analysis via SQL)
- **OS/Infrastructure:** Linux (Ubuntu), systemd, cron, ufw/iptables
- **Networking:** NAT traversal, TCP tunneling, DNS (dynamic DNS)
- **Integration:** REST APIs (curl, JSON), Discord Webhooks

## Repo Structure

```
azerothcore-infra/
├── README.md
├── README_EN.md
├── docs/
│   ├── SETUP.md
│   └── TUNNELING.md
├── scripts/
│   ├── server-start.sh
│   ├── server-stop.sh
│   ├── scheduled-restart.sh
│   ├── watchdog.sh
│   └── memlog.sh
├── bashrc-functions.sh
└── config/
    └── discord-webhooks.conf.example
```

## What I Learned

- Systematic debugging across multiple infrastructure layers (network, OS, application, database)
- Evaluating and comparing different technical solutions based on cost, stability, and fit for purpose
- Automating operational workflows (deployment, monitoring, recovery) without manual intervention
- The importance of logging and monitoring for diagnosing issues that only become visible over time

---

*This is a personal learning project. The underlying application server is based on [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk) (open source, AGPL-3.0).*
