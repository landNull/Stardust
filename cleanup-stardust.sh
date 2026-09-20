#!/bin/sh
# cleanup-stardust.sh — Modular tear-down control engine for Stardust
set -eu

PROG=${0##*/}
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

DRYRUN=0
FORCE=0
STARDUST=/srv/stardust

usage() {
  cat <<EOF
Usage: $PROG [-n] [-f]
  -n  Dry run. Prints the destructive actions without executing them.
  -f  Force execution. Skips safety verification prompts.
EOF
}

# Parse options
while [ $# -gt 0 ]; do
  case $1 in
    -n) DRYRUN=1 ;;
    -f) FORCE=1 ;;
    -h) usage; exit 0 ;;
    *) echo "Unknown flag $1" >&2; exit 1 ;;
  esac
  shift
done

as_root() { [ "$(id -u)" -ne 0 ] && sudo "$@" || "$@"; }

# Guard rails: Force confirming user intent
if [ "$FORCE" -ne 1 ] && [ "$DRYRUN" -ne 1 ]; then
  printf "⚠️ WARNING: This will completely tear down the Stardust control plane. Continue? [y/N]: "
  read -r ans
  case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "Tear-down aborted."; exit 0 ;; esac
fi

echo "🧹 Initializing Stardust system removal..."

# Execute cleanup modules in REVERSE alphabetical order to handle system dependencies
# By reversing the sequence loop, we peel away layers from the outside in.
if [ -d "$HERE/cleanup-modules" ]; then
  for module in "$HERE/cleanup-modules/"[0-9][0-9]-*.sh; do
    # Collect files into a list we can reverse sort
    echo "$module"
  done | sort -r | while read -r module_path; do
    if [ -f "$module_path" ]; then
      echo "▶️ Running Tear-down Module: $(basename "$module_path")"
      . "$module_path"
    fi
  done
fi

echo "🏁 Stardust platform footprint successfully purged."
