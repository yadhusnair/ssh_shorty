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

    local subcommands="--list --add --set --remove --tag --sync --ping --poll --edit --paths --help --status --watch --run --run-script --sysinfo --tail --tunnel --close --export-ssh-config --keydeploy --last --import -u --upload -d --download -m"
    local mapfile_path="$HOME/.config/ssh_shorty/machines.txt"
    local paths_file="$HOME/.config/ssh_shorty/machine-paths.txt"
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
                ssh -o BatchMode=yes -o ConnectTimeout=3 "$target" \
                    "bash -c 'for p in \$(compgen -f -- \"$partial\"); do [ -d \"\$p\" ] && echo \"\$p/\" || echo \"\$p\"; done'" \
                    2>/dev/null
            )
            printf '%s\n' "${remote_paths[@]}" > "$cache_file"
        fi

        COMPREPLY=( "${remote_paths[@]}" )
        compopt -o nospace
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
            --set|-s|--remove|-r|--ping|-p|--poll|--tunnel|-t)
                [[ "$cword" -eq 2 ]] && \
                    COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                ;;
            --status|--list|--watch|--sysinfo)
                if [[ "$cword" -eq 2 && "$cur" == @* ]]; then
                    local -a groups; mapfile -t groups < <(_get_groups)
                    COMPREPLY=( $(compgen -W "${groups[*]}" -- "$cur") )
                fi
                ;;
            --run|--keydeploy|--close|-m)
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
            -d|--download)
                if [[ "$cword" -eq 2 ]]; then
                    local -a aliases
                    mapfile -t aliases < <(_get_all_aliases)
                    COMPREPLY=( $(compgen -W "${aliases[*]}" -- "$cur") )
                elif [[ "$cword" -eq 3 ]]; then
                    COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
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
            --last|--add|--edit|--import|--help|--export-ssh-config)
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
