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

    local subcommands="--list --add --set --remove --tag --sync --ping --poll --edit --help --status --watch --run --close --export-ssh-config --keydeploy --last --import -u --upload"
    local mapfile_path="$HOME/.config/ssh_shorty/machines.txt"
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

        # Bare paths — readline places them after the ':' word-break automatically
        COMPREPLY=( "${remote_paths[@]}" )
        compopt -o nospace
    }

    local first="${COMP_WORDS[1]}"

    if [[ "$cword" -eq 1 ]]; then
        if [[ -n "$nick_for_path" ]]; then
            _complete_nick_path "$nick_for_path" "$cur"
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
            --set|-s|--remove|-r|--ping|-p|--poll)
                [[ "$cword" -eq 2 ]] && \
                    COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                ;;
            --status|--list|--watch)
                if [[ "$cword" -eq 2 && "$cur" == @* ]]; then
                    local -a groups; mapfile -t groups < <(_get_groups)
                    COMPREPLY=( $(compgen -W "${groups[*]}" -- "$cur") )
                fi
                ;;
            --run|--keydeploy|--close)
                [[ "$cword" -eq 2 ]] && _complete_nick_or_group "$cur"
                ;;
            -u|--upload)
                if [[ "$cword" -eq 2 ]]; then
                    COMPREPLY=( $(compgen -f -- "$cur") )
                    compopt -o nospace
                elif [[ "$cword" -eq 3 ]]; then
                    if [[ -n "$nick_for_path" ]]; then
                        _complete_nick_path "$nick_for_path" "$cur"
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
                    mapfile -t tags_raw < <(_get_tags_raw)
                    COMPREPLY=( $(compgen -W "${tags_raw[*]}" -- "$cur") )
                fi
                ;;
            --last|--add|--edit|--import|--help|--export-ssh-config)
                ;;
            *)
                # First arg is a nick — rsync pull or multi-device
                if [[ -n "$nick_for_path" ]]; then
                    _complete_nick_path "$nick_for_path" "$cur"
                else
                    COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                    compopt -o nospace
                fi
                ;;
        esac
    fi
}

complete -F _ssh_shorty_complete s
