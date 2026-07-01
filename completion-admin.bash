_s_admin_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local first="${COMP_WORDS[1]}"
    local cword=$COMP_CWORD

    local subcommands="--add-user --edit-user --remove-user --list-users --user-log --provide-access --pending-requests --help"
    local mapfile_path="$HOME/.config/ssh_shorty/machines.txt"
    local users_file="$HOME/.config/ssh_shorty/users.txt"

    local -a machines=() users=()
    [[ -f "$mapfile_path" ]] && \
        mapfile -t machines < <(awk 'NF >= 2 && $1 !~ /^#/ {print $1}' "$mapfile_path" 2>/dev/null)
    [[ -f "$users_file" ]] && \
        mapfile -t users < <(awk 'NF >= 2 && $1 !~ /^#/ {print $1}' "$users_file" 2>/dev/null)

    if [[ "$cword" -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$subcommands" -- "$cur") )
    else
        case "$first" in
            --user-log)
                [[ "$cword" -eq 2 ]] && \
                    COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                ;;
            --provide-access)
                if [[ "$cword" -eq 2 ]]; then
                    COMPREPLY=( $(compgen -W "${users[*]}" -- "$cur") )
                elif [[ "$cword" -eq 3 ]]; then
                    COMPREPLY=( $(compgen -W "${machines[*]}" -- "$cur") )
                fi
                ;;
            --edit-user|--remove-user)
                [[ "$cword" -eq 2 ]] && \
                    COMPREPLY=( $(compgen -W "${users[*]}" -- "$cur") )
                ;;
        esac
    fi
}

complete -F _s_admin_complete s-admin
