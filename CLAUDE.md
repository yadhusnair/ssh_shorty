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

## Version bumping

- Bump `VERSION` in both `s` and `VERSION` file together
- After bumping: `git add s VERSION && git commit && git push && make release`
