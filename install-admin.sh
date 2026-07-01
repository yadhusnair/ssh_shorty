#!/bin/bash
# install-admin.sh — install s-admin for fleet admins

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
COMPLETION_ZSH_DIR="${HOME}/.zsh/completions"
COMPLETION_BASH_DIR="${HOME}/.local/share/bash-completion/completions"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing s-admin..."

# Install binary
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/s-admin" "$INSTALL_DIR/s-admin"
chmod +x "$INSTALL_DIR/s-admin"
echo "  ✓ s-admin → $INSTALL_DIR/s-admin"

# Install zsh completion if present
if [[ -f "$SCRIPT_DIR/completion-admin.zsh" ]]; then
    mkdir -p "$COMPLETION_ZSH_DIR"
    cp "$SCRIPT_DIR/completion-admin.zsh" "$COMPLETION_ZSH_DIR/_s-admin"
    rm -f ~/.zcompdump*
    echo "  ✓ zsh completion → $COMPLETION_ZSH_DIR/_s-admin"
fi

# Install bash completion if present
if [[ -f "$SCRIPT_DIR/completion-admin.bash" ]]; then
    mkdir -p "$COMPLETION_BASH_DIR"
    cp "$SCRIPT_DIR/completion-admin.bash" "$COMPLETION_BASH_DIR/s-admin"
    echo "  ✓ bash completion → $COMPLETION_BASH_DIR/s-admin"
fi

echo ""
echo "Done. Run 'exec zsh' (or 'exec bash') to reload completions."
echo ""
echo "Quick start:"
echo "  s-admin --add-user <name> \"<ssh-pubkey>\""
echo "  s-admin --list-users"
echo "  s-admin --pending-requests"
