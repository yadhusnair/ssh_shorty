_ssh_shorty_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"

    # bash breaks on ':' by default, so "fm14:/hom" becomes three tokens:
    # ["fm14", ":", "/hom"]. Detect that case and track the nick separately.
    local nick_for_path=""
    if [[ $COMP_CWORD -ge 2 && "${COMP_WORDS[COMP_CWORD-1]}" == ":" ]]; then
        nick_for_path="${COMP_WORDS[COMP_CWORD-2]}"
    fi

    # Compute logical word index: each colon-pair inflates COMP_CWORD by 2.
    local cword=$COMP_CWORD i
    for (( i=1; i<COMP_CWORD; i++ )); do
        [[ "${COMP_WORDS[i]}" == ":" ]] && (( cword -= 2 ))
    done

    local subcommands="--list --add --set --set-mac --add-alt --remove-alt --rename --remove --tag --untag --sync --ping --oneshot --poll --edit --paths --help --update --fav --status --watch --run --run-script --script --sysinfo --tail --tunnel --close --register --export-ssh-config --keydeploy --last --import -u --upload --docker-cp --docker-download -d --download --view -m"
    local mapfile_path="$HOME/.config/ssh_shorty/machines.txt"
    local paths_file="$HOME/.config/ssh_shorty/machine-paths.txt"
    local scripts_file="$HOME/.config/ssh_shorty/scripts.txt"
    local machines=()

    if [[ -f "$mapfile_path" ]]; then
        mapfile -t machines < <(awk 'NF >= 2 && $1 !~ /^#/ {print $1}' "$mapfile_path" 2>/dev/null)
    fi

    _get_tags_raw() {
        awk 'NF >= 2 && $1 !~ /^#/ {
            for (i=3; i<=NF; i++) if ($i ~ /^#/) print $i
        }' "$mapfile_path" 2>/dev/null | sort -u
    }

    _get_groups() {
        awk 'NF >= 2 && $1 !~ /^#/ {
            for (i=3; i<=NF; i++) if ($i ~ /^#/) { gsub(/^#/, "@", $i); print $i }
        }' "$mapfile_path" 2>/dev/null | sort -u
    }

    # All alias names defined in machine-paths.txt
    _get_all_aliases() {
        [[ ! -f "$paths_file" ]] && return
        awk 'NF >= 3 && $1 !~ /^#/ { print $2 }' "$paths_file" | sort -u
    }

    # Alias names applicable to a specific nick (via its tags)
    _get_aliases_for_nick() {
        local nick="$1"
        [[ ! -f "$paths_file" ]] && return
        local -a tags=()
        mapfile -t tags < <(awk -v n="$nick" 'NF >= 2 && $1 == n {
            for (i=3; i<=NF; i++) if ($i ~ /^#/) print substr($i,2)
        }' "$mapfile_path" 2>/dev/null)
        for tag in "${tags[@]}"; do
            awk -v t="$tag" 'NF >= 3 && $1 !~ /^#/ && $1 == t { print $2 }' "$paths_file"
        done | sort -u
    }

    _complete_nick_or_group() {
        local cur="$1"
        if [[ "$cur" == @* ]]; then
            local -a groups
            mapfile -t groups < <(_get_groups)
            COMPREPLY=( $(compgen -W "${groups[*]} --all" -- "$cur") )
        else
            COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
            compopt -o nospace
        fi
    }

    # Remote path completion with 30s cache.
    # COMPREPLY is set to bare paths (no nick: prefix) — readline inserts them
    # right after the ':' word-break, so the final result is nick:/path.
    _complete_nick_path() {
        local nick="$1" partial="$2"
        local target
        target=$(awk -v n="$nick" '$1 == n {print $2; exit}' "$mapfile_path" 2>/dev/null)
        [[ -z "$target" ]] && return

        local cache_dir="$HOME/.cache/ssh_shorty"
        local cache_key="${nick}_${partial//\//_}"
        local cache_file="${cache_dir}/${cache_key}"

        local -a remote_paths
        if [[ -f "$cache_file" ]] && \
           (( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) < 30 )); then
            mapfile -t remote_paths < "$cache_file"
        else
            mkdir -p "$cache_dir"
            mapfile -t remote_paths < <(
                ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "$target" \
                    "bash -c 'for p in \$(compgen -f -- \"$partial\"); do e=\"\${p/#~/\$HOME}\"; [ -d \"\$e\" ] && echo \"\$p/\" || echo \"\$p\"; done'" \
                    2>/dev/null
            )
            printf '%s\n' "${remote_paths[@]}" > "$cache_file"
        fi

        COMPREPLY=( "${remote_paths[@]}" )
        compopt -o nospace
    }

    # List containers (running or not) on a device via `docker ps -a`, cached 30s.
    _complete_docker_containers() {
        local nick="$1" cur="$2"
        local target
        target=$(awk -v n="$nick" '$1 == n {print $2; exit}' "$mapfile_path" 2>/dev/null)
        [[ -z "$target" ]] && return

        local cache_dir="$HOME/.cache/ssh_shorty"
        local cache_file="${cache_dir}/dockerps_${nick}"

        local -a names
        if [[ -f "$cache_file" ]] && \
           (( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) < 30 )); then
            mapfile -t names < "$cache_file"
        else
            mkdir -p "$cache_dir"
            mapfile -t names < <(
                ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "$target" \
                    "docker ps -a --format '{{.Names}}'" 2>/dev/null
            )
            printf '%s\n' "${names[@]}" > "$cache_file"
        fi
        COMPREPLY=( $(compgen -W "${names[*]}" -- "$cur") )
    }

    # Paths inside a specific container, cached 30s per (nick, container, partial).
    # Plain POSIX sh globbing (not bash's compgen) since many container images
    # have only /bin/sh, or no shell at all — the latter just yields nothing.
    _complete_docker_container_path() {
        local nick="$1" container="$2" partial="$3"
        local target
        target=$(awk -v n="$nick" '$1 == n {print $2; exit}' "$mapfile_path" 2>/dev/null)
        [[ -z "$target" ]] && return

        local cache_dir="$HOME/.cache/ssh_shorty"
        local cache_key="dockerpath_${nick}_${container}_${partial//\//_}"
        local cache_file="${cache_dir}/${cache_key}"

        local -a paths
        if [[ -f "$cache_file" ]] && \
           (( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) < 30 )); then
            mapfile -t paths < "$cache_file"
        else
            mkdir -p "$cache_dir"
            mapfile -t paths < <(
                ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "$target" \
                    "docker exec '$container' sh -c 'set -- \"\$1\"*; for p; do [ -e \"\$p\" ] || continue; [ -d \"\$p\" ] && printf \"%s/\n\" \"\$p\" || printf \"%s\n\" \"\$p\"; done' _ \"$partial\"" \
                    2>/dev/null
            )
            printf '%s\n' "${paths[@]}" > "$cache_file"
        fi
        COMPREPLY=( "${paths[@]}" )
        compopt -o nospace
    }

    # All registered script names, for `s --script <TAB>`.
    _get_script_names() {
        [[ -f "$scripts_file" ]] || return
        awk 'NF>=3{print $1}' "$scripts_file" 2>/dev/null
    }

    # Prints "<type> <path>" for a registered script name.
    _get_script_type_path() {
        [[ -f "$scripts_file" ]] || return
        awk -v n="$1" '$1==n{print $2, $3; exit}' "$scripts_file" 2>/dev/null
    }

    # Best-effort flag discovery: run the script with --help (timeout-guarded,
    # stdin closed so it can't block waiting for input) and pull --flag-looking
    # tokens out of the output. A script that doesn't handle --help safely
    # could run its real logic instead of printing usage — this is a tradeoff
    # of auto-detecting args from the script itself rather than registering
    # them by hand.
    _complete_script_flags() {
        local script_path="$1" cur="$2"
        [[ -x "$script_path" ]] || return
        local out
        out=$(timeout 2 "$script_path" --help < /dev/null 2>&1)
        [[ -z "$out" ]] && out=$(timeout 2 "$script_path" -h < /dev/null 2>&1)
        [[ -z "$out" ]] && return
        local -a flags
        mapfile -t flags < <(tr -d '[]<>(),' <<< "$out" | grep -oE -- '--[a-zA-Z][a-zA-Z0-9_-]*' | sort -u)
        (( ${#flags[@]} > 0 )) && COMPREPLY=( $(compgen -W "${flags[*]}" -- "$cur") )
    }

    # For nick:<TAB>: offer aliases first (no / prefix); fall back to remote paths.
    _complete_nick_colon() {
        local nick="$1" partial="$2"
        if [[ "$partial" != /* && "$partial" != ~* ]]; then
            local -a aliases
            mapfile -t aliases < <(_get_aliases_for_nick "$nick")
            if [[ ${#aliases[@]} -gt 0 ]]; then
                COMPREPLY=( $(compgen -W "${aliases[*]}" -- "$partial") )
                [[ ${#COMPREPLY[@]} -gt 0 ]] && return
            fi
        fi
        _complete_nick_path "$nick" "$partial"
    }

    local first="${COMP_WORDS[1]}"

    if [[ "$cword" -eq 1 ]]; then
        if [[ -n "$nick_for_path" ]]; then
            _complete_nick_colon "$nick_for_path" "$cur"
        elif [[ "$cur" == -* ]]; then
            COMPREPLY=( $(compgen -W "$subcommands" -- "$cur") )
        elif [[ "$cur" == @* ]]; then
            local -a groups
            mapfile -t groups < <(_get_groups)
            COMPREPLY=( $(compgen -W "${groups[*]}" -- "$cur") )
        else
            COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
            compopt -o nospace
        fi
    else
        case "$first" in
            --set|-s|--set-mac|--add-alt|--remove-alt|--rename|--remove|-r|--poll|--tunnel|-t)
                [[ "$cword" -eq 2 ]] && \
                    COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                ;;
            --ping|-p)
                if [[ "$cword" -eq 2 ]]; then
                    local -a groups
                    mapfile -t groups < <(_get_groups)
                    COMPREPLY=( $(compgen -W "${machines[*]} ${groups[*]} --all" -- "$cur") )
                fi
                ;;
            --untag)
                if [[ "$cword" -eq 2 ]]; then
                    COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                elif [[ "$cword" -eq 3 ]]; then
                    local -a tags_raw
                    mapfile -t tags_raw < <(_get_tags_raw | sed 's/^#//')
                    COMPREPLY=( $(compgen -W "${tags_raw[*]}" -- "$cur") )
                fi
                ;;
            --status|--list|--watch|--sysinfo)
                if [[ "$cword" -eq 2 ]]; then
                    local -a groups
                    mapfile -t groups < <(_get_groups)
                    COMPREPLY=( $(compgen -W "${machines[*]} ${groups[*]} --all" -- "$cur") )
                fi
                ;;
            --run)
                if [[ "$cword" -eq 2 ]]; then
                    local favs_file="$HOME/.config/ssh_shorty/favorites.txt"
                    local -a fav_aliases=()
                    [[ -f "$favs_file" ]] && mapfile -t fav_aliases < <(
                        awk 'NF>=3 && $2=="=" && $1!~/^#/{print $1}' "$favs_file" 2>/dev/null)
                    local -a matches=()
                    for a in "${fav_aliases[@]}"; do
                        [[ "$a" == "${cur}"* ]] && matches+=("$a")
                    done
                    if [[ ${#matches[@]} -gt 0 ]]; then
                        COMPREPLY=( "${matches[@]}" )
                    else
                        COMPREPLY=( '""' )
                    fi
                else
                    # A parameterized favorite (has a #var marker) needs its
                    # value typed in position 3 before the device — no
                    # completion there. Only offer the device/group once that
                    # slot is filled (position 4). A plain favorite/raw
                    # command has no value slot, so device is position 3.
                    local favs_file="$HOME/.config/ssh_shorty/favorites.txt"
                    local run_alias="${COMP_WORDS[2]}"
                    local has_var=0
                    if [[ -f "$favs_file" ]] && awk -v a="$run_alias" \
                        '$1==a && $2=="=" && $0 ~ / #var / {f=1} END{exit !f}' "$favs_file" 2>/dev/null; then
                        has_var=1
                    fi
                    if [[ "$has_var" -eq 1 ]]; then
                        [[ "$cword" -eq 4 ]] && _complete_nick_or_group "$cur"
                    else
                        [[ "$cword" -eq 3 ]] && _complete_nick_or_group "$cur"
                    fi
                fi
                ;;
            --keydeploy|--close|-m)
                [[ "$cword" -eq 2 ]] && _complete_nick_or_group "$cur"
                ;;
            --run-script)
                if [[ "$cword" -eq 2 ]]; then
                    _complete_nick_or_group "$cur"
                elif [[ "$cword" -eq 3 ]]; then
                    COMPREPLY=( $(compgen -f -- "$cur") )
                fi
                ;;
            --tail)
                if [[ "$cword" -eq 2 ]]; then
                    COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                elif [[ "$cword" -eq 3 ]]; then
                    local -a aliases
                    mapfile -t aliases < <(_get_aliases_for_nick "${COMP_WORDS[2]}")
                    COMPREPLY=( $(compgen -W "${aliases[*]}" -- "$cur") )
                fi
                ;;
            --view)
                if [[ "$cword" -eq 2 ]]; then
                    COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                elif [[ "$cword" -eq 3 ]]; then
                    if [[ -n "$nick_for_path" ]]; then
                        _complete_nick_colon "$nick_for_path" "$cur"
                    else
                        _complete_nick_path "${COMP_WORDS[2]}" "$cur"
                    fi
                fi
                ;;
            -d|--download)
                if [[ "$cword" -eq 2 ]]; then
                    if [[ -n "$nick_for_path" ]]; then
                        _complete_nick_colon "$nick_for_path" "$cur"
                    elif [[ "$cur" == *:* ]]; then
                        local _nick="${cur%%:*}" _partial="${cur##*:}"
                        _complete_nick_path "$_nick" "$_partial"
                    else
                        local -a aliases
                        mapfile -t aliases < <(_get_all_aliases)
                        COMPREPLY=( $(compgen -W "${aliases[*]} ${machines[*]}" -- "$cur") )
                        # nospace so nick: can be continued
                        [[ ${#COMPREPLY[@]} -eq 1 && "${COMPREPLY[0]}" == "${machines[*]%% *}" ]] && \
                            compopt -o nospace 2>/dev/null || true
                        compopt -o nospace 2>/dev/null
                    fi
                elif [[ "$cword" -eq 3 ]]; then
                    # bash's COMP_WORDBREAKS splits "nick:path" into three
                    # physical words (nick, ":", path) — COMP_WORDS[2] alone
                    # is just the nick, so check the token right after it for
                    # the literal ":" that marks arg2 as nick:path rather
                    # than a bare nick (the alias-based `-d <alias> <nick>`
                    # form).
                    if [[ "${COMP_WORDS[3]}" == ":" ]]; then
                        # nick:path was arg2 — arg3 is local dest
                        COMPREPLY=( $(compgen -f -- "$cur") )
                        compopt -o nospace
                    else
                        COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                    fi
                elif [[ "$cword" -eq 4 ]]; then
                    COMPREPLY=( $(compgen -f -- "$cur") )
                    compopt -o nospace
                fi
                ;;
            -u|--upload)
                if [[ "$cword" -eq 2 ]]; then
                    COMPREPLY=( $(compgen -f -- "$cur") )
                    compopt -o nospace
                elif [[ "$cword" -eq 3 ]]; then
                    if [[ -n "$nick_for_path" ]]; then
                        _complete_nick_colon "$nick_for_path" "$cur"
                    else
                        COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                        compopt -o nospace
                    fi
                fi
                ;;
            --docker-cp)
                if [[ "$cword" -eq 2 ]]; then
                    COMPREPLY=( $(compgen -f -- "$cur") )
                    compopt -o nospace
                elif [[ "$cword" -eq 3 ]]; then
                    COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                elif [[ "$cword" -eq 4 ]]; then
                    if [[ -n "$nick_for_path" ]]; then
                        # nick_for_path here is actually the container name —
                        # we just typed "container:" and are completing dest.
                        _complete_docker_container_path "${COMP_WORDS[3]}" "$nick_for_path" "$cur"
                    else
                        _complete_docker_containers "${COMP_WORDS[3]}" "$cur"
                        compopt -o nospace
                    fi
                fi
                ;;
            --docker-download)
                if [[ "$cword" -eq 2 ]]; then
                    COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                elif [[ "$cword" -eq 3 ]]; then
                    if [[ -n "$nick_for_path" ]]; then
                        # nick_for_path here is actually the container name —
                        # we just typed "container:" and are completing the
                        # in-container source path.
                        _complete_docker_container_path "${COMP_WORDS[2]}" "$nick_for_path" "$cur"
                    else
                        _complete_docker_containers "${COMP_WORDS[2]}" "$cur"
                        compopt -o nospace
                    fi
                elif [[ "$cword" -eq 4 ]]; then
                    COMPREPLY=( $(compgen -f -- "$cur") )
                    compopt -o nospace
                fi
                ;;
            --script)
                if [[ "$cword" -eq 2 ]]; then
                    local -a script_names
                    mapfile -t script_names < <(_get_script_names)
                    COMPREPLY=( $(compgen -W "add remove list edit push pull ${script_names[*]}" -- "$cur") )
                elif [[ "${COMP_WORDS[2]}" == "add" ]]; then
                    if [[ "$cword" -eq 4 ]]; then
                        COMPREPLY=( $(compgen -W "remote local local+ssh" -- "$cur") )
                    elif [[ "$cword" -eq 5 ]]; then
                        COMPREPLY=( $(compgen -f -- "$cur") )
                        compopt -o nospace
                    fi
                elif [[ "${COMP_WORDS[2]}" == "remove" ]]; then
                    if [[ "$cword" -eq 3 ]]; then
                        local -a script_names
                        mapfile -t script_names < <(_get_script_names)
                        COMPREPLY=( $(compgen -W "${script_names[*]}" -- "$cur") )
                    fi
                elif [[ "${COMP_WORDS[2]}" == "list" || "${COMP_WORDS[2]}" == "push" || "${COMP_WORDS[2]}" == "pull" ]]; then
                    :
                else
                    local _sc_type _sc_path
                    read -r _sc_type _sc_path < <(_get_script_type_path "${COMP_WORDS[2]}")
                    if [[ "$_sc_type" == "remote" || "$_sc_type" == "local+ssh" ]]; then
                        if [[ "$cword" -eq 3 ]]; then
                            COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                        elif [[ "$cword" -ge 4 ]]; then
                            _complete_script_flags "$_sc_path" "$cur"
                        fi
                    else
                        [[ "$cword" -ge 3 ]] && _complete_script_flags "$_sc_path" "$cur"
                    fi
                fi
                ;;
            --tag)
                if [[ "$cword" -eq 2 ]]; then
                    COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                elif [[ "$cword" -eq 3 ]]; then
                    local -a tags_raw
                    # Strip leading '#' — the shell treats '#foo' as a comment;
                    # the command auto-prepends '#' when it receives the plain name.
                    mapfile -t tags_raw < <(_get_tags_raw | sed 's/^#//')
                    COMPREPLY=( $(compgen -W "${tags_raw[*]}" -- "$cur") )
                fi
                ;;
            --fav)
                local _ffile="$HOME/.config/ssh_shorty/favorites.txt"
                local -a _faliases=()
                [[ -f "$_ffile" ]] && mapfile -t _faliases < <(
                    awk 'NF>=3 && $2=="=" && $1!~/^#/{print $1}' "$_ffile" 2>/dev/null)
                if [[ "$cword" -eq 2 ]]; then
                    COMPREPLY=( $(compgen -W "--list --edit --remove ${_faliases[*]}" -- "$cur") )
                elif [[ "$cword" -eq 3 && "${COMP_WORDS[2]}" == "--remove" ]]; then
                    COMPREPLY=( $(compgen -W "${_faliases[*]}" -- "$cur") )
                fi
                ;;
            --add)
                if [[ "$cword" -ge 4 ]]; then
                    local -a tags_raw
                    mapfile -t tags_raw < <(_get_tags_raw | sed 's/^#//')
                    COMPREPLY=( $(compgen -W "${tags_raw[*]}" -- "$cur") )
                fi
                ;;
            --last|--edit|--import|--help|--export-ssh-config)
                ;;
            *)
                # First arg is a nick — rsync pull or multi-device
                if [[ -n "$nick_for_path" ]]; then
                    _complete_nick_colon "$nick_for_path" "$cur"
                else
                    COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                    compopt -o nospace
                fi
                ;;
        esac
    fi
}

complete -F _ssh_shorty_complete s
