#compdef s-admin

_s_admin() {
  local -a subcommands
  local users_file="$HOME/.config/ssh_shorty/users.txt"
  local mapfile="$HOME/.config/ssh_shorty/machines.txt"

  local -a machines users
  machines=(${(f)"$(awk 'NF >= 2 && $1 !~ /^#/ {print $1}' "$mapfile" 2>/dev/null)"})
  users=(${(f)"$(awk 'NF >= 2 && $1 !~ /^#/ {print $1}' "$users_file" 2>/dev/null)"})

  subcommands=(
    '--add-user:register a user with their SSH key'
    '--edit-user:update a user SSH key'
    '--remove-user:remove a user'
    '--list-users:list all registered users'
    '--user-log:show login history for a device'
    '--provide-access:grant a user SSH access to a device'
    '--pending-requests:list pending access requests'
    '--help:show usage'
  )

  if (( CURRENT == 2 )); then
    _describe 'subcommand' subcommands
  else
    local first="${words[2]}"
    case "$first" in
      --user-log)
        (( CURRENT == 3 )) && _describe 'machine' machines
        ;;
      --provide-access)
        if (( CURRENT == 3 )); then
          compadd -S ' ' -- "${users[@]}"
        elif (( CURRENT == 4 )); then
          _describe 'machine' machines
        fi
        ;;
      --edit-user|--remove-user)
        (( CURRENT == 3 )) && compadd -S ' ' -- "${users[@]}"
        ;;
    esac
  fi
}

_s_admin
