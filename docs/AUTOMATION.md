# AUTOMATION SET UP
---
**This document is a WIP, certain parts might be incomplete or totally missing**
---


In here we cover the automation layer on top of a functioning AzerothCore server. If you need to get up to speed, follow the [video guide](https://www.youtube.com/watch?v=DwJ6OfPophw) first for software setup first and then the [tunneling](TUNNELING.md) section for network setup.

Another prerequiste would be installing `tmux`, `mysql-client` and `curl` since the scripts use them, but if you followed all the spets thus far you should already have them.

## Working pieces

The whole infrastructure can be broken down into three independent main parts:

- A restart schedule does a server reboot on a customizable timer. This is mainly due to a likely **memory leak** on the server, more on this in the detailed section. Our start and stop scripts are quite important for this process so they will also be explained there, since we override the default ones with additional functionality
- 'watchdog' checks periodically if everything is running correctly and, in case something isn't, kicks off a server restart
- Memory logs are taken on a timer documenting memory overhead. The logs are quite simple at the moment but will be expanded later on to help diagnose the possible memory leak, again, more on this later

There is also a collection of handy console shortcuts for frequently used commands.

## Cron

To understand any of the automation we first have to understand `cron`. It is a time-based job scheduling utility in Linux and Unix-like operating systems that allows users to automate repetitive and recurring tasks. It runs continuously in the background as a daemon process (typically named crond), waking up every minute to check if any scheduled tasks need to be executed. Scheduled tasks managed by this system are called cron jobs, and they are written inside text configuration files known as crontabs (short for "cron tables")

Scheduled tasks managed by this system are called cron jobs, and they are written inside text configuration files known as crontabs (short for "cron tables"). To open your crontab use the `crontab -e` command. At the top you will find an already quite good introduction to how it works. After the (blue) commented out section you can insert cronjobs, each one in a new line, by first specifying the [schedule](https://www.ibm.com/docs/en/db2/11.5.x?topic=task-unix-cron-format) and then the path to the executable command. We will be needing two cron jobs for this whole project, which we will type out in the installation part.

## Automation Scripts

All scripts live in [`scripts/`](../scripts). A note about Discord integration: you can see `discord-webhooks.conf`mentioned in all the scripts, those are the parts that communicate with your text channels.  We will be handling the webhook setup for remote status messages in TUNNELING.md. That process is totally optional and should you choose to not set it up the cripts will ignore the message sending.

### Installation

```
cp scripts/*.sh ~/
chmod +x ~/server-start.sh ~/server-stop.sh ~/scheduled-restart.sh ~/watchdog.sh ~/memlog.sh

cat bashrc-functions.sh >> ~/.bashrc
source ~/.bashrc
```


**Important:** absolute paths, not relative
Every script sources its config via an **absolute home-directory path**:
```bash
source ~/discord-webhooks.conf
```
not a path relative to where the script itself lives. This matters if you're used to keeping scripts and their configs in the same folder — here, `discord-webhooks.conf` must exist directly under your home directory (`~`) regardless of where the scripts themselves are placed or run from.

### Scheduled restarts

This will be a longer one. When setting up the server it took me some time to arrive at the right amount of memory I should dedicate to the machine. My first boot lead straight to a OOM (Out of Memory) complete crash. On later tries I assigned too much memory. I would monitor this myself with a 'top' command until I arrived at an amount that gave me a comfortable 15% overhead. Further monitoring would show fluctuations, but not big enough to be worrying, so I celebrated my victory.

After some 48 hours of hands-off uptime I was delighted to see the server still up, but schocked to see only one fourth of the original overhead still available. I rushed to do a restart and saw the overhead go right buck up to its original value.

Right after that I made the memory logging scripts to try and quiantify the memory drop. The results showed a constant ~30MB/hour decline over a 12 hour test period without any signs of plateauing. This looks like a **memory leak**. There might be a process in the background that grows uncontrollably and if left unchecked eats up all available memory. Whether this is a AzerothCore issue or is caused by my infrastructure/installed modules ist still unclear. In fact I am still looking for the exact origin of this problem. My next step will be upgrading the Memory Log scripts to include more information about the running system to get a good information source for analytics.

Since a restart cleared up the memory I decided to periodically do one on a schedule as a workaround solution until I can correctly diagnose the problem.

**Script:** We reference ~/restart-log.txt as LOGFILE and world-session as SESSION. world-session is the [tmux session](https://github.com/tmux/tmux/wiki/Getting-Started) in which the world-server lives. Then we create an announce function that takes a string and sends it into the world-session as a server announcement in-game and to the Discord text channel. This function will repeatedly be called to create a staggered countdown starting at 15 minutes before shutdown and ending in a 10 second countdown. Then the following happens:

- a final announcement is sent
- a .saveall command is sent to the world-server to correctly save all player progress
- the server restart is logged into LOGFILE
- a server stop is run, followed by an offset server start (more on these later)
- the succesful server restar is logged into LOGFILE

It runs inside its own dedicated tmux session specifically so it can be cancelled mid-countdown (`restartcancel` in `bashrc-functions.sh`) without touching the actual running server — the real shutdown only happens at the very end of the sequence, so cancelling anytime before that point is completely safe.

Also, notice how we call server-start.sh and server-stop.sh. Let's look at those:

```bash
#!/bin/bash
# Starts authserver/worldserver, restarts the memory logger if needed,
# logs the event, and notifies Discord.
#
# Depends on:
#   - ~/discord-webhooks.conf (see config/discord-webhooks.conf.example) — optional
#   - memlog.sh (in the same directory as this script, or ~/memlog.sh)

cd ~/azerothcore-wotlk/env/dist/bin

if [ -f ~/discord-webhooks.conf ]; then
	source ~/discord-webhooks.conf
else
	send_discord() { :; }  # no-op if Discord isn't configured
fi

LOGFILE=~/memory-log.csv
authserver="./authserver"
worldserver="./worldserver"
authserver_session="auth-session"
worldserver_session="world-session"

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

echo "running" > ~/.server-expected-state

# Start the memory logger if it isn't already running
if ! tmux has-session -t memlog 2>/dev/null; then
    tmux new -d -s memlog "~/memlog.sh"
fi

echo "$(date '+%Y-%m-%d %H:%M:%S'),SERVER STARTED,,,,," >> "$LOGFILE"
send_discord "$WEBHOOK_STATUS" "🟢 **Server started** at $(date '+%Y-%m-%d %H:%M:%S')"
```

```bash
cd ~/azerothcore-wotlk/env/dist/bin

if [ -f ~/discord-webhooks.conf ]; then 
	source ~/discord-webhooks.conf 
else 
	send_discord() { :; }  # no-op if Discord isn't configured 
fi
LOGFILE=~/memory-log.csv

echo "$(date '+%Y-%m-%d %H:%M:%S'),SERVER STOPPED,,,,," >> "$LOGFILE"
send_discord "$WEBHOOK_STATUS" "🔴 **Server stopped** at $(date '+%Y-%m-%d %H:%M:%S')"
echo "stopped" > ~/.server-expected-state

tmux kill-server
```

This runs twice a day, at 5am and 5 pm, by adding the following line to the 'crontab':

```bash
0 5,17 * * * tmux new -d -s restartcountdown "bash /root/scheduled-restart.sh"
```

Feel free to change the scheduling to your liking.
### Memory Monitoring

**Explanation:**

**Script:**

### Watchdog & expected-state tracking

When dealing with a persistent service that has to run without being directly supervised there has to be a system in place that handles unexpected crashes and, as we do in this case, clean everything out and start up again. This is typically handled by something called a 'watchdog', which is a very fitting name. This process runs constantly in the background and watches over all other working parts, compares to what they should be doing, and, in case of a difference, tries to rectify them.

**Script:** We reference files /.server-expected-state as STATEFILE and ~/watchdog-log.txt  as LOGFILE. STATEFILE is the backbone of the whole script. Here the expected state of the server gets tracked by server-start.sh and server-stop and is compared to the actual state when the watchdog runs. Should the server be expected to be running but be offline, the following happens:

- the server crash is logged into LOGFILE
- a server crash notification is sent to Discord
- a server restart attempt is logged into LOGFILE
- a server stop is run to shut down possible remaining processes, followed by an offset server start
- a server restart attempt notification is sent to Discord

This runs every two minutes by adding the following line to the 'crontab':

```bash
*/2 * * * * /root/watchdog.sh
```

Feel free to change the scheduling to your liking.

## Bash functions and aliases

All interactive shortcuts live in [`bashrc-functions.sh`](../bashrc-functions.sh). 

| NAME/COMMAND  | DESCRIPTION                                                                                            |
| ------------- | ------------------------------------------------------------------------------------------------------ |
| start         | calls for server-start.sh to execute, which starts the servers                                         |
| stop          | calls for server-stop.sh to execute, which stops the servers                                           |
| restart       | starts a standard 15 minute restart countdown with announcements                                       |
| restartcancel | stops an ongoing restart countdown                                                                     |
| restartnow    | forces an immediate restart                                                                            |
| serverstatus  | prints useful server runtime data                                                                      |
| goonline      | starts tunnel connections and changes IP and ports in database acordingly to allow outside connections |
| golocal       | stops tunnel connections and changes IP and ports in database acordingly to play singleplayer          |
| whosonline    | prints out all online non-bot characters                                                               |
| printallchars | prints out all existing non-bot characters from the database                                           |
| memlogstart   | start memory logging                                                                                   |
| memlogstop    | stop memory logging                                                                                    |
| memlogread    | print out memory logging                                                                               |












