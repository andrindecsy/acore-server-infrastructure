#!/bin/bash
# ============================================================
# Custom Bash Aliases & Functions
# AzerothCore Server Infrastructure Project
#
# Usage: append this file's contents to your ~/.bashrc, then:
#   source ~/.bashrc
#
# Requires:
#   - discord-webhooks.conf (see discord-webhooks.conf.example)
#   - Localtonet account + API key (see below) OR adapt goonline/
#     golocal to your own tunnel provider
#   - AzerothCore installed under ~/azerothcore-wotlk
# ============================================================

# ---- Localtonet API credentials (fill in your own) ----
LOCALTONET_APIKEY="YOUR_LOCALTONET_API_KEY_HERE"
LOCALTONET_AUTH_ID="YOUR_AUTH_TUNNEL_ID_HERE"
LOCALTONET_WORLD_ID="YOUR_WORLD_TUNNEL_ID_HERE"

# ============================================================
# AzerothCore convenience aliases
# ============================================================
alias wow='cd ~/azerothcore-wotlk;tmux attach -t world-session'
alias auth='cd ~/azerothcore-wotlk;tmux attach -t auth-session'
alias compile='cd ~/azerothcore-wotlk;./acore.sh compiler all'
alias build='cd ~/azerothcore-wotlk;./acore.sh compiler build'
alias update='cd ~/azerothcore-wotlk;git pull;cd ~/azerothcore-wotlk/modules/mod-playerbots;git pull'
alias updatemods="cd ~/azerothcore-wotlk/modules;find . -mindepth 1 -maxdepth 1 -type d -print -exec git -C {} pull \;"
alias pb='nano ~/azerothcore-wotlk/env/dist/etc/modules/playerbots.conf'
alias world='nano ~/azerothcore-wotlk/env/dist/etc/worldserver.conf'
alias ah='nano ~/azerothcore-wotlk/env/dist/etc/modules/mod_ahbot.conf'

# ---- Server lifecycle (overrides default AzerothCore guide aliases) ----
# NOTE: the "stock" start/stop aliases from most AzerothCore setup guides
# use `tmux kill-server`, which kills ALL tmux sessions indiscriminately
# (including unrelated tunnels). These versions call dedicated scripts
# instead, which also handle logging, Discord notifications, and
# expected-state tracking for the watchdog.
alias start='bash ~/server-start.sh'
alias stop='bash ~/server-stop.sh'
alias restart='tmux new -d -s restartcountdown "bash ~/scheduled-restart.sh"'

# ============================================================
# Tunnel control (Localtonet-specific — adapt to your provider)
# ============================================================

golocal() {
    echo "Switching to LOCAL mode (no tunnels, free)..."
    curl -s -X POST "https://localtonet.com/api/v2/tunnels/${LOCALTONET_AUTH_ID}/actions/stop" -H "Authorization: Bearer ${LOCALTONET_APIKEY}" > /dev/null
    curl -s -X POST "https://localtonet.com/api/v2/tunnels/${LOCALTONET_WORLD_ID}/actions/stop" -H "Authorization: Bearer ${LOCALTONET_APIKEY}" > /dev/null
    mysql -u acore -pacore -h 127.0.0.1 acore_auth -e "UPDATE realmlist SET address = 'YOUR_LAN_IP', localAddress = 'YOUR_LAN_IP', localSubnetMask = '255.255.255.255', port = 8085 WHERE id = 1;" 2>/dev/null
    echo "Done. Both tunnels stopped (billing paused), realmlist set to LAN IP."
    echo "On your PC's realmlist.wtf, use: set realmlist YOUR_LAN_IP"
}

goonline() {
    echo "Switching to ONLINE mode (tunnels active)..."
    curl -s -X POST "https://localtonet.com/api/v2/tunnels/${LOCALTONET_AUTH_ID}/actions/start" -H "Authorization: Bearer ${LOCALTONET_APIKEY}" > /dev/null
    curl -s -X POST "https://localtonet.com/api/v2/tunnels/${LOCALTONET_WORLD_ID}/actions/start" -H "Authorization: Bearer ${LOCALTONET_APIKEY}" > /dev/null
    sleep 3
    mysql -u acore -pacore -h 127.0.0.1 acore_auth -e "UPDATE realmlist SET address = 'YOUR_WORLD_TUNNEL_HOSTNAME', localAddress = 'YOUR_WORLD_TUNNEL_HOSTNAME', localSubnetMask = '255.255.255.255', port = YOUR_WORLD_TUNNEL_PORT WHERE id = 1;" 2>/dev/null
    echo "Done. Both tunnels started, realmlist set to Localtonet address."
    echo "For players, use: set realmlist YOUR_AUTH_TUNNEL_HOSTNAME:YOUR_AUTH_TUNNEL_PORT"
}

