# Tunneling & Network Setup

This document covers how external players can reach a game server hosted on a home connection with no usable public IPv4 — including the diagnosis process and every approach that was evaluated before settling on the final solution.

## The Root Problem: CGNAT / DS-Lite

Port forwarding on the home router appeared correctly configured (firewall rules, NAT rules, all verified), but external connections still failed to reach the server. The underlying cause: the ISP connection used **DS-Lite** — a native IPv6 connection with a *shared* IPv4 address provided via Carrier-Grade NAT (CGNAT) for backward compatibility.

Under DS-Lite, outbound IPv4 traffic works fine (a public IPv4 address is visible via services like `curl -4 ifconfig.me`), but **inbound** port forwarding is fundamentally impossible — the router isn't actually the edge of the internet for that IPv4 address; the ISP's shared NAT box is, and it has no way to know which of its many customers a given inbound packet is meant for.

### How to check if you're affected
On a FRITZ!Box: **Internet → Zugangsdaten → IPv6** tab. If "IPv4-Anbindung über DS-Lite herstellen" is checked under a native IPv6 connection, you're on DS-Lite. Other routers/ISPs expose this differently, but the underlying concept is the same: look for "DS-Lite," "IPv6 with CGNAT," or "shared IPv4" in your connection details.

### Confirming packets never arrive (not just a misconfigured firewall)
Before concluding it's DS-Lite/CGNAT rather than a local firewall issue, confirm with a live packet capture on the server while attempting a connection from outside:
```bash
sudo tcpdump -i any port <YOUR_PORT> -n -v
```
If zero packets ever appear — even though local firewall rules (`ufw`, `iptables`) and cloud security groups are all correctly configured — the block is happening upstream, before traffic ever reaches the machine at all.

## Approaches Evaluated

Since traditional port forwarding wasn't possible, the practical alternative is a **tunnel**: a relay service that has a real public IP, which forwards traffic from the internet back to the home server via an outbound connection the home server itself initiates (outbound connections aren't blocked by CGNAT, only inbound ones).

### 1. Cloudflare Tunnel — ruled out
Cloudflare Tunnel handles HTTP/HTTPS natively, but non-HTTP protocols (raw TCP, which a game server needs) require **every connecting client** to run `cloudflared` locally and connect via `localhost`. This doesn't work for a multiplayer server where anonymous players need to connect directly with just an address — it's designed for personal/admin access to a single service, not public multiplayer traffic.

### 2. `bore` (open-source, self-hosted relay) — worked, with caveats
[bore](https://github.com/ekzhang/bore) is a minimal open-source TCP tunnel. Two deployment options were tried:

**Public `bore.pub` relay (free, no account needed):**
- Works well for basic connectivity
- **Major limitation**: assigns a random port on every restart — required a wrapper script to detect the new port and update the realmlist database automatically (see `scripts/server-start.sh`'s pattern, adapted from an earlier `bore`-specific version)
- **Second major limitation**: some players' networks block arbitrary high ports (10000-65535 range) even when the port itself is reachable from most locations — confirmed via `Test-NetConnection`/custom TCP connection tests from the affected player's machine, which failed on the tunnel's specific port but succeeded on common ports like 443

**Self-hosted `bore server` on a cloud VM:**
- Would solve the "random port" and "blocked high port" problems by using fixed, standard ports
- Attempted on an Oracle Cloud free-tier VM — despite correct Security List rules, correct `ufw`/`iptables` rules, and the `bore server` process confirmed listening (`ss -tulpn`), external connections still timed out
- Root-caused via `tcpdump` showing **zero packets ever arriving** at the VM's network interface, ruling out any local misconfiguration — pointed to an undocumented account-level or infrastructure-level restriction specific to the free-tier instance, which Oracle support could not confirm or resolve
- **Conclusion**: free-tier cloud VMs may have undocumented inbound restrictions on non-standard ports; not recommended if you hit the same wall

### 3. Localtonet (commercial tunnel service) — final solution
Supports raw TCP tunnels directly (not just HTTP), works out of the box without any cloud VM of your own, and offers reserved/static addresses on paid tiers, eliminating the random-port problem entirely.

**Setup:**
1. Create two TCP tunnels on the dashboard — one for port `3724` (authserver), one for `8085` (worldserver)
2. Enable the **static/reserved address** option on each tunnel, so the hostname:port never changes across restarts
3. Point the realmlist at the tunnel addresses (see below)

**Cost control:** Localtonet bills per tunnel based on running time (not bandwidth) — roughly a couple dollars/month per tunnel if left running continuously. Since this is a hobby server without 24/7 demand, tunnels are started/stopped on demand via the Localtonet REST API (see `bashrc-functions.sh`'s `golocal`/`goonline` functions), rather than the local `--start-service`/`--stop-service` CLI commands, which only control the local client process and **do not** stop billing — billing is tied to the tunnel's state on Localtonet's servers, controlled via `POST /api/v2/tunnels/{id}/actions/start` and `.../stop`.

## Realmlist Configuration

The `realmlist` table needs both the public tunnel address and a `localAddress` for same-subnet connections:

```sql
UPDATE realmlist SET
  address = 'your-tunnel-hostname.localto.net',
  localAddress = 'your-tunnel-hostname.localto.net',
  localSubnetMask = '255.255.255.255',
  port = <your-world-tunnel-port>
WHERE id = 1;
```

**Why `localAddress` is set to the same value as `address`:** setting `localSubnetMask` to `255.255.255.255` (the most restrictive possible mask) makes the "local" branch of the address-selection logic effectively unreachable for any real client, so every connection — regardless of network — is routed through the exact same tunnel path. This avoids a subtle bug where players on the same LAN as the server get redirected to a `localAddress` that only makes sense from the server's own perspective (e.g. `127.0.0.1`), resulting in a connection that authenticates successfully but then hangs indefinitely on "Logging in to game server."

Players connect using:
```
set realmlist your-auth-tunnel-hostname.localto.net:<auth-tunnel-port>
```

## Switching Between Local-Only and Tunneled Play

Since tunnel uptime costs money, `golocal`/`goonline` (in `bashrc-functions.sh`) toggle between two modes:
- **`golocal`**: stops both tunnels via the Localtonet API and points the realmlist at the server's LAN IP — free, but only reachable from the same local network
- **`goonline`**: starts both tunnels and points the realmlist back at the tunnel addresses — reachable externally, incurs tunnel running-time cost

`serverstatus` (also in `bashrc-functions.sh`) reports current tunnel state and the exact `realmlist.wtf` line to use, pulled live from both the Localtonet API and the database, so it stays accurate even as tunnel addresses/ports change.
