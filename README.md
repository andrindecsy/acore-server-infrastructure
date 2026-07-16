# acore-server-infrastructure

Self-Hosted Game Server Infrastructure

Setup, operation, and automation of a Linux-based multiplayer server — including network troubleshooting, monitoring, and CI-like automation — built as a personal learning project.

Overview

This project covers the complete setup of a persistent application server (AzerothCore, an open-source emulator for a well-known MMO client) on a self-managed Linux VM, including:


Database setup and troubleshooting (MySQL)
Network diagnosis and resolution (CGNAT/DS-Lite issues, NAT traversal via tunneling)
Fully automated operations (scheduled restarts, crash recovery, monitoring)
External notifications via REST API integration (Discord Webhooks)


The focus of this repo is not the server application itself (which is open source, see AzerothCore), but the independently developed infrastructure and automation layer built on top of it.

Architecture

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

Problems Solved (Selection)

Network Diagnosis: CGNAT/DS-Lite

The host's internet connection turned out to be a DS-Lite connection (IPv6-only with a shared, non-forwardable IPv4 address via Carrier-Grade NAT). This made traditional port forwarding technically impossible. Solution: evaluated multiple tunneling approaches (including bore, Cloudflare Tunnel, self-hosted relay servers, and commercial tunnel providers), weighing cost, stability, and suitability for raw TCP traffic (not just HTTP).

Database Constraint Error on IPv6 Connections

After setting up a tunnel, authentication began failing. Root-cause analysis across multiple layers (network → application logs → database) revealed that the last_ip column was sized for plain IPv4 addresses only and too small for the IPv4-mapped IPv6 notation (::ffff:x.x.x.x) produced by tunneled connections. Fixed via a schema adjustment.

Long-Term Memory Analysis

Systematic logging of memory usage across multiple test runs (up to 48h) to distinguish between normal caching behavior (Linux page cache) and genuine, continuous memory growth. Result: identified as documented, known behavior in the underlying software — mitigated by implementing automated, scheduled restarts.

Automation

ScriptFunctionserver-start.sh / server-stop.shClean start/stop with logging and state trackingscheduled-restart.shScheduled restart with staggered player warnings (15 min down to a live countdown) and a forced savewatchdog.shCron-based crash detection with automatic recovery restartmemlog.shContinuous memory monitoring with threshold-based alertsDiscord integrationStatus updates (start/stop/restart), warnings (crashes, low memory), periodic reports

Tech Stack


- Scripting: Bash
- Database: MySQL (schema adjustments, data analysis via SQL)
- OS/Infrastructure: Linux (Ubuntu), systemd, cron, ufw/iptables
- Networking: NAT traversal, TCP tunneling, DNS (dynamic DNS)
- Integration: REST APIs (curl, JSON), Discord Webhooks





This is a personal learning project. The underlying application server is based on AzerothCore (open source, AGPL-3.0).
