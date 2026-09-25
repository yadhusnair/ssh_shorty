#compdef s

# Load zsh/stat for fast mtime checks (used in cache TTL)
zmodload zsh/stat 2>/dev/null

_ssh_shorty() {
  local -a machines groups tags_raw all_aliases subcommands
  local mapfile="$HOME/.config/ssh_shorty/machines.txt"
  local paths_file="$HOME/.config/ssh_shorty/machine-paths.txt"
  local scripts_file="$HOME/.config/ssh_shorty/scripts.txt"

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
    '--docker-cp:copy a file into a container on a device'
    '--docker-download:copy a file out of a container on a device'
    '--script:run a registered script (or add/remove/list)'
    '--list:list all devices'
    '--add:add a new device'
    '--set:update a device IP'
    '--set-mac:set/update a device MAC address'
    '--add-alt:add an alternate address for a device'
    '--remove-alt:remove an alternate address from a device'
    '--rename:rename a device'
    '--remove:remove a device'
    '--tag:add a tag to a device'
    '--untag:remove a tag from a device'
    '--sync:pull/push fleet from SYNC_HOST'
    '--ping:check reachability'
    '--oneshot:fleet-wide MAC/IP reconciliation'
    '--poll:wait until online then connect'
    '--edit:open machines.txt in $EDITOR'
    '--paths:open machine-paths.txt and sync'
    '--help:show usage'
    '--update:check for and apply updates'
    '--fav:save/list/remove favorite run commands'
    '--status:parallel online/offline status table'
    '--watch:live-refreshing fleet status'
    '--sysinfo:live resource dashboard'
    '--view:stream a remote image/video to local viewer'
    '--run:run command on one or many devices'
    '--run-script:run local script remotely'
    '--tail:tail a remote log using alias'
    '--tunnel:open SSH tunnel'
    '-t:open SSH tunnel'
    '-m:tmux synchronized panes'
    '--close:close ControlMaster socket'
    '--export-ssh-config:write machines.txt to ~/.ssh/config'
    '--register:submit your SSH public key for admin review'
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
      # compgen's own matching against $partial already handles a leading ~
      # fine and returns candidates in ~-relative form (needed so zsh's
      # prefix matching against what was actually typed still works) — but
      # `[ -d ]` on a *quoted* variable never tilde-expands, so directories
      # never got their trailing "/" without a separate, explicit expansion
      # just for the existence check.
      paths=(${(f)"$(ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "$target" \
        "bash -c 'for p in \$(compgen -f -- \"$partial\"); do e=\"\${p/#~/\$HOME}\"; [ -d \"\$e\" ] && echo \"\$p/\" || echo \"\$p\"; done'" \
        2>/dev/null)"})
      print -l -- "${paths[@]}" > "$cache_file"
    fi

    compadd -f -Q -S '' -- "${paths[@]}"
  }

  # List containers (running or not) on a device via `docker ps -a`, cached 30s.
  _docker_containers_for() {
    local nick="$1"
    local target
    target=$(awk -v n="$nick" '$1 == n {print $2; exit}' "$mapfile" 2>/dev/null)
    [[ -z "$target" ]] && return

    local cache_dir="$HOME/.cache/ssh_shorty"
    local cache_file="${cache_dir}/dockerps_${nick}"
    local -a names

    local mtime=0
    zstat -A mtime +mtime "$cache_file" 2>/dev/null
    if [[ -f "$cache_file" ]] && (( EPOCHSECONDS - mtime < 30 )); then
      names=(${(f)"$(<$cache_file)"})
    else
      mkdir -p "$cache_dir"
      names=(${(f)"$(ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "$target" \
        "docker ps -a --format '{{.Names}}'" 2>/dev/null)"})
      print -l -- "${names[@]}" > "$cache_file"
    fi
    # Auto-append ':' — container[:dest-path] mirrors the nick:path idiom
    # used elsewhere, so picking a container continues straight into its
    # in-container path completion without having to type the colon.
    compadd -S ':' -- "${names[@]}"
  }

  # Paths inside a specific container, cached 30s per (nick, container, partial).
  # Uses plain POSIX sh globbing (not bash's compgen) since many container
  # images have only /bin/sh, or no shell at all — in the latter case docker
  # exec fails and this just yields no candidates rather than erroring.
  _docker_container_paths_for() {
    local nick="$1" container="$2" partial="$3"
    local target
    target=$(awk -v n="$nick" '$1 == n {print $2; exit}' "$mapfile" 2>/dev/null)
    [[ -z "$target" ]] && return

    local cache_dir="$HOME/.cache/ssh_shorty"
    local cache_key="dockerpath_${nick}_${container}_${partial//\//_}"
    local cache_file="${cache_dir}/${cache_key}"
    local -a paths

    local mtime=0
    zstat -A mtime +mtime "$cache_file" 2>/dev/null
    if [[ -f "$cache_file" ]] && (( EPOCHSECONDS - mtime < 30 )); then
      paths=(${(f)"$(<$cache_file)"})
    else
      mkdir -p "$cache_dir"
      paths=(${(f)"$(ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "$target" \
        "docker exec '$container' sh -c 'set -- \"\$1\"*; for p; do [ -e \"\$p\" ] || continue; [ -d \"\$p\" ] && printf \"%s/\n\" \"\$p\" || printf \"%s\n\" \"\$p\"; done' _ \"$partial\"" \
        2>/dev/null)"})
      print -l -- "${paths[@]}" > "$cache_file"
    fi
    compadd -f -Q -S '' -- "${paths[@]}"
  }

  # For container:<TAB> (the 4th --docker-cp arg): strip 'container:' via
  # compset so in-container path candidates match just the partial.
  _docker_container_colon_complete() {
    local nick="$1" token="$2"
    local container="${token%%:*}"
    local partial="${token#*:}"
    compset -P '*:'
    _docker_container_paths_for "$nick" "$container" "$partial"
  }

  # All registered script names, for `s --script <TAB>`.
  _script_names() {
    [[ -f "$scripts_file" ]] || return
    compadd -- ${(f)"$(awk 'NF>=3{print $1}' "$scripts_file" 2>/dev/null)"}
  }

  # Looks up a registered script's type/path into $reply[1]/$reply[2].
  _script_lookup() {
    local name="$1" line
    line=$(awk -v n="$name" '$1==n{print;exit}' "$scripts_file" 2>/dev/null)
    reply=("${${=line}[2]}" "${${=line}[3]}")
  }

  # Best-effort flag discovery: run the script with --help (timeout-guarded,
  # stdin closed so it can't block waiting for input) and pull --flag-looking
  # tokens out of the output. A script that doesn't handle --help safely
  # could run its real logic instead of printing usage — this is a tradeoff
  # of auto-detecting args from the script itself rather than registering
  # them by hand.
  _script_flags_for() {
    # NOT named "path" — that's a zsh-special parameter tied to $PATH (as an
    # array); shadowing it locally corrupts command lookup for the rest of
    # this function's scope (grep/sed/sort/timeout all silently break).
    local script_path="$1"
    [[ -x "$script_path" ]] || return
    local out
    out=$(timeout 2 "$script_path" --help < /dev/null 2>&1)
    [[ -z "$out" ]] && out=$(timeout 2 "$script_path" -h < /dev/null 2>&1)
    [[ -z "$out" ]] && return
    local -a flags
    flags=(${(fu)"$(tr -d '[]<>(),' <<< "$out" | grep -oE -- '--[a-zA-Z][a-zA-Z0-9_-]*' | sort -u)"})
    (( ${#flags} > 0 )) && compadd -- "${flags[@]}"
  }

  # For nick:<TAB>: strip 'nick:' from PREFIX via compset so bare alias/path
  # names are matched against just the partial after the colon.
  _nick_colon_complete() {
    local token="$1"
    local nick="${token%%:*}"
    local partial="${token#*:}"

    # Move 'nick:' into IPREFIX so completions match only the path/alias part
    compset -P '*:'

    # "~" quoted (not a bare glob char): zsh's completion system runs with
    # EXTENDED_GLOB active, under which an unquoted ~* pattern doesn't match
    # a literal leading tilde the way it looks like it should.
    if [[ "$partial" != /* && "$partial" != "~"* ]]; then
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
      --set|--set-mac|--add-alt|--remove-alt|--rename|--remove|--tunnel|-t)
        (( CURRENT == 3 )) && _describe 'machine' machines
        ;;
      --ping|-p)
        if (( CURRENT == 3 )); then
          if [[ "$PREFIX" == @* ]]; then
            compadd -Q -S ' ' -- "${groups[@]}" '--all'
          else
            compadd -S ' ' -- "${machines[@]}"
            compadd -Q -S ' ' -- "${groups[@]}"
          fi
        fi
        ;;
      --poll)
        (( CURRENT == 3 )) && _describe 'machine' machines
        ;;
      --status|--list|--watch|--sysinfo)
        if (( CURRENT == 3 )); then
          if [[ "$PREFIX" == @* ]]; then
            compadd -Q -S ' ' -- "${groups[@]}" '--all'
          else
            compadd -S ' ' -- "${machines[@]}"
            compadd -Q -S ' ' -- "${groups[@]}"
          fi
        fi
        ;;
      --run)
        if (( CURRENT == 3 )); then
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
        else
          # A parameterized favorite (has a #var marker) needs its value typed
          # in position 4 before the device — no completion there. Only offer
          # the device/group once that slot is filled (position 5). A plain
          # favorite/raw command has no value slot, so device is position 4.
          local favs_file="$HOME/.config/ssh_shorty/favorites.txt"
          local run_alias="${words[3]}"
          local has_var=0
          if [[ -f "$favs_file" ]] && awk -v a="$run_alias" \
              '$1==a && $2=="=" && $0 ~ / #var / {f=1} END{exit !f}' "$favs_file" 2>/dev/null; then
            has_var=1
          fi
          if (( has_var )); then
            (( CURRENT == 5 )) && _nick_or_group
          else
            (( CURRENT == 4 )) && _nick_or_group
          fi
        fi
        ;;
      --keydeploy|--close|-m)
        (( CURRENT == 3 )) && _nick_or_group
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
      --view)
        if (( CURRENT == 3 )); then
          _describe 'machine' machines
        elif (( CURRENT == 4 )); then
          if [[ "$PREFIX" == *:* ]]; then
            _nick_colon_complete "$PREFIX"
          else
            _remote_paths_for "${words[3]}" "$PREFIX"
          fi
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
      --docker-cp)
        if (( CURRENT == 3 )); then
          _files
        elif (( CURRENT == 4 )); then
          _describe 'machine' machines
        elif (( CURRENT == 5 )); then
          if [[ "$PREFIX" == *:* ]]; then
            _docker_container_colon_complete "${words[4]}" "$PREFIX"
          else
            _docker_containers_for "${words[4]}"
          fi
        fi
        ;;
      --docker-download)
        if (( CURRENT == 3 )); then
          _describe 'machine' machines
        elif (( CURRENT == 4 )); then
          if [[ "$PREFIX" == *:* ]]; then
            _docker_container_colon_complete "${words[3]}" "$PREFIX"
          else
            _docker_containers_for "${words[3]}"
          fi
        elif (( CURRENT == 5 )); then
          _files
        fi
        ;;
      --script)
        if (( CURRENT == 3 )); then
          compadd -- add remove list edit push pull
          _script_names
        elif [[ "${words[3]}" == "add" ]]; then
          if (( CURRENT == 5 )); then
            compadd -- remote local local+ssh
          elif (( CURRENT == 6 )); then
            _files
          fi
        elif [[ "${words[3]}" == "remove" ]]; then
          (( CURRENT == 4 )) && _script_names
        elif [[ "${words[3]}" == "list" || "${words[3]}" == "push" || "${words[3]}" == "pull" ]]; then
          :
        else
          local -a reply
          _script_lookup "${words[3]}"
          local _sc_type="${reply[1]}" _sc_path="${reply[2]}"
          if [[ "$_sc_type" == "remote" || "$_sc_type" == "local+ssh" ]]; then
            if (( CURRENT == 4 )); then
              _describe 'machine' machines
            elif (( CURRENT >= 5 )); then
              _script_flags_for "$_sc_path"
            fi
          else
            (( CURRENT >= 4 )) && _script_flags_for "$_sc_path"
          fi
        fi
        ;;
      --tag|--untag)
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
      --add)
        if (( CURRENT >= 5 )); then
          compadd -S ' ' -- "${tags_raw[@]}"
        fi
        ;;
      --last|--edit|--import|--help|--export-ssh-config)
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
