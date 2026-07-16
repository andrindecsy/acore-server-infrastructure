#!/bin/bash
# Continuously logs system memory usage once per minute to a CSV file,
# sends a Discord warning the first time available memory drops below
# a threshold (self-resetting once it recovers), and posts an hourly
# summary to a separate Discord channel.
#
# Intended to run inside a dedicated tmux session, auto-started by
# server-start.sh:
#   tmux new -d -s memlog "~/memlog.sh"
#
# Depends on:
#   - ~/discord-webhooks.conf (see config/discord-webhooks.conf.example)

source ~/discord-webhooks.conf
LOGFILE=~/memory-log.csv
LOW_MEM_THRESHOLD=1000  # MB - adjust to roughly 15-20% of your total RAM
ALERTED=0
COUNTER=0

# Write CSV header if the log file doesn't exist yet
if [ ! -f "$LOGFILE" ]; then
    echo "timestamp,total,used,free,available,swap_used" > "$LOGFILE"
fi

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    MEM_LINE=$(free -m | awk '/^Mem:/ {print $2","$3","$4","$7}')
    SWAP_USED=$(free -m | awk '/^Swap:/ {print $3}')
    AVAILABLE=$(free -m | awk '/^Mem:/ {print $7}')
    echo "${TIMESTAMP},${MEM_LINE},${SWAP_USED}" >> "$LOGFILE"

    # Low memory warning - fires once, resets once memory recovers
    if [ "$AVAILABLE" -lt "$LOW_MEM_THRESHOLD" ] && [ "$ALERTED" -eq 0 ]; then
        send_discord "$WEBHOOK_WARNINGS" "⚠️ **Low memory warning**: only ${AVAILABLE}MB available (threshold: ${LOW_MEM_THRESHOLD}MB) at ${TIMESTAMP}"
        ALERTED=1
    elif [ "$AVAILABLE" -ge "$LOW_MEM_THRESHOLD" ]; then
        ALERTED=0
    fi

    # Hourly summary (every 60 iterations = 60 minutes)
    COUNTER=$((COUNTER + 1))
    if [ "$COUNTER" -ge 60 ]; then
        send_discord "$WEBHOOK_MEMORY" "📊 **Hourly memory check** (${TIMESTAMP}): ${AVAILABLE}MB available"
        COUNTER=0
    fi

    sleep 60
done
