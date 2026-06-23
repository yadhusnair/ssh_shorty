#!/bin/bash

# Runs the full install inside a fresh Ubuntu container and checks every piece.
# Usage: ./test.sh [--shell]

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DROP_SHELL=false
[[ "$1" == "--shell" ]] && DROP_SHELL=true

IMAGE="ubuntu:22.04"

echo "Pulling $IMAGE..."
docker pull -q "$IMAGE"

if $DROP_SHELL; then
  echo "Starting interactive container (repo at /opt/ssh_shorty)..."
  docker run --rm -it \
    -v "$REPO_DIR":/opt/ssh_shorty \
    "$IMAGE" bash -c '
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq && apt-get install -y -qq zsh rsync openssh-client bash-completion > /dev/null 2>&1
      cd /opt/ssh_shorty && bash install.sh
      export PATH="$HOME/.local/bin:$PATH"
      echo ""
      echo "Ready. Try: s --list   s --add foo ati@1.2.3.4   s fm85:/home/<TAB>"
      exec bash --rcfile <(
        echo "source \$HOME/.bashrc 2>/dev/null"
        echo "source \$HOME/.config/ssh_shorty/completion.bash 2>/dev/null"
        echo "export PATH=\$HOME/.local/bin:\$PATH"
        echo "PS1=\"[fresh-install] \$ \""
      )
    '
  exit $?
fi

docker run --rm \
  -v "$REPO_DIR":/opt/ssh_shorty:ro \
  "$IMAGE" bash /opt/ssh_shorty/test_inner.sh
