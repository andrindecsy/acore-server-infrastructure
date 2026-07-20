#!/bin/bash
#
# Unified external notification handler. All other scripts call this instead of sourcing discord-webhooks.conf / calling send_discord themselves - this is now the only place that touches the webhook URLs.
#
# Usage:
#   bash ~/notify.sh <channel> "<message>"
#
# Channels: status | memory | warnings
#
# If ~/discord-webhooks.conf doesn't exist, this exits quietly (code 0)
# so callers never need special-case handling for "Discord isn't set up."

if [ ! -f ~/discord-webhooks.conf ]; then
    exit 0
fi

source ~/discord-webhooks.conf

CHANNEL="$1"
MESSAGE="$2"

if [ -z "$CHANNEL" ] || [ -z "$MESSAGE" ]; then
    echo "Usage: notify.sh <status|memory|warnings> <message>" >&2
    exit 1
fi

case "$CHANNEL" in
    status)   WEBHOOK="$WEBHOOK_STATUS" ;;
    memory)   WEBHOOK="$WEBHOOK_MEMORY" ;;
    warnings) WEBHOOK="$WEBHOOK_WARNINGS" ;;
    *)
        echo "Unknown channel: $CHANNEL (expected status|memory|warnings)" >&2
        exit 1
        ;;
esac

if [ -z "$WEBHOOK" ]; then
    exit 0
fi

curl -s -H "Content-Type: application/json" \
     -X POST \
     -d "{\"content\": \"${MESSAGE}\"}" \
     "$WEBHOOK" > /dev/null
