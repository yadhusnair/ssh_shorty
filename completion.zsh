#compdef s

# Load zsh/stat for fast mtime checks (used in cache TTL)
zmodload zsh/stat 2>/dev/null

_ssh_shorty() {
  local -a machines groups subcommands
  local mapfile="$HOME/.config/ssh_shorty/machines.txt"

  machines=(${(f)"$(awk 'NF >= 2 && $1 !~ /^#/ {print $1}' "$mapfile" 2>/dev/null)"})
  groups=(${(f)"$(awk 'NF >= 2 && $1 !~ /^#/ {
    for(i=3;i<=NF;i++) if($i~/^#/) { gsub(/^#/,"@",$i); print $i }
  }' "$mapfile" 2>/dev/null | sort -u)"})

  subcommands=(
    '--list:list all devices'
    '--add:add a new device'
    '--set:update a device IP'
    '--remove:remove a device'
    '--sync:pull/push fleet from SYNC_HOST'
    '--ping:check reachability'
    '--poll:wait until online then connect'
    '--edit:open machines.txt in $EDITOR'
    '--help:show usage'
    '--status:parallel online/offline status table'
    '--watch:live-refreshing fleet status'
    '--run:run command on one or many devices'
    '--close:close ControlMaster socket'
    '--export-ssh-config:write machines.txt to ~/.ssh/config'
    '--keydeploy:deploy SSH key via ssh-copy-id'
    '--last:show last n connections'
    '--import:import from ~/.ssh/config'
  )

  _remote_paths_for() {
    local token="$1"
    local nick="${token%%:*}"
    local partial="${token#*:}"
    local target
    target=$(awk -v n="$nick" '$1 == n {print $2; exit}' "$mapfile" 2>/dev/null)
    [[ -z "$target" ]] && return

    local cache_dir="$HOME/.cache/ssh_shorty"
    local cache_key="${nick}_${partial//\//_}"
    local cache_file="${cache_dir}/${cache_key}"
    local -a paths

    local mtime=0
    zstat -A mtime +mtime "$cache_file" 2>/dev/null
    if [[ -f "$cache_file" ]] && (( EPOCHSECONDS - mtime < 30 )); then
      paths=(${(f)"$(<$cache_file)"})
    else
      mkdir -p "$cache_dir"
      paths=(${(f)"$(ssh -o BatchMode=yes -o ConnectTimeout=3 "$target" \
        "bash -c 'for p in \$(compgen -f -- \"$partial\"); do [ -d \"\$p\" ] && echo \"\$p/\" || echo \"\$p\"; done'" \
        2>/dev/null)"})
      print -l -- "${paths[@]}" > "$cache_file"
    fi

    compadd -f -Q -- "${paths[@]/#/${nick}:}"
  }

  _nick_or_group() {
    if [[ "$PREFIX" == @* ]]; then
      compadd -S ' ' -- "${groups[@]}" '--all'
    else
      compadd -S '' -- "${machines[@]}"
    fi
  }

  local first="${words[2]}"

  if (( CURRENT == 2 )); then
    # Completing the first argument
    if [[ "$PREFIX" == *:* ]]; then
      _remote_paths_for "$PREFIX"
    elif [[ "$PREFIX" == @* ]]; then
      compadd -S '' -- "${groups[@]}"
    elif [[ "$PREFIX" == -* ]]; then
      _describe 'subcommand' subcommands
    else
      compadd -S '' -- "${machines[@]}"
    fi
  else
    # Completing second argument and beyond
    case "$first" in
      --set|--remove|--ping|--poll)
        (( CURRENT == 3 )) && _describe 'machine' machines
        ;;
      --status|--list|--watch)
        (( CURRENT == 3 )) && compadd -S ' ' -- "${groups[@]}"
        ;;
      --run|--keydeploy|--close)
        (( CURRENT == 3 )) && _nick_or_group
        ;;
      --last|--add|--edit|--import|--help|--export-ssh-config)
        ;; # no further completion for these
      *)
        # First arg is a nickname (or local path for rsync push) — not a flag
        if [[ "$PREFIX" == *:* ]]; then
          _remote_paths_for "$PREFIX"
        else
          # Multi-device mode: keep offering nicknames at any depth
          compadd -S '' -- "${machines[@]}"
        fi
        ;;
    esac
  fi
}

_ssh_shorty
