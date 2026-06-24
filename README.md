# ssh_shorty

SSH into robots and servers by nickname. Tab-complete everything. Keep your whole team's fleet in sync.

```bash
s fm85                               # connect
s fm8                                # prefix match → fm85 (if unambiguous)
s fm85 fm11 fm12                     # open each in a tmux window
s --poll fm85                        # wait until online, then connect
s --status fm                        # live online/offline for all fm* devices
s --sysinfo @fm                      # CPU / RAM / disk dashboard for all fm devices
s --run @fm "ros2 node list"         # run command across entire group, in parallel
s --run-script @fm deploy.sh         # push and execute a local script on every device
s --tunnel fm85 8080                 # forward port 8080 through fm85
s --tail fm85 /var/log/app.log       # live log tail over SSH
s fm85:/home/ati/bags/ .             # rsync pull
```

---

## Install (individual)

```bash
git clone <repo-url>
cd ssh_shorty
./install.sh
exec zsh        # or: exec bash
```

What the installer does:
- Copies `s` to `~/.local/bin/s`
- Copies `machines.txt` to `~/.config/ssh_shorty/machines.txt` (skips if already exists)
- Copies `machine-paths.txt` to `~/.config/ssh_shorty/machine-paths.txt` (skips if already exists)
- Creates `~/.config/ssh_shorty/config` with commented-out sync options
- Installs tab completion for zsh (`~/.zsh/completions/_s`) and bash
- Wires `fpath`, `compinit`, and `PATH` into your shell rc if missing
- Adds Tab cycling (`menu-complete`) to `~/.inputrc` so bash cycles instead of listing
- Clears the zsh completion cache so it's active immediately
- Safe to re-run at any time — never overwrites your device list or config

---

## Fleet sync setup (team)

One shared device holds the authoritative `machines.txt`. Everyone pulls from it automatically; writes push back immediately.

### Step 1 — Pick a sync server

Choose any device that is always on and reachable by everyone who needs fleet access. In this project the validation server is used:

```
ati@192.168.6.12   (fm12 — ~/validation/machines.txt)
```

### Step 2 — Each person adds one line to their config

```bash
echo 'SYNC_HOST=ati@192.168.6.12' >> ~/.config/ssh_shorty/config
```

### Step 3 — First sync

```bash
s --sync
```

- If the server has no `machines.txt` yet → your local copy is pushed as the fleet seed.
- If the server already has one → it is pulled to your machine.

### Day-to-day behaviour

| Action | What happens |
|--------|-------------|
| `s --set tug42 ati@192.168.6.200` | Updates locally + pushes to sync server immediately |
| `s --add newbot ati@10.0.0.5 #fm` | Adds locally + pushes |
| `s --remove oldbot` | Removes locally + pushes |
| Any `s` command | Background pull fires if last sync was >10 min ago (never blocks your prompt) |
| `s --sync` | Manual pull/push |

### No access to the sync server?

If a team member cannot SSH to the sync server everything still works — writes are saved locally and push failures are silent. The script never errors out due to sync issues.

---

## machines.txt format

Location: `~/.config/ssh_shorty/machines.txt`

```
nickname    user@host-or-ip    [#tag ...]    [port=N]    [key=/path]    [mac=XX:XX:XX:XX:XX:XX]
```

Tags enable group operations. `port=` and `key=` are optional per-device SSH overrides.
`mac=` enables ARP-based IP resolution (useful when the device has a dynamic IP).

```
fm85              ati@192.168.100.85   #fm #robot
fm11              ati@192.168.6.11     #fm #robot
sherpa-16         ati@192.168.6.35     #sherpa
lifter_unit02     ati@192.168.6.246    #lifter
bastion           ati@192.168.10.26    #server
qa_dm             ubuntu@qa_dm.local   #server
edge-node         ati@10.0.0.5         port=2222
build-server      ati@10.0.0.6         key=~/.ssh/build_key
tug-42            ati@tug-42.local     mac=aa:bb:cc:dd:ee:ff  #fm
```

**Multiple tags per device** are fine — a device participates in every group whose tag it carries:

```
cpval   ati@192.168.100.120   #instance #fm #sherpa
```

This means `s --status @fm`, `s --run @sherpa`, and `s --status @instance` all include `cpval`.

---

## machine-paths.txt format

Location: `~/.config/ssh_shorty/machine-paths.txt`

Named path aliases per tag, used with `-d` (download) and `-u` (upload):

```
# tag     alias_name    remote_path
sherpa    config        /opt/ati/config/config.toml
sherpa    logs          /opt/ati/logs
fm        config        /opt/fm/config/config.toml
```

```bash
s -d config fm85              # download fm85's config alias to current dir
s -u config.toml fm85:config  # upload to fm85's config alias path
```

---

## Command reference

### Connect

```bash
s fm85                       # connect by exact nickname
s fm8                        # prefix match — connects if unambiguous
s fm85 -X                    # pass extra SSH flags
s -                          # reconnect to last device
s                            # interactive picker (fzf)
```

**Multi-device (tmux)** — opens each in its own tmux window:
```bash
s fm85 fm11 fm12
```

**Wait until online then connect:**
```bash
s --poll fm85                # polls every 5s, connects the moment port 22 opens
s --poll fm8                 # prefix match works here too
```

### File transfer

```bash
s fm85:/home/ati/bags/ .             # pull directory to current folder
s fm85:/home/ati/bags/run1.bag .     # pull single file
s ./config.yaml fm85:/home/ati/      # push file to device
s -d config fm85                     # download using a named path alias
s -u config.toml fm85:config         # upload using a named path alias
```

