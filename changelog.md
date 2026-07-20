# Changelog

This tracks how the automation/monitoring layer evolved, starting from the point the server was already reachable by external players. For the connectivity work that came before this (CGNAT diagnosis, tunnel evaluation), see [TUNNELING.md](docs/TUNNELING.md) — that's a story better told as prose than as a changelog entry.

## Unreleased — Monitoring Overhaul

Restructuring memory monitoring and crash recovery so each script has exactly one job, instead of the responsibilities being split awkwardly across two.

- **Changed**: `memlog.sh` from an always-running background loop (`sleep 60` inside a persistent `tmux` session) to a stateless script triggered by cron every minute. Removes a single point of failure — a killed/crashed loop process used to mean silent, total loss of logging until manually noticed and restarted.
- **Changed**: memory logging destination from a flat CSV file to a proper MySQL table (`acore_monitoring.memory_log`), enabling actual queries instead of manual `column -t` squinting.
- **Added**: process-level metrics beyond system-wide `free -m` — `worldserver`/`authserver` RSS, thread count, open file descriptor count, and process uptime, plus online character count for correlation. Groundwork for actually diagnosing the memory growth pattern rather than just restarting around it.
- **Added**: `hourly-report.sh` — a small cron job that reads the latest logged row and posts a summary to Discord, replacing an in-script counter that used to count up to 60 inside the old loop.
- **Added**: `notify.sh` — a single unified dispatcher that every other script calls to send a Discord message, instead of each script knowing how to talk to Discord's webhook API itself. Swapping notification providers in the future means changing one file, not five.
- **Changed**: memory-threshold restart logic moved fully into `watchdog.sh`. Previously, `memlog.sh` could only *warn* about low memory; it had no ability to act. `watchdog.sh` now reads the latest row `memlog.sh` wrote and restarts the server if available memory drops below a critical threshold — restart *decisions* now live in exactly one place, alongside the existing crash-detection logic, instead of being split across two scripts with overlapping concerns.

## SSH Access for Collaborators

- **Added**: a third Localtonet tunnel (port 22) so a friend could get SSH access without needing a static public IP on the home connection either.
- **Added**: a dedicated non-root account, key-based authentication, and hardened `sshd_config` (`PasswordAuthentication no`, `PermitRootLogin no`) before exposing SSH to the internet via the tunnel.
- **Fixed**: an intermittent "Connection closed" error over mobile data traced to IPv6/IPv4 route selection differing between networks (`ssh -4` forced the working path); resolved permanently by pinning `AddressFamily inet` for the host in `~/.ssh/config`.

## Documentation Rewrite

- **Changed**: documentation from a single procedural README to a proper multi-document structure (`README.md` as a short summary, `docs/SETUP.md`, `docs/TUNNELING.md`, `docs/NOTIFICATION-SYSTEM.md`), each covering one concern.
- **Changed**: writing style from step-by-step instructions to a first-person account of what broke, why, and what was tried — the goal shifted from "a guide to copy" to "a record of what was actually learned."

## Housekeeping

- **Removed**: `start.sh` as a separate file, merging its tmux-session/authserver/worldserver launch logic directly into `server-start.sh`. It was only ever called from one place, so the indirection wasn't earning its keep.
- **Changed**: Discord integration made fully optional — scripts check for `~/discord-webhooks.conf` before sourcing it and no-op the notification function if it's missing, rather than erroring on every run for anyone who clones this without setting up Discord.

## Discord Integration

- **Added**: webhook-based Discord notifications across three channels (`#server-status`, `#memory-log`, `#warnings`), replacing "manually SSH in to check if anything's wrong" as the primary way of noticing problems.
- **Added**: start/stop/restart events, staggered restart countdown warnings (mirrored from the in-game `.announce` messages), crash alerts, and low-memory alerts, each routed to the channel that made sense for its urgency.

## Crash Recovery

- **Added**: `watchdog.sh`, run via cron every 1–2 minutes, comparing whether `worldserver`/`authserver` are actually running against an "expected state" marker file written by the start/stop scripts — distinguishing a genuine crash from an intentional stop.
- **Added**: automatic recovery restart on crash detection, tested by force-killing `worldserver` directly and confirming the watchdog brought it back without manual intervention.

## Scheduled Restarts

- **Added**: `scheduled-restart.sh`, running on a cron schedule with a staggered in-game warning sequence (15m → 10m → 5m → 3m → 1m → 30s → live countdown) and a forced `.saveall` immediately before shutdown.
- **Changed**: restart trigger from a single instant `.server shutdown` to a full warned sequence, run inside its own `tmux` session specifically so it can be cancelled mid-countdown (`restartcancel`) without touching the live server.
- **Added**: `restartnow` — a bypass for solo testing sessions where a 15-minute warning sequence isn't useful.

## Memory Investigation (v1)

- **Added**: `memlog.sh` (original loop-based version), logging `free -h` output to a CSV every minute to investigate a suspected memory leak.
- **Confirmed**: a slow, steady, non-recovering decline in available memory over multi-hour unattended test runs (~30MB/hour, observed continuously over an 11+ hour stretch with zero swap usage) — consistent with documented behavior in the underlying game server software rather than a local misconfiguration. This finding is what justified adding scheduled restarts as a mitigation, rather than chasing the root cause in third-party C++.

## Fixing the Default Server Lifecycle Scripts

- **Fixed**: replaced the commonly-used `alias stop='tmux kill-server'` with `server-stop.sh`/`server-start.sh`, since `tmux kill-server` kills *every* tmux session on the machine indiscriminately — including unrelated tunnel clients — not just the game server. This had been silently killing tunnel connectivity on every restart.
- **Added**: `.server-expected-state` marker file, written by the new stop/start scripts, laying the groundwork for the crash watchdog added later.

## Baseline — External Connections Working

Starting point for this changelog: the server was reachable by external players through a working tunnel setup, with a manually-managed realmlist and no automation beyond the default aliases from the original setup guide.

- Database schema fix: widened `account.last_ip` / `account.last_attempt_ip` from a plain-IPv4-sized column to `VARCHAR(45)`, fixing a silent authentication failure caused by IPv4-mapped IPv6 addresses (`::ffff:x.x.x.x`) produced by tunneled connections. See [TUNNELING.md](docs/TUNNELING.md) for the full story.
- Realmlist `localAddress`/`localSubnetMask` set to make every connection — regardless of network — route through the same address, avoiding a separate bug where same-LAN players got redirected to a `localAddress` that only made sense from the server's own perspective.
