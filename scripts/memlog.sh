#!/bin/bash
#
# Logs detailed system + process-level memory metrics to MySQL every minute.
#
# Posts an hourly summary to Discord. Does NOT take any restart action — that responsibility now lives entirely in watchdog.sh.
#
# Depends on:
#   - notify.sh (in the same directory  or ~/notify.sh)
# acore_monitoring database with the following memory_log table:
#
# id INT AUTO_INCREMENT PRIMARY KEY,
# timestamp DATETIME NOT NULL,
# total_mb INT,
# used_mb INT,
# free_mb INT,
# available_mb INT,
# swap_used_mb INT,
# worldserver_rss_mb INT,
# worldserver_threads INT,
# worldserver_fds INT,
# worldserver_uptime_sec INT,
# authserver_rss_mb INT,
# characters_online INT

# look up process data and save in variables
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

read TOTAL USED FREE AVAILABLE < <(free -m | awk '/^Mem:/ {print $2, $3, $4, $7}')
SWAP_USED=$(free -m | awk '/^Swap:/ {print $3}')

WORLD_PID=$(pgrep -x worldserver | head -1)
AUTH_PID=$(pgrep -x authserver | head -1)

WORLD_RSS=$([ -n "$WORLD_PID" ] && ps -o rss= -p "$WORLD_PID" | tr -d ' ' || echo 0)
WORLD_RSS_MB=$((WORLD_RSS / 1024))
WORLD_THREADS=$([ -n "$WORLD_PID" ] && ps -o nlwp= -p "$WORLD_PID" | tr -d ' ' || echo 0)
WORLD_FDS=$([ -n "$WORLD_PID" ] && ls /proc/"$WORLD_PID"/fd 2>/dev/null | wc -l || echo 0)
WORLD_UPTIME=$([ -n "$WORLD_PID" ] && ps -o etimes= -p "$WORLD_PID" | tr -d ' ' || echo 0)

AUTH_RSS=$([ -n "$AUTH_PID" ] && ps -o rss= -p "$AUTH_PID" | tr -d ' ' || echo 0)
AUTH_RSS_MB=$((AUTH_RSS / 1024))

CHARS_ONLINE=$(mysql -u acore -pacore -h 127.0.0.1 acore_characters -N -e "SELECT COUNT(*) FROM characters WHERE online = 1;" 2>/dev/null)
CHARS_ONLINE=${CHARS_ONLINE:-0}

# load variables into database
mysql -u acore -pacore -h 127.0.0.1 acore_monitoring -e "
        INSERT INTO memory_log
        (timestamp, total_mb, used_mb, free_mb, available_mb, swap_used_mb,
         worldserver_rss_mb, worldserver_threads, worldserver_fds, worldserver_uptime_sec,
         authserver_rss_mb, characters_online)
        VALUES
        ('$TIMESTAMP', $TOTAL, $USED, $FREE, $AVAILABLE, $SWAP_USED,
         $WORLD_RSS_MB, $WORLD_THREADS, $WORLD_FDS, $WORLD_UPTIME,
         $AUTH_RSS_MB, $CHARS_ONLINE);" 2>/dev/null
