#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# `curl ... install.sh | bash` has no real file on disk for this script, so
# ${BASH_SOURCE[0]} resolves to nothing and SCRIPT_DIR above silently becomes
# the caller's cwd — which doesn't have the sibling files (s, completion.zsh,
# ...) this script expects, since curl only piped install.sh's own content,
# never the rest of the repo. Detect that (no "s" next to us) and self-fetch
# a real checkout, matching how `s --update` already does it.
if [[ ! -f "$SCRIPT_DIR/s" ]]; then
    echo "Fetching ssh_shorty..."
    _install_tmp=$(mktemp -d)
    trap 'rm -rf "$_install_tmp"' EXIT
    _tarball="$_install_tmp/repo.tar.gz"
    if ! curl -fsSL --max-time 60 \
            "https://github.com/yadhusnair/ssh_shorty/archive/refs/heads/main.tar.gz" \
            -o "$_tarball"; then
        echo "Download failed." >&2
        exit 1
    fi
    if ! tar -xzf "$_tarball" -C "$_install_tmp"; then
        echo "Extract failed." >&2
        exit 1
    fi
    _repo_dir=$(find "$_install_tmp" -maxdepth 1 -type d -name 'ssh_shorty-*' | head -1)
    if [[ -z "$_repo_dir" || ! -f "$_repo_dir/s" ]]; then
        echo "Unexpected archive layout — aborted." >&2
        exit 1
    fi
    bash "$_repo_dir/install.sh" "$@"
    exit $?
fi

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/ssh_shorty"
ZSH_COMPLETIONS_DIR="$HOME/.zsh/completions"
BASH_COMPLETIONS_DIR="$HOME/.local/share/bash-completion/completions"

# Optional: fzf powers the live-filtering search box in the table editors
# (s --edit etc.) and the top-level device picker. Everything already
# degrades gracefully without it (a plain search box + list instead), so
# this is a nice-to-have, never fatal to the rest of install/update.
offer_fzf() {
    command -v fzf &>/dev/null && return 0

    echo "  Installing fzf (powers the live-filtering search box in 's --edit' etc.)..."

    if command -v brew &>/dev/null; then
        echo "  Installing fzf via brew..."
        brew install fzf && { echo "  Installed: fzf"; return 0; }
        echo "  brew install failed — falls back to a plain search box + list."
        return 0
    fi

    if command -v apt-get &>/dev/null; then
        echo "  Installing fzf via apt..."
        if sudo apt-get install -y fzf 2>/dev/null; then
            echo "  Installed: fzf"
            return 0
        fi
        echo "  apt install failed/unavailable — trying a user-local binary instead..."
    fi

    # User-local binary — no root needed, works regardless of package manager.
    local _fzf_os
    case "$(uname -s)" in
        Linux)  _fzf_os="linux" ;;
        Darwin) _fzf_os="darwin" ;;
        *)
            echo "  Unrecognized OS — install fzf manually: https://github.com/junegunn/fzf#installation"
            return 0 ;;
    esac
    local _fzf_arch
    case "$(uname -m)" in
        x86_64)         _fzf_arch="amd64" ;;
        aarch64|arm64)  _fzf_arch="arm64" ;;
        *)
            echo "  Unrecognized CPU arch — install fzf manually: https://github.com/junegunn/fzf#installation"
            return 0 ;;
    esac
    local _fzf_ver
    _fzf_ver=$(curl -fsSL --max-time 10 https://api.github.com/repos/junegunn/fzf/releases/latest 2>/dev/null \
        | grep -m1 '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    if [[ -z "$_fzf_ver" ]]; then
        echo "  Could not check the latest fzf version — install manually: https://github.com/junegunn/fzf#installation"
        return 0
    fi
    local _fzf_tmp; _fzf_tmp=$(mktemp -d)
    if curl -fsSL --max-time 30 \
            "https://github.com/junegunn/fzf/releases/download/v${_fzf_ver}/fzf-${_fzf_ver}-${_fzf_os}_${_fzf_arch}.tar.gz" \
            -o "$_fzf_tmp/fzf.tar.gz" \
            && mkdir -p "$BIN_DIR" \
            && tar -xzf "$_fzf_tmp/fzf.tar.gz" -C "$BIN_DIR" fzf; then
        chmod +x "$BIN_DIR/fzf"
        echo "  Installed: fzf"
    else
        echo "  fzf install failed — falls back to a plain search box + list."
    fi
    rm -rf "$_fzf_tmp"
}

# --update mode: called by 's --update' after downloading a fresh repo tarball.
# Only updates the script + completions — never touches user data files.
UPDATE_MODE=false
[[ "${1:-}" == "--update" ]] && UPDATE_MODE=true

