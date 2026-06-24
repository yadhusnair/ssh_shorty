#compdef s

# Load zsh/stat for fast mtime checks (used in cache TTL)
zmodload zsh/stat 2>/dev/null

_ssh_shorty() {
  local -a machines groups tags_raw all_aliases subcommands
  local mapfile="$HOME/.config/ssh_shorty/machines.txt"
  local paths_file="$HOME/.config/ssh_shorty/machine-paths.txt"

  machines=(${(f)"$(awk 'NF >= 2 && $1 !~ /^#/ {print $1}' "$mapfile" 2>/dev/null)"})
  groups=(${(f)"$(awk 'NF >= 2 && $1 !~ /^#/ {
    for(i=3;i<=NF;i++) if($i~/^#/) { gsub(/^#/,"@",$i); print $i }
  }' "$mapfile" 2>/dev/null | sort -u)"})
  # Strip leading '#' — shell treats '#foo' as a comment in completion context;
  # --tag auto-prepends '#' when it receives the plain name.
  tags_raw=(${(f)"$(awk 'NF >= 2 && $1 !~ /^#/ {
    for(i=3;i<=NF;i++) if($i~/^#/) { gsub(/^#/,"",$i); print $i }
  }' "$mapfile" 2>/dev/null | sort -u)"})
  [[ -f "$paths_file" ]] && \
    all_aliases=(${(f)"$(awk 'NF >= 3 && $1 !~ /^#/ { print $2 }' "$paths_file" | sort -u)"})

  subcommands=(
    '-d:download via path alias'
    '--download:download via path alias'
    '-u:upload file/dir to device'
    '--upload:upload file/dir to device'
    '--list:list all devices'
    '--add:add a new device'
    '--set:update a device IP'
    '--remove:remove a device'
    '--tag:add a tag to a device'
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

  # Return alias names defined for a nick's tags
  _aliases_for_nick() {
    local nick="$1"
    [[ ! -f "$paths_file" ]] && return
    local -a tags
    tags=(${(f)"$(awk -v n="$nick" 'NF >= 2 && $1 == n {
      for(i=3;i<=NF;i++) if($i~/^#/) print substr($i,2)
    }' "$mapfile" 2>/dev/null)"})
    for tag in "${tags[@]}"; do
      awk -v t="$tag" 'NF >= 3 && $1 !~ /^#/ && $1 == t { print $2 }' "$paths_file"
    done | sort -u
  }

  _remote_paths_for() {
    local nick="$1" partial="$2"
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

  # For nick:<TAB>: offer aliases first, fall back to remote path completion
  _nick_colon_complete() {
    local token="$1"
    local nick="${token%%:*}"
    local partial="${token#*:}"
    if [[ "$partial" != /* && "$partial" != ~* ]]; then
      local -a nick_aliases
      nick_aliases=(${(f)"$(_aliases_for_nick "$nick")"})
      if (( ${#nick_aliases} > 0 )); then
        compadd -S '' -- "${nick_aliases[@]}"
        return
      fi
    fi
    _remote_paths_for "$nick" "$partial"
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
    if [[ "$PREFIX" == *:* ]]; then
      _nick_colon_complete "$PREFIX"
    elif [[ "$PREFIX" == @* ]]; then
      compadd -S '' -- "${groups[@]}"
    elif [[ "$PREFIX" == -* ]]; then
      _describe 'subcommand' subcommands
    else
      compadd -S '' -- "${machines[@]}"
    fi
  else
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
      -d|--download)
        if (( CURRENT == 3 )); then
          compadd -S ' ' -- "${all_aliases[@]}"
        elif (( CURRENT == 4 )); then
          _describe 'machine' machines
        elif (( CURRENT == 5 )); then
          _files
        fi
        ;;
      -u|--upload)
        if (( CURRENT == 3 )); then
          _files
        elif (( CURRENT == 4 )); then
          if [[ "$PREFIX" == *:* ]]; then
            _nick_colon_complete "$PREFIX"
          else
            compadd -S '' -- "${machines[@]}"
          fi
        fi
        ;;
      --tag)
        if (( CURRENT == 3 )); then
          compadd -S ' ' -- "${machines[@]}"
        elif (( CURRENT == 4 )); then
          compadd -S ' ' -- "${tags_raw[@]}"
        fi
        ;;
      --last|--add|--edit|--import|--help|--export-ssh-config)
        ;;
      *)
        if [[ "$PREFIX" == *:* ]]; then
          _nick_colon_complete "$PREFIX"
        else
          compadd -S '' -- "${machines[@]}"
        fi
        ;;
    esac
  fi
}

_ssh_shorty
