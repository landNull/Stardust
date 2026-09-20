#!/bin/sh
# cleanup-stardust.sh — Modular tear-down control engine for Stardust
set -eu

PROG=${0##*/}
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# FIX SC2034: Export variables to ensure they are visible downstream to worker profiles
export STARDUST=/srv/stardust
DRYRUN=0
FORCE=0

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

# FIX SC2015: Avoid shorthand A && B || C traps to prevent duplicate non-root execution failures
as_root() {
  if [ "$(id -u)" -ne 0 ]; then
    sudo "$@"
  else
    "$@"
  fi
}

# Guard rails: Force confirming user intent
if [ "$FORCE" -ne 1 ] && [ "$DRYRUN" -ne 1 ]; then
  printf "⚠️ WARNING: This will completely tear down the Stardust control plane. Continue? [y/N]: "
  read -r ans
  case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "Tear-down aborted."; exit 0 ;; esac
fi

echo "🧹 Initializing Stardust system removal..."

# FIX SC2012: Drop problematic 'ls | sort | tr' string pipes. 
# We pull files via pure shell globbing, then utilize a clean conditional list builder.
if [ -d "$HERE/cleanup-modules" ]; then
  # Sift through matching path arrays natively
  for module_path in "$HERE/cleanup-modules/"[0-9][0-9]-*.sh; do
    [ -f "$module_path" ] || continue
    
    echo "▶️ Running Tear-down Module: $(basename "$module_path")"
    
    # Sourcing here guarantees global tracking context is flawlessly preserved
    # shellcheck source=/dev/null
    . "$module_path" || {
      echo "❌ Error: Module $(basename "$module_path") encountered a failure status." >&2
      exit 1
    }
  done
else
  echo "note: No cleanup modules detected in cleanup-modules/"
fi

echo "🏁 Stardust platform footprint successfully purged."
