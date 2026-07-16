# Self-Hosted Game Server Infrastructure

Setup, operation, and automation of a Linux-based multiplayer server — including network troubleshooting, monitoring, and CI-like automation — built as a personal learning project.

**Detailed documentation:**
- [Setup Guide](docs/SETUP.md) — database fixes, automation scripts, monitoring
- [Tunneling & Networking](docs/TUNNELING.md) — CGNAT/DS-Lite diagnosis, evaluated approaches, final configuration

## Repo Structure

```
azerothcore-infra/
├── config/
│   └── discord-webhooks.conf.example
├── docs/
│   ├── SETUP.md
│   └── TUNNELING.md
├── scripts/
│   ├── server-start.sh
│   ├── server-stop.sh
│   ├── scheduled-restart.sh
│   ├── watchdog.sh
│   └── memlog.sh
├── README.md
└── bashrc-functions.sh
```

## Overview

This project covers my journey of setting up a persistent application server on a Linux machine, which could be your main machine, a VM on your main machine, a cloud VM, a Raspberry Pi or any other device with enough memory and an internet connection. You could find any one piece of information in here useful for your own projects. It is meant more as a documentation of the learning process and less as a comprehensive, all-encompassing guide. It includes:

- Network diagnosis and resolution aka. my friends can't connect to my server
- Fully automated operations
- External Discord notifications via REST API integration

The focus of this repo is **not** the server application itself (which is open source, see [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk)), but the **independently developed infrastructure and automation layer** built on top of it. I will not be going into the server installation itself and instead [point you to this video guide](https://www.youtube.com/watch?v=DwJ6OfPophw) that I myself followed.

## Architecture

```
Player Client
      │
      ├─────────────────────────────┐
      │                             │
      ▼                             │  
Tunnel Service                      │
(optional, see docs/TUNNELING.md)   │
      │                             │
      │                             │
      ├─────────────────────────────┘
      │
      ▼
Your server
      │
      ├── AzerothCore applications and databases
      ├── systemd services -> tunnel clients, auto-start
      ├── Cron jobs -> scheduled restarts, watchdog, memory logging
      └── Bash automation -> status checks, deployment scripts
                │
                ▼
        Discord Webhooks (status, monitoring, and warning alerts)
```

For details on the network architecture (why a tunnel was needed, do you also need one, the solution I ended up using and some alternatives), see [docs/TUNNELING.md](docs/TUNNELING.md).

## Highlights

- **CGNAT/DS-Lite diagnosis**: systematically narrowed down a network issue across multiple layers (router configuration → ISP connection type → cloud firewall → `tcpdump` packet analysis)
- **Database root-cause analysis**: traced a schema constraint error that was silently breaking player logins, from application logs down to the exact cause
- **Long-term monitoring**: logged and analyzed memory usage across multiple test runs (up to 48h) to distinguish normal caching behavior from genuine resource growth
- **Fully automated operations**: scheduled restarts with staggered player warnings, automatic crash detection and recovery, real-time Discord notifications

## Tech Stack

- **Scripting:** Bash
- **Database:** MySQL
- **OS/Infrastructure:** Linux (Debian13), systemd, cron, ufw/iptables
- **Networking:** NAT traversal, TCP tunneling, DDNS
- **Integration:** REST APIs (curl, JSON), Discord Webhooks







---

*This is a personal learning project. The underlying application server is based on [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk) (open source, AGPL-3.0).*
