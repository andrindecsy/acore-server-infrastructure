# Discord Integration

This builds on [SETUP.md](SETUP.md) — everything here assumes you've already got the automation scripts in place, since the whole point of this doc is getting *those* scripts to actually tell you something instead of silently doing their job somewhere you're not looking.

## Why I Wanted This

I was checking `serverstatus` a lot. Like, a lot. Every time I remembered the server existed, I'd SSH in just to see if it was still up. That's a fine habit for an afternoon of active testing, but it doesn't scale to "I have a server running unattended and want to know if something's wrong without going looking for it." Discord webhooks fixed that pretty cheaply — I already have Discord open basically all the time anyway.

## What a Webhook Actually Is

If you haven't used one before, it's simpler than it sounds: Discord gives you a URL, and any `POST` request to that URL with the right JSON body shows up as a message in whatever channel you created it for. No bot account, no OAuth, no permissions dance — just a URL and `curl`.

```bash
curl -H "Content-Type: application/json" \
     -X POST \
     -d '{"content": "hello from a script"}' \
     "https://discord.com/api/webhooks/..."
```

That's genuinely the whole mechanism. Everything below is just "which script sends what, and when."

## Three Channels, On Purpose

I split notifications across three channels rather than dumping everything into one, because I noticed pretty quickly that "server started" and "available memory just dropped below 1GB" are not things I want mixed together in the same feed — one's routine, the other's something I actually want to *notice*.

- **`#server-status`** — start, stop, restart events, and the full staggered restart countdown mirrored from in-game
- **`#memory-log`** — a boring hourly "still fine" summary, mostly so I can eyeball a trend without opening the CSV
- **`#warnings`** — the channel I actually have notifications on for. Low memory, crash detection, auto-recovery attempts.

Setting them up is just: create three text channels, then per channel, *Channel Settings → Integrations → Webhooks → New Webhook → Copy Webhook URL*. Three URLs, three channels, done.

## The Shared Helper

Every script that sends a Discord message sources the same small config file (`~/discord-webhooks.conf`, template at [`config/discord-webhooks.conf.example`](../config/discord-webhooks.conf.example)), which — beyond just holding the three URLs — also defines one function everything else reuses:

```bash
send_discord() {
    local webhook="$1"
    local message="$2"
    curl -s -H "Content-Type: application/json" -X POST -d "{\"content\": \"${message}\"}" "$webhook" > /dev/null
}
```

So the actual call site anywhere else in the codebase is just:
```bash
send_discord "$WEBHOOK_WARNINGS" "🚨 something's wrong"
```

Nothing clever, but having it in one place meant I only had to get the `curl` syntax right once, instead of re-deriving it in five different scripts and inevitably getting one of them slightly wrong.

## Who Sends What

**`server-start.sh` / `server-stop.sh`** — a single line each, to `#server-status`:
```
🟢 Server started at 2026-07-12 13:28:07
🔴 Server stopped at 2026-07-12 13:27:59
```

**`scheduled-restart.sh`** — every staggered warning gets mirrored to Discord at the same moment it's announced in-game, so `#server-status` ends up with the same 15m → 10m → 5m → ... → countdown sequence players see in their chat window. Nice side effect: if I'm not actually in-game when a restart is coming up, I still see it coming.

**`watchdog.sh`** — this is the one that actually taught me something about myself, namely that I check Discord notifications way more reliably than I check a terminal. Fires two messages to `#warnings` when it catches a crash: one the moment it detects the problem, one confirming the automatic recovery restart went through.

**`memlog.sh`** — two different behaviors depending on the channel:
- `#memory-log` gets a plain summary once an hour, regardless of anything — just a number, so I can watch the trend over days without needing to SSH in and read the CSV myself
- `#warnings` gets a one-time alert the moment available memory drops below a threshold I set, and — this part mattered to me — it doesn't fire again on every single check while memory stays low. It resets itself once things recover, then can fire again if it happens a second time. Otherwise a genuinely low-memory period would just spam the channel into uselessness.

## One Thing I'd Do Differently

If I were starting over, I'd probably add a fourth, very quiet channel just for the tunnel start/stop events from `golocal`/`goonline` (see [TUNNELING.md](TUNNELING.md)) — right now those are silent, and the one time I forgot I'd left the tunnels running for a few days, a small "hey, this is still costing you money" nudge would've been nice. Might still add it.
