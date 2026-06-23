# ssh_shorty

SSH into robots and servers by nickname. Tab-complete everything. Keep your whole team's fleet in sync.

```bash
s fm85                               # connect
s fm8                                # prefix match → fm85 (if unambiguous)
s fm85 fm11 fm12                     # open each in a tmux window
s --poll fm85                        # wait until online, then connect
s --status fm                        # live online/offline for all fm* devices
s --run @fm "ros2 node list"         # run command across entire group, in parallel
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
- Creates `~/.config/ssh_shorty/config` with commented-out sync options
- Installs tab completion for zsh (`~/.zsh/completions/_s`) and bash
- Wires `fpath`, `compinit`, and `PATH` into your shell rc if missing
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
nickname    user@host-or-ip    [#tag ...]    [port=N]    [key=/path]
```

Tags enable group operations. `port=` and `key=` are optional per-device SSH overrides.

```
fm85              ati@192.168.100.85   #fm #robot
fm11              ati@192.168.6.11     #fm #robot
sherpa-16         ati@192.168.6.35     #sherpa
lifter_unit02     ati@192.168.6.246    #lifter
bastion           ati@192.168.10.26    #server
qa_dm             ubuntu@qa_dm.atimotors.com  #server
edge-node         ati@10.0.0.5         port=2222
build-server      ati@10.0.0.6         key=~/.ssh/build_key
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

### Run commands remotely

```bash
s --run fm85 "uptime"                # single device
s --run @fm "ros2 node list"         # all #fm devices, in parallel
s --run --all "df -h"                # every device
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

Works in both bash and zsh after install.

```
s <TAB>                 → all nicknames
s fm<TAB>               → fm85, fm11, fm12, fm14 ...
s fm85 <TAB>            → more nicknames (multi-device mode)
s fm85:<TAB>            → remote paths on fm85
s fm85:/home/<TAB>      → drill into remote directory
s --run <TAB>           → nicknames + @groups
s --run @<TAB>          → @fm, @sherpa, @lifter ...
s --status <TAB>        → @groups
s --set <TAB>           → nicknames
s --poll <TAB>          → nicknames
```

Remote path completions are cached for 30 seconds. Requires key-based auth on the remote device — use `s --keydeploy` to set that up.

---

## Tips

**Fuzzy prefix matching** — any unambiguous prefix works anywhere a nickname is accepted:
```bash
s bas           # → bastion (only match)
s fm8           # → fm85   (only match)
s sher          # → error: ambiguous (sherpa-16, sherpa-20, sherpa10k16 ...)
```

**Per-device SSH options** in `machines.txt`:
```
edge-node    ati@10.0.0.5    port=2222
build        ati@10.0.0.6    key=~/.ssh/build_ed25519
```

**Groups** — tag devices with `#name` and use `@name` in any command that accepts a target:
```bash
s --status @sherpa
s --run @lifter "systemctl restart ros2"
s --keydeploy @fm
s --close @fm
```

---

## Testing

```bash
./test.sh           # full automated suite in a fresh Ubuntu container
./test.sh --shell   # interactive fresh install to explore manually
```