if [[ "$UPDATE_MODE" == true ]]; then
    echo "Applying update..."
    echo ""

    # Update the s script
    cp "$SCRIPT_DIR/s" "$BIN_DIR/s"
    chmod +x "$BIN_DIR/s"
    echo "  ✓ s"

    # Update completion files (only where already installed)
    if [[ -f "$ZSH_COMPLETIONS_DIR/_s" ]]; then
        cp "$SCRIPT_DIR/completion.zsh" "$ZSH_COMPLETIONS_DIR/_s"
        echo "  ✓ completion.zsh"
        rm -f "$HOME/.zcompdump" "$HOME"/.zcompdump-* 2>/dev/null
    fi
    local_xdg="$BASH_COMPLETIONS_DIR/s"
    local_cfg="$CONFIG_DIR/completion.bash"
    if [[ -f "$local_xdg" ]]; then
        cp "$SCRIPT_DIR/completion.bash" "$local_xdg"
        echo "  ✓ completion.bash (xdg)"
    fi
    if [[ -f "$local_cfg" ]]; then
        cp "$SCRIPT_DIR/completion.bash" "$local_cfg"
        echo "  ✓ completion.bash (cfg)"
    fi

    echo ""
    offer_fzf
    echo ""
    echo "Done. Open a new shell tab to activate new completions."
    exit 0
fi

echo "Installing ssh_shorty..."
echo ""

# ── Shell selection ────────────────────────────────────────────────────────────
USE_ZSH=false
if command -v zsh &>/dev/null; then
    USE_ZSH=true
    echo "  zsh detected — enhanced completions will be set up."
else
    echo "  zsh not found. zsh offers richer tab-completion and a better interactive"
    echo "  experience than bash (native cycling, smarter matching, and more)."
    _zsh_resp="n"
    if [[ -t 0 ]]; then
        printf "  Install zsh now? [Y/n] "
        read -r _zsh_resp
    fi
    if [[ ! "$_zsh_resp" =~ ^[Nn] ]]; then
        # Detect package manager and install
        if command -v apt-get &>/dev/null; then
            echo "  Installing zsh via apt..."
            sudo apt-get install -y zsh
        elif command -v dnf &>/dev/null; then
            echo "  Installing zsh via dnf..."
            sudo dnf install -y zsh
        elif command -v pacman &>/dev/null; then
            echo "  Installing zsh via pacman..."
            sudo pacman -S --noconfirm zsh
        elif command -v brew &>/dev/null; then
            echo "  Installing zsh via brew..."
            brew install zsh
        else
            echo "  Could not detect package manager. Install zsh manually, then re-run install.sh."
            echo "  Continuing with bash..."
        fi

        if command -v zsh &>/dev/null; then
            USE_ZSH=true
            echo "  Installed: zsh $(zsh --version | awk '{print $2}')"

            # Offer to set zsh as the default shell
            _zsh_path="$(command -v zsh)"
            if [[ "$SHELL" != "$_zsh_path" ]]; then
                _chsh_resp="n"
                if [[ -t 0 ]]; then
                    printf "  Set zsh as your default shell? [Y/n] "
                    read -r _chsh_resp
                fi
                if [[ ! "$_chsh_resp" =~ ^[Nn] ]]; then
                    # Ensure zsh is in /etc/shells
                    if ! grep -qx "$_zsh_path" /etc/shells 2>/dev/null; then
                        echo "$_zsh_path" | sudo tee -a /etc/shells > /dev/null
                    fi
                    chsh -s "$_zsh_path"
                    echo "  Default shell set to zsh — takes effect on next login."
                fi
            fi
        fi
    else
        echo "  Skipping zsh — continuing with bash."
    fi
fi
echo ""

mkdir -p "$BIN_DIR"
mkdir -p "$CONFIG_DIR"

# Install the 's' script
cp "$SCRIPT_DIR/s" "$BIN_DIR/s"
chmod +x "$BIN_DIR/s"
echo "  Installed: $BIN_DIR/s"

# ── Fleet config + machines.txt ───────────────────────────────────────────────
_sync_pulled_machines=false
_sync_pulled_paths=false
_sync_pulled_favs=false

# Write config (skip if already exists)
if [ -f "$CONFIG_DIR/config" ]; then
    echo "  Skipped:   $CONFIG_DIR/config (already exists)"
    # Load existing SYNC_HOST so the pull attempt below can use it
    # shellcheck source=/dev/null
    source "$CONFIG_DIR/config" 2>/dev/null || true
else
    # If machines.txt is absent, offer to configure sync and pull fleet files now
    if [ ! -f "$CONFIG_DIR/machines.txt" ]; then
        echo ""
        echo "  No fleet config found. You can pull machines.txt from a shared sync"
        echo "  server now, or start with a stub file and add devices manually later."
        echo ""
        _setup_sync="n"
        if [[ -t 0 ]]; then
            printf "  Set up fleet sync host now? [Y/n] "
            read -r _setup_sync
        fi
        if [[ ! "$_setup_sync" =~ ^[Nn] ]]; then
            printf "  Sync host (e.g. ati@192.168.6.12): "
            read -r SYNC_HOST
            printf "  Remote path [default: validation/machines.txt]: "
            read -r _rpath
            SYNC_REMOTE_PATH="${_rpath:-validation/machines.txt}"
        fi
        echo ""
    fi

    # Write config file
    cat > "$CONFIG_DIR/config" << EOF
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

