#!/bin/bash
# install-admin.sh — install s-admin and the access-request watcher daemon

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
COMPLETION_ZSH_DIR="${HOME}/.zsh/completions"
COMPLETION_BASH_DIR="${HOME}/.local/share/bash-completion/completions"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing s-admin..."

# ── s-admin binary ─────────────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/s-admin" "$INSTALL_DIR/s-admin"
chmod +x "$INSTALL_DIR/s-admin"
echo "  ✓ s-admin → $INSTALL_DIR/s-admin"

# ── Completions ────────────────────────────────────────────────────────────────
if [[ -f "$SCRIPT_DIR/completion-admin.zsh" ]]; then
    mkdir -p "$COMPLETION_ZSH_DIR"
    cp "$SCRIPT_DIR/completion-admin.zsh" "$COMPLETION_ZSH_DIR/_s-admin"
    rm -f ~/.zcompdump*
    echo "  ✓ zsh completion → $COMPLETION_ZSH_DIR/_s-admin"
fi

if [[ -f "$SCRIPT_DIR/completion-admin.bash" ]]; then
    mkdir -p "$COMPLETION_BASH_DIR"
    cp "$SCRIPT_DIR/completion-admin.bash" "$COMPLETION_BASH_DIR/s-admin"
    echo "  ✓ bash completion → $COMPLETION_BASH_DIR/s-admin"
fi

# ── s-admin-watch daemon ───────────────────────────────────────────────────────
echo ""
echo "Installing s-admin-watch (access-request notification daemon)..."

cp "$SCRIPT_DIR/s-admin-watch" "$INSTALL_DIR/s-admin-watch"
chmod +x "$INSTALL_DIR/s-admin-watch"
echo "  ✓ s-admin-watch → $INSTALL_DIR/s-admin-watch"

if command -v systemctl &>/dev/null && systemctl --user status &>/dev/null 2>&1; then
    mkdir -p "$SYSTEMD_USER_DIR"
    cp "$SCRIPT_DIR/s-admin-watch.service" "$SYSTEMD_USER_DIR/s-admin-watch.service"
    systemctl --user daemon-reload
    systemctl --user enable --now s-admin-watch
    echo "  ✓ systemd user service enabled and started"
    echo "    Logs: journalctl --user -u s-admin-watch -f"
    echo "    Stop: systemctl --user stop s-admin-watch"
else
    echo "  ℹ systemd not available — start manually:"
    echo "    s-admin-watch &"
    echo "    (add to ~/.profile or ~/.zprofile to start on login)"
fi

# ── Check notify-send ──────────────────────────────────────────────────────────
echo ""
if command -v notify-send &>/dev/null; then
    echo "  ✓ notify-send found — desktop pop-ups will work"
else
    echo "  ⚠ notify-send not found — install it for pop-ups:"
    echo "    sudo apt install libnotify-bin"
fi

echo ""
echo "Done. The watcher polls SYNC_HOST every 60s."
echo "Override interval: add SHORTY_WATCH_INTERVAL=30 to ~/.config/ssh_shorty/config"
echo ""
echo "Quick start:"
echo "  s-admin --list-users"
echo "  s-admin --pending-requests"
