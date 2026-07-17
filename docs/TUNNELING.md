# Network

This is your first stop after succesfully installing the server applications and confirming they run, which is where the [video guide](https://www.youtube.com/watch?v=DwJ6OfPophw) I mentioned will leave you. In here we will cover how external players can reach a game server hosted on a home connection and what roadblocks you might encounter

## Port Forwarding, or maybe not

When you break down a World of Warcraft server, there are two separate applications running on the machine, the **authentication server** and the **world server**. The auth-server handles log in, realm selection, character selection and forwards the connection to the world-server, which handles all the game logic. As they are completly different processes, their access is also separate; auth-server is assigned port 3724, world-server gets 8085, these numbers will the important in a moment. That means incoming internet traffic has to specify that they want to access the right port when reaching your machine, and that is where we hit our first checkpoint

### IPv4 vs IPv6

There are two types of internet addresses, **IPv4 and IPv6**. Here is a small history tangent (feel free to skip three paragraphs): the internet was at first experimental research that started around the 1960s; the first big scale network infrastructure was built between universities in '69, the World Wide Web with its user-friendly interface came in '89. Back then in the research phase there were decisions to be made, like for example how to uniquely identify all machines connected to the network. The solution Vincent Cerf and Bob Kahn at DARPA came up with was TCP/IP. It works on binary digits and in theory assigns a unique set of 32 bits to each machine on the network as an address that you can send information to/from. Having an address space of 32 bits means there are $2^{32}$ = 4.3 billion possible unique addresses, give or take. At the time the researchers deemed impossible for their project ever to reach that number of connected machines. Currently there are around **21.9 billion** active connected devices worldwide. It is safe to say they underestimated the potential usage of their internet.

That was IPv4. Over a decade after that IPv6 was deployed with 128 bit addresses, allowing $2^{128}$ unique addresses. These addresses began being given out, and they should be enough for the next while, but the problem wasn't completly solved. By the time IPv6 was ratified as an Internet Standard in 2017 the whole world's internet infrastructure was based on IPv4. Many services such as websites, servers and smart home devices rely on the IPv4 standard, but we ran out of those addresses years ago. That is where **NAT** (Network Address Translation) comes into play. With NAT you can map several devices onto the same IPv4 address, so they share the same identifier to the ousite world. When information is recieved, the NAT is then responsible to identify which of the devices it is supposed to go and reroutes it.

As we can imagine, IPv4 addresses are rare and comparetively expensive. That is why ISPs all over the world use CGNAT (Carrier-Grade Network Address Translation) to assign one IPv4 address to up to hundreds of individual devices. So someone on a CGNAT wouldn't have a unique IPv4 address, and that's a problem.

**Why this all matters:** for you to make your game server visible to the internet you need to open ports 3724 and 8085 (auth and world respectively) on your router to allow incoming traffic to the server applications, but that only works if you have a native IPv4 address, otherwise you can send data just fine, but can't recieve it, because it doesn't reroute to you and gets lost at the NAT entrance. Depending on where you live it will be more or less common for ISPs to give out a IPv4 address on a regular plan if you haven't specifically asked for one. Where I come from you can only get one on a very expensive plan. So here is a workaround

### Does my ISP allow incoming IPv4 traffic?

Now most people are on CGNATs, but it's worth double checking before jumping into the workaround. If you are lucky enough to have a native IPv4 connection you can skip the whole tunneling section entirely.

Go to your router's settings page by typing its local IP into your browser — typically something like 192.168.1.1 or 192.168.178.1, though it varies by manufacturer. Once you're in, look for your internet/WAN connection settings. What you're hunting for is any explicit mention of DS-Lite or "Native IPv6 with IPv4 via CGNAT" — if either of those shows up, you're on the tunnel path, and none of the port forwarding below will ever work no matter how correctly you configure it, since your router genuinely isn't the edge of the internet for your IPv4 address; your ISP's shared NAT box is.

If instead you see Native IPv4 (or nothing suggesting a workaround at all), you're in the easier position. All you need is:


Open ports 3724 and 8085 on your router — portforward.com has walkthroughs for basically every consumer router model
Give your friends your public IPv4 address followed by :3724


They paste that into their realmlist.wtf (typically wow_directory/Data/enUS/realmlist.WTF) after the existing set realmlist string, replacing whatever's there.

One thing worth double-checking either way, regardless of which category you fall into: a correctly forwarded port doesn't always mean traffic is actually arriving. If people still can't connect after this, a live packet capture while someone attempts a connection is the most reliable way to know for certain whether the problem is your configuration or something further upstream you can't fix from your end:

```
bashsudo tcpdump -i any port 3724 -n -v
```

If you see SYN packets arriving from the outside while someone's testing, your forwarding works and the problem is elsewhere (server-side, most likely). If you see nothing at all, something between you and the internet is still eating the traffic — which is exactly the symptom that sent me down the CGNAT rabbit hole in the first place.

## Tunnels

For most people a simple port forwarding will not work, since most people can't recieve IPv4 traffic, only IPv6. So the solution is to transform the incoming traffic into IPv6 addresses, and that is where tunnels come into play. Tunnels sit between your machine and the internet and your machine, recieving information, transforming it into the right format (IPv6) and rerouting it to your machine. Here are some of the tunnel service options I explored:

### Cloudflare Tunnel

Cloudflare Tunnel handles HTTP/HTTPS natively, but non-HTTP protocols (which a game server is not) require every connecting client to run `cloudflared` locally and connect via `localhost`. I didn't explore this solution further because I didn't find it satisfying having players download extra software to connect. You can go down this route and have it work, it's free and stable, but I can't offer more guidance than this.

### [bore](https://github.com/ekzhang/bore)

bore is a minimal open-source Tunnel. This option was tried and saw a bit of success, but it had two major limitations. First, the bore process running on the server would assign random ports on restart or any time the bore process crashed and had to be brought up again. This meant that players would have to manually change their realmlist.WTF file every time one of those happened. Second, some players' networks block arbitrary high ports (10000+ range) which is exactly the port range the publicly hosted service at `bore.pub` would assign. This was confirmed via `Test-NetConnection` connection tests from the affected player's machine, which failed on the tunnel's specific port but succeeded on common ports like 443.

The alternative to the public bore service is a self-hosted bore server on an external machine which allows IPv4 traffic. This option was also tried on a free Oracle Cloud VM. On paper it would have been perfect, no more random ports or too high ports that get blocked (self hosting assigns lower ports). Unfortunately I hit a wall getting incoming traffic into the Cloud VM. Any attempts of accessing any port other than 22 (ssh) wouldn't get to the machine. This was confirmed via `tcpdump` showing zero packets ever arriving at the VM's network interface, ruling out any local misconfiguration.

Don't feel discouraged to go down this route though, I only opted for a different solution entirely because it was taking me too much time to diagnose the cloud VM's network problems.

### [Localtonet](https://localtonet.com/)

It supports TCP tunnels right out of the box without any VM hosting, and also offers static IP addresses. The setup:

- Create two TCP tunnels on the dashboard — one for port `3724` (authserver), one for `8085` (worldserver)
- Enable the static/reserved address option on each tunnel, so the hostname:port never changes across restarts
- Point the realmlist at the tunnel addresses (see below)

There is a caveat: Localtonet bills per tunnel based on running time, not bandwidth - roughly a couple dollars/month per tunnel if left running continuously. Since this is a hobby server without 24/7 demand, there is no need to leave the tunnels running while noone is playing or you are by yourself. We will not be going into the scripting here, that is covered in [SETUP.md](SETUP.md), just know that there are two bash functions for that, golocal and goonline, to switch between the two from your console and avoid unnecessary billing.

## Realmlist Configuration

The `realmlist` table on your server needs both the public tunnel address and a `localAddress` for same-subnet connections:

UPDATE realmlist SET
  address = 'your-tunnel-hostname.localto.net',
  localAddress = 'your-tunnel-hostname.localto.net',
  localSubnetMask = '255.255.255.255',
  port = <your-world-tunnel-port>
WHERE id = 1;

Why localAddress is set to the same value as address: setting localSubnetMask to 255.255.255.255 (the most restrictive possible mask) makes the "local" branch of the address-selection logic effectively unreachable for any real client, so every connection - regardless of network - is routed through the exact same tunnel path. This avoids a subtle bug where players on the same LAN as the server get redirected to a localAddress that only makes sense from the server's own perspective (e.g. 127.0.0.1), resulting in a connection that authenticates successfully but then hangs indefinitely on "Logging in to game server."

Players connect using:

```
set realmlist your-auth-tunnel-hostname.localto.net:<auth-tunnel-port>
```
### Database Fix

Once the tunnel is actually working there is still a small database tweak to be made.

If you or anyone else tried to log in at this point you would get to the character selection for a split second before getting logged off, after which the following would appear on your world-server log:

```
WorldSocket::HandleAuthSession: Authentication failed for account: 101 ('ACCOUNTNAME') address: ::ffff:127.0.0.1
```

We see an error message telling us the authentification process for a log in attempt from the specified IP address failed. Do you notice anything strange about the address? The right half looks like regular IPv4, the left half is just a bunch of letters. That actually means the tunnel is working correctly, this is IPv4-mapped IPv6 notation. The localtonet servers recieve the incoming IPv4 formatted IP and extend it to IPv6 length when sending it to you. It has something to do with dual-stack sockets, haven't looked that in detail into it yet.

When taking a look at the auth-server log files (if you ever need to troubleshoot an issue these can be great sources of information, usually located in the ~/azerothcore-wotlk/env/dist/bin directory, look for Auth.log and Server.log) we see the following entries from when we tried logging in:

```
[ERROR]: [1406] Data too long for column 'last_ip' at row 1
```

And here we have the problem spelled out for us. Auth-server writes the connecting IP into the account table's last_ip column as part of finishing the login handshake — and if that column was sized for plain IPv4 addresses only, the write fails outright. Also, since that same SQL statement also sets the account's session_key, the failed write means the session key never gets saved either — which is the actual reason the world server then rejects the connection a moment later. Two failures, one root cause, and the second one is what you actually see in the logs unless you go looking at Auth.log specifically.

The fix is a one-time schema change:

```
ALTER TABLE account MODIFY last_ip VARCHAR(45);
ALTER TABLE account MODIFY last_attempt_ip VARCHAR(45);
```

VARCHAR(45) is the standard safe size for any IPv6 representation, mapped or native. Run it once, restart nothing, and the very next login attempt should go through cleanly.
