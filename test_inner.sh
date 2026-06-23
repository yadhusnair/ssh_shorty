#!/bin/bash
# Runs inside the container — do not call directly

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq zsh rsync openssh-client bash-completion > /dev/null 2>&1

PASS=0; FAIL=0

ok()  { echo "  PASS  $1"; PASS=$((PASS+1)); }
fail(){ echo "  FAIL  $1"; FAIL=$((FAIL+1)); }
chk() { local label="$1"; shift; "$@" > /dev/null 2>&1 && ok "$label" || fail "$label"; }

echo ""
echo "── Installing ──────────────────────────────────────────"
cd /opt/ssh_shorty && bash install.sh
export PATH="$HOME/.local/bin:$PATH"

echo ""
echo "── Files ───────────────────────────────────────────────"
chk "s script installed"          test -x "$HOME/.local/bin/s"
chk "machines.txt present"        test -f "$HOME/.config/ssh_shorty/machines.txt"
chk "machines.txt has entries"    grep -q "fm85" "$HOME/.config/ssh_shorty/machines.txt"
chk "zsh completion installed"    test -f "$HOME/.zsh/completions/_s"
chk "bash completion installed"   test -f "$HOME/.config/ssh_shorty/completion.bash"
chk ".bashrc sources completion"  grep -q "ssh_shorty" "$HOME/.bashrc"
chk ".zshrc has fpath entry"      grep -q "zsh/completions" "$HOME/.zshrc"

echo ""
echo "── Commands ────────────────────────────────────────────"
chk "s --list runs"               s --list
chk "s --list shows fm85"         bash -c "s --list | grep -q fm85"
chk "s --add new device"          bash -c "s --add testdev ati@10.0.0.1 && grep -q testdev \$HOME/.config/ssh_shorty/machines.txt"
chk "s --set updates IP"          bash -c "s --set testdev ati@10.0.0.2 && grep -q '10.0.0.2' \$HOME/.config/ssh_shorty/machines.txt"
chk "s --remove deletes entry"    bash -c "s --remove testdev && ! grep -q testdev \$HOME/.config/ssh_shorty/machines.txt"
chk "s --add duplicate rejected"  bash -c "! s --add fm85 ati@1.2.3.4"
chk "s --ping missing arg fails"  bash -c "! s --ping"
chk "s bad flag fails"            bash -c "! s --badoption"
chk "s unknown nick fails"        bash -c "! s doesnotexist"
chk "s fuzzy suggestion shown"    bash -c "s fm 2>&1 | grep -qi 'did you mean'"

echo ""
echo "── Idempotency (re-run install) ────────────────────────"
bash /opt/ssh_shorty/install.sh > /dev/null 2>&1
chk "machines.txt unchanged after re-install"  grep -q "fm85" "$HOME/.config/ssh_shorty/machines.txt"
chk ".bashrc not duplicated"      bash -c "[[ \$(grep -c '^# ssh_shorty' \$HOME/.bashrc) -le 1 ]]"

echo ""
echo "── Results ─────────────────────────────────────────────"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""
(( FAIL == 0 )) && exit 0 || exit 1
