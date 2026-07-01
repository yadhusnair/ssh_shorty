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

3. **Tell the user** to run `exec zsh` after any completion change.

## When adding a new `--command`:

- Add the case to `s` (the script)
- Add `'--command:description'` to the `subcommands` array in `completion.zsh`
- Add `--command` to the `subcommands` string in `completion.bash`
- Add tab-complete logic (CURRENT==3 machine picker, etc.) in both completion files
- Add to the help text (`_usage` function in `s`)
- Deploy all three files

## File ownership — what goes where

- **`s`** — user-facing: connect, list, add/remove devices, sync, ping, fav, run, upload/download, etc.
  - Also owns: transparent login logging (`_log_remote_connection`), permission-denied → access request prompt
- **`s-admin`** — admin-facing: user registry (`--add-user`, `--edit-user`, `--remove-user`, `--list-users`), access control (`--provide-access`, `--pending-requests`), audit (`--user-log`)
  - Future admin features go here as new `case` entries
- **`completion-admin.zsh` / `completion-admin.bash`** — completions for `s-admin` (create when s-admin gets enough commands to warrant them)

## When adding a new admin command to `s-admin`:

- Add the case to `s-admin`
- Add `'--command:description'` to `completion-admin.zsh` subcommands array (create file if not yet present)
- Add `--command` to `completion-admin.bash` subcommands string (create file if not yet present)
- Add tab-complete logic in both admin completion files
- Add to the `_usage` function in `s-admin`
- Deploy: `cp s-admin ~/.local/bin/s-admin` (or `bash install-admin.sh`)

## Deploying `s-admin`:

```bash
cp s-admin ~/.local/bin/s-admin
# completions (once created):
cp completion-admin.zsh ~/.zsh/completions/_s-admin
cp completion-admin.bash ~/.local/share/bash-completion/completions/s-admin
rm -f ~/.zcompdump*
```
Or: `bash install-admin.sh`

## Version bumping

- Bump `VERSION` in both `s` and `VERSION` file together
- After bumping: `git add s VERSION && git commit && git push && make release`
