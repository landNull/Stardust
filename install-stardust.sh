#!/bin/sh
# install-stardust.sh — Modular orchestrator control engine for Stardust
# Enhanced with verbose debugging logging infrastructure (install.log)
set -eu

PROG=${0##*/}
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
STARDUST_VERSION=0.4.0

# --- SETUP VERBOSE FILE LOGGING DIRECTIVES ---
LOGFILE="$HERE/install.log"
# Clear or create a fresh trace log file for this execution session
: > "$LOGFILE"

# Custom logging engine that captures standard messages and updates file traces
log_info() {
  echo "$1"
  echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

log_err() {
  echo "$1" >&2
  echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

if [ -f "$HERE/VERSION" ]; then
  STARDUST_VERSION=$(tr -d ' \r\n' < "$HERE/VERSION")
fi
if [ -d "$HERE/bin" ] && [ -d "$HERE/lib" ]; then
  BINDIR=$HERE/bin; LIBSRC=$HERE/lib; MANDIR=$HERE/man; TUIDIR=$HERE/tui
else
  BINDIR=$HERE; LIBSRC=$HERE/stardust-lib; MANDIR=$HERE; TUIDIR=$HERE/stardust-tui
fi

export DRYRUN=0; export DO_CSF=0; export LOCALHOST=0; export ROLE=devel
export OWNER="${OWNER:-deploy}"; export ADMIN="${ADMIN:-www-admin}"; export GROUP="${GROUP:-www-admin}"
HUMAN=""; DAEMON=""; PLATFORMS=/srv/platforms; export STARDUST=/srv/stardust
CSF_ALLOW="10.8.0.0/24 192.168.1.0/24"; BEE_SRC=https://github.com
BEE_DST=/usr/local/src/bee; BEE_BIN=/usr/local/bin/bee

export PKG=unknown; export INIT=unknown; export OS_ID=unknown; export SVC_APACHE=""
export SVC_DB=""; export RELOAD_APACHE=""

usage() {
  cat <<EOF
Usage: $PROG [options]
  -n               Dry run mode. Simulates configuration passings.
  -lh|--localhost  Force local runtime environments.
  -F               Enable CSF firewall setups.
  -m <role>        System deployment role (devel, test, live).
  -u <owner>       Override code asset storage owner account.
  -a <admin>       Override administrator account identity.
  -g <group>       Override default systems worker execution group.
  -h               Show this help architecture overview menu.
EOF
}

as_root() { if [ "$(id -u)" -ne 0 ]; then sudo "$@"; else "$@"; fi }

run_root() {
  if [ "$DRYRUN" -eq 1 ]; then
    printf '+'; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; return 0
  fi
  cmd_summary="$1"
  [ -n "${2:-}" ] && cmd_summary="$cmd_summary $2"
  printf "  \\033[33m⏳ Processing:\\033[0m [%s] ...                     \r" "$cmd_summary"
  
  # Stream raw sub-command terminal streams comprehensively into the logfile background
  echo "Executing Root Command: $*" >> "$LOGFILE"
  
  set +e
  as_root "$@" >> "$LOGFILE" 2>&1
  cmd_status=$?
  set -eu
  
  if [ $cmd_status -eq 0 ]; then
    printf "  \\033[32m✓\\033[0m Completed: [%s]                               \n" "$cmd_summary"
    echo "Command completed successfully." >> "$LOGFILE"
  else
    printf "  \\033[31m✗\\033[0m Failed (%s): [%s]                             \n" "$cmd_status" "$cmd_summary"
    echo "Command failed with status code: $cmd_status" >> "$LOGFILE"
    return $cmd_status
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

normalize_role() {
  case $1 in
    devel|localhost|dev) echo "devel" ;;
    test|vps-test) echo "test" ;;
    live|vps-live|prod|production) echo "live" ;;
    *) echo "" ;;
  esac
}

detect_os() {
  [ -f /etc/os-release ] && OS_ID=$(. /etc/os-release; echo "${ID:-unknown}")
  if have apt-get && have dpkg; then PKG=apt
  elif have apk; then PKG=apk
  elif have dnf; then PKG=dnf
  elif have yum; then PKG=yum
  else PKG=unknown; fi
  echo "OS Detection: ID=$OS_ID, PKG=$PKG" >> "$LOGFILE"
}

detect_init() {
  if [ -d /run/systemd/system ] && have systemctl; then INIT=systemd
  elif [ -d /etc/init.d ] && [ ! -d /run/systemd/system ]; then INIT=sysv
  elif have rc-service; then INIT=openrc
  elif [ -x /etc/init.d/apache2 ] || [ -x /etc/init.d/httpd ]; then INIT=sysv
  elif have systemctl; then INIT=systemd
  else INIT=unknown; fi
  echo "Init Detection: INIT=$INIT" >> "$LOGFILE"
}

detect_group() {
  if [ -z "$DAEMON" ]; then
    if getent passwd www-data >/dev/null 2>&1; then DAEMON=www-data
    elif getent passwd apache >/dev/null 2>&1; then DAEMON=apache
    else DAEMON=www-data; fi
  fi
  echo "Group Detection: DAEMON=$DAEMON" >> "$LOGFILE"
}

