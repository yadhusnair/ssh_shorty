#!/bin/bash

MAPFILE="$HOME/.config/ssh_shorty/machines.txt"
PATHS_FILE="$HOME/.config/ssh_shorty/machine-paths.txt"
CONFIG_DIR="$HOME/.config/ssh_shorty"
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
    printf "  s -u <local-path> <nick>[:<alias|path>]    upload file/dir (alias resolved)\n"
    printf "  s --remove <nickname>                       remove a device\n"
    printf "  s --tag <nickname> <tag>                    add a tag to a device (# auto-added)\n"
    printf "  s --sync                                    pull/push fleet from SYNC_HOST\n"
    printf "  s --ping <nickname>                         check reachability\n"
    printf "  s --poll <nickname>                         wait until online then connect\n"
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
    if scp -q -o BatchMode=yes -o ConnectTimeout=5 \
            "$MAPFILE" "${SYNC_HOST}:${SYNC_REMOTE_PATH}" 2>/dev/null; then
        # Also push machine-paths.txt alongside machines.txt
        [[ -f "$PATHS_FILE" ]] && \
            scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                "$PATHS_FILE" "${SYNC_HOST}:${PATHS_SYNC_REMOTE_PATH}" 2>/dev/null
        # Bump version file so all clients know to pull within 30s
        local ver; ver=$(date +%s)
        ssh -q -o BatchMode=yes -o ConnectTimeout=5 \
            "$SYNC_HOST" "echo $ver > ~/${rdir}/.machines_version" 2>/dev/null
        echo "$ver" > "$CONFIG_DIR/.machines_version" 2>/dev/null
        printf "  ${GREEN}synced${RESET} → %s\n" "$SYNC_HOST"
        touch "$CONFIG_DIR/.last_sync" 2>/dev/null
    fi
    # Push failure is silent — no access or server down; change is saved locally
}

# Push machine-paths.txt only (called after --paths edit)
_sync_push_paths() {
    [[ -z "$SYNC_HOST" ]] && return 0
    [[ ! -f "$PATHS_FILE" ]] && return 0
    local rdir; rdir=$(_sync_remote_dir)
    if scp -q -o BatchMode=yes -o ConnectTimeout=5 \
            "$PATHS_FILE" "${SYNC_HOST}:${PATHS_SYNC_REMOTE_PATH}" 2>/dev/null; then
        local ver; ver=$(date +%s)
        ssh -q -o BatchMode=yes -o ConnectTimeout=5 \
            "$SYNC_HOST" "echo $ver > ~/${rdir}/.machines_version" 2>/dev/null
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
    (
        touch "$stamp" 2>/dev/null
        local tmp_ver; tmp_ver=$(mktemp)
        # Fetch tiny version file — cheap check before pulling the full fleet
        if scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                "${SYNC_HOST}:${rdir}/.machines_version" "$tmp_ver" 2>/dev/null; then
            if ! diff -q "$tmp_ver" "$local_ver" &>/dev/null; then
                # Version changed — pull both files and update local version
                if scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                        "${SYNC_HOST}:${SYNC_REMOTE_PATH}" "$MAPFILE" 2>/dev/null; then
                    scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                        "${SYNC_HOST}:${PATHS_SYNC_REMOTE_PATH}" "$PATHS_FILE" 2>/dev/null
                    cp "$tmp_ver" "$local_ver" 2>/dev/null
                fi
            fi
        else
            # No version file yet — pull unconditionally (first sync or legacy server)
            scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                "${SYNC_HOST}:${SYNC_REMOTE_PATH}" "$MAPFILE" 2>/dev/null
            scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                "${SYNC_HOST}:${PATHS_SYNC_REMOTE_PATH}" "$PATHS_FILE" 2>/dev/null
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
    if [[ "$host" == *.local ]] && command -v getent &>/dev/null; then
        local ip; ip=$(getent hosts "$host" | awk '{print $1}' | head -n1)
        [[ -n "$ip" ]] && { printf '%s%s\n' "$user" "$ip"; return 0; }
    fi
    if [[ -n "$mac" ]] && command -v arp &>/dev/null; then
        local ip; ip=$(arp -n | awk -v m="${mac,,}" 'tolower($0) ~ m {print $1; exit}')
        [[ -n "$ip" ]] && { printf '%s%s\n' "$user" "$ip"; return 0; }
    fi
    printf '%s\n' "$t"
}

# Sets global DEVICE_SSH_OPTS array for nick — reads port= and key= from machines.txt
_load_device_opts() {
    DEVICE_SSH_OPTS=()
    DEVICE_FORWARD=""
    local line
    line=$(awk -v n="$1" '$1 == n {print; exit}' "$MAPFILE" 2>/dev/null)
    for field in $line; do
        case "$field" in
            port=*) DEVICE_SSH_OPTS+=(-p "${field#port=}") ;;
            key=*)  DEVICE_SSH_OPTS+=(-i "${field#key=}") ;;
            forward=*) DEVICE_FORWARD="${field#forward=}" ;;
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
    local TF; TF=$(mktemp)
    "$@" > "$TF" && mv "$TF" "$MAPFILE"
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
            --bind "ctrl-p:execute($0 --ping {1})+clear-query" \
            --bind "ctrl-k:execute($0 --keydeploy {1})+clear-query" \
            --bind "ctrl-s:execute($0 --sysinfo {1})+clear-query" \
            --bind "ctrl-e:execute($0 --edit)+clear-query" \
            2>/dev/null | awk '{print $1}')
        [[ -z "$PICK" ]] && exit 0
        set -- "$PICK"
    else
        usage; exit 1
    fi
