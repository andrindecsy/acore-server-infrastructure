#!/bin/bash
# Runs a full staggered-warning restart sequence:
#   15m -> 10m -> 5m -> 3m -> 1m -> 30s -> 10s countdown -> saveall -> restart
# Each warning is sent both in-game (.announce) and to Discord.
#
# Intended to be launched inside its own tmux session so it can be
# cancelled mid-countdown without affecting the running server:
#   tmux new -d -s restartcountdown "bash ~/scheduled-restart.sh"
#
# To cancel: tmux kill-session -t restartcountdown
# (see restartcancel() in bashrc-functions.sh for a wrapper that also
#  sends a cancellation notice in-game)
#
# Depends on:
#   - ~/discord-webhooks.conf (see config/discord-webhooks.conf.example)
#   - server-stop.sh / server-start.sh (in the same directory or ~)
#   - a running tmux session named "world-session" for the game server console

source ~/discord-webhooks.conf
LOGFILE=~/restart-log.txt
SESSION="world-session"

announce() {
    tmux send-keys -t "$SESSION" ".announce $1" Enter
    send_discord "$WEBHOOK_STATUS" "⏰ $1"
}

echo "$(date): Starting scheduled restart sequence" >> "$LOGFILE"

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

# Final 10-second countdown
for i in 10 9 8 7 6 5 4 3 2 1; do
    announce "Restarting in $i..."
    sleep 1
done

announce "Restarting now!"
tmux send-keys -t "$SESSION" ".saveall" Enter
sleep 3

echo "$(date): Countdown complete, shutting down" >> "$LOGFILE"

bash ~/server-stop.sh
sleep 5
bash ~/server-start.sh

echo "$(date): Restart complete" >> "$LOGFILE"
