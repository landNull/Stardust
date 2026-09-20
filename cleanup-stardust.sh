#!/bin/sh
# cleanup-stardust.sh — Modular tear-down control engine for Stardust
set -eu

PROG=${0##*/}
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# Export core boundaries to worker profiles
export STARDUST=/srv/stardust
export DRYRUN=0
export PURGE_ALL=0  # Initialize flag state tracker as false (0)
FORCE=0

usage() {
  cat <<EOF
Usage: $PROG [-n] [-f] [-p]
  -n  Dry run. Prints the destructive actions without executing them.
  -f  Force execution. Skips safety verification prompts.
  -p  Purge all. Wipes out core system packages (apt) and downloaded binaries (Gitea/Bee).
EOF
}

# Parse options
while [ $# -gt 0 ]; do
  case $1 in
    -n) DRYRUN=1 ;;
    -f) FORCE=1 ;;
    -p) PURGE_ALL=1 ;; # Capture the purge flag trigger
    -h) usage; exit 0 ;;
    *) echo "Unknown flag $1" >&2; exit 1 ;;
  esac
  shift
done

as_root() {
  if [ "$(id -u)" -ne 0 ]; then
    sudo "$@"
  else
    "$@"
  fi
}

# Guard rails: Force confirming user intent
if [ "$FORCE" -ne 1 ] && [ "$DRYRUN" -ne 1 ]; then
  if [ "$PURGE_ALL" -eq 1 ]; then
    printf "🚨 CRITICAL WARNING: This will completely UNINSTALL all database, web server, and binary engines. Continue? [y/N]: "
  else
    printf "⚠️ WARNING: This will completely tear down the Stardust control plane configurations. Continue? [y/N]: "
  fi
  read -r ans
  case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "Tear-down aborted."; exit 0 ;; esac
fi

echo "🧹 Initializing Stardust system removal..."

# Execute cleanup modules in REVERSE alphabetical order
if [ -d "$HERE/cleanup-modules" ]; then
  for module_path in "$HERE/cleanup-modules/"[0-9][0-9]-*.sh; do
    [ -f "$module_path" ] || continue
    
    echo "▶️ Running Tear-down Module: $(basename "$module_path")"
    
    # Sourcing guarantees $PURGE_ALL is cleanly available inside the sub-script
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
