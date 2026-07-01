# ssh_shorty — Agent Rules

## After every change, always:

1. **Deploy** — copy updated files to their live locations:
   ```bash
   cp s ~/.local/bin/s
   cp completion.zsh ~/.zsh/completions/_s
   cp completion.bash ~/.local/share/bash-completion/completions/s
   rm -f ~/.zcompdump*
   ```
   Or run `bash install.sh` for a full install.

2. **Commit and push** — every change goes to `main`:
   ```bash
   git add <files> && git commit -m "..." && git push origin main
   ```

3. **Always tell the user** to run `exec zsh` — say it every time, even if you think you already said it. Completions never activate until the shell is reloaded.

## File ownership — what goes where

| File | Purpose |
|------|---------|
| `s` | User tool: connect, list, add/remove devices, sync, ping, fav, run, upload/download, rsync, tunnel, poll, status, watch, sysinfo |
| `completion.zsh` | Zsh completion for `s` → `~/.zsh/completions/_s` |
| `completion.bash` | Bash completion for `s` → `~/.local/share/bash-completion/completions/s` |
| `install.sh` | First-run installer for regular users |
| `s-admin` | Admin tool: user registry, access control, audit (see below) |
| `completion-admin.zsh` | Zsh completion for `s-admin` → `~/.zsh/completions/_s-admin` |
| `completion-admin.bash` | Bash completion for `s-admin` → `~/.local/share/bash-completion/completions/s-admin` |
| `install-admin.sh` | Installer for admins |

### What `s` owns
- All device management and SSH connect commands
- Transparent login logging: `_log_remote_connection` (bg SSH → `~/.ssh_shorty/userlog.txt` on device)
- Permission-denied detection → "Request access from admin? [y/N]" → writes `.req` to SYNC_HOST
- `SHORTY_USER` identity (set in `~/.config/ssh_shorty/config`, defaults to `$USER`)

### What `s-admin` owns
- `--add-user / --edit-user / --remove-user / --list-users` — user registry (`users.txt`)
- `--provide-access <user> <device>` — grant SSH access (idempotent, key via heredoc)
- `--pending-requests` — list/review queued access requests
- `--user-log <nick>` — view device login history
- Future admin features go here as new `case` entries

### Admin differentiation (current state)
There is **no enforcement** — anyone who runs `install-admin.sh` gets `s-admin`. The implicit gate is SSH key access: `--provide-access` and `--pending-requests` require SSH access to SYNC_HOST or the target device, so they naturally fail for unauthorized users. Formal role enforcement (e.g. `admins.txt` on SYNC_HOST) is a planned future feature.

## When adding a new user command to `s`:

- Add the `case` entry to `s`
- **Always** add `'--command:description'` to the `subcommands` array in `completion.zsh`
- **Always** add `--command` to the `subcommands` string in `completion.bash`
- Add tab-complete logic in both completion files (CURRENT==3 machine picker, etc.)
- Add to the `usage()` function in `s`
- Deploy: `cp s ~/.local/bin/s` + both completion files + `rm -f ~/.zcompdump*`
- **Tell the user to run `exec zsh`**

## When adding a new admin command to `s-admin`:

- Add the `case` entry to `s-admin`
- **Always** add `'--command:description'` to the `subcommands` array in `completion-admin.zsh`
- **Always** add `--command` to the `subcommands` string in `completion-admin.bash`
- Add tab-complete logic in both admin completion files
- Add to the `_usage()` function in `s-admin`
- Deploy: `cp s-admin ~/.local/bin/s-admin` + both admin completion files + `rm -f ~/.zcompdump*`
- **Tell the user to run `exec zsh`**

## Deploying everything at once:

```bash
# User tool
cp s ~/.local/bin/s
cp completion.zsh ~/.zsh/completions/_s
cp completion.bash ~/.local/share/bash-completion/completions/s

# Admin tool
cp s-admin ~/.local/bin/s-admin
cp completion-admin.zsh ~/.zsh/completions/_s-admin
cp completion-admin.bash ~/.local/share/bash-completion/completions/s-admin

rm -f ~/.zcompdump*
```
Or run `bash install.sh` (user) / `bash install-admin.sh` (admin).

## Version bumping

- Bump `VERSION` in both `s` and `VERSION` file together (s-admin reads `VERSION` from the same repo but has its own hardcoded version string — bump both)
- After bumping: `git add s s-admin VERSION && git commit && git push && make release`
