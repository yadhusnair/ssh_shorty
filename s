#!/bin/bash
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

VERSION="20260713"
REPO_RAW="https://raw.githubusercontent.com/yadhusnair/ssh_shorty/main"

MAPFILE="$HOME/.config/ssh_shorty/machines.txt"
PATHS_FILE="$HOME/.config/ssh_shorty/machine-paths.txt"
CONFIG_DIR="$HOME/.config/ssh_shorty"
FAVS_FILE="$CONFIG_DIR/favorites.txt"
HISTORY_DIR="$HOME/.local/share/ssh_shorty"
HISTORY_FILE="$HISTORY_DIR/history"
CACHE_DIR="$HOME/.cache/ssh_shorty"
SSH_CTRL_DIR="$HOME/.ssh/ctrl"

# ── Fleet sync config ──────────────────────────────────────────────────────────
# Set SYNC_HOST in ~/.config/ssh_shorty/config to share machines.txt across team
SYNC_HOST=""
SYNC_REMOTE_PATH="validation/machines.txt"
[[ -f "$CONFIG_DIR/config" ]] && source "$CONFIG_DIR/config"
# Derived — always sits next to machines.txt on the remote
PATHS_SYNC_REMOTE_PATH="${SYNC_REMOTE_PATH%/*}/machine-paths.txt"
FAVS_SYNC_REMOTE_PATH="${SYNC_REMOTE_PATH%/*}/favorites.txt"
USERS_SYNC_REMOTE_PATH="${SYNC_REMOTE_PATH%/*}/users.txt"

# User identity for fleet logs — set SHORTY_USER in config, defaults to $USER
SHORTY_USER="${SHORTY_USER:-$USER}"

# Local paths for user registry and access-request queue
USERS_FILE="$CONFIG_DIR/users.txt"
PENDING_REQ_DIR="$CONFIG_DIR/pending_requests"

