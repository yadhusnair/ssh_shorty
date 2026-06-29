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
    '--paths:open machine-paths.txt and sync'
    '--help:show usage'
    '--update:check for and apply updates'
    '--fav:save/list/remove favorite run commands'
    '--status:parallel online/offline status table'
    '--watch:live-refreshing fleet status'
    '--sysinfo:live resource dashboard'
    '--run:run command on one or many devices'
    '--run-script:run local script remotely'
    '--tail:tail a remote log using alias'
    '--tunnel:open SSH tunnel'
    '-t:open SSH tunnel'
    '-m:tmux synchronized panes'
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

  # Called after compset -P '*:' has moved 'nick:' into IPREFIX.
  # Adds bare paths so zsh matches them against just the partial.
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

    compadd -f -Q -S '' -- "${paths[@]}"
  }

  # For nick:<TAB>: strip 'nick:' from PREFIX via compset so bare alias/path
  # names are matched against just the partial after the colon.
  _nick_colon_complete() {
    local token="$1"
    local nick="${token%%:*}"
    local partial="${token#*:}"

    # Move 'nick:' into IPREFIX so completions match only the path/alias part
    compset -P '*:'

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
      --set|--remove|--tunnel|-t)
        (( CURRENT == 3 )) && _describe 'machine' machines
        ;;
      --ping)
        if (( CURRENT == 3 )); then
          if [[ "$PREFIX" == @* ]]; then
            compadd -S ' ' -- "${groups[@]}" '--all'
          else
            compadd -S ' ' -- "${machines[@]}"
            compadd -S ' ' -- "${groups[@]}"
          fi
        fi
        ;;
      --poll|-p)
        (( CURRENT == 3 )) && _describe 'machine' machines
        ;;
      --status|--list|--watch|--sysinfo)
        (( CURRENT == 3 )) && compadd -S ' ' -- "${groups[@]}"
        ;;
      --run|--keydeploy|--close|-m)
        (( CURRENT == 3 )) && _nick_or_group
        if [[ "$first" == "--run" ]] && (( CURRENT == 4 )); then
          local favs_file="$HOME/.config/ssh_shorty/favorites.txt"
          local -a fav_aliases=()
          [[ -f "$favs_file" ]] && fav_aliases=(${(f)"$(awk 'NF>=3 && $2=="=" && $1!~/^#/{print $1}' "$favs_file" 2>/dev/null)"})
          local -a matches=(${(M)fav_aliases:#${PREFIX}*})
          if (( ${#matches} > 0 )); then
            compadd -S ' ' -- "${matches[@]}"
          else
            # No alias match — offer "" so user can type a one-off command
            compadd -Q -U -P '"' -S '"' -- ""
          fi
        fi
        ;;
      --run-script)
        if (( CURRENT == 3 )); then
          _nick_or_group
        elif (( CURRENT == 4 )); then
          _files
        fi
        ;;
      --tail)
        if (( CURRENT == 3 )); then
          _describe 'machine' machines
        elif (( CURRENT == 4 )); then
          local -a nick_aliases
          nick_aliases=(${(f)"$(_aliases_for_nick "${words[3]}")"})
          compadd -S '' -- "${nick_aliases[@]}"
        fi
        ;;
      -d|--download)
        if (( CURRENT == 3 )); then
          if [[ "$PREFIX" == *:* ]]; then
            _nick_colon_complete "$PREFIX"
          else
            # offer both machine names (with : suffix) and path aliases
            compadd -S ':' -- "${machines[@]}"
            compadd -S ' ' -- "${all_aliases[@]}"
          fi
        elif (( CURRENT == 4 )); then
          local _prev="${words[3]}"
          if [[ "$_prev" == *:* ]]; then
            _files
          else
            _describe 'machine' machines
          fi
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
      --fav)
        local _ffile="$HOME/.config/ssh_shorty/favorites.txt"
        local -a _faliases=()
        [[ -f "$_ffile" ]] && _faliases=(${(f)"$(awk 'NF>=3 && $2=="=" && $1!~/^#/{print $1}' "$_ffile" 2>/dev/null)"})
        if (( CURRENT == 3 )); then
          local -a fav_opts=('--list:list favorites' '--edit:open in $EDITOR' '--remove:remove a favorite')
          _describe 'option' fav_opts
          (( ${#_faliases} > 0 )) && compadd -S ' ' -- "${_faliases[@]}"
        elif (( CURRENT == 4 )) && [[ "${words[3]}" == "--remove" ]]; then
          compadd -S ' ' -- "${_faliases[@]}"
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