### Fleet status

```bash
s --status                   # all devices
s --status fm                # prefix filter — only fm* devices
s --status @fm               # group filter — only #fm tagged devices
s --watch                    # live-refreshing status (Ctrl-C to exit)
s --watch fm                 # live-refreshing, prefix filtered
```

Status checks SSH port 22 (not ICMP ping) — works through VPNs and tunnels.

### System resource dashboard

```bash
s --sysinfo                  # CPU load, RAM %, disk % for all devices
s --sysinfo fm               # prefix filter
s --sysinfo @fm              # group filter
```

Shows load average, RAM usage, and root disk usage for every reachable device in parallel.

### Run commands remotely

```bash
s --run fm85 "uptime"                # single device
s --run @fm "ros2 node list"         # all #fm devices, in parallel
s --run --all "df -h"                # every device
```

### Broadcast a local script

```bash
s --run-script fm85 deploy.sh             # single device
s --run-script @fm deploy.sh arg1         # all #fm devices, in parallel, with args
s --run-script --all health_check.sh      # every device
```

The script is piped over SSH (`bash -s`) — no prior copy needed. Arguments are forwarded.

### SSH tunnels

```bash
s --tunnel fm85 8080                 # forward localhost:8080 → fm85:8080
s --tunnel fm85 8080:9090            # forward localhost:8080 → fm85:9090
s --tunnel fm85 -D 1080              # SOCKS5 proxy on local port 1080 via fm85
```

Tunnel stays open until you Ctrl-C.

### Log tailing

```bash
s --tail fm85 /var/log/app.log       # tail -f a specific path
s --tail fm85 logs                   # tail -f using a named path alias from machine-paths.txt
```

### Manage devices

```bash
s --list                             # all devices with tags
s --list fm                          # prefix filter
s --list @fm                         # group filter
s --add mydevice ati@10.0.0.5 #fm    # add (with optional tags)
s --set mydevice ati@10.0.0.9        # update IP or user
s --remove mydevice                  # remove
s --edit                             # open machines.txt in $EDITOR
s --ping fm85                        # single reachability check
```

### Fleet sync

```bash
s --sync                             # manual pull/push with sync server
```

### SSH keys

```bash
s --keydeploy fm85                   # copy your public key to fm85
s --keydeploy @lifter                # copy to all #lifter devices (serial)
```

### SSH config export / import

```bash
s --export-ssh-config                # write all devices to ~/.ssh/config as Host blocks
s --import                           # pull Host entries from ~/.ssh/config into machines.txt
```

### ControlMaster

Connections automatically reuse existing TCP sockets (10 minute persist) — second connect to the same host is nearly instant.

```bash
s --close fm85               # close the persistent socket for fm85
s --close @fm                # close all fm group sockets
s --close --all              # close everything
```

### History

```bash
s --last                     # last 10 connections
s --last 25                  # last 25
```

---

## Tab completion

Works in both bash and zsh after install. In bash, the installer sets up `~/.inputrc` so Tab **cycles** through candidates one by one (same as zsh) instead of dumping a list.

```
s <TAB>                 → all nicknames
s fm<TAB>               → fm85, fm11, fm12, fm14 ... (cycles)
s fm85 <TAB>            → more nicknames (multi-device mode)
s fm85:<TAB>            → remote paths on fm85
s fm85:/home/<TAB>      → drill into remote directory
s --run <TAB>           → nicknames + @groups
s --run @<TAB>          → @fm, @sherpa, @lifter ...
s --status <TAB>        → @groups
s --set <TAB>           → nicknames
s --poll <TAB>          → nicknames
s --tail <TAB>          → nicknames
s --tunnel <TAB>        → nicknames
```

Remote path completions are cached for 30 seconds. Requires key-based auth on the remote device — use `s --keydeploy` to set that up.

If you already have bash and didn't run install, add this to `~/.inputrc` manually:

```
TAB: menu-complete
"\e[Z": menu-complete-backward
set show-all-if-ambiguous on
set menu-complete-display-prefix on
```

---

## Tips

**Fuzzy prefix matching** — any unambiguous prefix works anywhere a nickname is accepted:
```bash
s bas           # → bastion (only match)
s fm8           # → fm85   (only match)
s sher          # → error: ambiguous (sherpa-16, sherpa-20, ...)
```

**Per-device SSH options** in `machines.txt`:
```
edge-node    ati@10.0.0.5    port=2222
build        ati@10.0.0.6    key=~/.ssh/build_ed25519
```

**mDNS / .local hostnames** are resolved automatically — no need to hardcode IPs for devices advertising on the local network:
```
tug-05    ati@tug-05.local    #fm
```

**MAC address fallback** — if a device has a dynamic IP, add `mac=` and the tool will find it via ARP:
```
tug-42    ati@tug-42.local    mac=aa:bb:cc:dd:ee:ff    #fm
```

**Groups** — tag devices with `#name` and use `@name` in any command that accepts a target:
```bash
s --status @sherpa
s --run @lifter "systemctl restart ros2"
s --keydeploy @fm
s --close @fm
s --run-script @fm deploy.sh
```

**fzf picker** (`s` with no args) — keyboard shortcuts:
```
Enter       connect
Ctrl-P      ping selected device
Ctrl-S      sysinfo for selected device
Ctrl-K      deploy SSH key to selected device
Ctrl-E      open machines.txt in editor
```

---

## Testing

```bash
./test.sh           # full automated suite in a fresh Ubuntu container
./test.sh --shell   # interactive fresh install to explore manually
```