# ============================================================
# Server status & monitoring
# (merged: process status, scheduled restarts, tunnel status,
#  and current realmlist connection string in one command)
# ============================================================

serverstatus() {
    echo "=== Server Status ==="
    echo ""
    WORLD_PID=$(pgrep -x worldserver | head -1)
    if [ -z "$WORLD_PID" ]; then
        echo "Server: OFFLINE"
    else
        echo "Server: ONLINE"
        ELAPSED=$(ps -o etime= -p "$WORLD_PID" | tr -d ' ')
        echo "Uptime: $ELAPSED"
        echo ""
        echo "-- Scheduled Restarts --"
        CRON_LINE=$(crontab -l 2>/dev/null | grep "scheduled-restart.sh" | grep -v "^#")
        if [ -z "$CRON_LINE" ]; then
            echo "No scheduled restart found in crontab."
        else
            MIN=$(echo "$CRON_LINE" | awk '{print $1}')
            HOUR_FIELD=$(echo "$CRON_LINE" | awk '{print $2}')
            if [[ "$HOUR_FIELD" == */* ]]; then
                STEP="${HOUR_FIELD#*/}"
                HOURS=$(seq 0 "$STEP" 23)
            else
                HOURS=$(echo "$HOUR_FIELD" | tr ',' ' ')
            fi
            # Human-readable schedule list
            READABLE=""
            for H in $HOURS; do
                READABLE="${READABLE}$(printf '%02d:%02d' "$H" "$MIN") "
            done
            echo "Daily at: $READABLE"
            NOW_EPOCH=$(date +%s)
            TODAY=$(date +%Y-%m-%d)
            TOMORROW=$(date -d "+1 day" +%Y-%m-%d)
            NEXT_EPOCH=0
            for H in $HOURS; do
                for D in "$TODAY" "$TOMORROW"; do
                    CANDIDATE=$(date -d "$D $H:$MIN" +%s 2>/dev/null)
                    if [ -n "$CANDIDATE" ] && [ "$CANDIDATE" -gt "$NOW_EPOCH" ]; then
                        if [ "$NEXT_EPOCH" -eq 0 ] || [ "$CANDIDATE" -lt "$NEXT_EPOCH" ]; then
                            NEXT_EPOCH=$CANDIDATE
                        fi
                    fi
                done
            done
            if [ "$NEXT_EPOCH" -gt 0 ]; then
                NEXT_HUMAN=$(date -d "@$NEXT_EPOCH" '+%Y-%m-%d %H:%M')
                DIFF=$((NEXT_EPOCH - NOW_EPOCH))
                HOURS_LEFT=$((DIFF / 3600))
                MIN_LEFT=$(((DIFF % 3600) / 60))
                echo "Next restart: $NEXT_HUMAN (in ${HOURS_LEFT}h ${MIN_LEFT}m)"
            fi
        fi
    fi
    echo ""
    echo "=== Tunnel & Realmlist Status ==="
    echo ""
    echo "-- Auth Tunnel --"
    AUTH_STATUS=$(curl -s "https://localtonet.com/api/v2/tunnels/${LOCALTONET_AUTH_ID}" -H "Authorization: Bearer ${LOCALTONET_APIKEY}" | grep -o '"connectionStatus":[a-z]*' | cut -d: -f2)
    if [ "$AUTH_STATUS" = "true" ]; then echo "ONLINE"; else echo "OFFLINE"; fi
    echo "-- World Tunnel --"
    WORLD_STATUS=$(curl -s "https://localtonet.com/api/v2/tunnels/${LOCALTONET_WORLD_ID}" -H "Authorization: Bearer ${LOCALTONET_APIKEY}" | grep -o '"connectionStatus":[a-z]*' | cut -d: -f2)
    if [ "$WORLD_STATUS" = "true" ]; then echo "ONLINE"; else echo "OFFLINE"; fi
    echo ""
    echo "-- Current Realmlist (DB) --"
    mysql -u acore -pacore -h 127.0.0.1 acore_auth -e "SELECT address, port FROM realmlist WHERE id = 1;" 2>/dev/null
    REALM_ADDRESS=$(mysql -u acore -pacore -h 127.0.0.1 acore_auth -N -e "SELECT address FROM realmlist WHERE id = 1;" 2>/dev/null)
    echo ""
    echo "-- realmlist.wtf content to use --"
    echo ""
    if [ "$REALM_ADDRESS" = "YOUR_LAN_IP" ]; then
        echo "set realmlist YOUR_LAN_IP"
    else
        echo "set realmlist YOUR_AUTH_TUNNEL_HOSTNAME:YOUR_AUTH_TUNNEL_PORT"
    fi
    echo ""
}

whosonline() {
    echo "=== Real Players Online ==="
    mysql -u acore -pacore -h 127.0.0.1 acore_characters -e "
    SELECT c.name, c.level, c.online
    FROM characters c
    JOIN acore_auth.account a ON c.account = a.id
    WHERE c.online = 1 AND a.username NOT REGEXP '^RNDBOT';" 2>/dev/null
}

printallchars() {
    echo "=== All Real Player Characters ==="
    mysql -u acore -pacore -h 127.0.0.1 acore_characters -e "
    SELECT
        c.name,
        c.level,
        CASE c.class
            WHEN 1 THEN 'Warrior' WHEN 2 THEN 'Paladin' WHEN 3 THEN 'Hunter'
            WHEN 4 THEN 'Rogue' WHEN 5 THEN 'Priest' WHEN 6 THEN 'Death Knight'
            WHEN 7 THEN 'Shaman' WHEN 8 THEN 'Mage' WHEN 9 THEN 'Warlock'
            WHEN 11 THEN 'Druid' ELSE 'Unknown'
        END AS class,
        CASE c.race
            WHEN 1 THEN 'Human' WHEN 2 THEN 'Orc' WHEN 3 THEN 'Dwarf'
            WHEN 4 THEN 'Night Elf' WHEN 5 THEN 'Undead' WHEN 6 THEN 'Tauren'
            WHEN 7 THEN 'Gnome' WHEN 8 THEN 'Troll' WHEN 9 THEN 'Blood Elf'
            WHEN 10 THEN 'Draenei' ELSE 'Unknown'
        END AS race,
        c.zone AS zone_id,
        c.online
    FROM characters c
    JOIN acore_auth.account a ON c.account = a.id
    WHERE a.username NOT REGEXP '^RNDBOT'
    ORDER BY c.level DESC;" 2>/dev/null
}

# ============================================================
# Memory logging controls
# ============================================================

memlogstart() {
    if tmux has-session -t memlog 2>/dev/null; then
        echo "memlog is already running."
    else
        tmux new -d -s memlog "~/memlog.sh"
        echo "memlog started in background (tmux session: memlog)."
    fi
}

memlogstop() {
    if tmux has-session -t memlog 2>/dev/null; then
        tmux kill-session -t memlog
        echo "memlog stopped."
    else
        echo "memlog was not running."
    fi
}

memlogread() {
    if [ -f ~/memory-log.csv ]; then
        column -s, -t ~/memory-log.csv | less
    else
        echo "No log file found yet. Run memlogstart first."
    fi
}

# ============================================================
# Restart controls
# ============================================================

restartnow() {
    echo "Performing instant restart (no warnings)..."
    tmux send-keys -t world-session ".saveall" Enter
    sleep 2
    bash ~/server-stop.sh
    sleep 5
    bash ~/server-start.sh
    echo "Instant restart complete."
}

restartcancel() {
    if tmux has-session -t restartcountdown 2>/dev/null; then
        tmux kill-session -t restartcountdown
        tmux send-keys -t world-session '.announce Scheduled restart has been CANCELLED.' Enter
        echo "Restart countdown cancelled."
    else
        echo "No restart countdown is currently running."
    fi
}
