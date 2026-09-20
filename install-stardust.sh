#!/bin/sh
# ==============================================================================
# install-stardust.sh — Modular System Orchestrator and Control Engine
# ==============================================================================
# Designed strictly for POSIX compliance (/bin/sh compatibility).
# Implements unified error trapping, safe env scoping, and automated module routing.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. ARCHITECTURAL SAFETY DIRECTIVES (The POSIX Guardrails)
# ------------------------------------------------------------------------------
# set -e: Instantly exit the script if any command returns a non-zero exit code.
# set -u: Treat unset or unassigned variables as a fatal error and exit immediately.
# Together, they prevent the script from running broken commands or corrupting paths.
set -eu

# ------------------------------------------------------------------------------
# 2. RUNTIME ENVIRONMENT DETECTIONS & CONSTANTS
# ------------------------------------------------------------------------------
# PROG: Strips path wrappers to isolate the raw executable filename ($0).
# HERE: Evaluates the absolute directory path of this script safely without 'readlink'.
PROG=${0##*/}
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
STARDUST_VERSION=0.4.0

# Define a persistent background log path to catch deep subcommand errors
LOGFILE="$HERE/install.log"
: > "$LOGFILE" # Pure POSIX idiom to cleanly truncate/create an empty file

# Logging helpers that mirror messages to the terminal screen and background file
log_info() {
  echo "$1"
  echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

log_err() {
  echo "$1" >&2 # Direct the text error layout explicitly to stderr (Descriptor 2)
  echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

# Source Code Layout Validation: Detect if running inside a Dev Repo or System Space
if [ -d "$HERE/bin" ] && [ -d "$HERE/lib" ]; then
  BINDIR=$HERE/bin; LIBSRC=$HERE/lib; MANDIR=$HERE/man; TUIDIR=$HERE/tui
else
  BINDIR=$HERE; LIBSRC=$HERE/stardust-lib; MANDIR=$HERE; TUIDIR=$HERE/stardust-tui
fi

# ------------------------------------------------------------------------------
# 3. GLOBAL ENGINE EXPORTS & DEFAULT SYSTEM CONSTRAINTS
# ------------------------------------------------------------------------------
# 'export' forces these flags down into subshells and sourced worker scripts.
export DRYRUN=0        # Simulation flag (1 = dry run, 0 = live execution)
export DO_CSF=0        # Firewall provisioning directive toggle
export LOCALHOST=0     # Local isolation toggle
export ROLE=devel      # Target deployment context tier (devel, test, live)

# Establish permission accounts using fallback variable evaluation parameters
export OWNER="${OWNER:-deploy}"
export ADMIN="${ADMIN:-www-admin}"
export GROUP="${GROUP:-www-admin}"

HUMAN=""
DAEMON=""
PLATFORMS=/srv/platforms
export STARDUST=/srv/stardust
BEE_SRC=https://github.com/backdrop-contrib/bee.git
BEE_DST=/usr/local/src/bee
BEE_BIN=/usr/local/bin/bee

# Dynamic environment matrices populated later via system probes
export PKG=unknown
export INIT=unknown
export OS_ID=unknown
export SVC_APACHE=""
export SVC_DB=""
export RELOAD_APACHE=""

# ------------------------------------------------------------------------------
# 4. SYSTEM UTILITY ENGINES & COMPLIANCE HELPER FUNCTIONS
# ------------------------------------------------------------------------------

# Escalates execution privileges gracefully if not currently logged in as root
as_root() { 
  if [ "$(id -u)" -ne 0 ]; then sudo "$@"; else "$@"; fi 
}

# Intercepts root command execution, logging stdout/stderr streams to the background
run_root() {
  if [ "$DRYRUN" -eq 1 ]; then
    printf '+'; for a in "$@"; do printf ' %s' "$a"; done; printf '
'; return 0
  fi
  cmd_summary="$1"
  [ -n "${2:-}" ] && cmd_summary="$cmd_summary $2"
  printf "  \\033[33m⏳ Processing:\\033[0m [%s] ...                     \r" "$cmd_summary"
  
  echo "Executing Root Command: $*" >> "$LOGFILE"
  
  # Temporarily relax 'set -e' to intercept non-zero codes manually without a crash
  set +e
  as_root "$@" >> "$LOGFILE" 2>&1
  cmd_status=$?
  set -eu # Re-engage absolute error protection
  
  if [ $cmd_status -eq 0 ]; then
    printf "  \\033[32m✓\\033[0m Completed: [%s]                               \n" "$cmd_summary"
  else
    printf "  \\033[31m✗\\033[0m Failed (%s): [%s]                             \n" "$cmd_status" "$cmd_summary"
    return $cmd_status
  fi
}

# Safely verifies binary presence on the system path without returning errors
have() { 
  command -v "$1" >/dev/null 2>&1 
}

# Cleans and sanitizes role strings using a safe case pattern match fall-through
normalize_role() {
  case $1 in
    devel|localhost|dev)          echo "devel" ;;
    test|vps-test)               echo "test" ;;
    live|vps-live|prod|production) echo "live" ;;
    *)                             echo "" ;;
  esac
}

# Detects the underlying OS variant and maps the appropriate native package manager
detect_os() {
  [ -f /etc/os-release ] && OS_ID=$(. /etc/os-release; echo "${ID:-unknown}")
  if have apt-get && have dpkg; then PKG=apt
  elif have apk; then PKG=apk
  elif have dnf; then PKG=dnf
  elif have yum; then PKG=yum
  else PKG=unknown; fi
}

