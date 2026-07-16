# Setup Guide

This document covers the practical setup steps and gotchas encountered while building this infrastructure — beyond what's already covered in AzerothCore's own installation docs.

For the network/tunneling side specifically, see [TUNNELING.md](TUNNELING.md).

## Prerequisites

- A Linux VM (Ubuntu used throughout this project) with AzerothCore already compiled and its base databases imported
- `tmux`, `mysql-client`, `curl`
- A Discord server with three text channels for notifications (e.g. `#server-status`, `#memory-log`, `#warnings`)

## 1. Database Setup Gotchas

### Missing base tables
If `worldserver` fails on startup with something like:
```
ERROR 1146 (42S02) at line 2: Table 'acore_world.version' doesn't exist
```
this means the base SQL files were never imported — only the incremental update files were attempted. Fresh AzerothCore checkouts ship the `acore_world` base data as many individual per-table `.sql` files rather than one bundled dump. Import them all before starting the server:

```bash
cd ~/azerothcore-wotlk/data/sql/base/db_world/
for f in *.sql; do
  mysql -u acore -pacore -h 127.0.0.1 acore_world < "$f"
done
```

### `last_ip` column too small for tunneled connections
When traffic reaches your server through a tunnel/relay, the connecting IP is often recorded in IPv4-mapped IPv6 notation (e.g. `::ffff:127.0.0.1`), which is longer than a plain IPv4 address. If the `last_ip` column is sized for IPv4 only, this causes a silent authentication failure — the player reaches character selection but gets disconnected, and `Auth.log` shows:
```
[ERROR]: [1406] Data too long for column 'last_ip' at row 1
```

Fix:
```sql
ALTER TABLE account MODIFY last_ip VARCHAR(45);
ALTER TABLE account MODIFY last_attempt_ip VARCHAR(45);
```

## 2. Automation Scripts

All scripts live in [`scripts/`](../scripts) and interactive shortcuts live in [`bashrc-functions.sh`](../bashrc-functions.sh).

### Installation
```bash
# Copy scripts to your home directory
cp scripts/*.sh ~/
chmod +x ~/server-start.sh ~/server-stop.sh ~/scheduled-restart.sh ~/watchdog.sh ~/memlog.sh

# Set up Discord webhook config
cp config/discord-webhooks.conf.example ~/discord-webhooks.conf
nano ~/discord-webhooks.conf   # fill in your real webhook URLs

# Add the interactive functions to your shell
cat bashrc-functions.sh >> ~/.bashrc
source ~/.bashrc
```

### Important: absolute paths, not relative
Every script sources its config via an **absolute home-directory path**:
```bash
source ~/discord-webhooks.conf
```
not a path relative to where the script itself lives. This matters if you're used to keeping scripts and their configs in the same folder — here, `discord-webhooks.conf` must exist directly under your home directory (`~`) regardless of where the scripts themselves are placed or run from.

### Why `stop`/`start` are overridden
Most AzerothCore setup guides define:
```bash
alias stop='tmux kill-server'
```
This kills **every** tmux session on the system indiscriminately — including unrelated sessions like tunnel clients or the memory logger. `scripts/server-stop.sh` replaces this with a version that also logs the event, notifies Discord, and marks the "expected state" so the crash watchdog doesn't misfire during an intentional stop.

### Watchdog & expected-state tracking
`scripts/watchdog.sh` is designed to run via cron every 1-2 minutes:
```
*/2 * * * * /root/watchdog.sh
```
It compares whether `worldserver`/`authserver` are actually running against a small state file (`~/.server-expected-state`) written by `server-start.sh`/`server-stop.sh`. If the server is expected to be up but isn't, it's treated as a crash: Discord gets alerted, and a recovery restart is triggered automatically.

### Scheduled restarts
```
0 5,17 * * * tmux new -d -s restartcountdown "bash /root/scheduled-restart.sh"
```
Running this via a dedicated tmux session (rather than directly) means it can be cancelled mid-countdown with `restartcancel` (see `bashrc-functions.sh`) without affecting the running server, since the actual shutdown only happens at the very end of the sequence.

### Why scheduled restarts at all?
Long-running test sessions (48h+) showed a slow, steady decline in available memory that never plateaued — consistent with documented, known memory behavior in the underlying server software rather than anything specific to this setup. Scheduled restarts (paired with `memlog.sh`'s logging) are the practical mitigation: reclaim memory periodically rather than chase the root cause in third-party C++ code.

## 3. Memory Monitoring

`scripts/memlog.sh` logs system memory to `~/memory-log.csv` once per minute, with:
- A one-time Discord warning when available memory drops below a threshold (self-resets once it recovers)
- An hourly summary posted to a separate Discord channel

Useful commands (from `bashrc-functions.sh`):
```bash
memlogstart   # start logging (also auto-started by server-start.sh)
memlogread    # view the log, nicely column-aligned
memlogstop    # stop logging
```

When reading the log, note the difference between `free` and `available` in `free -h`/the CSV — `free` naturally shrinks over time as Linux fills idle RAM with disk cache, which is normal and not a leak. `available` is the number that actually matters.
