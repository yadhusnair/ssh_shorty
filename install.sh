#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/ssh_shorty"
ZSH_COMPLETIONS_DIR="$HOME/.zsh/completions"
BASH_COMPLETIONS_DIR="$HOME/.local/share/bash-completion/completions"

echo "Installing ssh_shorty..."

mkdir -p "$BIN_DIR"
mkdir -p "$CONFIG_DIR"

# Install the 's' script
cp "$SCRIPT_DIR/s" "$BIN_DIR/s"
chmod +x "$BIN_DIR/s"
echo "  Installed: $BIN_DIR/s"

# Install machines.txt (don't overwrite if it already exists)
if [ -f "$CONFIG_DIR/machines.txt" ]; then
    echo "  Skipped:   $CONFIG_DIR/machines.txt (already exists)"
else
    cp "$SCRIPT_DIR/machines.txt" "$CONFIG_DIR/machines.txt"
    echo "  Installed: $CONFIG_DIR/machines.txt"
fi

# Install machine-paths.txt (don't overwrite if it already exists)
if [ -f "$CONFIG_DIR/machine-paths.txt" ]; then
    echo "  Skipped:   $CONFIG_DIR/machine-paths.txt (already exists)"
else
    cp "$SCRIPT_DIR/machine-paths.txt" "$CONFIG_DIR/machine-paths.txt"
    echo "  Installed: $CONFIG_DIR/machine-paths.txt  (edit to add path aliases)"
fi

# Create config file template (don't overwrite)
if [ ! -f "$CONFIG_DIR/config" ]; then
    cat > "$CONFIG_DIR/config" << 'EOF'
# ssh_shorty fleet sync config
#
# Set SYNC_HOST to share machines.txt across your team via a shared server.
# Every s --add / --set / --remove will push to this host automatically.
# Each user's shell pulls in the background every 10 minutes.
#
# Example:
#   SYNC_HOST=ati@192.168.10.26
#
# Optional — override the remote path (default: ~/validation/machines.txt):
#   SYNC_REMOTE_PATH=validation/machines.txt

SYNC_HOST=""
EOF
    echo "  Installed: $CONFIG_DIR/config  (edit to enable fleet sync)"
else
    echo "  Skipped:   $CONFIG_DIR/config (already exists)"
fi

# ── Zsh completion ─────────────────────────────────────────────────────────────
if command -v zsh &>/dev/null; then
    mkdir -p "$ZSH_COMPLETIONS_DIR"
    cp "$SCRIPT_DIR/completion.zsh" "$ZSH_COMPLETIONS_DIR/_s"
    echo "  Installed: $ZSH_COMPLETIONS_DIR/_s"

    touch "$HOME/.zshrc"

    # fpath must come before compinit
    if ! grep -q '\.zsh/completions' "$HOME/.zshrc"; then
        printf '\n# ssh_shorty completions\nfpath=(~/.zsh/completions $fpath)\n' >> "$HOME/.zshrc"
        echo "  Updated:   ~/.zshrc (fpath)"
    fi

    # compinit must be present for completions to load at all
    if ! grep -q 'compinit' "$HOME/.zshrc"; then
        printf 'autoload -Uz compinit && compinit\n' >> "$HOME/.zshrc"
        echo "  Updated:   ~/.zshrc (compinit)"
    fi

    # Clear stale completion cache so _s is picked up immediately
    rm -f "$HOME/.zcompdump" "$HOME"/.zcompdump-*
    echo "  Cleared:   ~/.zcompdump (completion cache)"
fi

# ── Bash completion ────────────────────────────────────────────────────────────
mkdir -p "$BASH_COMPLETIONS_DIR"
cp "$SCRIPT_DIR/completion.bash" "$BASH_COMPLETIONS_DIR/s"
echo "  Installed: $BASH_COMPLETIONS_DIR/s"

# Write a fallback copy and source it from .bashrc
# (covers bash-completion v1 and systems where XDG dir isn't auto-loaded)
FALLBACK="$CONFIG_DIR/completion.bash"
cp "$SCRIPT_DIR/completion.bash" "$FALLBACK"

if [ -f "$HOME/.bashrc" ]; then
    # Ensure bash-completion package is sourced before our file
    if ! grep -q 'bash_completion' "$HOME/.bashrc"; then
        cat >> "$HOME/.bashrc" << 'EOF'

# bash-completion
if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi
EOF
        echo "  Updated:   ~/.bashrc (bash-completion)"
    fi

    if ! grep -q 'ssh_shorty/completion' "$HOME/.bashrc"; then
        printf '\n# ssh_shorty\n[ -f "%s" ] && source "%s"\n' "$FALLBACK" "$FALLBACK" >> "$HOME/.bashrc"
        echo "  Updated:   ~/.bashrc (completion)"
    fi
fi

# ── Bash menu-complete (Tab cycling) ──────────────────────────────────────────
# Without this, bash lists all completions but never cycles. With it, Tab cycles
# through candidates one by one (like zsh). Written to ~/.inputrc which readline
# reads for all programs — safe to add if not already present.
INPUTRC="$HOME/.inputrc"
if ! grep -q 'menu-complete' "$INPUTRC" 2>/dev/null; then
    cat >> "$INPUTRC" << 'EOF'

# Cycle through completions with Tab (added by ssh_shorty install)
TAB: menu-complete
"\e[Z": menu-complete-backward
set show-all-if-ambiguous on
set menu-complete-display-prefix on
EOF
    echo "  Updated:   ~/.inputrc (Tab cycling for bash)"
else
    echo "  Skipped:   ~/.inputrc (menu-complete already set)"
fi

# ── PATH ───────────────────────────────────────────────────────────────────────
for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$RC" ] || continue
    if ! grep -q '\.local/bin' "$RC"; then
        printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$RC"
        echo "  Updated:   $RC (PATH)"
    fi
done

echo ""
echo "Done. Open a new shell tab, then try:"
echo "  s --list"
echo "  s <nickname>"
echo "  s <TAB>"
echo ""
echo "Machine list: $CONFIG_DIR/machines.txt"
