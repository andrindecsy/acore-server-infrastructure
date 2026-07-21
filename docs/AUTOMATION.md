# Automation

This covers the automation layer on top of a functioning AzerothCore server. If you need to get up to speed first, follow the [video guide](https://www.youtube.com/watch?v=DwJ6OfPophw) for software setup, then [TUNNELING.md](https://claude.ai/chat/TUNNELING.md) for network setup.

A few prerequisites: `tmux`, `mysql-client`, and `curl`, since the scripts use them - if you've followed everything up to this point, you should already have all three.

## Working Pieces

The whole infrastructure breaks down into four main parts:

- A **restart schedule** reboots the server on a customizable timer. This exists mainly because of a likely **memory leak** - more on this below. Our `server-start.sh`/`server-stop.sh` scripts are central to this process too, since we've overridden the default ones with additional functionality.
- **Memory logging** runs on a timer, recording detailed memory and process metrics to help track down (and eventually diagnose) that leak.
- An **hourly report** reads the latest memory log entry and posts a summary to Discord, so the data is visible without needing to query the database yourself.
- **`watchdog`** checks periodically whether everything is running as expected — both "is the server actually up" and "is memory dangerously low" — and kicks off a recovery restart if either check fails.

Underneath all of this sits a MySQL database (`acore_monitoring`) that logs every event and every memory reading, and is what lets these otherwise-independent scripts stay in sync with each other.

There's also `notify.sh`, a single shared script every other script calls to actually send a Discord message — more on why that's separate below.

Finally, there's a collection of handy console shortcuts for frequently used commands.

## Cron

To understand any of the automation, we first have to understand `cron`. It's a time-based job scheduling utility in Linux and Unix-like operating systems that automates repetitive, recurring tasks. It runs continuously in the background as a daemon process (typically named `crond`), waking up every minute to check whether any scheduled tasks need to run. These scheduled tasks are called cron jobs, and they're written inside text configuration files known as crontabs ("cron tables").

To open your crontab, use `sudo crontab -e`. `sudo` is needed here because we want it to call scripts that live in a root-owned location. At the top of the `nano` window you'll find a solid built-in introduction to the syntax. After the commented-out section, you can insert cron jobs — one per line — by specifying the [schedule](https://www.ibm.com/docs/en/db2/11.5.x?topic=task-unix-cron-format) followed by the command to run.

This project uses **four** cron jobs in total. Each is introduced alongside the script it runs, below, and they're all collected together in one place at the end of this doc for easy copy-pasting.

## Automation Scripts

All seven scripts (`notify.sh`, `memlog.sh`, `hourly-report.sh`, `watchdog.sh`, `scheduled-restart.sh`, `server-start.sh`, `server-stop.sh`) need to live together in the same directory — they locate each other at runtime relative to their own location, so the exact folder doesn't matter, as long as they all stay in it together. Moving the whole folder later just means updating the (necessarily absolute) paths in your crontab — nothing inside the scripts themselves needs to change.

**Discord integration** works via `notify.sh` and it's the only part that  ever touches `discord-webhooks.conf` or talks to Discord's API directly. Every other script just calls `notify.sh <channel> "<message>"` and lets it handle the rest. This means swapping notification providers later, or debugging notification issues, only ever involves one file. It also means Discord is fully optional — `notify.sh` checks for the config file first and silently does nothing if it's missing, so the rest of the automation works identically whether or not you've bothered to set up webhooks.

### Installation

Place all the files from `scripts/` together in one directory of your choice (e.g. `~/scripts/`):

```bash
mkdir -p ~/scripts
cp scripts/*.sh ~/scripts/
chmod +x ~/scripts/*.sh
```

Then set up the interactive shortcuts:

```bash
cat bashrc-functions.sh >> ~/.bashrc
source ~/.bashrc
```

**One path distinction worth understanding:** scripts find _each other_ using a path computed at runtime (`SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`), so they don't care where you put them, only that they're together. Config and state are different — `discord-webhooks.conf` and `.server-expected-state` are always read from your **home directory** (`~`), regardless of where the scripts themselves live. That's a deliberate separation: it means updating the scripts (e.g. `git pull`) never risks touching your actual secrets or runtime state.

### Scheduled Restarts

This will be a longer one. When setting up the server, it took some time to arrive at the right amount of memory to dedicate to the machine. My first boot led straight to an OOM (Out of Memory) crash. On later tries I assigned too much memory. I monitored things myself with `top` until I arrived at an amount that gave a comfortable 15% overhead. Further monitoring showed fluctuations, but nothing worrying — so I celebrated the victory.

After about 48 hours of hands-off uptime, I was delighted to see the server still up, but shocked to see only a quarter of the original overhead still available. I rushed to do a restart and watched the overhead go right back up to its original value.

Right after that, I built the memory logging scripts to try and quantify the drop. The results showed a constant ~30MB/hour decline over a 12-hour test period with no signs of plateauing. This looks like a **memory leak**. Whether it's an AzerothCore issue or something caused by my specific stack of modules is still unclear, and I'm still actively narrowing it down — see the Memory Monitoring section below for where that investigation currently stands.

Since a restart reliably clears the memory back up, I decided to do one periodically on a schedule as a mitigation until the actual cause is found.

**Script:** `scheduled-restart.sh` uses `world-session` — the [tmux session](https://github.com/tmux/tmux/wiki/Getting-Started) the world server lives in — as its target. An `announce` function takes a string and sends it both into `world-session` as an in-game server announcement and to Discord via `notify.sh`. This function gets called repeatedly to produce a staggered countdown: 15 minutes, 10, 5, 3, 1, 30 seconds, then a second-by-second countdown to zero. After the final "Restarting now" announcement, the script hands off directly to `server-stop.sh` and `server-start.sh` — since `server-stop.sh`'s own `.server shutdown 5` command already saves every connected character as part of a normal graceful shutdown, no separate save step is needed here.

The whole sequence starts with a `RESTART_SEQUENCE_START` event logged to the database (see Memory Monitoring below for the table this lands in) — this is a change from an earlier version of this script, which logged to a plain `restart-log.txt` file instead. Everything now lands in the same MySQL table as the rest of the system, rather than being scattered across several text files.

It runs inside its own dedicated tmux session specifically so it can be cancelled mid-countdown (`restartcancel` in `bashrc-functions.sh`) without touching the actual running server — the real shutdown only happens at the very end of the sequence, so cancelling anytime before that point is completely safe.

**Cron job** (twice a day, 5am and 5pm):

```bash
0 5,17 * * * tmux new -d -s restartcountdown "bash /path/to/scripts/scheduled-restart.sh"
```

Adjust the schedule to your liking — this is just what worked for my own usage pattern.

### Memory Monitoring

As mentioned above, an automated logging system was needed to track the memory usage over time, rather than relying on catching a `top` reading.

**Script:** `memlog.sh` runs once a minute via cron and writes a single row to `acore_monitoring.memory_log`, covering both system-wide numbers (`free -m`'s total/used/free/available/swap) and, more usefully for actually diagnosing a leak, **per-process** metrics for `worldserver` specifically: resident memory (RSS), thread count, open file descriptor count, and process uptime. It also logs `authserver`'s RSS and the current count of online (non-bot) characters, so growth can later be correlated against population size.

This is a meaningful upgrade from an earlier version of this script, which only logged system-wide `free -h` output to a CSV file and ran as an always-on background loop rather than a cron job. The loop-based approach had a real downside: if the process ever died (a crash, an errant `tmux kill-server`), logging would silently stop until someone noticed — a cron-triggered script has no equivalent single point of failure, since it simply runs fresh again next minute regardless of what happened to the previous run.

**Cron job** (every minute):

```bash
* * * * * /path/to/scripts/memlog.sh
```

**Script:** `hourly-report.sh` complements this — once an hour, it reads the single most recent row from `memory_log` and posts a summary to Discord via `notify.sh`, so the trend is visible at a glance without needing to query the database directly.

**Cron job** (once an hour):

```bash
0 * * * * /path/to/scripts/hourly-report.sh
```

**Where the investigation stands:** with the upgraded process-level logging in place, I ran a clean comparison test — the server idle, zero bots, for roughly 12 hours (split across two runs due to the scheduled restart landing in between). Available memory held flat the whole time, well within normal fluctuation, no decline at all. That rules out core `worldserver` idle behavior as the source.

A follow-up test with 50 Playerbots active and AHBot disabled told a very different story: `worldserver`'s RSS climbed steadily and essentially without pause, at a rate of roughly 500–650MB/hour depending on the window measured — noticeably faster than the original ~30MB/hour figure, and with no plateau in sight over the test's duration. That's a strong signal the leak is tied to bot activity rather than the core server itself, though the gap between this rate and the original 30MB/hour figure means bot count/composition likely matters too, and isn't yet fully pinned down. This is still an open investigation — the next step is comparing test runs with matched bot counts to the original long-running tests, to figure out whether growth scales linearly with bot count or something less predictable.

### Watchdog & Expected-State Tracking

A persistent service that has to run without direct supervision needs something in place to handle unexpected crashes — detect them, clean up, and start fresh again. This is typically handled by a **watchdog**, a very fitting name for what it does. It runs on a timer, checks whether things are in the state they should be, and if not, tries to correct that.

**Script:** `watchdog.sh` reads `~/.server-expected-state` — a single-word file (`running` or `stopped`) written by `server-start.sh` and `server-stop.sh` respectively — and compares it against reality on two fronts:

1. **Process check** — are `worldserver` and `authserver` actually running? If the state file says `running` but either process is missing, that's a crash.
2. **Memory check** — if the process check passes, it queries the most recent `available_mb` value from `memory_log` (the table `memlog.sh` writes to) and compares it against a configured critical threshold (500MB by default). If memory has dropped below that, a restart is triggered pre-emptively, before things get bad enough to crash on their own.

Either condition triggers the same recovery sequence: a `RESTART_TRIGGERED` event is logged (with the specific reason — crash or low memory — recorded in its details), a Discord alert goes out, `server-stop.sh` runs, then `server-start.sh`, then a `WATCHDOG_RESTART` event is logged and a second Discord message confirms recovery is complete. Having both the trigger and completion logged as separate timestamped events means recovery time itself becomes measurable later, not just "a restart happened at some point."

This is a deliberate consolidation from an earlier version: memory-based restarts used to be split awkwardly between `memlog.sh` (which could only warn, never act) and this script. Now `watchdog.sh` is the only place that decides "does the server need restarting right now," for either reason — one script, one responsibility.

`.server-expected-state` deliberately stays a plain text file rather than living in the database along with everything else — this is the one piece of state whose reliability the watchdog itself depends on, and a flat file read essentially never fails, even in scenarios where MySQL itself might be the thing that's unhealthy.

**Cron job** (every two minutes):

```bash
*/2 * * * * /path/to/scripts/watchdog.sh
```

### All Cron Jobs, Together

For convenience, here's the full set in one place — substitute `/path/to/scripts/` with wherever you actually placed the files:

```bash
* * * * * /path/to/scripts/memlog.sh
0 * * * * /path/to/scripts/hourly-report.sh
*/2 * * * * /path/to/scripts/watchdog.sh
0 5,17 * * * tmux new -d -s restartcountdown "bash /path/to/scripts/scheduled-restart.sh"
```

## Bash Functions and Aliases

All interactive shortcuts live in [`bashrc-functions.sh`](https://claude.ai/bashrc-functions.sh).

|Name/Command|Description|
|---|---|
|`start`|Calls `server-start.sh`, which starts the servers|
|`stop`|Calls `server-stop.sh`, which stops the servers|
|`restart`|Starts the standard 15-minute staggered restart countdown, with announcements|
|`restartcancel`|Cancels an ongoing restart countdown|
|`restartnow`|Forces an immediate restart, skipping the countdown|
|`serverstatus`|Prints server runtime data — process status, uptime, scheduled restart timing, tunnel status|
|`goonline`|Starts tunnel connections and updates the database's IP/port so outside players can connect|
|`golocal`|Stops tunnel connections and updates the database's IP/port for local-only play|
|`whosonline`|Prints all currently online non-bot characters|
|`printallchars`|Prints all existing non-bot characters from the database|
|`memlogread`|Prints memory growth statistics and a combined timeline of memory readings and server events|

`notify.sh` and `hourly-report.sh` don't have interactive aliases — the former is called internally by the other scripts, and the latter is meant to run on its own via cron rather than being triggered by hand.
