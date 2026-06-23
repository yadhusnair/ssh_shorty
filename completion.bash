_ssh_shorty_complete() {
    local cur
    cur="${COMP_WORDS[COMP_CWORD]}"

    local subcommands="--list --add --set --remove --sync --ping --poll --edit --help --status --watch --run --close --export-ssh-config --keydeploy --last --import"
    local mapfile_path="$HOME/.config/ssh_shorty/machines.txt"
    local machines=()

    if [[ -f "$mapfile_path" ]]; then
        mapfile -t machines < <(awk 'NF >= 2 && $1 !~ /^#/ {print $1}' "$mapfile_path" 2>/dev/null)
    fi

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

    # Remote path completion with 30s cache
    _complete_nick_path() {
        local token="$1"
        local nick="${token%%:*}"
        local partial="${token#*:}"
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

        COMPREPLY=( "${remote_paths[@]/#/${nick}:}" )
        compopt -o nospace
    }

    local first="${COMP_WORDS[1]}"

    if [[ "$COMP_CWORD" -eq 1 ]]; then
        # Completing the first argument
        if [[ "$cur" == -* ]]; then
            COMPREPLY=( $(compgen -W "$subcommands" -- "$cur") )
        elif [[ "$cur" == @* ]]; then
            local -a groups
            mapfile -t groups < <(_get_groups)
            COMPREPLY=( $(compgen -W "${groups[*]}" -- "$cur") )
        elif [[ "$cur" == *:* ]]; then
            _complete_nick_path "$cur"
        else
            COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
            compopt -o nospace
        fi
    else
        # Completing second argument and beyond
        case "$first" in
            --set|-s|--remove|-r|--ping|-p|--poll)
                [[ "$COMP_CWORD" -eq 2 ]] && \
                    COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                ;;
            --status|--list|--watch)
                if [[ "$COMP_CWORD" -eq 2 && "$cur" == @* ]]; then
                    local -a groups; mapfile -t groups < <(_get_groups)
                    COMPREPLY=( $(compgen -W "${groups[*]}" -- "$cur") )
                fi
                ;;
            --run|--keydeploy|--close)
                [[ "$COMP_CWORD" -eq 2 ]] && _complete_nick_or_group "$cur"
                ;;
            --last|--add|--edit|--import|--help|--export-ssh-config)
                ;; # no further completion for these
            *)
                # First arg is a nickname (not a flag) — multi-device or rsync
                if [[ "$cur" == *:* ]]; then
                    _complete_nick_path "$cur"
                else
                    # Multi-device mode: offer nicknames at any depth
                    COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                    compopt -o nospace
                fi
                ;;
        esac
    fi
}

complete -F _ssh_shorty_complete s
