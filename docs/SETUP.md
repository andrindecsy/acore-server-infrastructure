# Setup Guide

In here we cover the automation layer on top of a functioning AzerothCore server. If you need to get up to speed, follow the [video guide](https://www.youtube.com/watch?v=DwJ6OfPophw) first for software setup first and then the [tunneling](TUNNELING.md) section for network setup.

Another prerequiste would be installing `tmux`, `mysql-client` and `curl` since the scripts use them, but if you followed all the spets thus far you should already have them.

## Parts

The whole infrastructure can be broken down into three independent main parts:

- 'watchdog' checks periodically if everything is running correctly and, in case something isn't, kicks off a server restart
- A restart schedule does a server reboot on a customizable timer. This is mainly due to a likely **memory leak** on the server, more on this in the detailed section
- Memory logs are taken on a timer documenting memory overhead. The logs are quite simple at the moment but will be expanded later on to help diagnose the possible memory leak, again, more on this later

There is also a collection of handy console shortcuts for frequently used commands.

## Cron

To understand any of the automation we first have to understand `cron`. It is a time-based job scheduling utility in Linux and Unix-like operating systems that allows users to automate repetitive and recurring tasks. It runs continuously in the background as a daemon process (typically named crond), waking up every minute to check if any scheduled tasks need to be executed. Scheduled tasks managed by this system are called cron jobs, and they are written inside text configuration files known as crontabs (short for "cron tables")

Scheduled tasks managed by this system are called cron jobs, and they are written inside text configuration files known as crontabs (short for "cron tables"). To open your crontab use the `crontab -e` command. At the top you will find an already quite good introduction to how it works. After the (blue) commented out section you can insert cronjobs, each one in a new line, by first specifying the [schedule](https://www.ibm.com/docs/en/db2/11.5.x?topic=task-unix-cron-format) and then the path to the executable command. We will be needing two cron jobs for this whole project, which we will type out later.

## Automation Scripts

All scripts live in [`scripts/`](../scripts) and interactive shortcuts live in [`bashrc-functions.sh`](../bashrc-functions.sh).

### Installation

**Important:** absolute paths, not relative
Every script sources its config via an **absolute home-directory path**:
```bash
source ~/discord-webhooks.conf
```
not a path relative to where the script itself lives. This matters if you're used to keeping scripts and their configs in the same folder — here, `discord-webhooks.conf` must exist directly under your home directory (`~`) regardless of where the scripts themselves are placed or run from.

### Watchdog & expected-state tracking

### Scheduled restarts

### Memory Monitoring

## Bash functions and aliases


