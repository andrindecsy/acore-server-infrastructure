# !/bin/bash
#
# Two independent checks, run every minute via cron:
#   1. Process crash detection
#   2. Memory-threshold restart, reading the latest row memlog.sh wrote to MySQL
#
# Depends on:
#   - notify.sh (in the same directory or ~/notify.sh)
#   - server-start.sh (in the same directory or ~/server-start.sh)
#   - server-stop.sh (in the same directory or ~/server-stop.sh)

STATEFILE=~/.server-expected-state
CRITICAL_MEM_THRESHOLD=500  # MB - adjust based on your own memlog history

# fallback in case server-expected-state doesn't exist. avoids potential reset loop the very first time watchdog is run
if [ ! -f "$STATEFILE" ]; then
    echo "running" > "$STATEFILE"
fi

# load expected server state and per-PID metrics from database
EXPECTED=$(cat "$STATEFILE")
WORLD_PID=$(pgrep -x worldserver | head -1)
AUTH_PID=$(pgrep -x authserver | head -1)

RESTART_NEEDED=0
REASON=""

# check 1: crash detection and fail identification
if [ "$EXPECTED" = "running" ] && { [ -z "$WORLD_PID" ] || [ -z "$AUTH_PID" ]; }; then
    MISSING=""
    [ -z "$WORLD_PID" ] && MISSING="${MISSING}worldserver "
    [ -z "$AUTH_PID" ] && MISSING="${MISSING}authserver "
    REASON="crash (missing: ${MISSING})"
    RESTART_NEEDED=1
fi

# check 2: memory threshold
if [ "$RESTART_NEEDED" -eq 0 ] && [ "$EXPECTED" = "running" ]; then
    AVAILABLE=$(mysql -u acore -pacore -h 127.0.0.1 acore_monitoring -N -e "
        SELECT available_mb FROM memory_log ORDER BY id DESC LIMIT 1;" 2>/dev/null)

    if [ -n "$AVAILABLE" ] && [ "$AVAILABLE" -lt "$CRITICAL_MEM_THRESHOLD" ]; then
        REASON="low memory (${AVAILABLE}MB available, threshold ${CRITICAL_MEM_THRESHOLD}MB)"
        RESTART_NEEDED=1
    fi
fi

# perfom restart+notifications if needed
if [ "$RESTART_NEEDED" -eq 1 ]; then
    mysql -u acore -pacore -h 127.0.0.1 acore_monitoring -e "
    INSERT INTO server_events (timestamp, event_type, details)
    VALUES (NOW(), 'RESTART_TRIGGERED', '${REASON}');" 2>/dev/null

    bash ~/notify.sh "warnings" "🚨 **Restart triggered**: ${REASON} ($(date '+%Y-%m-%d %H:%M:%S'))"

    bash ~/server-stop.sh
    sleep 5
    bash ~/server-start.sh

    mysql -u acore -pacore -h 127.0.0.1 acore_monitoring -e "
    INSERT INTO server_events (timestamp, event_type, details)
    VALUES (NOW(), 'WATCHDOG_RESTART', '${REASON}');" 2>/dev/null

    bash ~/notify.sh "warnings" "🔧 **Recovery restart complete**."
fi