detect_services() {
  if [ -x /etc/init.d/apache2 ] || [ -d /etc/apache2 ]; then SVC_APACHE=apache2
  elif [ -x /etc/init.d/httpd ] || [ -d /etc/httpd ]; then SVC_APACHE=httpd
  else SVC_APACHE=apache2; fi
  if [ -x /etc/init.d/mysql ] || have mysql; then SVC_DB=mysql
  elif [ -x /etc/init.d/mariadb ]; then SVC_DB=mariadb
  else SVC_DB=mysql; fi
  case $INIT in
    systemd) RELOAD_APACHE="systemctl reload $SVC_APACHE" ;;
    openrc) RELOAD_APACHE="rc-service $SVC_APACHE reload" ;;
    sysv|unknown) RELOAD_APACHE="/etc/init.d/$SVC_APACHE reload" ;;
  esac
  echo "Service Detection: SVC_APACHE=$SVC_APACHE, SVC_DB=$SVC_DB" >> "$LOGFILE"
}

pkg_ok() {
  case $PKG in
    apt) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' ;;
    apk) apk info -e "$1" >/dev/null 2>&1 ;;
    dnf|yum) rpm -q "$1" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

pkg_install() {
  case $PKG in
    apt) run_root apt-get update && run_root apt-get install -y "$@" ;;
    apk) run_root apk add --no-cache "$@" ;;
    dnf) run_root dnf install -y "$@" ;;
    yum) run_root yum install -y "$@" ;;
    *) echo "$PROG: no package manager detected" >&2; return 1 ;;
  esac
}

svc_start() {
  name=$1
  case $INIT in
    systemd) run_root systemctl enable "$name" 2>/dev/null || true; run_root systemctl start "$name" || true ;;
    openrc) run_root rc-update add "$name" default 2>/dev/null || true; run_root rc-service "$name" start || true ;;
    sysv|unknown) [ -x "/etc/init.d/$name" ] && run_root "/etc/init.d/$name" start || true ;;
  esac
}

write_dropin() {
  dest=$1
  [ "$DRYRUN" -eq 1 ] && echo "+ write $dest" && return 0
  as_root mkdir -p "$(dirname "$dest")"
  tmp=$(mktemp)
  cat > "$tmp"
  as_root install -m 0644 "$tmp" "$dest"
  rm -f "$tmp"
  echo "wrote $dest"
}

write_if_absent() {
  target_file=$1
  [ -e "$target_file" ] && echo "exists: $target_file" || write_dropin "$target_file"; 
}

write_etc_conf() {
  dest=/etc/stardust.conf
  [ -f "$dest" ] && echo "global config exists: $dest" && return 0
  [ "$DRYRUN" -eq 1 ] && echo "+ write $dest" && return 0
  as_root sh -c "cat > '$dest'" << 'EOF'
STARDUST_ROLE=$ROLE
STARDUST_ROOT=$STARDUST
PLATFORMS=$PLATFORMS
OWNER=$OWNER
ADMIN=$ADMIN
DAEMON=$DAEMON
GROUP=$GROUP
BEE=$(command -v bee 2>/dev/null || echo $BEE_BIN)
APACHE_SERVICE=$SVC_APACHE
DB_SERVICE=$SVC_DB
APACHE_RELOAD="$RELOAD_APACHE"
STARDUST_VERSION=$STARDUST_VERSION
EOF
  as_root chmod 0644 "$dest"
}

# --- CLI Flag Sifter ---
while [ $# -gt 0 ]; do
  case $1 in
    -n) DRYRUN=1 ;;
    -lh|--localhost) LOCALHOST=1 ;;
    -F) DO_CSF=1 ;;
    -m) ROLE=$(normalize_role "$2"); [ "$ROLE" = "devel" ] && LOCALHOST=1; shift ;;
    -u) OWNER=$2; shift ;;
    -a) ADMIN=${2:-}; shift ;;
    -H) HUMAN=${2:-}; shift ;;
    -g) GROUP=${2:-}; shift ;;
    -h) usage; exit 0 ;;
    *) echo "$PROG: unknown flag $1" >&2; exit 1 ;;
  esac
  shift
done

[ -z "$HUMAN" ] && HUMAN=${SUDO_USER:-$(whoami)}
detect_os; detect_init; detect_group; detect_services
ROLE=$(normalize_role "$ROLE")

log_info "===================================================="
log_info "$PROG $STARDUST_VERSION — Starting Stardust installation..."
log_info "===================================================="

echo "Active Environment Options Locked:" >> "$LOGFILE"
echo "  DRYRUN=$DRYRUN, LOCALHOST=$LOCALHOST, ROLE=$ROLE, OWNER=$OWNER, ADMIN=$ADMIN" >> "$LOGFILE"

write_etc_conf

# --- Sequential Orchestration Loop with Explicit File Tapping ---
if [ -d "$HERE/modules" ]; then
  for module in "$HERE/modules/"[0-9][0-9]-*.sh; do
    if [ -f "$module" ]; then
      log_info "▶️ Running module: $(basename "$module")"
      
      # Open subshell architecture isolation to lock trace streams seamlessly
      (
        # Turn on extreme line-by-line statement profiling inside the module boundary
        set -x
        # Force stderr evaluation tracks straight into the central text file
        . "$module"
      ) >> "$LOGFILE" 2>&1
      module_status=$?
      
      echo "[STATUS] Module $(basename "$module") finished execution with exit code ($module_status)." >> "$LOGFILE"
      
      if [ $module_status -ne 0 ]; then
        log_err "❌ Error: Module $(basename "$module") failed to execute correctly (Check install.log for details)."
        exit 1
      fi
    fi
  done
else
  log_err "❌ Error: The modules/ folder configuration area could not be reached."
  exit 1
fi

log_info "Stardust installation sequence complete successfully!"
