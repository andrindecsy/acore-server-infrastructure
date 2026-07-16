#!/bin/bash
# Crash detection watchdog. Intended to run every 1-2 minutes via cron:
#   */2 * * * * /root/watchdog.sh
#
# Compares the "expected" server state (set by server-start.sh /
# server-stop.sh) against whether authserver/worldserver are actually
# running. If the server is expected to be up but either process is
# missing, this is treated as a crash: it alerts Discord and attempts
# an automatic recovery restart.
#
# Depends on:
#   - ~/discord-webhooks.conf (see config/discord-webhooks.conf.example)
#   - ~/.server-expected-state (written by server-start.sh / server-stop.sh)
#   - server-stop.sh / server-start.sh (in the same directory or ~)

source ~/discord-webhooks.conf
STATEFILE=~/.server-expected-state
LOGFILE=~/watchdog-log.txt

# If no state file exists yet, assume the server is expected to be running
if [ ! -f "$STATEFILE" ]; then
    echo "running" > "$STATEFILE"
fi

EXPECTED=$(cat "$STATEFILE")
WORLD_PID=$(pgrep -x worldserver | head -1)
AUTH_PID=$(pgrep -x authserver | head -1)

if [ "$EXPECTED" = "running" ] && { [ -z "$WORLD_PID" ] || [ -z "$AUTH_PID" ]; }; then
    MISSING=""
    [ -z "$WORLD_PID" ] && MISSING="${MISSING}worldserver "
    [ -z "$AUTH_PID" ] && MISSING="${MISSING}authserver "

    echo "$(date): CRASH DETECTED - missing: $MISSING" >> "$LOGFILE"
    send_discord "$WEBHOOK_WARNINGS" "🚨 **CRASH DETECTED**: ${MISSING}not running but expected to be! ($(date '+%Y-%m-%d %H:%M:%S'))"

    echo "$(date): Attempting automatic recovery restart" >> "$LOGFILE"
    bash ~/server-stop.sh
    sleep 5
    bash ~/server-start.sh
    send_discord "$WEBHOOK_WARNINGS" "🔧 **Auto-recovery attempted**: server restart triggered after crash detection."
fi
