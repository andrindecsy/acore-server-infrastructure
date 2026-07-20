#!/bin/bash
#
# Starts authserver/worldserver, restarts the memory logger if needed, logs the event, and notifies Discord.
#
# Depends on:
#   - notify.sh (in the same directory or ~/notify.sh)
#   - memlog.sh (in the same directory or ~/memlog.sh)

cd ~/azerothcore-wotlk/env/dist/bin

authserver="./authserver"
worldserver="./worldserver"
authserver_session="auth-session"
worldserver_session="world-session"

# standard auth- und world-server start in own tmux sessions
if tmux new-session -d -s $authserver_session; then
    echo "Created authserver session: $authserver_session"
else
    echo "Error when trying to create authserver session: $authserver_session"
fi

if tmux new-session -d -s $worldserver_session; then
    echo "Created worldserver session: $worldserver_session"
else
    echo "Error when trying to create worldserver session: $worldserver_session"
fi

if tmux send-keys -t $authserver_session "$authserver" C-m; then
    echo "Executed \"$authserver\" inside $authserver_session"
    echo "You can attach to $authserver_session and check the result using \"tmux attach -t $authserver_session\""
else
    echo "Error when executing \"$authserver\" inside $authserver_session"
fi

if tmux send-keys -t $worldserver_session "$worldserver" C-m; then
    echo "Executed \"$worldserver\" inside $worldserver_session"
    echo "You can attach to $worldserver_session and check the result using \"tmux attach -t $worldserver_session\""
else
    echo "Error when executing \"$worldserver\" inside $worldserver_session"
fi

# start the memory logger if it isn't already running
if ! tmux has-session -t memlog 2>/dev/null; then
    tmux new -d -s memlog "~/memlog.sh"
fi

# log succesfull start
mysql -u acore -pacore -h 127.0.0.1 acore_monitoring -e "
    INSERT INTO server_events (timestamp, event_type, details)
    VALUES (NOW(), 'START', 'Server started successfully');" 2>/dev/null

# log expected state for watchdog
echo "running" > ~/.server-expected-state

# send discord notif
bash ~/notify.sh "status" "🟢 **Server started** at $(date '+%Y-%m-%d %H:%M:%S')"
