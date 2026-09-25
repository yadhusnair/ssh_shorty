#!/usr/bin/env bash
#
# test-copy-dummy.sh — throwaway test script for `s --script`'s fzf arg-picker.
# Copies a dummy file into a dummy folder. Nothing real, safe to run/probe.

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<EOF
Usage: test-copy-dummy.sh --src <file> --dest <folder> [--name <newname>] [--force] [--dry-run]

  --src      source file to copy (default: a generated dummy file)
  --dest     destination folder (default: /tmp/test-copy-dummy-out)
  --name     rename the copy to this (default: keep original name)
  --force    overwrite if the destination file already exists
  --dry-run  print what would happen, don't actually copy
EOF
    exit 0
fi

SRC=""
DEST="/tmp/test-copy-dummy-out"
NAME=""
FORCE=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --src) [[ $# -lt 2 ]] && { echo "Missing value for --src"; exit 1; }; SRC="$2"; shift 2 ;;
        --dest) [[ $# -lt 2 ]] && { echo "Missing value for --dest"; exit 1; }; DEST="$2"; shift 2 ;;
        --name) [[ $# -lt 2 ]] && { echo "Missing value for --name"; exit 1; }; NAME="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

mkdir -p "$DEST"

if [[ -z "$SRC" ]]; then
    SRC=$(mktemp /tmp/test-copy-dummy-src.XXXXXX)
    echo "dummy content $(date)" > "$SRC"
    echo "No --src given, generated a dummy file: $SRC"
fi

TARGET="$DEST/${NAME:-$(basename "$SRC")}"

if [[ -f "$TARGET" && "$FORCE" -ne 1 ]]; then
    echo "FAILED: $TARGET already exists (use --force to overwrite)"
    exit 1
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY RUN: would copy $SRC -> $TARGET"
    exit 0
fi

cp "$SRC" "$TARGET" && echo "OK: copied $SRC -> $TARGET"