fi

# Background pull — keeps fleet in sync without blocking the prompt
_sync_bg

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
        _anim_enabled && spinner_pid=$(_spinner_start "Querying resources for ${#st_nicks[@]} device(s)...")
        tmpdir=$(mktemp -d)
        trap 'rm -rf "$tmpdir"; _show_cursor' EXIT INT TERM
        for i in "${!st_nicks[@]}"; do
            host="${st_targets[$i]#*@}"
            safe="${st_nicks[$i]//\//_}"
            ( ssh "${SSH_CTRL_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=3 "${st_targets[$i]}" \
              "awk '{printf \"%s \",\$1}' /proc/loadavg 2>/dev/null; free | awk '/Mem:/ {printf \"%d%% \", int(\$3/\$2 * 100)}' 2>/dev/null; df -h / | awk 'NR==2 {print \$5}' 2>/dev/null" 2>/dev/null > "$tmpdir/${safe}_sys" && echo online || echo offline ) > "$tmpdir/$safe" &
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

    --tunnel|-t)
        [[ -z "$2" ]] && { printf "Usage: s --tunnel <nick> [local_port:]remote_port\n"; exit 1; }
        _require_mapfile
        NICK="$2"; TARGET=$(_lookup_target "$NICK")
        [[ -z "$TARGET" ]] && { printf "Nickname not found: %s\n" "$NICK"; exit 1; }
        _load_device_opts "$NICK"
        mapping="$3"
        [[ -z "$mapping" ]] && mapping="$DEVICE_FORWARD"
        [[ -z "$mapping" ]] && { printf "No tunnel mapping provided or found in machines.txt for %s.\n" "$NICK"; exit 1; }
        if [[ "$mapping" == -D* ]]; then
            _anim_enabled && _glitch_line "SOCKS Proxy  →  ${NICK} (${mapping#-D })" "${BOLD}${YELLOW}"
            ssh "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" -N -D "${mapping#-D }" "$TARGET"
        else
            local_port="${mapping%:*}"; remote_port="${mapping#*:}"
            [[ "$local_port" == "$remote_port" ]] && remote_port="$local_port"
            _anim_enabled && _glitch_line "Tunneling localhost:${local_port}  →  ${NICK}:${remote_port}" "${BOLD}${YELLOW}"
            ssh "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" -N -L "${local_port}:localhost:${remote_port}" "$TARGET"
        fi
        ;;

    --tail)
        [[ -z "$2" || -z "$3" ]] && { printf "Usage: s --tail <nick> <alias|/path>\n"; exit 1; }
        NICK="$2"; ALIAS="$3"; TARGET=$(_lookup_target "$NICK")
        [[ -z "$TARGET" ]] && { printf "Nickname not found: %s\n" "$NICK"; exit 1; }
        if [[ "$ALIAS" == /* || "$ALIAS" == ~* ]]; then
            REMOTE_PATH="$ALIAS"
        else
            REMOTE_PATH=$(_resolve_alias "$NICK" "$ALIAS") || { printf "Alias '%s' not found for '%s'.\n" "$ALIAS" "$NICK"; exit 1; }
        fi
        _load_device_opts "$NICK"
        _anim_enabled && _glitch_line "Tailing  ${NICK}:${REMOTE_PATH}" "${BOLD}${GREEN}"
        ssh "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" -t "$TARGET" "if [ -d \"$REMOTE_PATH\" ]; then tail -n 100 -f \"$REMOTE_PATH\"/*; else tail -n 100 -f \"$REMOTE_PATH\"; fi"
        ;;

    --run-script)
        [[ -z "$2" || -z "$3" ]] && { printf "Usage: s --run-script <nick|@group|--all> <local_script_path> [args]\n"; exit 1; }
        _require_mapfile
        spec="$2"; script_path="$3"; shift 3
        [[ ! -f "$script_path" ]] && { printf "Script not found: %s\n" "$script_path"; exit 1; }
        run_nicks=(); run_targets=()
        while IFS=' ' read -r nick target; do run_nicks+=("$nick"); run_targets+=("$target"); done < <(_resolve_targets "$spec")
        [[ ${#run_nicks[@]} -eq 0 ]] && { printf "No devices found for: %s\n" "$spec"; exit 1; }
        if [[ ${#run_nicks[@]} -eq 1 ]]; then
            _anim_enabled && _glitch_line "[ ${run_nicks[0]} ]  $script_path" "${CYAN}"
            ssh "${SSH_CTRL_OPTS[@]}" "${run_targets[0]}" 'bash -s' -- "$@" < "$script_path"
        else
            _anim_enabled && _matrix_header "[ BROADCAST SCRIPT ]"
            tmpdir=$(mktemp -d); trap 'rm -rf "$tmpdir"; _show_cursor' EXIT INT TERM
            spinner_pid=""; _anim_enabled && spinner_pid=$(_spinner_start "Transmitting to ${#run_nicks[@]} device(s)...")
            for i in "${!run_nicks[@]}"; do
                safe="${run_nicks[$i]//\//_}"
                ( ssh "${SSH_CTRL_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "${run_targets[$i]}" 'bash -s' -- "$@" < "$script_path" 2>&1 ) > "$tmpdir/$safe.out" &
            done
            wait
            [[ -n "$spinner_pid" ]] && _spinner_stop "$spinner_pid"
            for i in "${!run_nicks[@]}"; do
                safe="${run_nicks[$i]//\//_}"
                printf "\n${CYAN}[%s]${RESET}\n" "${run_nicks[$i]}"
                while IFS= read -r line; do printf "${DIM}  %s${RESET}\n" "$line"; done < "$tmpdir/$safe.out"
            done
            printf "\n"
        fi
        ;;

    --list|-l)
        _require_mapfile
        filter="${2-}"
        printf "${BOLD}  %-24s %-30s %s${RESET}\n" "NICKNAME" "TARGET" "TAGS"
        printf "  %s\n" "$(printf '─%.0s' {1..64})"
        awk -v filter="$filter" -v bold="$BOLD" -v dim="$DIM" -v reset="$RESET" '
            NF < 2 || $1 ~ /^#/ { next }
            {
                if (filter != "" && filter ~ /^@/) {
                    tag = filter; sub(/^@/, "#", tag)
                    found = 0
                    for (i=3; i<=NF; i++) if ($i == tag) { found=1; break }
                    if (!found) next
                }
                tags = ""
                for (i=3; i<=NF; i++) if ($i ~ /^#/) tags = tags " " $i
                printf bold "  %-24s" reset " %-30s" dim " %s" reset "\n", $1, $2, tags
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
                host="${watch_targets[$i]#*@}"
                safe="${watch_nicks[$i]//\//_}"
                ( nc -z -w3 "$host" 22 &>/dev/null && echo online || echo offline ) \
                    > "$watch_tmp/$safe" &
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
            if ssh -o "ControlPath=${SSH_CTRL_DIR}/%h-%p-%r" \
                   -o ControlMaster=no \
                   -O stop "$target" 2>/dev/null; then
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
            spinner_pid=$(_spinner_start "Pinging ${#st_nicks[@]} device(s)...")
        else
            printf "Pinging %d device(s)...\n" "${#st_nicks[@]}"
        fi

        tmpdir=$(mktemp -d)
        trap 'rm -rf "$tmpdir"; _show_cursor' EXIT INT TERM

        for i in "${!st_nicks[@]}"; do
            host="${st_targets[$i]#*@}"
            safe="${st_nicks[$i]//\//_}"
            _load_device_opts "${st_nicks[$i]}"
            resolved_target=$(_apply_mac_resolution "${st_nicks[$i]}" "${st_targets[$i]}")
            host="${resolved_target#*@}"
            
            if [[ $sysinfo -eq 1 ]]; then
                ( 
                    if nc -z -w3 "$host" 22 &>/dev/null; then
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
                ( nc -z -w3 "$host" 22 &>/dev/null && echo online || echo offline ) > "$tmpdir/$safe" &
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
            _load_device_opts "$nick"
            target=$(_apply_mac_resolution "$nick" "$target")
            run_nicks+=("$nick"); run_targets+=("$target")
        done < <(_resolve_targets "$spec")
        
        [[ ${#run_nicks[@]} -eq 0 ]] && { printf "No devices found for: %s\n" "$spec"; exit 1; }
        
        if [[ ${#run_nicks[@]} -eq 1 ]]; then
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
                ( ssh "${SSH_CTRL_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "${run_targets[$i]}" 'bash -s' -- "${local_args[@]}" < "$script_file" 2>&1 ) > "$tmpdir/$safe.out" &
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
        spec="$2"; cmd="$3"

        run_nicks=(); run_targets=()
        while IFS=' ' read -r nick target; do
            run_nicks+=("$nick"); run_targets+=("$target")
        done < <(_resolve_targets "$spec")

        [[ ${#run_nicks[@]} -eq 0 ]] && {
            printf "No devices found for: %s\n" "$spec"; exit 1; }

        if [[ ${#run_nicks[@]} -eq 1 ]]; then
            _anim_enabled && _glitch_line \
                "[ ${run_nicks[0]} ]  $cmd" "${CYAN}"
            ssh "${SSH_CTRL_OPTS[@]}" "${run_targets[0]}" "$cmd"
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
                ( ssh "${SSH_CTRL_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 \
                    "${run_targets[$i]}" "$cmd" 2>&1 ) > "$tmpdir/$safe.out" &
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
        [[ -z "$2" || -z "$3" ]] && {
            printf "Usage: s -d <alias|/path> <nick> [local_dest]\n"; exit 1; }
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
        _load_device_opts "$NICK"
        ssh_cmd="ssh"
        for o in "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}"; do ssh_cmd+=" $o"; done
        _anim_enabled && _glitch_line \
            "Downloading  ${NICK}:${REMOTE_PATH}  →  ${LOCAL_DEST}" "${BOLD}${GREEN}"
        rsync -avP -e "$ssh_cmd" "$TARGET:$REMOTE_PATH" "$LOCAL_DEST"
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
        ssh_cmd="ssh"
        for o in "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}"; do ssh_cmd+=" $o"; done
        _anim_enabled && _glitch_line \
            "Uploading  ${LOCAL_PATH}  →  ${NICK}:${REMOTE_PATH}" "${BOLD}${GREEN}"
        rsync -avP -e "$ssh_cmd" "$LOCAL_PATH" "$TARGET:$REMOTE_PATH"
        ;;

    --add|-a)
        [[ -z "$2" || -z "$3" ]] && {
            printf "Usage: s --add <nickname> <user@ip> [#tag ...]\n"; exit 1; }
        NICK="$2"; TARGET="$3"; shift 3; TAGS="$*"
        if [[ -f "$MAPFILE" ]] && _nick_exists "$NICK"; then
            printf "Nickname '%s' already exists. Use --set to update it.\n" "$NICK"; exit 1
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
        _nick_exists "$NICK" || {
            printf "Nickname '%s' not found. Use --add to add it.\n" "$NICK"; exit 1; }
        _inplace_edit awk -v n="$NICK" -v t="$TARGET" \
            '$1 == n {$2 = t} {print}' "$MAPFILE"
        printf "Updated: %s → %s\n" "$NICK" "$TARGET"
        _sync_push
        ;;

    --remove|-r)
        [[ -z "$2" ]] && { printf "Usage: s --remove <nickname>\n"; exit 1; }
        _require_mapfile
        _nick_exists "$2" || {
            printf "Nickname '%s' not found.\n" "$2"; exit 1; }
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

    --sync)
        if [[ -z "$SYNC_HOST" ]]; then
            printf "SYNC_HOST not configured.\n"
            printf "Add this line to %s/config:\n\n" "$CONFIG_DIR"
            printf "  SYNC_HOST=user@hostname\n\n"
            printf "Then re-run:  s --sync\n"
            exit 1
        fi

        if _anim_enabled; then
            _glitch_line "Fleet sync  ←→  ${SYNC_HOST}" "${DIM}${CYAN}"
        else
            printf "Syncing with %s...\n" "$SYNC_HOST"
        fi

        # Ensure the remote directory exists
        ssh -q -o BatchMode=yes -o ConnectTimeout=10 \
            "$SYNC_HOST" "mkdir -p \$(dirname ~/${SYNC_REMOTE_PATH})" 2>/dev/null

        _sync_rdir=$(_sync_remote_dir)
        # Pull remote → local; if remote has no file yet, push ours as the seed
        if scp -q -o BatchMode=yes -o ConnectTimeout=10 \
                "${SYNC_HOST}:${SYNC_REMOTE_PATH}" "$MAPFILE" 2>/dev/null; then
            printf "  ${GREEN}pulled${RESET}   %s:%s\n" "$SYNC_HOST" "$SYNC_REMOTE_PATH"
            scp -q -o BatchMode=yes -o ConnectTimeout=10 \
                "${SYNC_HOST}:${PATHS_SYNC_REMOTE_PATH}" "$PATHS_FILE" 2>/dev/null \
                && printf "  ${GREEN}pulled${RESET}   %s:%s\n" "$SYNC_HOST" "$PATHS_SYNC_REMOTE_PATH"
            # Grab the remote version file so bg-check knows we're current
            scp -q -o BatchMode=yes -o ConnectTimeout=5 \
                "${SYNC_HOST}:${_sync_rdir}/.machines_version" \
                "$CONFIG_DIR/.machines_version" 2>/dev/null
            touch "$CONFIG_DIR/.last_sync" 2>/dev/null
            printf "  ${DIM}next background check in 30s${RESET}\n"
        else
            # Try to push (seeds remote if it doesn't exist yet)
            if scp -q -o BatchMode=yes -o ConnectTimeout=10 \
                    "$MAPFILE" "${SYNC_HOST}:${SYNC_REMOTE_PATH}" 2>/dev/null; then
                [[ -f "$PATHS_FILE" ]] && \
                    scp -q -o BatchMode=yes -o ConnectTimeout=10 \
                        "$PATHS_FILE" "${SYNC_HOST}:${PATHS_SYNC_REMOTE_PATH}" 2>/dev/null \
                    && printf "  ${GREEN}pushed${RESET}   %s → %s:%s\n" \
                        "$PATHS_FILE" "$SYNC_HOST" "$PATHS_SYNC_REMOTE_PATH"
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
        ;;

    --ping|-p)
        [[ -z "$2" ]] && { printf "Usage: s --ping <nickname>\n"; exit 1; }
        _require_mapfile
        TARGET=$(_lookup_target "$2")
        [[ -z "$TARGET" ]] && {
            printf "Nickname not found: %s\n" "$2"; exit 1; }
        HOST="${TARGET#*@}"
        printf "Pinging %s (%s)... " "$2" "$HOST"
        if ping -c1 -W2 "$HOST" &>/dev/null; then
            printf "${GREEN}reachable${RESET}\n"
        else
            printf "${RED}unreachable${RESET}\n"; exit 1
        fi
        ;;

    --poll)
        [[ -z "$2" ]] && { printf "Usage: s --poll <nickname>\n"; exit 1; }
        _require_mapfile
        _get_single_target "$2" || exit 1
        NICK="$RESOLVED_NICK"; TARGET="$RESOLVED_TARGET"

        _load_device_opts "$NICK"
        TARGET=$(_apply_mac_resolution "$NICK" "$TARGET")
        HOST="${TARGET#*@}"

        if _anim_enabled; then
            _matrix_header "[ WAITING FOR ${NICK^^} ]"
        fi

        _hide_cursor
        trap '_show_cursor; printf "\n"; exit 130' INT TERM

        start_ts=$SECONDS

        while true; do
            # nc check in background so we can animate while waiting
            nc -z -w5 "$HOST" 22 &>/dev/null &
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
        done
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
        exec ssh "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" "$LAST_TARGET"
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
                _glitch_line "Connecting to ${NICK}  →  ${TARGET}" "${DIM}${GREEN}"
            else
                printf "${DIM}Connecting to %s → %s${RESET}\n" "$NICK" "$TARGET"
            fi
            _log_connection "$NICK" "$TARGET"
            ssh "${SSH_CTRL_OPTS[@]}" "${DEVICE_SSH_OPTS[@]}" "$TARGET" "$@"
        fi
        ;;
esac