SYNC_HOST="${SYNC_HOST:-}"
SYNC_REMOTE_PATH="${SYNC_REMOTE_PATH:-validation/machines.txt}"
EOF
    echo "  Installed: $CONFIG_DIR/config"
fi

# If sync is configured, try to pull fleet files now
if [[ -n "${SYNC_HOST:-}" ]]; then
    _rdir="${SYNC_REMOTE_PATH%/*}"
    echo "  Pulling fleet files from $SYNC_HOST..."

    if scp -q -o BatchMode=yes -o ConnectTimeout=8 \
            "$SYNC_HOST:${SYNC_REMOTE_PATH}" "$CONFIG_DIR/machines.txt" 2>/dev/null; then
        echo "  Pulled:    $CONFIG_DIR/machines.txt"
        _sync_pulled_machines=true
    else
        echo "  Warning:   could not reach $SYNC_HOST — will create stub machines.txt"
    fi

    if scp -q -o BatchMode=yes -o ConnectTimeout=8 \
            "$SYNC_HOST:${_rdir}/machine-paths.txt" "$CONFIG_DIR/machine-paths.txt" 2>/dev/null; then
        echo "  Pulled:    $CONFIG_DIR/machine-paths.txt"
        _sync_pulled_paths=true
    fi

    if scp -q -o BatchMode=yes -o ConnectTimeout=8 \
            "$SYNC_HOST:${_rdir}/favorites.txt" "$CONFIG_DIR/favorites.txt" 2>/dev/null; then
        echo "  Pulled:    $CONFIG_DIR/favorites.txt"
        _sync_pulled_favs=true
    fi
fi

# machines.txt — use pulled copy, existing copy, or create stub
if [ -f "$CONFIG_DIR/machines.txt" ] && [ "$_sync_pulled_machines" = false ]; then
    echo "  Skipped:   $CONFIG_DIR/machines.txt (already exists)"
elif [ "$_sync_pulled_machines" = false ]; then
    cat > "$CONFIG_DIR/machines.txt" << 'EOF'
# nickname   user@host-or-ip   [#tag ...]
# Add devices with:   s --add mydevice ati@10.0.0.5 #tag
# Remove with:        s --remove mydevice
# List all:           s --list
test         test@1234
EOF
    echo "  Created:   $CONFIG_DIR/machines.txt  (stub — add your devices with s --add)"
fi

# machine-paths.txt
if [ -f "$CONFIG_DIR/machine-paths.txt" ] && [ "$_sync_pulled_paths" = false ]; then
    echo "  Skipped:   $CONFIG_DIR/machine-paths.txt (already exists)"
elif [ "$_sync_pulled_paths" = false ]; then
    cp "$SCRIPT_DIR/machine-paths.txt" "$CONFIG_DIR/machine-paths.txt" 2>/dev/null || \
        touch "$CONFIG_DIR/machine-paths.txt"
    echo "  Installed: $CONFIG_DIR/machine-paths.txt  (edit to add path aliases)"
fi

# favorites.txt
if [ -f "$CONFIG_DIR/favorites.txt" ] && [ "$_sync_pulled_favs" = false ]; then
    echo "  Skipped:   $CONFIG_DIR/favorites.txt (already exists)"
elif [ "$_sync_pulled_favs" = false ]; then
    cat > "$CONFIG_DIR/favorites.txt" << 'EOF'
# Favorite run commands — alias = full command
# Add with: s --fav docker_restart_mule = docker restart mule
# Run with: s --run <nick> docker_restart_mule
# Tab-complete aliases with: s --run <nick> <TAB>
docker_ps = docker ps
systemctl_status = systemctl status
journalctl_follow = journalctl -f
EOF
    echo "  Installed: $CONFIG_DIR/favorites.txt  (edit to add your own)"
fi

# ── Zsh completion ─────────────────────────────────────────────────────────────
if [[ "$USE_ZSH" == true ]]; then
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

# touch first — a brand-new machine/account may not have a .bashrc yet, and
# without this the whole block below used to be silently skipped, leaving
# the completion file installed but never actually sourced anywhere.
touch "$HOME/.bashrc"

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
offer_fzf

echo ""
echo "Done."
if [[ "$USE_ZSH" == true ]]; then
    echo "  Run: exec zsh    (reload shell to activate completions)"
else
    echo "  Open a new shell tab to activate completions."
fi
echo ""
echo "Then try:"
echo "  s --list"
echo "  s <nickname>"
echo "  s <TAB>"
echo ""
echo "Machine list: $CONFIG_DIR/machines.txt"
