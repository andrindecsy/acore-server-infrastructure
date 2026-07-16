#!/bin/bash
# Stops all AzerothCore tmux sessions (auth, world, and any tunnel
# sessions), logs the event, and notifies Discord.
#
# IMPORTANT: `tmux kill-server` kills ALL tmux sessions on the system,
# not just the AzerothCore ones. The expected-state marker is written
# BEFORE the kill so the watchdog doesn't mistake this for a crash.
#
# Depends on:
#   - ~/discord-webhooks.conf (see config/discord-webhooks.conf.example)

source ~/discord-webhooks.conf
LOGFILE=~/memory-log.csv

echo "$(date '+%Y-%m-%d %H:%M:%S'),SERVER STOPPED,,,,," >> "$LOGFILE"
send_discord "$WEBHOOK_STATUS" "🔴 **Server stopped** at $(date '+%Y-%m-%d %H:%M:%S')"
echo "stopped" > ~/.server-expected-state

tmux kill-server