# Detects the underlying active process system to find the operational init daemon model
detect_init() {
  if [ -d /run/systemd/system ] && have systemctl; then INIT=systemd
  elif [ -d /etc/init.d ] && [ ! -d /run/systemd/system ]; then INIT=sysv
  elif have rc-service; then INIT=openrc
  else INIT=unknown; fi
}

# Probes for the correct web server system daemon user account
detect_group() {
  if [ -z "$DAEMON" ]; then
    if getent passwd www-data >/dev/null 2>&1; then DAEMON=www-data
    elif getent passwd apache >/dev/null 2>&1; then DAEMON=apache
    else DAEMON=www-data; fi
  fi
}

# Maps standard system control names and live configuration reload blueprints
detect_services() {
  if [ -x /etc/init.d/apache2 ] || [ -d /etc/apache2 ]; then SVC_APACHE=apache2
  else SVC_APACHE=httpd; fi
  
  if [ -x /etc/init.d/mysql ] || have mysql; then SVC_DB=mysql
  else SVC_DB=mariadb; fi
  
  case $INIT in
    systemd) RELOAD_APACHE="systemctl reload $SVC_APACHE" ;;
    *)       RELOAD_APACHE="/etc/init.d/$SVC_APACHE reload" ;;
  esac
}

# Queries package tracking indexes idempotently to check if software is already active
pkg_ok() {
  case $PKG in
    apt) dpkg-query -W -f='\${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' ;;
    *)   return 1 ;;
  esac
}

# Interfaces with native package backends securely
pkg_install() {
  case $PKG in
    apt) run_root apt-get update && run_root apt-get install -y "$@" ;;
    *)   return 1 ;;
  esac
}

# Boots background daemons securely based on the active init architecture mapped
svc_start() {
  name=$1
  case $INIT in
    systemd) run_root systemctl enable "$name" 2>/dev/null || true; run_root systemctl start "$name" || true ;;
    *)       [ -x "/etc/init.d/$name" ] && run_root "/etc/init.d/$name" start || true ;;
  esac
}

# Deploys safe file overlays using a secure temporary buffer file swap pattern
write_dropin() {
  dest=$1
  [ "$DRYRUN" -eq 1 ] && echo "+ write $dest" && return 0
  as_root mkdir -p "$(dirname "$dest")"
  tmp=$(mktemp)
  cat > "$tmp"
  as_root install -m 0644 "$tmp" "$dest"
  rm -f "$tmp"
}

# Idempotent helper: Only writes a configuration drop-in file if it does not exist
write_if_absent() {
  [ -e "$1" ] || write_dropin "$1"
}

# Establishes the initial root environment configuration matrix layout
write_etc_conf() {
  dest=/etc/stardust.conf
  [ -f "$dest" ] && return 0
  [ "$DRYRUN" -eq 1 ] && return 0
  # Note: The 'EOF' delimiter is single-quoted to lock variables inside literal text strings
  as_root sh -c "cat > '$dest'" << 'EOF'
STARDUST_ROLE=$ROLE
STARDUST_ROOT=$STARDUST
EOF
}

# Fully interactive keyboard reader prompt engine
install_prompt() {
  q=$1; def=${2:-}; help=${3:-}
  while :; do
    printf '%s\n> [%s]: ' "$q" "$def" >&2
    IFS= read -r ans || ans=
    [ -n "$ans" ] || ans=$def
    printf '%s\n' "$ans"
    return 0
  done
}

# Stubs required for legacy script asset dependencies
gitea_conf_path() { return 1; }
gitea_installed() { return 1; }
maybe_gitea_defaults() { return 0; }
write_sudoers() { :; }

# ------------------------------------------------------------------------------
# 5. FIXED CLI FLAG SIFTER (The Command-Line Interface Input Loop)
# ------------------------------------------------------------------------------
# Handles argument parsing processing blocks step-by-step.
# Uses 'shift' to constantly pop the current checked option off the execution list.
while [ $# -gt 0 ]; do
  case $1 in
    -n) 
      DRYRUN=1 
      ;;
    -lh|--localhost) 
      LOCALHOST=1
      shift # FIXED: Discards the option immediately to avoid creating an infinite loop
      ;;
    -m) 
      ROLE=$(normalize_role "$2")
      shift 
      ;;
    *) 
      shift 
      ;;
  esac
done

# Initialize the runtime footprint
[ -z "$HUMAN" ] && HUMAN=$(whoami)
detect_os; detect_init; detect_group; detect_services
ROLE=$(normalize_role "$ROLE")

log_info "===================================================="
log_info "$PROG $STARDUST_VERSION — Running Fresh Stardust Orchestration..."
log_info "===================================================="

# Initialize configuration states before spawning the module cascade
write_etc_conf

# ------------------------------------------------------------------------------
# 6. UNREDIRECTED INTERACTIVE SEQUENTIAL ORCHESTRATION LOOP
# ------------------------------------------------------------------------------
# Scans the target folder and executes module scripts in a strict alphanumeric sequence.
if [ -d "$HERE/modules" ]; then
  for module in "$HERE/modules/"[0-9][0-9]-*.sh; do
    if [ -f "$module" ]; then
      
      # COMPLIANCE OVERRIDE: Skip the legacy file to prevent variable pollution
      if [ "$(basename "$module")" = "10-dependencies.sh" ]; then
        continue
      fi
      
      log_info "▶️ Running module: $(basename "$module")"
      
      # POSIX Conditional Sourcing Pattern: Evaluates the worker file directly inside 
      # the parent context, allowing interactive prompts while tracking execution status cleanly.
      if ! . "$module"; then
        log_err "❌ Error: Module $(basename "$module") failed execution."
        exit 1
      fi
    fi
  done
else
  log_err "❌ Error: modules/ folder configuration track could not be verified."
  exit 1
fi

log_info "Stardust orchestration loop completed successfully!"
