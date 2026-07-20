  GNU nano 8.4                                                                                                   scheduled-restart.sh
#!/bin/bash
#
# Full staggered-warning restart sequence:
#   15m -> 10m -> 5m -> 3m -> 1m -> 30s -> 10s countdown -> saveall -> restart
# Each warning is sent both in-game and to Discord.
#
# Intended to be launched inside its own tmux session so it can be cancelled mid-countdown without affecting the running server:
#   tmux new -d -s restartcountdown "bash ~/scheduled-restart.sh"
#
# To cancel: tmux kill-session -t restartcountdown
# (see restartcancel() in bashrc-functions.sh for a wrapper that also sends a cancellation notice in-game)
#
# Depends on:
#   - notify.sh (in the same directory  or ~/notify.sh)
#   - server-start.sh (in the same directory or ~/server-start.sh)
#   - server-stop.sh (in the same directory or ~/server-stop.sh)
#   - a running tmux session named "world-session" for the game server console - watchdog should ensure that one such process is running

SESSION="world-session"

# sends string in-game and to discord (if configured)
announce() {
    tmux send-keys -t "$SESSION" ".announce $1" Enter
    bash ~/notify.sh "status" "⏰ $1"
}

# log start of process
mysql -u acore -pacore -h 127.0.0.1 acore_monitoring -e "
INSERT INTO server_events (timestamp, event_type, details)
VALUES (NOW(), 'RESTART_SEQUENCE_START', 'Scheduled restart countdown initiated');" 2>/dev/null

# staggered announcements
announce "Scheduled server restart in 15 minutes."
sleep 300

announce "Scheduled server restart in 10 minutes."
sleep 300

announce "Scheduled server restart in 5 minutes."
sleep 120

announce "Scheduled server restart in 3 minutes."
sleep 120

announce "Scheduled server restart in 1 minute."
sleep 30

announce "Scheduled server restart in 30 seconds."
sleep 20

for i in 10 9 8 7 6 5 4 3 2 1; do
    announce "Restarting in $i..."
    sleep 1
done

announce "Restarting now"

bash ~/server-stop.sh
sleep 3
bash ~/server-start.sh
