#!/bin/bash
# Starts authserver/worldserver, restarts the memory logger if needed,
# logs the event, and notifies Discord.
#
# Depends on:
#   - ~/discord-webhooks.conf (see config/discord-webhooks.conf.example)
#   - ~/start.sh (from your AzerothCore setup guide's tmux launcher script)
#   - memlog.sh (in the same directory as this script, or ~/memlog.sh)

source ~/discord-webhooks.conf
LOGFILE=~/memory-log.csv

bash /root/start.sh
echo "running" > ~/.server-expected-state

# Start the memory logger if it isn't already running
if ! tmux has-session -t memlog 2>/dev/null; then
    tmux new -d -s memlog "~/memlog.sh"
fi

echo "$(date '+%Y-%m-%d %H:%M:%S'),SERVER STARTED,,,,," >> "$LOGFILE"
send_discord "$WEBHOOK_STATUS" "🟢 **Server started** at $(date '+%Y-%m-%d %H:%M:%S')"
