#!/usr/bin/env bash
# Fleet history log (machines-main.txt) tests. Runs two simulated clients
# against a fake SYNC_HOST (a local dir) via stub ssh/scp — no network.
# Usage: bash tests/test_fleet_log.sh
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
REMOTE="$T/remote"; mkdir -p "$REMOTE/ssh_shorty" "$T/bin"
pass=0; fail=0
ok()   { printf '  \033[32mok\033[0m   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# Stub ssh: drop options + host, run the command with HOME=$REMOTE
cat > "$T/bin/ssh" <<STUB
#!/usr/bin/env bash
while [[ \$# -gt 0 ]]; do case "\$1" in -o) shift 2;; -*) shift;; *) break;; esac; done
shift   # host
HOME="$REMOTE" exec bash -c "\$*"
STUB
# Stub scp: host:path → \$REMOTE/path
cat > "$T/bin/scp" <<STUB
#!/usr/bin/env bash
a=()
while [[ \$# -gt 0 ]]; do case "\$1" in -o) shift 2;; -*) shift;; *) a+=("\$1"); shift;; esac; done
src="\${a[0]}"; dst="\${a[1]}"
[[ "\$src" == *:* ]] && src="$REMOTE/\${src#*:}"
[[ "\$dst" == *:* ]] && dst="$REMOTE/\${dst#*:}"
cp "\$src" "\$dst"
STUB
chmod +x "$T/bin/"*

mkclient() {
    local h="$T/$1"; mkdir -p "$h/.config/ssh_shorty"
    printf 'SYNC_HOST="ati@fake"\nSYNC_REMOTE_PATH="ssh_shorty/machines.txt"\nSHORTY_USER="%s"\n' "$1" \
        > "$h/.config/ssh_shorty/config"
}
# Run s as a client; a fresh .last_sync keeps the background sync out of the way
s_as() {
    local who="$1"; shift
    touch "$T/$who/.config/ssh_shorty/.last_sync"
    HOME="$T/$who" PATH="$T/bin:$PATH" NO_COLOR=1 bash "$REPO/s" "$@" </dev/null 2>&1
}
map()  { cat "$T/$1/.config/ssh_shorty/machines.txt"; }
host_of() { awk -v n="$2" '$1==n{print $2}' "$T/$1/.config/ssh_shorty/machines.txt"; }
LOG="$REMOTE/ssh_shorty/machines-main.txt"
LEGACY="$REMOTE/ssh_shorty/machines.txt"

mkclient alice; mkclient bob
printf 'fm12 ati@10.0.0.12 #fm\nfm14 ati@10.0.0.14 #fm\ntug1 ati@10.0.0.31\ntug2 ati@10.0.0.32\ntug3 ati@10.0.0.33\n' \
    > "$T/alice/.config/ssh_shorty/machines.txt"

echo "bootstrap"
s_as alice --sync >/dev/null
check "first sync seeds the log with alice's 5 devices"  '[[ $(grep -c " set " "$LOG") -eq 5 ]]'
check "legacy machines.txt generated on host"           '[[ $(wc -l < "$LEGACY") -eq 5 ]]'
s_as bob --sync >/dev/null
check "bob (empty) gets all 5 devices"                  '[[ $(map bob | wc -l) -eq 5 ]]'

echo "add + IP change propagate, newest wins"
s_as bob --add fm20 ati@10.0.0.20 '#fm' >/dev/null
s_as alice --sync >/dev/null
check "bob's new device reaches alice"                  '[[ $(host_of alice fm20) == ati@10.0.0.20 ]]'
sleep 1; s_as alice --set fm12 ati@10.0.0.112 >/dev/null
s_as bob --sync >/dev/null
check "alice's deliberate IP change reaches bob"        '[[ $(host_of bob fm12) == ati@10.0.0.112 ]]'
check "old IP still in the log"                         'grep -q "fm12 set ati@10.0.0.12" "$LOG"'
# concurrent edits of the same device: later timestamp wins on both sides
sed -i "s|^tug1 .*|tug1 ati@10.0.1.1|" "$T/alice/.config/ssh_shorty/machines.txt"
sleep 1
sed -i "s|^tug1 .*|tug1 ati@10.0.2.2|" "$T/bob/.config/ssh_shorty/machines.txt"
s_as bob --sync >/dev/null; s_as alice --sync >/dev/null; s_as bob --sync >/dev/null
check "conflict: newer edit (bob) wins for alice"       '[[ $(host_of alice tug1) == ati@10.0.2.2 ]]'
check "conflict: newer edit (bob) wins for bob"         '[[ $(host_of bob tug1) == ati@10.0.2.2 ]]'
check "conflict: losing edit still in history"          'grep -q "tug1 set ati@10.0.1.1" "$LOG"'

echo "retire / restore"
s_as alice --remove tug2 >/dev/null
s_as bob --sync >/dev/null
check "retired device gone for bob"                     '[[ -z $(host_of bob tug2) ]]'
check "retire is an event, set events kept"             'grep -q "tug2 retire" "$LOG" && grep -q "tug2 set" "$LOG"'
s_as bob --restore tug2 >/dev/null
s_as alice --sync >/dev/null
check "restored device back for alice"                  '[[ $(host_of alice tug2) == ati@10.0.0.32 ]]'
out=$(s_as alice --history tug2)
check "--history shows added/retired/restored"          'grep -q added <<<"$out" && grep -q retired <<<"$out" && grep -q restored <<<"$out"'
out=$(s_as alice --history fm12)
check "--history flags the IP change with old IP"       'grep -q "was ati@10.0.0.12" <<<"$out"'

echo "the incident: an emptied machines.txt"
lines_before=$(wc -l < "$LOG")
: > "$T/bob/.config/ssh_shorty/machines.txt"
s_as bob --sync >/dev/null
check "empty local file appends nothing"                '[[ $(wc -l < "$LOG") -eq $lines_before ]]'
check "bob's empty file rebuilt from the log"           '[[ $(map bob | wc -l) -eq 6 ]]'
head -1 "$T/bob/.config/ssh_shorty/machines.txt" > "$T/x" && mv "$T/x" "$T/bob/.config/ssh_shorty/machines.txt"
s_as bob --sync >/dev/null
check "truncated file can't bulk-retire"                '! grep -q " bob .* retire" <(tail -n +$((lines_before+1)) "$LOG")'
check "truncated file rebuilt (6 devices)"              '[[ $(map bob | wc -l) -eq 6 ]]'
: > "$LEGACY"
s_as alice --sync >/dev/null
check "empty legacy file doesn't hurt anyone"           '[[ $(map alice | wc -l) -eq 6 ]]'

echo "old-version clients (legacy machines.txt)"
cp "$T/alice/.config/ssh_shorty/machines.txt" "$LEGACY"
echo "oldnew ati@10.0.9.9" >> "$LEGACY"                         # old client adds a device
sed -i "s|^fm12 .*|fm12 ati@10.0.0.12 #fm|" "$LEGACY"            # …and has a stale IP
echo "tug2 ati@10.0.0.32" >> "$LEGACY"                           # …and a device the log knows
s_as alice --sync >/dev/null
check "old client's new device imported"                '[[ $(host_of alice oldnew) == ati@10.0.9.9 ]]'
check "old client's stale IP ignored"                   '[[ $(host_of alice fm12) == ati@10.0.0.112 ]]'

echo "first sync of an upgraded client with a stale copy"
mkclient carol
printf 'fm12 ati@10.0.0.12 #fm\ntug3 ati@10.0.0.33\ncarol1 ati@10.0.7.7\n' > "$T/carol/.config/ssh_shorty/machines.txt"
s_as alice --remove tug3 >/dev/null
s_as carol --sync >/dev/null
check "stale IP not pushed on first sync"               '[[ $(host_of carol fm12) == ati@10.0.0.112 ]]'
check "retired device not resurrected"                  '[[ -z $(host_of carol tug3) ]]'
check "carol's unknown device added"                    'grep -q "carol1 set ati@10.0.7.7" "$LOG"'

echo "concurrent appends don't lose events"
for i in 1 2 3 4 5; do
    echo "par$i ati@10.0.5.$i" >> "$T/alice/.config/ssh_shorty/machines.txt"
    s_as alice --sync >/dev/null &
    echo "pbr$i ati@10.0.6.$i" >> "$T/bob/.config/ssh_shorty/machines.txt"
    s_as bob --sync >/dev/null &
    wait
done
s_as alice --sync >/dev/null; s_as bob --sync >/dev/null
check "all 10 concurrent adds in the log"               '[[ $(grep -cE " (par|pbr)[0-9] set" "$LOG" | sort -u) -ge 10 ]]'
check "alice and bob converge"                          'diff <(map alice) <(map bob) >/dev/null'

echo "log is append-only from clients"
check "every log line is a well-formed event"           '! grep -qvE "^[0-9]+ [^ ]+ [^ ]+ (set .+|retire)$" "$LOG"'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
