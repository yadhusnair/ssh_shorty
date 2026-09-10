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

## graphify

This project's knowledge graph does NOT live inside this repo — per the routing rule in
`~/.claude/CLAUDE.md`, it lives at the central path:
`~/Desktop/Yadhusnair/graphify/personal/ssh_shorty/graphify-out/` (Obsidian notes at `~/Desktop/Yadhusnair/life_notes/graphify/personal/ssh_shorty/`).

Rules:
- For a narrow, specific lookup (find a function, check a config value, trace one call
  site) — default to grep/Read directly. It is cheaper and more precise than a graph query
  for this case. Confirmed live 2026-07-23: querying the graph for one specific function
  returned 40+ loosely-related node names with no synthesized answer, truncated by the
  token budget — actually answering still required reading the function directly, so the
  query added cost without removing the read.
- For a broad, cross-file question, check this project's own CLAUDE.md architecture
  writeup FIRST (already loaded in context, already synthesized into prose — cheaper than
  any query). Confirmed live 2026-07-23: a graph query for a genuinely broad question
  ("how does sherpa pool management interact across 3 named files") returned 357 nodes
  (62 shown, 295 cut by the token budget) as a bare file/line/community list with no
  synthesized explanation — still required reading the actual functions afterward, so it
  added cost without removing the read.
- Only fall back to `graphify query "<question>" --graph ~/Desktop/Yadhusnair/graphify/personal/ssh_shorty/graphify-out/graph.json` (or
  `graphify path "<A>" "<B>"` / `graphify explain "<concept>"`) if CLAUDE.md does not cover
  the question AND grep/Read cannot find a starting point either — i.e. genuinely unfamiliar
  territory in the codebase, not a case grep or the existing docs already handle.
- If `~/Desktop/Yadhusnair/graphify/personal/ssh_shorty/graphify-out/wiki/index.md` exists, use it for broad navigation instead of raw source browsing.
- Read `~/Desktop/Yadhusnair/graphify/personal/ssh_shorty/graphify-out/GRAPH_REPORT.md` only for broad architecture review or when query/path/explain don't surface enough.
- After modifying code, run `graphify update` yourself for the routine case: a normal edit
  session touching a handful of files, re-extracted via AST only — no LLM involved, cheap and
  fast (`cd ~/Desktop/Yadhusnair/graphify/personal/ssh_shorty && graphify update`).
- Only delegate to Antigravity (agy) for a genuinely large rebuild: a full re-extraction from
  scratch, `--mode deep` semantic extraction, or anything that would otherwise dispatch many
  subagents to read/summarize a large corpus. Delegating a routine small update is a measured
  net token loss, not a saving — confirmed live 2026-07-23 (a failed delegate attempt alone cost
  ~88K tokens for zero result, and even a successful one returns a verbose trace that lands
  entirely in Claude's own context regardless). When you do delegate, prefer the
  `antigravity-delegate` subagent; if it fails due to `CLAUDE_PLUGIN_ROOT` being unset in this
  environment, fall back to invoking `agy-delegate.sh` directly with that variable exported
  manually.