# Colors
if [[ -t 1 && -z "${NO_COLOR-}" ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    RESET=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' RESET=''
fi

# ── ControlMaster ──────────────────────────────────────────────────────────────
# Reuse existing TCP connections — second connect to the same host is ~instant
mkdir -p "$SSH_CTRL_DIR" 2>/dev/null
SSH_CTRL_OPTS=(-o ControlMaster=auto
               -o "ControlPath=${SSH_CTRL_DIR}/%h-%p-%r"
               -o ControlPersist=10m)

# ── Animation primitives ───────────────────────────────────────────────────────

MCHARS='ｦｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃ01#!@%&*'

_CURSOR_HIDDEN=0
_anim_enabled()  { [[ -t 1 && -z "${NO_COLOR-}" && -z "${NO_ANIM-}" ]]; }
_hide_cursor()   { _CURSOR_HIDDEN=1; printf '\033[?25l'; }
_show_cursor()   { _CURSOR_HIDDEN=0; printf '\033[?25h'; }
_clear_line()   { printf '\033[2K\r'; }
_move_up()      { printf '\033[%dA' "${1:-1}"; }

_rand_char() { printf '%s' "${MCHARS:$(( RANDOM % ${#MCHARS} )):1}"; }

_matrix_header() {
    local title="$1"
    local width=60
    local rain_lines=3
    _hide_cursor
    for (( f=0; f<2; f++ )); do
        for (( r=0; r<rain_lines; r++ )); do
            for (( c=0; c<width; c++ )); do
                if (( RANDOM % 4 == 0 )); then
                    printf "${BOLD}${GREEN}%s${RESET}" "$(_rand_char)"
                else
                    printf "${DIM}${GREEN}%s${RESET}" "$(_rand_char)"
                fi
            done
            printf '\n'
        done
        sleep 0.07
        _move_up "$rain_lines"
        for (( r=0; r<rain_lines; r++ )); do _clear_line; printf '\n'; done
        _move_up "$rain_lines"
    done
    for (( r=0; r<rain_lines; r++ )); do _clear_line; printf '\n'; done
    _move_up "$rain_lines"
    local pad=$(( (width - ${#title}) / 2 ))
    local steps=10
    for (( step=0; step<=steps; step++ )); do
        _clear_line
        printf '%*s' "$pad" ''
        for (( i=0; i<${#title}; i++ )); do
            if (( i < step * ${#title} / steps )); then
                printf "${BOLD}${GREEN}%s${RESET}" "${title:$i:1}"
            else
                printf "${DIM}${GREEN}%s${RESET}" "$(_rand_char)"
            fi
        done
        sleep 0.03
    done
    printf '\n\n'
    _show_cursor
}

_glitch_line() {
    local text="$1"
    local color="${2:-${DIM}${GREEN}}"
    local steps=8
    _hide_cursor
    for (( step=0; step<=steps; step++ )); do
        _clear_line
        for (( i=0; i<${#text}; i++ )); do
            if (( i <= step * ${#text} / steps )); then
                printf "${color}%s${RESET}" "${text:$i:1}"
            else
                printf "${DIM}${GREEN}%s${RESET}" "$(_rand_char)"
            fi
        done
        sleep 0.025
    done
    printf '\n'
    _show_cursor
}

# NOTE: exec >/dev/tty severs the spinner from the $() pipe so the parent shell
# doesn't block waiting for EOF when capturing the PID via spinner_pid=$(...).
_spinner_start() {
    local msg="$1"
    ( exec > /dev/tty 2>/dev/null
      local i=0
      while true; do
          _clear_line
          local bar=""
          for (( j=0; j<12; j++ )); do
              bar+="${MCHARS:$(( (i + j*2) % ${#MCHARS} )):1}"
          done
          printf '%s' "${GREEN}[${bar}]${RESET} ${DIM}${msg}${RESET}"
          i=$(( (i+1) % ${#MCHARS} ))
          sleep 0.055
      done
    ) &
    printf '%d' $!
}

_spinner_stop() {
    kill "$1" 2>/dev/null
    wait "$1" 2>/dev/null
    _clear_line
}

_osc_spin_start() {
    local msg="$1"
    ( exec > /dev/tty 2>/dev/null
      local -a wave=('▁' '▂' '▃' '▄' '▅' '▆' '▇' '█' '▇' '▆' '▅' '▄' '▃' '▂')
      local n=${#wave[@]} w=12 i=0
      while true; do
          _clear_line
          local bar="" j
          for (( j=0; j<w; j++ )); do bar+="${wave[$(( (i+j) % n ))]}"; done
          printf "${CYAN}%s${RESET} ${DIM}%s${RESET}" "$bar" "$msg"
          i=$(( (i+1) % n ))
          sleep 0.07
      done
    ) &
    printf '%d' $!
}

_neon_trace() {
    local text="$1" len j
    len=${#text}
    _hide_cursor
    for (( i=0; i<=len; i++ )); do
        _clear_line
        for (( j=0; j<i; j++ )); do
            if (( i - j <= 3 )); then
                printf $'\033[1;36m%s\033[0m' "${text:$j:1}"
            else
                printf "${GREEN}%s${RESET}" "${text:$j:1}"
            fi
        done
        (( i < len )) && printf $'\033[1;37m%s\033[0m' "${text:$i:1}"
        sleep 0.018
    done
    printf '\n'
    _show_cursor
}

_braille_header() {
    local msg="$1"
    local -a frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local n=${#frames[@]}
    _hide_cursor
    for (( i=0; i<12; i++ )); do
        _clear_line
        printf "${CYAN}%s${RESET} ${DIM}%s${RESET}" "${frames[$(( i % n ))]}" "$msg"
        sleep 0.07
    done
    _clear_line
    printf "${CYAN}⠿${RESET} ${DIM}%s${RESET}\n" "$msg"
    _show_cursor
}

_radar_spin_start() {
    local msg="$1"
    ( exec > /dev/tty 2>/dev/null
      local -a frames=('◌' '○' '◎' '◉' '◎' '○')
      local n=${#frames[@]} i=0
      while true; do
          _clear_line
          printf "${CYAN}%s${RESET}  %s" "${frames[$i]}" "$msg"
          i=$(( (i+1) % n ))
          sleep 0.1
      done
    ) &
    printf '%d' $!
}

_block_header() {
    local msg="$1" w=20 j
    _hide_cursor
    for (( i=0; i<=w; i++ )); do
        _clear_line
        printf "${GREEN}[${RESET}"
        for (( j=0; j<i; j++ )); do printf "${BOLD}${GREEN}█${RESET}"; done
        for (( j=i; j<w; j++ )); do printf "${DIM}░${RESET}"; done
        printf "${GREEN}]${RESET} ${DIM}%s${RESET}" "$msg"
        sleep 0.02
    done
    printf '\n'
    _show_cursor
}

_block_spin_start() {
    local msg="$1"
    ( exec > /dev/tty 2>/dev/null
      local w=20 i=0 j pos
      while true; do
          pos=$(( i % (w * 2) ))
          [[ $pos -ge $w ]] && pos=$(( w * 2 - 1 - pos ))
          _clear_line
          printf "${GREEN}[${RESET}"
          for (( j=0; j<w; j++ )); do
              if (( j == pos )); then printf "${BOLD}${GREEN}█${RESET}"
              elif (( j == pos - 1 || j == pos + 1 )); then printf "${GREEN}▓${RESET}"
              else printf "${DIM}░${RESET}"
              fi
          done
          printf "${GREEN}]${RESET} ${DIM}%s${RESET}" "$msg"
          i=$(( i + 1 ))
          sleep 0.05
      done
    ) &
    printf '%d' $!
}

trap '[[ $_CURSOR_HIDDEN -eq 1 ]] && printf '\''\033[?25h'\''' EXIT INT TERM

# ── Core helpers ───────────────────────────────────────────────────────────────

usage() {
    printf "${BOLD}Usage:${RESET}\n"
    printf "  s                                           pick device interactively (fzf)\n"
    printf "  s <nick> [ssh args]                         connect (prefix match if needed)\n"
    printf "  s <nick1> <nick2> ...                       open each in a tmux window\n"
    printf "  s -m <nick1> <nick2> ...                    tmux synchronized panes\n"
    printf "  s -                                         reconnect to last device\n"
    printf "  s <nickname>:/remote/path [dest]            rsync pull from device\n"
    printf "  s /local/path <nickname>:/remote/           rsync push to device\n"
    printf "\n"
    printf "  s --list [@group]                           list devices\n"
    printf "  s --status [prefix|@group]                  online/offline status\n"
    printf "  s --sysinfo [prefix|@group]                 live resource dashboard\n"
    printf "  s --watch [prefix|@group]                   live-refreshing fleet status\n"
    printf "  s --run <nick|@group|--all> <cmd>           run command on device(s)\n"
    printf "  s --run-script <nick|@group> <file>         run local script remotely\n"
    printf "  s --tail <nick> <alias|/path>               tail a remote file\n"
    printf "  s --tunnel <nick> [local_port:]remote_port  open SSH tunnel\n"
    printf "  s --close <nick|@group|--all>               close ControlMaster socket\n"
    printf "  s --add <nickname> <user@ip> [#tags]        add a device\n"
    printf "  s --set <nickname> <user@ip>                update a device's IP\n"
    printf "  s -d <alias> <nick> [local_dest]            download via path alias\n"
    printf "  s --view <nick> <path>                      stream remote file to local viewer\n"
    printf "  s -u <local-path> <nick>[:<alias|path>]    upload file/dir (alias resolved)\n"
    printf "  s --rename <nickname> <new-name>            rename a device\n"
    printf "  s --remove <nickname>                       remove a device\n"
    printf "  s --tag <nickname> <tag>                    add a tag to a device (# auto-added)\n"
    printf "  s --untag <nickname> <tag>                  remove a tag from a device\n"
    printf "  s --sync                                    pull/push fleet from SYNC_HOST\n"
    printf "  s --ping <nick|@group|prefix|--all>         check reachability\n"
    printf "  s --poll <nickname> [--timeout <sec>]       wait until online then connect\n"
    printf "  s --register [pubkey]                       submit your SSH public key for admin review\n"
    printf "  s --keydeploy <nick|@group>                 deploy SSH key\n"
    printf "  s --export-ssh-config                       write machines.txt → ~/.ssh/config\n"
    printf "  s --import                                  import from ~/.ssh/config\n"
    printf "  s --last [n]                                show last n connections\n"
    printf "  s --edit                                    open machines.txt in \$EDITOR\n"
    printf "  s --paths                                   open machine-paths.txt and sync\n"
    printf "\n"
    printf "  machines.txt extra options: port=N  key=/path/to/key  forward=L:R  mac=00:...\n"
}

# ── Fleet sync helpers ─────────────────────────────────────────────────────────

_sync_remote_dir() { printf '%s' "${SYNC_REMOTE_PATH%/*}"; }

_sync_push() {
    [[ -z "$SYNC_HOST" ]] && return 0
    local rdir; rdir=$(_sync_remote_dir)

    # Pull-before-push: fetch remote, union-merge (add remote nicks absent locally), dedup IPs
    local _spr; _spr=$(mktemp "$CONFIG_DIR/.sync_r.XXXXXX")
    if scp -q -o BatchMode=yes -o ConnectTimeout=5 \
            "${SYNC_HOST}:${SYNC_REMOTE_PATH}" "$_spr" 2>/dev/null && [[ -f "$MAPFILE" ]]; then
        local _spm; _spm=$(mktemp "$CONFIG_DIR/.sync_m.XXXXXX")
        cp "$MAPFILE" "$_spm"
        # Append remote entries whose nick is not in local (preserves peer additions)
        while IFS= read -r _rl; do
            [[ -z "$_rl" || "$_rl" == \#* ]] && continue
            local _rn; _rn=$(printf '%s' "$_rl" | awk '{print $1}')
            [[ -z "$_rn" ]] && continue
            if ! awk -v n="$_rn" '$1==n{found=1;exit}END{exit !found}' "$_spm" 2>/dev/null; then
                printf '%s\n' "$_rl" >> "$_spm"
            fi
        done < "$_spr"
        # Dedup by host — local (first occurrence) wins; strips user@ for comparison
        awk 'NF==0||/^[[:space:]]*#/{print;next}{h=$2;sub(/^[^@]*@/,"",h);if(!seen[h]++)print}' \
            "$_spm" > "$MAPFILE"
        rm -f "$_spm"
    fi
    rm -f "$_spr"

    _dedup_mapfile "$MAPFILE"
    if scp -q -o BatchMode=yes -o ConnectTimeout=5 \
            "$MAPFILE" "${SYNC_HOST}:${SYNC_REMOTE_PATH}" 2>/dev/null; then
        # Also push machine-paths.txt and favorites.txt alongside machines.txt
        [[ -f "$PATHS_FILE" ]] && \
            scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                "$PATHS_FILE" "${SYNC_HOST}:${PATHS_SYNC_REMOTE_PATH}" 2>/dev/null
        [[ -f "$FAVS_FILE" ]] && \
            scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                "$FAVS_FILE" "${SYNC_HOST}:${FAVS_SYNC_REMOTE_PATH}" 2>/dev/null
        [[ -f "$USERS_FILE" ]] && \
            scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                "$USERS_FILE" "${SYNC_HOST}:${USERS_SYNC_REMOTE_PATH}" 2>/dev/null
        # Bump version file so all clients know to pull within 30s
        local ver; ver=$(date +%s)
        printf '%s\n' "$ver" | ssh -q -o BatchMode=yes -o ConnectTimeout=5 \
            "$SYNC_HOST" "cat > ~/${rdir}/.machines_version" 2>/dev/null
        echo "$ver" > "$CONFIG_DIR/.machines_version" 2>/dev/null
        printf "  ${GREEN}synced${RESET} → %s\n" "$SYNC_HOST"
        touch "$CONFIG_DIR/.last_sync" 2>/dev/null
    fi
    # Push failure is silent — no access or server down; change is saved locally
}

# Expand a single-word alias to its full command (returns key unchanged if no match)
_expand_fav() {
    local key="$1"
    [[ "$key" == *' '* || ! -f "$FAVS_FILE" ]] && { printf '%s' "$key"; return; }
    local result
    result=$(awk -v k="$key" 'NF >= 3 && $1 == k && $2 == "=" {
        $1=""; $2=""; gsub(/^ +/, ""); print; exit
    }' "$FAVS_FILE" 2>/dev/null)
    printf '%s' "${result:-$key}"
}

# Push favorites.txt only (called after --fav adds/removes)
_sync_push_favs() {
    [[ -z "$SYNC_HOST" || ! -f "$FAVS_FILE" ]] && return 0
    local rdir; rdir=$(_sync_remote_dir)
    scp -q -o BatchMode=yes -o ConnectTimeout=5 \
        "$FAVS_FILE" "${SYNC_HOST}:${FAVS_SYNC_REMOTE_PATH}" 2>/dev/null && \
        printf "  ${GREEN}synced${RESET} favorites → %s\n" "$SYNC_HOST"
}

# Push machine-paths.txt only (called after --paths edit)
_sync_push_paths() {
    [[ -z "$SYNC_HOST" ]] && return 0
    [[ ! -f "$PATHS_FILE" ]] && return 0
    local rdir; rdir=$(_sync_remote_dir)
    if scp -q -o BatchMode=yes -o ConnectTimeout=5 \
            "$PATHS_FILE" "${SYNC_HOST}:${PATHS_SYNC_REMOTE_PATH}" 2>/dev/null; then
        local ver; ver=$(date +%s)
        printf '%s\n' "$ver" | ssh -q -o BatchMode=yes -o ConnectTimeout=5 \
            "$SYNC_HOST" "cat > ~/${rdir}/.machines_version" 2>/dev/null
        echo "$ver" > "$CONFIG_DIR/.machines_version" 2>/dev/null
        printf "  ${GREEN}synced${RESET} paths → %s\n" "$SYNC_HOST"
        touch "$CONFIG_DIR/.last_sync" 2>/dev/null
    fi
}

# Background version check — fires every 30s; pulls only when fleet actually changed
_sync_bg() {
    [[ -z "$SYNC_HOST" ]] && return
    local stamp="$CONFIG_DIR/.last_sync"
    local age=99999
    [[ -f "$stamp" ]] && age=$(( $(date +%s) - $(stat -c %Y "$stamp" 2>/dev/null || echo 0) ))
    (( age < 30 )) && return
    local rdir; rdir=$(_sync_remote_dir)
    local local_ver="$CONFIG_DIR/.machines_version"
    # Skip if local file was touched more recently than last sync (un-pushed local edit in progress)
    if [[ -f "$MAPFILE" && -f "$stamp" ]]; then
        local _mtime _stime
        _mtime=$(stat -c %Y "$MAPFILE" 2>/dev/null || echo 0)
        _stime=$(stat -c %Y "$stamp"   2>/dev/null || echo 0)
        (( _mtime > _stime )) && return
    fi
    (
        touch "$stamp" 2>/dev/null
        local tmp_ver; tmp_ver=$(mktemp)
        # Fetch tiny version file — cheap check before pulling the full fleet
        if scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                "${SYNC_HOST}:${rdir}/.machines_version" "$tmp_ver" 2>/dev/null; then
            if ! diff -q "$tmp_ver" "$local_ver" &>/dev/null; then
                # Version changed — pull atomically to temp, then move into place + dedup
                local _dl; _dl=$(mktemp "$CONFIG_DIR/.pull.XXXXXX")
                if scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                        "${SYNC_HOST}:${SYNC_REMOTE_PATH}" "$_dl" 2>/dev/null; then
                    mv "$_dl" "$MAPFILE"
                    _dedup_mapfile "$MAPFILE"
                    local _pdl; _pdl=$(mktemp "$CONFIG_DIR/.pull.XXXXXX")
                    scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                        "${SYNC_HOST}:${PATHS_SYNC_REMOTE_PATH}" "$_pdl" 2>/dev/null \
                        && mv "$_pdl" "$PATHS_FILE" || rm -f "$_pdl"
                    local _fdl; _fdl=$(mktemp "$CONFIG_DIR/.pull.XXXXXX")
                    scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                        "${SYNC_HOST}:${FAVS_SYNC_REMOTE_PATH}" "$_fdl" 2>/dev/null \
                        && mv "$_fdl" "$FAVS_FILE" || rm -f "$_fdl"
                    local _udl; _udl=$(mktemp "$CONFIG_DIR/.pull.XXXXXX")
                    scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                        "${SYNC_HOST}:${USERS_SYNC_REMOTE_PATH}" "$_udl" 2>/dev/null \
                        && mv "$_udl" "$USERS_FILE" || rm -f "$_udl"
                    cp "$tmp_ver" "$local_ver" 2>/dev/null
                else
                    rm -f "$_dl"
                fi
            fi
        else
            # No version file yet — pull unconditionally (first sync or legacy server)
            local _dl; _dl=$(mktemp "$CONFIG_DIR/.pull.XXXXXX")
            scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                "${SYNC_HOST}:${SYNC_REMOTE_PATH}" "$_dl" 2>/dev/null \
                && { mv "$_dl" "$MAPFILE"; _dedup_mapfile "$MAPFILE"; } || rm -f "$_dl"
            local _pdl; _pdl=$(mktemp "$CONFIG_DIR/.pull.XXXXXX")
            scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                "${SYNC_HOST}:${PATHS_SYNC_REMOTE_PATH}" "$_pdl" 2>/dev/null \
                && mv "$_pdl" "$PATHS_FILE" || rm -f "$_pdl"
            local _fdl; _fdl=$(mktemp "$CONFIG_DIR/.pull.XXXXXX")
            scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                "${SYNC_HOST}:${FAVS_SYNC_REMOTE_PATH}" "$_fdl" 2>/dev/null \
                && mv "$_fdl" "$FAVS_FILE" || rm -f "$_fdl"
            local _udl; _udl=$(mktemp "$CONFIG_DIR/.pull.XXXXXX")
            scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                "${SYNC_HOST}:${USERS_SYNC_REMOTE_PATH}" "$_udl" 2>/dev/null \
                && mv "$_udl" "$USERS_FILE" || rm -f "$_udl"
        fi
        rm -f "$tmp_ver"
    ) &
    disown $!
}

_require_mapfile() {
    if [[ ! -f "$MAPFILE" ]]; then
        printf "Machine map file not found: %s\n" "$MAPFILE" >&2; exit 1
    fi
}

_nick_exists() {
    awk -v n="$1" '$1 == n {found=1} END {exit !found}' "$MAPFILE"
}

_lookup_target() {
    local n="$1"
    local line; line=$(awk -v n="$n" '$1 == n {print; exit}' "$MAPFILE")
    [[ -z "$line" ]] && return
    local t; t=$(echo "$line" | awk '{print $2}')
    local mac=""
    for field in $line; do
        [[ "$field" == mac=* ]] && mac="${field#mac=}"
    done
    local user="" host="$t"
    if [[ "$t" == *@* ]]; then user="${t%%@*}@"; host="${t#*@}"; fi
    if [[ "$host" == *.local ]]; then
        local ip=""
        if command -v getent &>/dev/null; then
            ip=$(getent hosts "$host" | awk '{print $1}' | head -n1)
        elif command -v dscacheutil &>/dev/null; then
            ip=$(dscacheutil -q host -a name "$host" 2>/dev/null | awk '/ip_address:/{print $2}' | head -n1)
        fi
        [[ -n "$ip" ]] && { printf '%s%s\n' "$user" "$ip"; return 0; }
    fi
    if [[ -n "$mac" ]] && command -v arp &>/dev/null; then
        local ip
        if [[ "$(uname)" == Darwin ]]; then
            ip=$(arp -a 2>/dev/null | awk -v m="${mac,,}" 'tolower($0) ~ m {gsub(/[()]/,"",$2); print $2; exit}')
        else
            ip=$(arp -n 2>/dev/null | awk -v m="${mac,,}" 'tolower($0) ~ m {print $1; exit}')
        fi
        [[ -n "$ip" ]] && { printf '%s%s\n' "$user" "$ip"; return 0; }
    fi
    printf '%s\n' "$t"
}

# Sets global DEVICE_SSH_OPTS array for nick — reads port=, key=, forward= from machines.txt
# forward= supports multiple entries: forward=8080:9090 forward=5432:5432
_load_device_opts() {
    DEVICE_SSH_OPTS=()
    DEVICE_FORWARD=()
    local line
    line=$(awk -v n="$1" '$1 == n {print; exit}' "$MAPFILE" 2>/dev/null)
    for field in $line; do
        case "$field" in
            port=*)    DEVICE_SSH_OPTS+=(-p "${field#port=}") ;;
            key=*)     DEVICE_SSH_OPTS+=(-i "${field#key=}") ;;
            forward=*) DEVICE_SSH_OPTS+=(-L "${field#forward=}")
                       DEVICE_FORWARD+=("${field#forward=}") ;;
        esac
    done
}

# Returns the raw tags (without #) for a nick
_nick_tags() {
    awk -v n="$1" 'NF >= 2 && $1 == n {
        for (i=3; i<=NF; i++) if ($i ~ /^#/) print substr($i, 2)
    }' "$MAPFILE"
}

# Resolves a path alias to its remote path via machine-paths.txt.
# Usage: _resolve_alias <nick> <alias>  → prints path, returns 1 if not found
_resolve_alias() {
    local nick="$1" alias="$2"
    [[ ! -f "$PATHS_FILE" ]] && return 1
    local tag path
    while IFS= read -r tag; do
        path=$(awk -v t="$tag" -v a="$alias" \
            'NF >= 3 && $1 !~ /^#/ && $1 == t && $2 == a { print $3; exit }' "$PATHS_FILE")
        [[ -n "$path" ]] && { printf '%s' "$path"; return 0; }
    done < <(_nick_tags "$nick")
    return 1
}

# Applies mDNS / ARP resolution to a target that may contain a .local hostname or have a
# mac= field in machines.txt. Returns the resolved target (user@ip), or the original if
# no resolution is possible. Safe to call even when _lookup_target already resolved it.
_apply_mac_resolution() {
    local nick="$1" target="$2"
    local user="" host="${target#*@}"
    [[ "$target" == *@* ]] && user="${target%%@*}@"

    # .local mDNS
    if [[ "$host" == *.local ]]; then
        local ip=""
        if command -v getent &>/dev/null; then
            ip=$(getent hosts "$host" | awk '{print $1}' | head -n1)
        elif command -v dscacheutil &>/dev/null; then
            ip=$(dscacheutil -q host -a name "$host" 2>/dev/null | awk '/ip_address:/{print $2}' | head -n1)
        fi
        [[ -n "$ip" ]] && { printf '%s%s\n' "$user" "$ip"; return; }
    fi

    # mac= ARP lookup
    local line mac=""
    line=$(awk -v n="$nick" '$1 == n {print; exit}' "$MAPFILE" 2>/dev/null)
    for field in $line; do
        [[ "$field" == mac=* ]] && mac="${field#mac=}"
    done
    if [[ -n "$mac" ]] && command -v arp &>/dev/null; then
        local ip
        if [[ "$(uname)" == Darwin ]]; then
            ip=$(arp -a 2>/dev/null | awk -v m="${mac,,}" 'tolower($0) ~ m {gsub(/[()]/,"",$2); print $2; exit}')
        else
            ip=$(arp -n 2>/dev/null | awk -v m="${mac,,}" 'tolower($0) ~ m {print $1; exit}')
        fi
        [[ -n "$ip" ]] && { printf '%s%s\n' "$user" "$ip"; return; }
    fi

    printf '%s\n' "$target"
}

# Resolves a single nick (with prefix matching) and sets RESOLVED_NICK / RESOLVED_TARGET.
# Returns 1 (with error message) if the nick is not found or ambiguous.
_get_single_target() {
    local input="$1"
    local nick target
    # Exact match first
    if _nick_exists "$input"; then
        nick="$input"
    else
        # Prefix match — collect ALL matches, error if ambiguous
        local -a matches
        mapfile -t matches < <(awk -v p="$input" \
            'NF >= 2 && $1 !~ /^#/ && substr($1,1,length(p)) == p {print $1}' "$MAPFILE")
        if [[ ${#matches[@]} -eq 0 ]]; then
            printf "Unknown device: %s\n" "$input" >&2
            return 1
        elif [[ ${#matches[@]} -gt 1 ]]; then
            printf "Ambiguous prefix '%s' matches: %s\n" "$input" "${matches[*]}" >&2
            return 1
        fi
        nick="${matches[0]}"
    fi
    target=$(_lookup_target "$nick")
    if [[ -z "$target" ]]; then
        printf "Could not resolve target for: %s\n" "$nick" >&2
        return 1
    fi
    RESOLVED_NICK="$nick"
    RESOLVED_TARGET="$target"
}

_resolve_targets() {
    local spec="$1"
    if [[ "$spec" == "--all" ]]; then
        awk 'NF >= 2 && $1 !~ /^#/ {print $1, $2}' "$MAPFILE"
    elif [[ "$spec" == @* ]]; then
        local tag="#${spec#@}"
        awk -v t="$tag" 'NF >= 2 && $1 !~ /^#/ {
            for (i=3; i<=NF; i++) if ($i == t) { print $1, $2; break }
        }' "$MAPFILE"
    else
        local target; target=$(_lookup_target "$spec")
        if [[ -n "$target" ]]; then
            printf '%s %s\n' "$spec" "$target"
        else
            # Prefix match: "fm" → fm85, fm11, fm12, ...
            awk -v n="${spec,,}" \
                'NF >= 2 && $1 !~ /^#/ && index(tolower($1), n) == 1 {print $1, $2}' \
                "$MAPFILE"
        fi
    fi
}

_inplace_edit() {
    local TF; TF=$(mktemp "$CONFIG_DIR/.edit.XXXXXX")
    if "$@" > "$TF"; then mv "$TF" "$MAPFILE"; else rm -f "$TF"; return 1; fi
}

# Remove entries that share the same host (strips user@) — first occurrence wins
_dedup_mapfile() {
    local file="$1"
    [[ -f "$file" ]] || return
    local TF; TF=$(mktemp "$CONFIG_DIR/.dedup.XXXXXX")
    awk 'NF==0||/^[[:space:]]*#/{print;next}{h=$2;sub(/^[^@]*@/,"",h);if(!seen[h]++)print}' \
        "$file" > "$TF" && mv "$TF" "$file" || rm -f "$TF"
}

# ── User tracking & access control helpers ────────────────────────────────────

_current_user() { printf '%s' "$SHORTY_USER"; }

# Validate an SSH public key with ssh-keygen; returns 0 if valid
_validate_pubkey() {
    ssh-keygen -l -f <(printf '%s\n' "$1") >/dev/null 2>&1
}

# Look up a user's pubkey from users.txt (returns full key string, minus username)
_lookup_pubkey() {
    local username="$1"
    [[ -f "$USERS_FILE" ]] || { printf ""; return; }
    awk -v u="$username" '$1==u{$1="";sub(/^[[:space:]]+/,"");print;exit}' "$USERS_FILE"
}

# Submit this user's SSH public key for admin review.
# Writes to SYNC_HOST:~/validation/pending_keys/USERNAME.key so the admin
# picks it up on the next s --sync and can then run --provide-access.
_register_key() {
    local key="$1"

    # Auto-detect if no key provided
    if [[ -z "$key" ]]; then
        local _found=()
        for _f in "$HOME/.ssh/"id_*.pub "$HOME/.ssh/"*.pub; do
            [[ -f "$_f" ]] && _found+=("$_f")
        done
        if [[ ${#_found[@]} -eq 1 ]]; then
            key=$(cat "${_found[0]}")
            printf "Using key: %s\n" "${_found[0]}"
        elif [[ ${#_found[@]} -gt 1 ]]; then
            printf "Multiple public keys found:\n"
            local i=1
            for _f in "${_found[@]}"; do
                printf "  %d) %s\n" "$i" "$_f"
                (( i++ ))
            done
            printf "Which? [1-%d] " "${#_found[@]}"
            read -r _pick
            _pick=$(( _pick - 1 ))
            [[ $_pick -lt 0 || $_pick -ge ${#_found[@]} ]] && { printf "Invalid choice.\n"; return 1; }
            key=$(cat "${_found[$_pick]}")
        else
            printf "No public key found in ~/.ssh/. Paste your public key: "
            read -r key
        fi
    fi

    [[ -z "$key" ]] && { printf "No key provided.\n"; return 1; }
    _validate_pubkey "$key" || { printf "Invalid SSH public key.\n"; return 1; }

    local rdir; rdir=$(_sync_remote_dir)
    local req_file="${SHORTY_USER}.key"
    local payload; payload=$(printf '%s %s\n' "$SHORTY_USER" "$key")

    if [[ -n "$SYNC_HOST" ]]; then
        ssh -q -o BatchMode=yes -o ConnectTimeout=5 \
            "$SYNC_HOST" "mkdir -p ~/${rdir}/pending_keys" 2>/dev/null
        if printf '%s\n' "$payload" | \
                ssh -q -o BatchMode=yes -o ConnectTimeout=5 \
                "$SYNC_HOST" "cat > ~/${rdir}/pending_keys/${req_file}" 2>/dev/null; then
            printf "Key submitted. The admin will be notified on their next sync.\n"
        else
            printf "${YELLOW}Could not reach sync server.${RESET} Key saved locally.\n"
            mkdir -p "$CONFIG_DIR/pending_keys"
            printf '%s\n' "$payload" > "$CONFIG_DIR/pending_keys/${req_file}"
        fi
    else
        printf "${YELLOW}No SYNC_HOST configured.${RESET} Key saved locally only.\n"
        mkdir -p "$CONFIG_DIR/pending_keys"
        printf '%s\n' "$payload" > "$CONFIG_DIR/pending_keys/${req_file}"
    fi
}

# Push users.txt to SYNC_HOST (silent on failure)
_sync_push_users() {
    [[ -z "$SYNC_HOST" || ! -f "$USERS_FILE" ]] && return 0
    scp -q -o BatchMode=yes -o ConnectTimeout=5 \
        "$USERS_FILE" "${SYNC_HOST}:${USERS_SYNC_REMOTE_PATH}" 2>/dev/null \
        && printf "  ${GREEN}synced${RESET} users → %s\n" "$SYNC_HOST"
}

# Fire-and-forget: append a login entry to the device's ~/.ssh_shorty/userlog.txt
# Uses ControlMaster socket already established by the main SSH connect call
_log_remote_connection() {
    local nick="$1" target="$2"
    local user; user=$(_current_user)
    [[ -z "$user" ]] && return 0
    [[ "$user" =~ ^[a-zA-Z0-9._-]+$ ]] || user="unknown"
    [[ "$nick" =~ ^[a-zA-Z0-9._-]+$ ]] || nick="unknown"
    local ts; ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    # Values expanded locally; single-quoted on the remote side so the shell
    # never re-interprets them. >> is outside the quotes — a real redirect.
    local _cmd="mkdir -p ~/.ssh_shorty 2>/dev/null && printf '%s %s %s\n' '${ts}' '${user}' '${nick}' >> ~/.ssh_shorty/userlog.txt"
    (
        ssh -q -o BatchMode=yes -o ConnectTimeout=5 \
            "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" "$target" \
            "$_cmd" 2>/dev/null
    ) </dev/null >/dev/null 2>&1 &
    disown $!
}

# Submit an access request to SYNC_HOST's pending_requests/ directory
_request_access() {
    local nick="$1"
    local user; user=$(_current_user)
    local ts; ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local req_name="${ts//:/-}_${user}_${nick}.req"
    mkdir -p "$PENDING_REQ_DIR"
    printf '%s %s %s\n' "$ts" "$user" "$nick" > "$PENDING_REQ_DIR/$req_name"
    if [[ -n "$SYNC_HOST" ]]; then
        local rdir; rdir=$(_sync_remote_dir)
        ssh -q -o BatchMode=yes -o ConnectTimeout=5 \
            "$SYNC_HOST" "mkdir -p ~/${rdir}/pending_requests" 2>/dev/null
        if scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                "$PENDING_REQ_DIR/$req_name" \
                "${SYNC_HOST}:${rdir}/pending_requests/${req_name}" 2>/dev/null; then
            printf "${GREEN}Access request sent.${RESET} Admin will be notified.\n"
        else
            printf "${YELLOW}Request saved locally.${RESET} Will sync when server is reachable.\n"
        fi
    else
        printf "${YELLOW}No SYNC_HOST configured.${RESET} Request saved locally.\n"
    fi
}

# Check for pending access requests; print a one-line notice if any exist.
# Throttled to at most one check per 5 minutes; runs in background so it doesn't block.
_check_pending_requests() {
    [[ -z "$SYNC_HOST" ]] && return
    local stamp="$CONFIG_DIR/.pending_check"
    if [[ -f "$stamp" ]]; then
        local _age; _age=$(( $(date +%s) - $(stat -c %Y "$stamp" 2>/dev/null || echo 0) ))
        (( _age < 300 )) && return
    fi
    touch "$stamp" 2>/dev/null
    local rdir; rdir=$(_sync_remote_dir)
    (
        local count
        count=$(ssh -q -o BatchMode=yes -o ConnectTimeout=3 "$SYNC_HOST" \
            "ls ~/${rdir}/pending_requests/*.req 2>/dev/null | wc -l" 2>/dev/null)
        [[ -n "$count" && "$count" -gt 0 ]] && \
            printf "${YELLOW}⚠ %d pending access request(s) — run: s-admin --pending-requests${RESET}\n" \
                "$count" >&2
    ) </dev/null &
    disown $!
}

# Self-update logic — defined as a function so bash reads the entire body into
# memory before install.sh replaces the running script on disk.
_do_update() {
    local remote_ver="$1"
    local _upd_dir _tarball _repo_dir _repo_url
    _upd_dir=$(mktemp -d)
    trap 'rm -rf "$_upd_dir"' EXIT
    _tarball="$_upd_dir/repo.tar.gz"
    _repo_url="https://github.com/yadhusnair/ssh_shorty/archive/refs/heads/main.tar.gz"
    printf "Downloading v%s...\n" "$remote_ver"
    if ! curl -fsSL --max-time 60 "$_repo_url" -o "$_tarball"; then
        printf "Download failed.\n"; return 1
    fi
    if ! tar -xzf "$_tarball" -C "$_upd_dir" 2>/dev/null; then
        printf "Extract failed.\n"; return 1
    fi
    _repo_dir=$(find "$_upd_dir" -maxdepth 1 -type d -name 'ssh_shorty-*' | head -1)
    if [[ -z "$_repo_dir" || ! -f "$_repo_dir/install.sh" ]]; then
        printf "Unexpected archive layout — aborted.\n"; return 1
    fi
    bash "$_repo_dir/install.sh" --update
    # Sync favorites before handing off
    if [[ -n "$SYNC_HOST" ]]; then
        scp -q -o BatchMode=yes -o ConnectTimeout=5 \
            "${SYNC_HOST}:${FAVS_SYNC_REMOTE_PATH}" "$FAVS_FILE" 2>/dev/null \
            && printf "  ${GREEN}✓${RESET} favorites synced from %s\n" "$SYNC_HOST" \
            || true
    fi
    # exec into the newly installed script to print the success message and exit.
    # This replaces this process entirely so bash never reads ;; or esac from the
    # replaced file at a stale byte offset.
    exec "$HOME/.local/bin/s" --finish-update "$remote_ver"
}

# Extract SSH port from DEVICE_SSH_OPTS (defaults to 22)
_get_ssh_port() {
    local j p=22
    for (( j=0; j<${#DEVICE_SSH_OPTS[@]}; j++ )); do
        [[ "${DEVICE_SSH_OPTS[j]}" == "-p" ]] && { p="${DEVICE_SSH_OPTS[j+1]}"; break; }
    done
    printf '%s' "$p"
}

# Throttle background jobs to at most MAX concurrent (default 15)
_throttle() {
    local max="${1:-15}"
    while (( $(jobs -rp 2>/dev/null | wc -l) >= max )); do sleep 0.05; done
}

_log_connection() {
    mkdir -p "$HISTORY_DIR"
    printf '%s %s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" "$2" >> "$HISTORY_FILE"
    if [[ $(wc -l < "$HISTORY_FILE") -gt 1000 ]]; then
        tail -n 1000 "$HISTORY_FILE" > "$HISTORY_FILE.tmp" \
            && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
    fi
}

# Open multiple devices each in its own tmux window or in panes
_tmux_multi() {
    local sync_panes=0
    if [[ "$1" == "-m" ]]; then
        sync_panes=1
        shift
    fi
    local -a nicks=("$@")
    local self; self=$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")

    if [[ "$sync_panes" -eq 1 ]]; then
        if [[ -z "$TMUX" ]]; then
            local session="sshorty_sync_$$"
            tmux new-session -d -s "$session" -n "sync" "$self ${nicks[0]}"
            for (( i=1; i<${#nicks[@]}; i++ )); do
                tmux split-window -t "$session" -h "$self ${nicks[$i]}"
                tmux select-layout -t "$session" tiled
            done
            tmux set-window-option -t "$session" synchronize-panes on
            tmux attach-session -t "$session"
        else
            tmux new-window -n "sync" "$self ${nicks[0]}"
            for (( i=1; i<${#nicks[@]}; i++ )); do
                tmux split-window -h "$self ${nicks[$i]}"
                tmux select-layout tiled
            done
            tmux set-window-option synchronize-panes on
        fi
        return
    fi

    if [[ -n "$TMUX" ]]; then
        for nick in "${nicks[@]}"; do
            tmux new-window -n "$nick" "$self $nick"
        done
        tmux select-window -t "${nicks[0]}" 2>/dev/null
    else
        local session="sshorty_$$"
        tmux new-session -d -s "$session" -n "${nicks[0]}" "$self ${nicks[0]}"
        for (( i=1; i<${#nicks[@]}; i++ )); do
            tmux new-window -t "$session" -n "${nicks[$i]}" "$self ${nicks[$i]}"
        done
        tmux select-window -t "${session}:${nicks[0]}"
        tmux attach-session -t "$session"
    fi
}

_tmux_sync_panes() {
    local -a nicks=("$@")
    local self; self=$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")
    if [[ -n "$TMUX" ]]; then
        tmux new-window -n "sync-${nicks[0]}" "$self ${nicks[0]}"
        for (( i=1; i<${#nicks[@]}; i++ )); do
            tmux split-window -h "$self ${nicks[$i]}"
            tmux select-layout tiled >/dev/null
        done
        tmux set-window-option synchronize-panes on >/dev/null
    else
        local session="sshorty_$$"
        tmux new-session -d -s "$session" -n "sync-${nicks[0]}" "$self ${nicks[0]}"
        for (( i=1; i<${#nicks[@]}; i++ )); do
            tmux split-window -t "$session" -h "$self ${nicks[$i]}"
            tmux select-layout -t "$session" tiled >/dev/null
        done
        tmux set-window-option -t "$session" synchronize-panes on >/dev/null
        tmux attach-session -t "$session"
    fi
}

# ── Update check ──────────────────────────────────────────────────────────────

UPDATE_CACHE="$CONFIG_DIR/.update_check"

_check_update() {
    [[ ! -t 1 ]] && return                        # skip in non-interactive / pipe
    command -v curl &>/dev/null || return          # need curl
    local now ts cached_ver
    now=$(date +%s)
    # If cache is fresh (<24h), just show notification if one is pending
    if [[ -f "$UPDATE_CACHE" ]]; then
        read -r ts cached_ver < "$UPDATE_CACHE" 2>/dev/null
        if (( now - ${ts:-0} < 86400 )); then
            if [[ -n "$cached_ver" && "$cached_ver" > "$VERSION" ]]; then
                printf "${YELLOW}  ↑ update available: %s → %s   run: s --update${RESET}\n\n" "$VERSION" "$cached_ver" >&2
            fi
            return
        fi
    fi
    # Cache stale — fetch remote version in background, write result for next run
    ( remote=$(curl -fsSL --max-time 4 "$REPO_RAW/VERSION" 2>/dev/null | tr -d '[:space:]')
      [[ -n "$remote" ]] && printf '%s %s\n' "$(date +%s)" "$remote" > "$UPDATE_CACHE" ) &
    disown
}

# ── Entry point ────────────────────────────────────────────────────────────────

# No args → fzf device picker (falls back to usage if fzf not installed)
if [[ -z "$1" ]]; then
    _require_mapfile
    if command -v fzf &>/dev/null; then
        PICK=$(awk 'NF >= 2 && $1 !~ /^#/ {
            printf "%-24s  %-30s", $1, $2
            for (i=3; i<=NF; i++) if ($i ~ /^#/) printf "  \033[2m%s\033[0m", $i
            printf "\n"
        }' "$MAPFILE" | \
        fzf --ansi \
            --height=50% \
            --border=rounded \
            --prompt="  connect → " \
            --header="  Enter: connect | Ctrl-P: ping | Ctrl-K: keydeploy | Ctrl-S: sysinfo | Ctrl-E: edit" \
            --color='fg+:bold,gutter:-1' \
            --bind "ctrl-p:execute($SELF --ping {1})+clear-query" \
            --bind "ctrl-k:execute($SELF --keydeploy {1})+clear-query" \
            --bind "ctrl-s:execute($SELF --sysinfo {1})+clear-query" \
            --bind "ctrl-e:execute($SELF --edit)+clear-query" \
            2>/dev/null | awk '{print $1}')
        [[ -z "$PICK" ]] && exit 0
        set -- "$PICK"
    else
        usage; exit 1
    fi
fi

# Dedup machines.txt on every run — cheap awk pass, catches anything that snuck in
_dedup_mapfile "$MAPFILE"

# Background pull — skipped for interactive file-edit commands to avoid clobbering open editor
case "$1" in --edit|--fav) ;; *) _sync_bg ;; esac

# Background admin notification — throttled to once per 5 minutes
_check_pending_requests

# Background update check — notifies on next run if newer version found
_check_update

case "$1" in

    --sysinfo)
        _require_mapfile
        filter="${2-}"
        _anim_enabled && _matrix_header "[ RESOURCE DASHBOARD ]"
        st_nicks=(); st_targets=()
        while IFS=' ' read -r nick target; do
            st_nicks+=("$nick"); st_targets+=("$target")
        done < <(_resolve_targets "${filter:---all}")
        [[ ${#st_nicks[@]} -eq 0 ]] && { printf "No devices found.\n"; exit 0; }
        spinner_pid=""
        _anim_enabled && spinner_pid=$(_osc_spin_start "Querying resources for ${#st_nicks[@]} device(s)...")
        tmpdir=$(mktemp -d)
        trap '[[ -n "$spinner_pid" ]] && { kill "$spinner_pid" 2>/dev/null; wait "$spinner_pid" 2>/dev/null; }; _clear_line; rm -rf "$tmpdir"; _show_cursor' INT TERM
        trap 'rm -rf "$tmpdir"; _show_cursor' EXIT
        for i in "${!st_nicks[@]}"; do
            safe="${st_nicks[$i]//\//_}"
            _load_device_opts "${st_nicks[$i]}"
            _sysinfo_target=$(_apply_mac_resolution "${st_nicks[$i]}" "${st_targets[$i]}")
            _sysinfo_port=$(_get_ssh_port)
            _sysinfo_host="${_sysinfo_target#*@}"
            _throttle 15
            ( trap - EXIT
              mkdir -p "$tmpdir" 2>/dev/null
              if ! nc -z -w3 "$_sysinfo_host" "$_sysinfo_port" &>/dev/null; then
                  echo offline > "$tmpdir/$safe" 2>/dev/null
              else
                  ssh "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=3 "$_sysinfo_target" \
                    "awk '{printf \"%s \",\$1}' /proc/loadavg 2>/dev/null; free | awk '/Mem:/ {printf \"%d%% \", int(\$3/\$2 * 100)}' 2>/dev/null; df -h / | awk 'NR==2 {print \$5}' 2>/dev/null" \
                    2>/dev/null > "$tmpdir/${safe}_sys"
                  if [[ -s "$tmpdir/${safe}_sys" ]]; then
                      echo online > "$tmpdir/$safe" 2>/dev/null
                  else
                      echo offline > "$tmpdir/$safe" 2>/dev/null
                  fi
              fi ) &
        done
        wait
        [[ -n "$spinner_pid" ]] && _spinner_stop "$spinner_pid"
        printf "${BOLD}  %-20s %-30s %-12s %-6s %-5s %s${RESET}\n" "NICKNAME" "TARGET" "STATUS" "LOAD" "RAM" "DISK"
        printf "  %s\n" "$(printf '─%.0s' {1..84})"
        online=0; offline=0
        for i in "${!st_nicks[@]}"; do
            safe="${st_nicks[$i]//\//_}"
            status=$(cat "$tmpdir/$safe" 2>/dev/null)
            if [[ "$status" == online ]]; then
                online=$(( online + 1 ))
                read -r s_load s_ram s_disk < "$tmpdir/${safe}_sys"
                printf "  ${GREEN}%-20s${RESET} %-30s ${GREEN}● online${RESET}    %-6s %-5s %s\n" "${st_nicks[$i]}" "${st_targets[$i]}" "${s_load:---}" "${s_ram:---}" "${s_disk:---}"
            else
                offline=$(( offline + 1 ))
                printf "  ${RED}%-20s${RESET} %-30s ${RED}○ offline${RESET}   --     --    --\n" "${st_nicks[$i]}" "${st_targets[$i]}"
            fi
        done
        printf "\n  ${GREEN}%d online${RESET}  ${RED}%d offline${RESET}\n\n" "$online" "$offline"
        ;;

    --list|-l)
        _require_mapfile
        filter="${2-}"
        printf "${BOLD}  %-24s %-30s %-20s %s${RESET}\n" "NICKNAME" "TARGET" "TAGS" "OPTIONS"
        printf "  %s\n" "$(printf '─%.0s' {1..84})"
        awk -v filter="$filter" -v bold="$BOLD" -v dim="$DIM" -v reset="$RESET" '
            NF < 2 || $1 ~ /^#/ { next }
            {
                if (filter != "" && filter ~ /^@/) {
                    tag = filter; sub(/^@/, "#", tag)
                    found = 0
                    for (i=3; i<=NF; i++) if ($i == tag) { found=1; break }
                    if (!found) next
                }
                tags = ""; opts = ""
                for (i=3; i<=NF; i++) {
                    if ($i ~ /^#/) tags = tags " " $i
                    else opts = opts " " $i
                }
                printf bold "  %-24s" reset " %-30s" dim " %-20s %s" reset "\n", $1, $2, tags, opts
            }
        ' "$MAPFILE" | sort
        ;;

    --watch)
        _require_mapfile
        watch_filter="${2-}"
        watch_interval=5

        trap '_show_cursor; printf "\n"; exit 0' INT TERM
        _hide_cursor

        while true; do
            watch_nicks=(); watch_targets=()
            while IFS=' ' read -r nick target; do
                watch_nicks+=("$nick"); watch_targets+=("$target")
            done < <(_resolve_targets "${watch_filter:---all}")

            [[ ${#watch_nicks[@]} -eq 0 ]] && { printf "No devices found.\n"; exit 0; }

            watch_tmp=$(mktemp -d)
            for i in "${!watch_nicks[@]}"; do
                safe="${watch_nicks[$i]//\//_}"
                _load_device_opts "${watch_nicks[$i]}"
                _watch_target=$(_apply_mac_resolution "${watch_nicks[$i]}" "${watch_targets[$i]}")
                _watch_host="${_watch_target#*@}"
                _watch_port=$(_get_ssh_port)
                _throttle 15
                ( mkdir -p "$watch_tmp" 2>/dev/null
                  if nc -z -w3 "$_watch_host" "$_watch_port" &>/dev/null; then
                      echo online > "$watch_tmp/$safe" 2>/dev/null
                  else
                      echo offline > "$watch_tmp/$safe" 2>/dev/null
                  fi ) &
            done
            wait

            clear
            printf '\n'
            pad=$(( (60 - 17) / 2 ))
            printf '%*s' "$pad" ''
            printf "${BOLD}${GREEN}[ FLEET STATUS ]${RESET}\n\n"
            printf "${BOLD}  %-24s %-30s %s${RESET}\n" "NICKNAME" "TARGET" "STATUS"
            printf "  %s\n" "$(printf '─%.0s' {1..64})"

            watch_online=0; watch_offline=0
            for i in "${!watch_nicks[@]}"; do
                safe="${watch_nicks[$i]//\//_}"
                wstatus=$(cat "$watch_tmp/$safe" 2>/dev/null)
                if [[ "$wstatus" == online ]]; then
                    printf "  ${GREEN}%-24s${RESET} %-30s ${GREEN}● online${RESET}\n" \
                        "${watch_nicks[$i]}" "${watch_targets[$i]}"
                    watch_online=$(( watch_online + 1 ))
                else
                    printf "  ${RED}%-24s${RESET} %-30s ${RED}○ offline${RESET}\n" \
                        "${watch_nicks[$i]}" "${watch_targets[$i]}"
                    watch_offline=$(( watch_offline + 1 ))
                fi
            done

            printf "\n  ${GREEN}%d online${RESET}  ${RED}%d offline${RESET}" \
                "$watch_online" "$watch_offline"
            printf "  ${DIM}│  every ${watch_interval}s  │  Ctrl+C to exit${RESET}\n"

            rm -rf "$watch_tmp"
            sleep "$watch_interval"
        done
        ;;

    --close)
        [[ -z "$2" ]] && { printf "Usage: s --close <nick|@group|--all>\n"; exit 1; }
        _require_mapfile
        while IFS=' ' read -r nick target; do
            _load_device_opts "$nick"
            resolved=$(_apply_mac_resolution "$nick" "$target")
            if ssh "${DEVICE_SSH_OPTS[@]}" \
                   -o "ControlPath=${SSH_CTRL_DIR}/%h-%p-%r" \
                   -o ControlMaster=no \
                   -O stop "$resolved" 2>/dev/null; then
                printf "  ${GREEN}closed${RESET}   %s\n" "$nick"
            else
                printf "  ${DIM}no socket${RESET}  %s\n" "$nick"
            fi
        done < <(_resolve_targets "$2")
        ;;

    --status)
        _require_mapfile
        filter="${2-}"
        sysinfo=0
        if [[ "$filter" == "--sysinfo" ]]; then
            sysinfo=1
            filter="${3-}"
        elif [[ "$3" == "--sysinfo" ]]; then
            sysinfo=1
        fi

        _anim_enabled && _matrix_header "[ FLEET STATUS ]"

        st_nicks=(); st_targets=()
        while IFS=' ' read -r nick target; do
            st_nicks+=("$nick"); st_targets+=("$target")
        done < <(_resolve_targets "${filter:---all}")

        [[ ${#st_nicks[@]} -eq 0 ]] && { printf "No devices found.\n"; exit 0; }

        spinner_pid=""
        if _anim_enabled; then
            spinner_pid=$(_radar_spin_start "Pinging ${#st_nicks[@]} device(s)...")
        else
            printf "Pinging %d device(s)...\n" "${#st_nicks[@]}"
        fi

        tmpdir=$(mktemp -d)
        trap '[[ -n "$spinner_pid" ]] && { kill "$spinner_pid" 2>/dev/null; wait "$spinner_pid" 2>/dev/null; }; _clear_line; rm -rf "$tmpdir"; _show_cursor' INT TERM
        trap 'rm -rf "$tmpdir"; _show_cursor' EXIT

        for i in "${!st_nicks[@]}"; do
            safe="${st_nicks[$i]//\//_}"
            _load_device_opts "${st_nicks[$i]}"
            resolved_target=$(_apply_mac_resolution "${st_nicks[$i]}" "${st_targets[$i]}")
            host="${resolved_target#*@}"
            port=$(_get_ssh_port)
            _throttle 15
            if [[ $sysinfo -eq 1 ]]; then
                ( trap - EXIT
                  if nc -z -w3 "$host" "$port" &>/dev/null; then
                      stats=$(ssh "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=3 "$resolved_target" "top -bn1 2>/dev/null | awk '/[Cc]pu\\(s\\)/ {print \$2 + \$4; exit}' || echo '-'; free -m 2>/dev/null | awk '/Mem:/ {printf \"%d%%\", \$3/\$2 * 100.0; exit}' || echo '-'; df -h / 2>/dev/null | awk 'NR==2 {print \$5}' || echo '-'" 2>/dev/null)
                      if [[ -n "$stats" ]]; then
                          printf "online\n%s\n" "$stats" > "$tmpdir/$safe"
                      else
                          printf "online\nerror\n" > "$tmpdir/$safe"
                      fi
                  else
                      echo "offline" > "$tmpdir/$safe"
                  fi
                ) &
            else
                ( trap - EXIT
                  mkdir -p "$tmpdir" 2>/dev/null
                  if nc -z -w3 "$host" "$port" &>/dev/null; then
                      echo online > "$tmpdir/$safe" 2>/dev/null
                  else
                      echo offline > "$tmpdir/$safe" 2>/dev/null
                  fi ) &
            fi
        done
        wait

        [[ -n "$spinner_pid" ]] && _spinner_stop "$spinner_pid"

        if [[ $sysinfo -eq 1 ]]; then
            printf "${BOLD}  %-24s %-30s %-12s %-10s %-10s %s${RESET}\n" "NICKNAME" "TARGET" "STATUS" "CPU" "RAM" "DISK"
            printf "  %s\n" "$(printf '─%.0s' {1..94})"
        else
            printf "${BOLD}  %-24s %-30s %s${RESET}\n" "NICKNAME" "TARGET" "STATUS"
            printf "  %s\n" "$(printf '─%.0s' {1..64})"
        fi

        online=0; offline=0
        for i in "${!st_nicks[@]}"; do
            safe="${st_nicks[$i]//\//_}"
            status_data=$(cat "$tmpdir/$safe" 2>/dev/null)
            status_line=$(head -n1 <<< "$status_data")
            
            if [[ "$status_line" == online ]]; then
                if [[ $sysinfo -eq 1 ]]; then
                    stats=$(tail -n +2 <<< "$status_data")
                    if [[ "$stats" == "error" || -z "$stats" ]]; then
                        printf "  ${GREEN}%-24s${RESET} %-30s ${GREEN}%-12s${RESET} %-10s %-10s %s\n" "${st_nicks[$i]}" "${st_targets[$i]}" "● online" "-" "-" "-"
                    else
                        cpu=$(echo "$stats" | sed -n '1p')
                        ram=$(echo "$stats" | sed -n '2p')
                        disk=$(echo "$stats" | sed -n '3p')
                        printf "  ${GREEN}%-24s${RESET} %-30s ${GREEN}%-12s${RESET} %-10s %-10s %s\n" "${st_nicks[$i]}" "${st_targets[$i]}" "● online" "${cpu}%" "$ram" "$disk"
                    fi
                else
                    printf "  ${GREEN}%-24s${RESET} %-30s ${GREEN}● online${RESET}\n" \
                        "${st_nicks[$i]}" "${st_targets[$i]}"
                fi
                online=$(( online + 1 ))
            else
                if [[ $sysinfo -eq 1 ]]; then
                    printf "  ${RED}%-24s${RESET} %-30s ${RED}%-12s${RESET} %-10s %-10s %s\n" "${st_nicks[$i]}" "${st_targets[$i]}" "○ offline" "-" "-" "-"
                else
                    printf "  ${RED}%-24s${RESET} %-30s ${RED}○ offline${RESET}\n" \
                        "${st_nicks[$i]}" "${st_targets[$i]}"
                fi
                offline=$(( offline + 1 ))
            fi
        done

        printf "\n  ${GREEN}%d online${RESET}  ${RED}%d offline${RESET}\n\n" \
            "$online" "$offline"
        ;;

    -m|--multi)
        [[ -z "$2" ]] && { printf "Usage: s -m <nick1> [nick2...] or s -m @group\n"; exit 1; }
        _require_mapfile
        shift
        sync_nicks=()
        for arg in "$@"; do
            while IFS=' ' read -r nick target; do
                sync_nicks+=("$nick")
            done < <(_resolve_targets "$arg")
        done
        [[ ${#sync_nicks[@]} -eq 0 ]] && { printf "No devices found.\n"; exit 1; }
        command -v tmux &>/dev/null || {
            printf "${YELLOW}tmux not found${RESET} — install: sudo apt install tmux\n"
            exit 1
        }
        _tmux_sync_panes "${sync_nicks[@]}"
        ;;

    -t|--tunnel)
        [[ -z "$2" || -z "$3" ]] && {
            printf "Usage: s --tunnel <nick> <port|local:remote> (or -D <port> for SOCKS)\n"; exit 1; }
        _require_mapfile
        _get_single_target "$2" || exit 1
        NICK="$RESOLVED_NICK"; TARGET="$RESOLVED_TARGET"
        shift 2
        
        _load_device_opts "$NICK"
        TARGET=$(_apply_mac_resolution "$NICK" "$TARGET")

        local tunnel_opts=()
        if [[ "$1" == "-D" ]]; then
            tunnel_opts=(-D "$2")
            _anim_enabled && _glitch_line "SOCKS Tunnel ${NICK} on port ${2}" "${BOLD}${CYAN}"
        elif [[ "$1" == *:* ]]; then
            tunnel_opts=(-L "$1")
            _anim_enabled && _glitch_line "Forwarding ${NICK} ${1}" "${BOLD}${CYAN}"
        else
            tunnel_opts=(-L "${1}:localhost:${1}")
            _anim_enabled && _glitch_line "Forwarding ${NICK} ${1} ↔ localhost:${1}" "${BOLD}${CYAN}"
        fi
        
        exec ssh "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" "${tunnel_opts[@]}" -N "$TARGET"
        ;;

    --tail)
        [[ -z "$2" || -z "$3" ]] && { printf "Usage: s --tail <nick> <alias_or_path>\n"; exit 1; }
        _require_mapfile
        _get_single_target "$2" || exit 1
        NICK="$RESOLVED_NICK"; TARGET="$RESOLVED_TARGET"
        ALIAS="$3"
        if [[ "$ALIAS" == /* || "$ALIAS" == ~* ]]; then
            REMOTE_PATH="$ALIAS"
        else
            REMOTE_PATH=$(_resolve_alias "$NICK" "$ALIAS") || {
                printf "Alias '%s' not found for '%s'.\n" "$ALIAS" "$NICK"
                exit 1
            }
        fi
        _load_device_opts "$NICK"
        TARGET=$(_apply_mac_resolution "$NICK" "$TARGET")
        _anim_enabled && _glitch_line "Tailing ${NICK}:${REMOTE_PATH}" "${BOLD}${CYAN}"
        exec ssh "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" "$TARGET" "tail -f $REMOTE_PATH"
        ;;

    --run-script)
        [[ -z "$2" || -z "$3" ]] && {
            printf "Usage: s --run-script <nick|@group|--all> <local_script> [args...]\n"; exit 1; }
        _require_mapfile
        spec="$2"; script_file="$3"
        shift 3
        local_args=("$@")
        [[ ! -f "$script_file" ]] && { printf "Script not found: %s\n" "$script_file"; exit 1; }
        
        run_nicks=(); run_targets=()
        while IFS=' ' read -r nick target; do
            run_nicks+=("$nick"); run_targets+=("$target")
        done < <(_resolve_targets "$spec")

        [[ ${#run_nicks[@]} -eq 0 ]] && { printf "No devices found for: %s\n" "$spec"; exit 1; }

        if [[ ${#run_nicks[@]} -eq 1 ]]; then
            _load_device_opts "${run_nicks[0]}"
            run_targets[0]=$(_apply_mac_resolution "${run_nicks[0]}" "${run_targets[0]}")
            _anim_enabled && _glitch_line "[ ${run_nicks[0]} ] Running $script_file" "${CYAN}"
            ssh "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" "${run_targets[0]}" 'bash -s' -- "${local_args[@]}" < "$script_file"
        else
            _anim_enabled && _matrix_header "[ SCRIPT BROADCAST ]"
            tmpdir=$(mktemp -d)
            trap 'rm -rf "$tmpdir"; _show_cursor' EXIT INT TERM
            spinner_pid=""
            _anim_enabled && spinner_pid=$(_spinner_start "Transmitting script to ${#run_nicks[@]} device(s)...")

            for i in "${!run_nicks[@]}"; do
                safe="${run_nicks[$i]//\//_}"
                _throttle 15
                ( _load_device_opts "${run_nicks[$i]}"
                  _t=$(_apply_mac_resolution "${run_nicks[$i]}" "${run_targets[$i]}")
                  ssh "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 \
                    "$_t" 'bash -s' -- "${local_args[@]}" < "$script_file" 2>&1 ) > "$tmpdir/$safe.out" &
            done
            wait
            [[ -n "$spinner_pid" ]] && _spinner_stop "$spinner_pid"
            
            for i in "${!run_nicks[@]}"; do
                safe="${run_nicks[$i]//\//_}"
                printf "\n${CYAN}[%s]${RESET}\n" "${run_nicks[$i]}"
                while IFS= read -r line; do
                    printf "${DIM}  %s${RESET}\n" "$line"
                done < "$tmpdir/$safe.out"
            done
            printf "\n"
        fi
        ;;

    --run)
        [[ -z "$2" || -z "$3" ]] && {
            printf "Usage: s --run <nick|@group|--all> \"cmd\"\n"; exit 1; }
        _require_mapfile
        spec="$2"; shift 2; cmd="$*"
        cmd=$(_expand_fav "$cmd")

        run_nicks=(); run_targets=()
        while IFS=' ' read -r nick target; do
            run_nicks+=("$nick"); run_targets+=("$target")
        done < <(_resolve_targets "$spec")

        [[ ${#run_nicks[@]} -eq 0 ]] && {
            printf "No devices found for: %s\n" "$spec"; exit 1; }

        if [[ "${cmd}" == "--dry-run" || "${2:-}" == "--dry-run" ]]; then
            printf "${BOLD}Dry run — targets that would receive: %s${RESET}\n" "$cmd"
            for i in "${!run_nicks[@]}"; do
                _load_device_opts "${run_nicks[$i]}"
                _dr=$(_apply_mac_resolution "${run_nicks[$i]}" "${run_targets[$i]}")
                _dp=$(_get_ssh_port)
                printf "  %-24s → %s (port %s)\n" "${run_nicks[$i]}" "$_dr" "$_dp"
            done
            exit 0
        fi

        if [[ ${#run_nicks[@]} -eq 1 ]]; then
            _load_device_opts "${run_nicks[0]}"
            run_targets[0]=$(_apply_mac_resolution "${run_nicks[0]}" "${run_targets[0]}")
            _anim_enabled && _glitch_line "[ ${run_nicks[0]} ]  $cmd" "${CYAN}"
            _run_tty_flag=()
            [[ -t 1 ]] && _run_tty_flag=(-t)
            ssh "${_run_tty_flag[@]}" "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" "${run_targets[0]}" "$cmd"
        else
            _anim_enabled && _matrix_header "[ BROADCAST ]"

            tmpdir=$(mktemp -d)
            trap 'rm -rf "$tmpdir"; _show_cursor' EXIT INT TERM

            spinner_pid=""
            _anim_enabled && \
                spinner_pid=$(_spinner_start \
                    "Transmitting to ${#run_nicks[@]} device(s)...")

            for i in "${!run_nicks[@]}"; do
                safe="${run_nicks[$i]//\//_}"
                _throttle 15
                ( _load_device_opts "${run_nicks[$i]}"
                  _t=$(_apply_mac_resolution "${run_nicks[$i]}" "${run_targets[$i]}")
                  ssh "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 \
                    "$_t" "$cmd" 2>&1 ) > "$tmpdir/$safe.out" &
            done
            wait

            [[ -n "$spinner_pid" ]] && _spinner_stop "$spinner_pid"

            for i in "${!run_nicks[@]}"; do
                safe="${run_nicks[$i]//\//_}"
                printf "\n${CYAN}[%s]${RESET}\n" "${run_nicks[$i]}"
                while IFS= read -r line; do
                    printf "${DIM}  %s${RESET}\n" "$line"
                done < "$tmpdir/$safe.out"
            done
            printf "\n"
        fi
        ;;

    -d|--download)
        [[ -z "$2" ]] && {
            printf "Usage: s -d <nick:path> [local_dest]\n"
            printf "       s -d <alias|/path> <nick> [local_dest]\n"; exit 1; }
        if [[ "$2" == *:* ]]; then
            # nick:path syntax — same as top-level rsync pull
            NICK="${2%%:*}"; REMOTE_PATH="${2#*:}"; LOCAL_DEST="${3:-.}"
            TARGET=$(_lookup_target "$NICK")
            [[ -z "$TARGET" ]] && { printf "Nickname not found: %s\n" "$NICK"; exit 1; }
        else
            [[ -z "$3" ]] && {
                printf "Usage: s -d <nick:path> [local_dest]\n"
                printf "       s -d <alias|/path> <nick> [local_dest]\n"; exit 1; }
            ALIAS="$2"; NICK="$3"; LOCAL_DEST="${4:-.}"
            TARGET=$(_lookup_target "$NICK")
            [[ -z "$TARGET" ]] && { printf "Nickname not found: %s\n" "$NICK"; exit 1; }
            if [[ "$ALIAS" == /* || "$ALIAS" == ~* ]]; then
                REMOTE_PATH="$ALIAS"
            else
                REMOTE_PATH=$(_resolve_alias "$NICK" "$ALIAS") || {
                    printf "Alias '%s' not found for '%s' (check machine-paths.txt).\n" "$ALIAS" "$NICK"
                    exit 1
                }
            fi
        fi
        _load_device_opts "$NICK"
        TARGET=$(_apply_mac_resolution "$NICK" "$TARGET")
        ssh_cmd="ssh"
        for o in "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}"; do ssh_cmd+=" $o"; done
        _dl_dest="${LOCAL_DEST}"; [[ "$LOCAL_DEST" == "." ]] && _dl_dest="$(pwd)"
        _anim_enabled && _neon_trace "Downloading  ${NICK}:${REMOTE_PATH}  →  ${_dl_dest}"
        rsync -avP -e "$ssh_cmd" "$TARGET:$REMOTE_PATH" "$LOCAL_DEST"
        ;;

    --view)
        [[ -z "$2" || -z "$3" ]] && {
            printf "Usage: s --view <nick> <remote-path>\n"; exit 1; }
        NICK="$2"; REMOTE_PATH="$3"
        TARGET=$(_lookup_target "$NICK")
        [[ -z "$TARGET" ]] && { printf "Nickname not found: %s\n" "$NICK"; exit 1; }
        _load_device_opts "$NICK"
        TARGET=$(_apply_mac_resolution "$NICK" "$TARGET")

        # Save to ~/Downloads/<nick>-<basename>, with counter if file already exists
        mkdir -p "$HOME/Downloads"
        _vbase="${REMOTE_PATH##*/}"
        _vname="${_vbase%.*}"; _vext="${_vbase##*.}"
        [[ "$_vname" == "$_vbase" ]] && _vext=""   # no extension
        _vdest="$HOME/Downloads/${NICK}-${_vbase}"
        if [[ -f "$_vdest" ]]; then
            _vctr=2
            while [[ -f "$HOME/Downloads/${NICK}-${_vname}-${_vctr}.${_vext}" ]]; do
                (( _vctr++ ))
            done
            _vdest="$HOME/Downloads/${NICK}-${_vname}-${_vctr}.${_vext}"
        fi

        printf "Fetching ${BOLD}%s${RESET}:%s ...\n" "$NICK" "$REMOTE_PATH"
        if ! ssh "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" "$TARGET" \
               "cat $(printf '%q' "$REMOTE_PATH")" > "$_vdest" 2>/dev/null; then
            rm -f "$_vdest"
            printf "${RED}Failed to fetch %s from %s${RESET}\n" "$REMOTE_PATH" "$NICK" >&2
            exit 1
        fi
        printf "Saved:  ${GREEN}%s${RESET}\n" "$_vdest"

        EXT="${_vext,,}"
        _view_opened=false
        case "$EXT" in
            png|jpg|jpeg|gif|bmp|webp|tiff|svg)
                for _v in feh eog gpicview shotwell display; do
                    if command -v "$_v" &>/dev/null; then
                        "$_v" "$_vdest" 2>/dev/null; _view_opened=true; break
                    fi
                done ;;
            mp4|mkv|avi|mov|webm|flv|m4v|wmv)
                for _v in mpv vlc mplayer; do
                    if command -v "$_v" &>/dev/null; then
                        "$_v" "$_vdest" 2>/dev/null; _view_opened=true; break
                    fi
                done ;;
        esac
        if [[ "$_view_opened" == false ]]; then
            if command -v xdg-open &>/dev/null; then
                xdg-open "$_vdest" 2>/dev/null &
            elif command -v open &>/dev/null; then
                open "$_vdest" &
            fi
        fi
        ;;

    -u|--upload)
        [[ -z "$2" || -z "$3" ]] && {
            printf "Usage: s -u <local-path> <nick>[:<alias|path>]\n"; exit 1; }
        LOCAL_PATH="$2"; DEST="$3"
        if [[ "$DEST" == *:* ]]; then
            NICK="${DEST%%:*}"; REMOTE_PATH="${DEST#*:}"
            # Resolve alias if remote path doesn't look like an absolute path
            if [[ "$REMOTE_PATH" != /* && "$REMOTE_PATH" != ~* ]]; then
                RESOLVED=$(_resolve_alias "$NICK" "$REMOTE_PATH") || {
                    printf "Alias '%s' not found for '%s'.\n" "$REMOTE_PATH" "$NICK" >&2
                    printf "Check %s or use an absolute path.\n" "$PATHS_FILE" >&2
                    exit 1
                }
                REMOTE_PATH="$RESOLVED"
            fi
        else
            NICK="$DEST"; REMOTE_PATH="~/"
        fi
        TARGET=$(_lookup_target "$NICK")
        [[ -z "$TARGET" ]] && { printf "Nickname not found: %s\n" "$NICK"; exit 1; }
        _load_device_opts "$NICK"
        TARGET=$(_apply_mac_resolution "$NICK" "$TARGET")
        ssh_cmd="ssh"
        for o in "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}"; do ssh_cmd+=" $o"; done
        _anim_enabled && _neon_trace "Uploading  ${LOCAL_PATH}  →  ${NICK}:${REMOTE_PATH}"
        rsync -avP -e "$ssh_cmd" "$LOCAL_PATH" "$TARGET:$REMOTE_PATH"
        ;;

    --add|-a)
        [[ -z "$2" || -z "$3" ]] && {
            printf "Usage: s --add <nickname> <user@ip> [#tag ...]\n"; exit 1; }
        NICK="$2"; TARGET="$3"; shift 3; TAGS="$*"
        [[ "$TARGET" != *@* ]] && {
            printf "Invalid target '%s' — expected user@host or user@ip.\n" "$TARGET"; exit 1; }
        if [[ -f "$MAPFILE" ]] && _nick_exists "$NICK"; then
            printf "Nickname '%s' already exists. Use --set to update it.\n" "$NICK"; exit 1
        fi
        # Check for duplicate host (strip user@ for comparison so ati@IP == root@IP)
        _add_host="${TARGET#*@}"
        _existing_nick=""
        [[ -f "$MAPFILE" ]] && _existing_nick=$(awk -v h="$_add_host" \
            '{host=$2; sub(/^[^@]*@/,"",host); if(host==h){print $1;exit}}' "$MAPFILE")
        # Also check remote fleet when sync is configured (catches peer additions)
        if [[ -z "$_existing_nick" && -n "$SYNC_HOST" ]]; then
            _add_tmp=$(mktemp "$CONFIG_DIR/.addchk.XXXXXX")
            scp -q -o BatchMode=yes -o ConnectTimeout=3 \
                "${SYNC_HOST}:${SYNC_REMOTE_PATH}" "$_add_tmp" 2>/dev/null \
                && _existing_nick=$(awk -v h="$_add_host" \
                    '{host=$2; sub(/^[^@]*@/,"",host); if(host==h){print $1;exit}}' "$_add_tmp")
            rm -f "$_add_tmp"
        fi
        if [[ -n "$_existing_nick" ]]; then
            if [[ -t 0 ]]; then
                printf "This IP is already assigned to '%s'. SSH into it? [y/N] " "$_existing_nick"
                read -r _add_resp
                [[ "${_add_resp,,}" == "y" ]] && exec "$0" "$_existing_nick"
            else
                printf "IP '%s' is already assigned to '%s'.\n" "$TARGET" "$_existing_nick"
            fi
            exit 1
        fi
        mkdir -p "$(dirname "$MAPFILE")"
        printf '%s %s %s\n' "$NICK" "$TARGET" "$TAGS" >> "$MAPFILE"
        printf "Added: %s → %s %s\n" "$NICK" "$TARGET" "$TAGS"
        _sync_push
        ;;

    --set|-s)
        [[ -z "$2" || -z "$3" ]] && {
            printf "Usage: s --set <nickname> <user@ip>\n"; exit 1; }
        _require_mapfile
        NICK="$2"; TARGET="$3"
        [[ "$TARGET" != *@* ]] && {
            printf "Invalid target '%s' — expected user@host or user@ip.\n" "$TARGET"; exit 1; }
        _nick_exists "$NICK" || {
            printf "Nickname '%s' not found. Use --add to add it.\n" "$NICK"; exit 1; }
        # Block if another nick already owns this host (strip user@ for comparison)
        _set_host="${TARGET#*@}"
        _set_conflict=$(awk -v h="$_set_host" -v n="$NICK" \
            '$1!=n{host=$2;sub(/^[^@]*@/,"",host);if(host==h){print $1;exit}}' "$MAPFILE")
        if [[ -n "$_set_conflict" ]]; then
            printf "IP '%s' is already assigned to '%s'.\n" "$TARGET" "$_set_conflict"; exit 1
        fi
        _inplace_edit awk -v n="$NICK" -v t="$TARGET" \
            '$1 == n {$2 = t} {print}' "$MAPFILE"
        printf "Updated: %s → %s\n" "$NICK" "$TARGET"
        _sync_push
        ;;

    --rename)
        [[ -z "$2" || -z "$3" ]] && {
            printf "Usage: s --rename <old-nickname> <new-nickname>\n"; exit 1; }
        _require_mapfile
        _nick_exists "$2" || {
            printf "Nickname '%s' not found.\n" "$2"; exit 1; }
        _nick_exists "$3" && {
            printf "Nickname '%s' already exists.\n" "$3"; exit 1; }
        _inplace_edit awk -v old="$2" -v new="$3" '$1==old{$1=new}{print}' "$MAPFILE"
        printf "Renamed: %s → %s\n" "$2" "$3"
        _sync_push
        ;;

    --remove|-r)
        [[ -z "$2" ]] && { printf "Usage: s --remove <nickname>\n"; exit 1; }
        _require_mapfile
        _nick_exists "$2" || {
            printf "Nickname '%s' not found.\n" "$2"; exit 1; }
        if [[ -t 0 ]]; then
            printf "Remove '%s' from fleet? [y/N] " "$2"
            read -r _confirm
            [[ ! "$_confirm" =~ ^[Yy]$ ]] && { printf "Aborted.\n"; exit 0; }
        fi
        _inplace_edit awk -v n="$2" '$1 != n' "$MAPFILE"
        printf "Removed: %s\n" "$2"
        _sync_push
        ;;

    --tag)
        [[ -z "$2" || -z "$3" ]] && {
            printf "Usage: s --tag <nickname> #tag\n"; exit 1; }
        _require_mapfile
        NICK="$2"; TAG="$3"
        [[ "$TAG" != "#"* ]] && TAG="#$TAG"
        _nick_exists "$NICK" || {
            printf "Nickname '%s' not found.\n" "$NICK"; exit 1; }
        if awk -v n="$NICK" -v t="$TAG" \
               'NF >= 2 && $1 == n { for (i=3; i<=NF; i++) if ($i == t) { found=1; exit } }
                END { exit !found }' "$MAPFILE"; then
            printf "Tag '%s' already on '%s'.\n" "$TAG" "$NICK"; exit 0
        fi
        _inplace_edit awk -v n="$NICK" -v t="$TAG" \
            '$1 == n { $0 = $0 " " t } { print }' "$MAPFILE"
        printf "Tagged: %s → %s\n" "$NICK" "$TAG"
        _sync_push
        ;;

    --untag)
        [[ -z "$2" || -z "$3" ]] && {
            printf "Usage: s --untag <nickname> <tag>\n"; exit 1; }
        _require_mapfile
        NICK="$2"; TAG="$3"
        [[ "$TAG" != "#"* ]] && TAG="#$TAG"
        _nick_exists "$NICK" || {
            printf "Nickname '%s' not found.\n" "$NICK"; exit 1; }
        _inplace_edit awk -v n="$NICK" -v t="$TAG" \
            '$1 == n { gsub(" "t,""); gsub(t" ","") } { print }' "$MAPFILE"
        printf "Untagged: %s removed %s\n" "$NICK" "$TAG"
        _sync_push
        ;;

    --sync)
        if [[ -z "$SYNC_HOST" ]]; then
            printf "SYNC_HOST not configured.\n"
            printf "Add this line to %s/config:\n\n" "$CONFIG_DIR"
            printf "  SYNC_HOST=user@hostname\n\n"
            printf "Then re-run:  s --sync\n"
            exit 1
        fi

        if _anim_enabled; then
            _braille_header "Fleet sync  ←→  ${SYNC_HOST}"
        else
            printf "Syncing with %s...\n" "$SYNC_HOST"
        fi

        # Ensure the remote directory exists
        ssh -q -o BatchMode=yes -o ConnectTimeout=10 \
            "$SYNC_HOST" "mkdir -p \$(dirname ~/${SYNC_REMOTE_PATH})" 2>/dev/null

        _sync_rdir=$(_sync_remote_dir)
        # Pull remote → local; if remote has no file yet, push ours as the seed
        _sdl=$(mktemp "$CONFIG_DIR/.pull.XXXXXX")
        if scp -q -o BatchMode=yes -o ConnectTimeout=10 \
                "${SYNC_HOST}:${SYNC_REMOTE_PATH}" "$_sdl" 2>/dev/null; then
            mv "$_sdl" "$MAPFILE"; _dedup_mapfile "$MAPFILE"
            printf "  ${GREEN}pulled${RESET}   %s:%s\n" "$SYNC_HOST" "$SYNC_REMOTE_PATH"
            _spdl=$(mktemp "$CONFIG_DIR/.pull.XXXXXX")
            scp -q -o BatchMode=yes -o ConnectTimeout=10 \
                "${SYNC_HOST}:${PATHS_SYNC_REMOTE_PATH}" "$_spdl" 2>/dev/null \
                && { mv "$_spdl" "$PATHS_FILE"; printf "  ${GREEN}pulled${RESET}   %s:%s\n" "$SYNC_HOST" "$PATHS_SYNC_REMOTE_PATH"; } \
                || rm -f "$_spdl"
            _sfdl=$(mktemp "$CONFIG_DIR/.pull.XXXXXX")
            scp -q -o BatchMode=yes -o ConnectTimeout=10 \
                "${SYNC_HOST}:${FAVS_SYNC_REMOTE_PATH}" "$_sfdl" 2>/dev/null \
                && { mv "$_sfdl" "$FAVS_FILE"; printf "  ${GREEN}pulled${RESET}   %s:%s\n" "$SYNC_HOST" "$FAVS_SYNC_REMOTE_PATH"; } \
                || rm -f "$_sfdl"
            _sudl=$(mktemp "$CONFIG_DIR/.pull.XXXXXX")
            scp -q -o BatchMode=yes -o ConnectTimeout=10 \
                "${SYNC_HOST}:${USERS_SYNC_REMOTE_PATH}" "$_sudl" 2>/dev/null \
                && { mv "$_sudl" "$USERS_FILE"; printf "  ${GREEN}pulled${RESET}   %s:%s\n" "$SYNC_HOST" "$USERS_SYNC_REMOTE_PATH"; } \
                || rm -f "$_sudl"
            # Grab the remote version file so bg-check knows we're current
            scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                "${SYNC_HOST}:${_sync_rdir}/.machines_version" \
                "$CONFIG_DIR/.machines_version" 2>/dev/null
            touch "$CONFIG_DIR/.last_sync" 2>/dev/null
            printf "  ${DIM}next background check in 30s${RESET}\n"
        else
            rm -f "$_sdl"
            # Try to push (seeds remote if it doesn't exist yet)
            _dedup_mapfile "$MAPFILE"
            if scp -q -o BatchMode=yes -o ConnectTimeout=10 \
                    "$MAPFILE" "${SYNC_HOST}:${SYNC_REMOTE_PATH}" 2>/dev/null; then
                [[ -f "$PATHS_FILE" ]] && \
                    scp -q -o BatchMode=yes -o ConnectTimeout=10 \
                        "$PATHS_FILE" "${SYNC_HOST}:${PATHS_SYNC_REMOTE_PATH}" 2>/dev/null \
                    && printf "  ${GREEN}pushed${RESET}   %s → %s:%s\n" \
                        "$PATHS_FILE" "$SYNC_HOST" "$PATHS_SYNC_REMOTE_PATH"
                [[ -f "$FAVS_FILE" ]] && \
                    scp -q -o BatchMode=yes -o ConnectTimeout=10 \
                        "$FAVS_FILE" "${SYNC_HOST}:${FAVS_SYNC_REMOTE_PATH}" 2>/dev/null \
                    && printf "  ${GREEN}pushed${RESET}   %s → %s:%s\n" \
                        "$FAVS_FILE" "$SYNC_HOST" "$FAVS_SYNC_REMOTE_PATH"
                [[ -f "$USERS_FILE" ]] && \
                    scp -q -o BatchMode=yes -o ConnectTimeout=10 \
                        "$USERS_FILE" "${SYNC_HOST}:${USERS_SYNC_REMOTE_PATH}" 2>/dev/null \
                    && printf "  ${GREEN}pushed${RESET}   %s → %s:%s\n" \
                        "$USERS_FILE" "$SYNC_HOST" "$USERS_SYNC_REMOTE_PATH"
                # Bump version file so everyone picks it up
                _sync_ver=$(date +%s)
                ssh -q -o BatchMode=yes -o ConnectTimeout=5 \
                    "$SYNC_HOST" "echo $_sync_ver > ~/${_sync_rdir}/.machines_version" 2>/dev/null
                echo "$_sync_ver" > "$CONFIG_DIR/.machines_version" 2>/dev/null
                printf "  ${GREEN}pushed${RESET}   %s → %s:%s\n" \
                    "$MAPFILE" "$SYNC_HOST" "$SYNC_REMOTE_PATH"
                touch "$CONFIG_DIR/.last_sync" 2>/dev/null
                printf "  ${DIM}next background check in 30s${RESET}\n"
            else
                printf "  ${DIM}fleet server unreachable — using local copy${RESET}\n"
            fi
        fi

        # Process any pending key registrations submitted by users via s --register
        _pk_list=$(ssh -q -o BatchMode=yes -o ConnectTimeout=5 "$SYNC_HOST" \
            "ls ~/${_sync_rdir}/pending_keys/*.key 2>/dev/null" 2>/dev/null)
        if [[ -n "$_pk_list" ]]; then
            _pk_any=0
            while IFS= read -r _pkpath; do
                [[ -z "$_pkpath" ]] && continue
                _pkentry=$(ssh -q -o BatchMode=yes -o ConnectTimeout=5 "$SYNC_HOST" \
                    "cat '$_pkpath'" 2>/dev/null)
                [[ -z "$_pkentry" ]] && continue
                _pkuser=$(printf '%s' "$_pkentry" | awk '{print $1}')
                [[ -z "$_pkuser" ]] && continue
                if grep -qE "^${_pkuser}[[:space:]]" "$USERS_FILE" 2>/dev/null; then
                    printf "  ${YELLOW}skip${RESET}     key for '${_pkuser}' already in users.txt\n"
                else
                    touch "$USERS_FILE" 2>/dev/null
                    # Ensure file ends with newline before appending
                    [[ -s "$USERS_FILE" ]] && \
                        [[ "$(tail -c 1 "$USERS_FILE" | wc -l)" -eq 0 ]] && \
                        printf '\n' >> "$USERS_FILE"
                    printf '%s\n' "$_pkentry" >> "$USERS_FILE"
                    printf "  ${GREEN}imported${RESET} key for '${_pkuser}'\n"
                    _pk_any=1
                fi
                ssh -q -o BatchMode=yes -o ConnectTimeout=5 "$SYNC_HOST" \
                    "rm -f '$_pkpath'" 2>/dev/null
            done <<< "$_pk_list"
            [[ $_pk_any -eq 1 ]] && _sync_push_users
        fi
        ;;

    --ping|-p)
        [[ -z "$2" ]] && { printf "Usage: s --ping <nick|@group|prefix|--all>\n"; exit 1; }
        _require_mapfile
        # Collect targets via _resolve_targets (supports nick, @group, prefix, --all)
        declare -a _ping_nicks _ping_targets
        while IFS=' ' read -r _pn _pt; do
            _ping_nicks+=("$_pn"); _ping_targets+=("$_pt")
        done < <(_resolve_targets "$2")
        if [[ ${#_ping_nicks[@]} -eq 0 ]]; then
            printf "No devices found for: %s\n" "$2"; exit 1
        fi
        if [[ ${#_ping_nicks[@]} -eq 1 ]]; then
            _load_device_opts "${_ping_nicks[0]}"
            _pr=$(_apply_mac_resolution "${_ping_nicks[0]}" "${_ping_targets[0]}")
            HOST="${_pr#*@}"
            _pp=$(_get_ssh_port)
            _radar_pid=""
            _anim_enabled && _radar_pid=$(_radar_spin_start "${_ping_nicks[0]}  ${HOST}:${_pp}")
            if nc -z -w2 "$HOST" "$_pp" &>/dev/null; then
                [[ -n "$_radar_pid" ]] && _spinner_stop "$_radar_pid"
                printf "${CYAN}◉${RESET}  %-18s ${DIM}%s:%s${RESET}  ${GREEN}reachable${RESET}\n" \
                    "${_ping_nicks[0]}" "$HOST" "$_pp"
            else
                [[ -n "$_radar_pid" ]] && _spinner_stop "$_radar_pid"
                printf "${CYAN}◌${RESET}  %-18s ${DIM}%s:%s${RESET}  ${RED}unreachable${RESET}\n" \
                    "${_ping_nicks[0]}" "$HOST" "$_pp"
                exit 1
            fi
        else
            printf "Pinging %d device(s)...\n" "${#_ping_nicks[@]}"
            printf "  %-24s %-30s %s\n" "NICKNAME" "TARGET" "STATUS"
            printf "  %s\n" "────────────────────────────────────────────────────────────────"
            for i in "${!_ping_nicks[@]}"; do
                _load_device_opts "${_ping_nicks[$i]}"
                _pr=$(_apply_mac_resolution "${_ping_nicks[$i]}" "${_ping_targets[$i]}")
                _ph="${_pr#*@}"
                _pp=$(_get_ssh_port)
                _throttle 15
                ( if nc -z -w2 "$_ph" "$_pp" &>/dev/null; then
                      printf "  ${GREEN}●${RESET} %-24s %-30s ${GREEN}reachable${RESET}\n" \
                          "${_ping_nicks[$i]}" "${_ping_targets[$i]}"
                  else
                      printf "  ${RED}○${RESET} %-24s %-30s ${RED}unreachable${RESET}\n" \
                          "${_ping_nicks[$i]}" "${_ping_targets[$i]}"
                  fi ) &
            done
            wait
        fi
        ;;

    --poll)
        [[ -z "$2" ]] && { printf "Usage: s --poll <nickname> [--timeout <seconds>]\n"; exit 1; }
        _require_mapfile
        # Parse optional --timeout flag: s --poll fm85 --timeout 60
        _poll_nick="$2"; _poll_timeout=0
        if [[ "${3:-}" == "--timeout" && -n "${4:-}" ]]; then
            _poll_timeout="$4"
        fi
        _get_single_target "$_poll_nick" || exit 1
        NICK="$RESOLVED_NICK"; TARGET="$RESOLVED_TARGET"

        _load_device_opts "$NICK"
        TARGET=$(_apply_mac_resolution "$NICK" "$TARGET")
        HOST="${TARGET#*@}"
        POLL_PORT=$(_get_ssh_port)

        if _anim_enabled; then
            _matrix_header "[ WAITING FOR ${NICK^^} ]"
        fi

        _hide_cursor
        trap '_show_cursor; printf "\n"; exit 130' INT TERM

        start_ts=$SECONDS

        while true; do
            # nc check in background so we can animate while waiting
            nc -z -w5 "$HOST" "$POLL_PORT" &>/dev/null &
            nc_pid=$!

            frame=0
            while kill -0 "$nc_pid" 2>/dev/null; do
                frame=$(( frame + 1 ))
                elapsed=$(( SECONDS - start_ts ))
                if _anim_enabled; then
                    _clear_line
                    bar=""
                    for (( j=0; j<12; j++ )); do
                        bar+="${MCHARS:$(( (frame + j*2) % ${#MCHARS} )):1}"
                    done
                    printf '%s' "${GREEN}[${bar}]${RESET} ${DIM}waiting for${RESET} ${BOLD}${NICK}${RESET}  ${DIM}${HOST}  ${elapsed}s${RESET}"
                fi
                sleep 0.055
            done

            wait "$nc_pid"
            if [[ $? -eq 0 ]]; then
                _clear_line
                _show_cursor
                if _anim_enabled; then
                    _glitch_line "● ${NICK} is online  →  ${TARGET}" "${BOLD}${GREEN}"
                else
                    printf "${GREEN}● %s is online${RESET} → %s\n" "$NICK" "$TARGET"
                fi
                _log_connection "$NICK" "$TARGET"
                exec ssh "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" "$TARGET"
            fi
            # Timeout check (0 = no timeout)
            if [[ $_poll_timeout -gt 0 ]] && (( SECONDS - start_ts >= _poll_timeout )); then
                _clear_line
                _show_cursor
                printf "${RED}✗ Timed out waiting for %s after %ds${RESET}\n" "$NICK" "$_poll_timeout"
                exit 1
            fi
        done
        ;;

    --register)
        _register_key "$2"
        ;;

    --keydeploy)
        [[ -z "$2" ]] && {
            printf "Usage: s --keydeploy <nick|@group>\n"; exit 1; }
        _require_mapfile
        while IFS=' ' read -r nick target; do
            printf "${BOLD}Deploying key → %s${RESET} (%s)\n" "$nick" "$target"
            ssh-copy-id "$target" && \
                printf "  ${GREEN}done${RESET}\n" || \
                printf "  ${RED}failed${RESET}\n"
        done < <(_resolve_targets "$2")
        ;;

    --export-ssh-config)
        _require_mapfile
        sshconfig="$HOME/.ssh/config"
        mkdir -p "$HOME/.ssh"
        touch "$sshconfig"
        chmod 600 "$sshconfig"
        added=0; skipped=0
        while IFS= read -r mapline; do
            [[ -z "$mapline" || "$mapline" =~ ^# ]] && continue
            ex_nick=$(awk '{print $1}' <<< "$mapline")
            ex_target=$(awk '{print $2}' <<< "$mapline")
            ex_user="${ex_target%%@*}"
            ex_host="${ex_target#*@}"
            if grep -qE "^Host[[:space:]]+${ex_nick}([[:space:]]|$)" "$sshconfig" 2>/dev/null; then
                skipped=$(( skipped + 1 )); continue
            fi
            ex_port=""; ex_key=""
            for field in $mapline; do
                case "$field" in
                    port=*) ex_port="${field#port=}" ;;
                    key=*)  ex_key="${field#key=}" ;;
                esac
            done
            {
                printf '\nHost %s\n' "$ex_nick"
                printf '    HostName %s\n' "$ex_host"
                printf '    User %s\n' "$ex_user"
                [[ -n "$ex_port" ]] && printf '    Port %s\n' "$ex_port"
                [[ -n "$ex_key"  ]] && printf '    IdentityFile %s\n' "$ex_key"
            } >> "$sshconfig"
            added=$(( added + 1 ))
        done < "$MAPFILE"
        printf "SSH config updated — added: %d  skipped: %d (already present)\n" \
            "$added" "$skipped"
        printf "Config: %s\n" "$sshconfig"
        ;;

    --import)
        sshconfig="$HOME/.ssh/config"
        [[ ! -f "$sshconfig" ]] && {
            printf "No ~/.ssh/config found.\n"; exit 1; }
        _require_mapfile
        added=0; skipped=0
        current_host=""; current_hostname=""; current_user=""

        _flush_import_entry() {
            [[ -z "$current_host" || -z "$current_hostname" ]] && return
            [[ "$current_host" == *"*"* || "$current_host" == *"?"* ]] && return
            local tgt="${current_user:+${current_user}@}${current_hostname}"
            if _nick_exists "$current_host"; then
                printf "  Skipped (exists): %s\n" "$current_host"
                skipped=$(( skipped + 1 ))
            else
                printf '%s %s\n' "$current_host" "$tgt" >> "$MAPFILE"
                printf "  Added:   %s → %s\n" "$current_host" "$tgt"
                added=$(( added + 1 ))
            fi
            current_host=""; current_hostname=""; current_user=""
        }

        while IFS= read -r line; do
            line="${line#"${line%%[! ]*}"}"
            if [[ "$line" =~ ^Host[[:space:]]+(.+)$ ]]; then
                _flush_import_entry
                current_host="${BASH_REMATCH[1]%% *}"
            elif [[ "$line" =~ ^HostName[[:space:]]+(.+)$ ]]; then
                current_hostname="${BASH_REMATCH[1]%% *}"
            elif [[ "$line" =~ ^User[[:space:]]+(.+)$ ]]; then
                current_user="${BASH_REMATCH[1]%% *}"
            fi
        done < "$sshconfig"
        _flush_import_entry

        printf "\nImport complete — added: %d  skipped: %d\n" "$added" "$skipped"
        ;;

    --last)
        n="${2:-10}"
        [[ ! -f "$HISTORY_FILE" ]] && {
            printf "No connection history yet.\n"; exit 0; }
        printf "${BOLD}  %-20s %-24s %s${RESET}\n" "TIME" "NICKNAME" "TARGET"
        printf "  %s\n" "$(printf '─%.0s' {1..56})"
        tail -n "$n" "$HISTORY_FILE" | \
            awk '{printf "  %-20s %-24s %s\n", $1, $2, $3}'
        ;;

    --edit|-e)
        _require_mapfile; ${EDITOR:-nano} "$MAPFILE"
        ;;

    --paths)
        mkdir -p "$CONFIG_DIR"
        [[ ! -f "$PATHS_FILE" ]] && touch "$PATHS_FILE"
        ${EDITOR:-nano} "$PATHS_FILE"
        _sync_push_paths
        ;;

    --fav)
        mkdir -p "$CONFIG_DIR"
        touch "$FAVS_FILE" 2>/dev/null
        case "${2-}" in
            --list|-l)
                if ! awk 'NF >= 3 && $1 !~ /^#/ && $2 == "="' "$FAVS_FILE" 2>/dev/null | grep -q .; then
                    printf "No favorites saved.\n"
                    printf "Add one: s --fav <alias> = <command>\n"
                    printf "Example: s --fav docker_restart_mule = docker restart mule\n"
                else
                    printf "${BOLD}  %-28s %s${RESET}\n" "ALIAS" "COMMAND"
                    printf "  %s\n" "$(printf '─%.0s' {1..60})"
                    awk 'NF >= 3 && $1 !~ /^#/ && $2 == "=" {
                        a=$1; $1=""; $2=""; gsub(/^ +/, "")
                        printf "  %-28s %s\n", a, $0
                    }' "$FAVS_FILE"
                fi
                ;;
            --edit|-e)
                "${EDITOR:-nano}" "$FAVS_FILE"
                ;;
            --remove)
                [[ -z "${3-}" ]] && { printf "Usage: s --fav --remove <alias>\n"; exit 1; }
                if grep -q "^${3}[[:space:]]*=" "$FAVS_FILE" 2>/dev/null; then
                    grep -v "^${3}[[:space:]]*=" "$FAVS_FILE" > "${FAVS_FILE}.tmp" \
                        && mv "${FAVS_FILE}.tmp" "$FAVS_FILE"
                    printf "Removed: %s\n" "$3"
                    _sync_push_favs
                else
                    printf "Alias not found: %s\n" "$3"; exit 1
                fi
                ;;
            "")
                printf "Usage:\n"
                printf "  s --fav <alias> = <command>     # save a favorite\n"
                printf "  s --fav --list                  # list all favorites\n"
                printf "  s --fav --remove <alias>        # remove a favorite\n"
                printf "  s --fav --edit                  # open in \$EDITOR\n"
                printf "\nExample:\n"
                printf "  s --fav docker_restart_mule = docker restart mule\n"
                printf "  s --run fm85 docker_restart_mule\n"
                ;;
            *)
                # s --fav docker_restart_mule = docker restart mule
                if [[ "${3-}" == "=" && -n "${4-}" ]]; then
                    _fav_alias="$2"; shift 3; _fav_cmd="$*"
                    if grep -q "^${_fav_alias}[[:space:]]*=" "$FAVS_FILE" 2>/dev/null; then
                        grep -v "^${_fav_alias}[[:space:]]*=" "$FAVS_FILE" > "${FAVS_FILE}.tmp"
                        printf '%s = %s\n' "$_fav_alias" "$_fav_cmd" >> "${FAVS_FILE}.tmp"
                        mv "${FAVS_FILE}.tmp" "$FAVS_FILE"
                        printf "${YELLOW}Updated:${RESET} %s = %s\n" "$_fav_alias" "$_fav_cmd"
                    else
                        printf '%s = %s\n' "$_fav_alias" "$_fav_cmd" >> "$FAVS_FILE"
                        printf "${GREEN}Saved:${RESET} %s = %s\n" "$_fav_alias" "$_fav_cmd"
                    fi
                    _sync_push_favs
                else
                    printf "Usage: s --fav <alias> = <command>\n"
                    printf "Example: s --fav docker_restart_mule = docker restart mule\n"
                fi
                ;;
        esac
        ;;

    --update)
        command -v curl &>/dev/null || { printf "curl is required for updates.\n"; exit 1; }
        printf "Checking for updates (current: %s)...\n" "$VERSION"
        remote_ver=$(curl -fsSL --max-time 8 "$REPO_RAW/VERSION" 2>/dev/null | tr -d '[:space:]')
        if [[ -z "$remote_ver" ]]; then
            printf "Could not reach update server. Check your connection.\n"; exit 1
        fi
        if [[ "$remote_ver" == "$VERSION" || ! "$remote_ver" > "$VERSION" ]]; then
            printf "Already up to date (v%s).\n" "$VERSION"
            printf '%s %s\n' "$(date +%s)" "$remote_ver" > "$UPDATE_CACHE"
            exit 0
        fi
        printf "\n  Current : %s\n  Latest  : ${GREEN}%s${RESET}\n\n" "$VERSION" "$remote_ver"
        printf "Update? [Y/n] "
        read -r _upd_resp
        [[ "$_upd_resp" =~ ^[Nn] ]] && { printf "Aborted.\n"; exit 0; }

        _do_update "$remote_ver"
        ;;

    --help|-h)
        usage
        ;;

    -)
        # Reconnect to last device — like `cd -` but for SSH
        [[ ! -f "$HISTORY_FILE" ]] && { printf "No connection history yet.\n"; exit 1; }
        LAST_NICK=$(tail -n1 "$HISTORY_FILE" | awk '{print $2}')
        LAST_TARGET=$(tail -n1 "$HISTORY_FILE" | awk '{print $3}')
        [[ -z "$LAST_NICK" ]] && { printf "No connection history yet.\n"; exit 1; }
        _load_device_opts "$LAST_NICK"
        LAST_TARGET=$(_apply_mac_resolution "$LAST_NICK" "$LAST_TARGET")

        if _anim_enabled; then
            _glitch_line "↩  ${LAST_NICK}  →  ${LAST_TARGET}" "${DIM}${GREEN}"
        else
            printf "${DIM}↩  %s → %s${RESET}\n" "$LAST_NICK" "$LAST_TARGET"
        fi
        _log_connection "$LAST_NICK" "$LAST_TARGET"
        shift  # drop the '-' arg so remaining args are extra ssh flags
        exec ssh "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" "$LAST_TARGET" "$@"
        ;;

    --finish-update)
        _fuver="$2"
        [[ -n "$_fuver" ]] && {
            printf '%s %s\n' "$(date +%s)" "$_fuver" > "$UPDATE_CACHE"
            printf "\n${GREEN}✓ Updated to v%s${RESET} — open a new shell tab to activate new completions\n" "$_fuver"
        }
        exit 0
        ;;

    -*)
        printf "Unknown option: %s\n" "$1"; usage; exit 1
        ;;

    *)
        _require_mapfile

        # Multi-device: s fm85 fm11 fm12 — if $2 is also a known nick, go tmux
        if [[ $# -ge 2 && "$2" != -* && "$2" != *:* ]] && \
           _nick_exists "$2" 2>/dev/null; then
            multi_nicks=()
            for arg in "$@"; do
                [[ "$arg" == -* || "$arg" == *:* ]] && break
                multi_nicks+=("$arg")
            done
            if [[ ${#multi_nicks[@]} -ge 2 ]]; then
                command -v tmux &>/dev/null || {
                    printf "${YELLOW}tmux not found${RESET} — install: sudo apt install tmux\n"
                    exit 1
                }
                _tmux_multi "${multi_nicks[@]}"
                exit 0
            fi
        fi

        # rsync pull: nick:/path [dest]
        if [[ "$1" == *:* ]]; then
            NICK="${1%%:*}"; REMOTE_PATH="${1#*:}"; LOCAL_DEST="${2:-.}"
            TARGET=$(_lookup_target "$NICK")
            [[ -z "$TARGET" ]] && { printf "Nickname not found: %s\n" "$NICK"; exit 1; }
            _load_device_opts "$NICK"
            TARGET=$(_apply_mac_resolution "$NICK" "$TARGET")
            ssh_cmd="ssh"
            for o in "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}"; do ssh_cmd+=" $o"; done
            _anim_enabled && _glitch_line \
                "Pulling  ${NICK}:${REMOTE_PATH}  →  ${LOCAL_DEST}" "${BOLD}${GREEN}"
            rsync -avP -e "$ssh_cmd" "$TARGET:$REMOTE_PATH" "$LOCAL_DEST"

        # rsync push: /local nick:/path
        elif [[ "$2" == *:* ]]; then
            LOCAL_PATH="$1"; NICK="${2%%:*}"; REMOTE_PATH="${2#*:}"
            TARGET=$(_lookup_target "$NICK")
            [[ -z "$TARGET" ]] && { printf "Nickname not found: %s\n" "$NICK"; exit 1; }
            _load_device_opts "$NICK"
            TARGET=$(_apply_mac_resolution "$NICK" "$TARGET")
            ssh_cmd="ssh"
            for o in "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}"; do ssh_cmd+=" $o"; done
            _anim_enabled && _glitch_line \
                "Pushing  ${LOCAL_PATH}  →  ${NICK}:${REMOTE_PATH}" "${BOLD}${GREEN}"
            rsync -avP -e "$ssh_cmd" "$LOCAL_PATH" "$TARGET:$REMOTE_PATH"

        # SSH: nick [extra ssh args]
        else
            _get_single_target "$1" || exit 1
            NICK="$RESOLVED_NICK"; TARGET="$RESOLVED_TARGET"
            shift

            _load_device_opts "$NICK"
            TARGET=$(_apply_mac_resolution "$NICK" "$TARGET")
            
            if _anim_enabled; then
                _neon_trace "Connecting to ${NICK}  →  ${TARGET}"
            else
                printf "${DIM}Connecting to %s → %s${RESET}\n" "$NICK" "$TARGET"
            fi
            _log_connection "$NICK" "$TARGET"
            # BatchMode pre-check: detects missing key access before SSH can fall
            # through to a password prompt. On success, also seeds the ControlMaster
            # socket so the real connect below is near-instant.
            _pc_err=$(mktemp "$CONFIG_DIR/.ssherr.XXXXXX")
            if ! ssh -o BatchMode=yes -o ConnectTimeout=5 \
                    "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" "$TARGET" true \
                    2>"$_pc_err"; then
                if grep -qi "permission denied" "$_pc_err" 2>/dev/null; then
                    rm -f "$_pc_err"
                    printf "\n${YELLOW}No key access to '%s'.${RESET}\n" "$NICK"
                    if [[ -t 0 ]]; then
                        printf "Request access from admin? [y/N] "
                        read -r _acc_resp
                        if [[ "${_acc_resp,,}" == "y" ]]; then
                            _request_access "$NICK"
                        fi
                    fi
                    exit 1
                fi
            fi
            rm -f "$_pc_err"
            _log_remote_connection "$NICK" "$TARGET"
            exec ssh "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" "$TARGET" "$@"
        fi
        ;;
esac
