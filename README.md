# Self-Hosted Game Server Infrastructure

Setup, operation, and automation of a Linux-based multiplayer server, including network troubleshooting, monitoring, and CI-like automation - built as a personal learning project.

**Detailed documentation:**
- [Tunneling & Networking](docs/TUNNELING.md) - network diagnosis, database fixes, evaluated approaches, final configuration
- [Setup Guide](docs/SETUP.md) - automation scripts, monitoring
- [Discord Integration](docs/NOTIFICATION-SYSTEM-md) - relay server data to text channels

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

- Network diagnosis and resolution aka. my friends can't connect to my server, what do I do?
- Fully automated monitoring and maintenance via Cron-Jobs. This includes server-data logging, scheduled controlled restart and a watchdog process for detecting crashed services and automatically restarting them
- External Discord notifications via REST API integration for relaying analytics data gained from monitoring processes. Make relevant information such as server status, performance and scheduled restarts easily accesible.

The focus of this repo is **not** the server application itself (which is open source, see [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk)), but the **independently developed infrastructure and automation layer** built on top of it. I will not be going into the server installation itself and instead point you to [the official wiki](https://www.azerothcore.org/wiki/installation) and [this video guide](https://www.youtube.com/watch?v=DwJ6OfPophw) that I myself followed.

AzerothCore is a modular server solution, meaning it was developed as a solid core to which auxilary modules can be attached with relative ease. The server this documentation is based has the following modules installed:

- [Playerbots](https://github.com/mod-playerbots/mod-playerbots)
- [AHBot](https://github.com/azerothcore/mod-ah-bot)
- [MultiBot Bridge](https://github.com/Wishmaster117/mod-multibot-bridge) serverside + [MultiBot Chatless](https://github.com/Wishmaster117/MultiBot-Chatless) client side
- [Dungeon Clear](https://github.com/jrad7/mod-dungeon-clear) serverside + [Dungeon Clear Addon](https://github.com/jrad7/mod-dungeon-clear-addon) client side

These are just listed for the sake of completeness, as the scripts talked about here don't rely on any other software other than the base core.


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
