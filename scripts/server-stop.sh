#!/bin/bash
#
# Saves progression, stops authserver/worldserver, logs the event, and notifies Discord.
#
# Depends on:
#   - notify.sh (in the same directory or ~/notify.sh)

SESSION="world-session"

# save character progression, wait, kill server
tmux send-keys -t $SESSION ".server shutdown 5" Enter
sleep 6
tmux kill-session -t auth-session 2>/dev/null
tmux kill-session -t world-session 2>/dev/null

# log succesfull stop
mysql -u acore -pacore -h 127.0.0.1 acore_monitoring -e "
    INSERT INTO server_events (timestamp, event_type, details)
    VALUES (NOW(), 'STOP', 'Server shut down gracefully');" 2>/dev/null

# log expected state for watchdog
echo "stopped" > ~/.server-expected-state

# send discord notif
bash ~/notify.sh "status" "🔴 **Server stopped** at $(date '+%Y-%m-%d %H:%M:%S')"
