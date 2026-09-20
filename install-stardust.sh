#!/bin/sh
# install-stardust.sh — Modular orchestrator control engine for Stardust
set -eu

PROG=${0##*/}
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
STARDUST_VERSION=0.4.0

LOGFILE="$HERE/install.log"
: > "$LOGFILE"

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

as_root() { if [ "$(id -u)" -ne 0 ]; then sudo "$@"; else "$@"; fi }

run_root() {
  if [ "$DRYRUN" -eq 1 ]; then
    printf '+'; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; return 0
  fi
  cmd_summary="$1"
  [ -n "${2:-}" ] && cmd_summary="$cmd_summary $2"
  printf "  \\033[33m⏳ Processing:\\033[0m [%s] ...                     \r" "$cmd_summary"
  
  echo "Executing Root Command: $*" >> "$LOGFILE"
  
  set +e
  as_root "$@" >> "$LOGFILE" 2>&1
  cmd_status=$?
  set -eu
  
  if [ $cmd_status -eq 0 ]; then
    printf "  \\033[32m✓\\033[0m Completed: [%s]                               \n" "$cmd_summary"
  else
    printf "  \\033[31m✗\\033[0m Failed (%s): [%s]                             \n" "$cmd_status" "$cmd_summary"
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
}

detect_init() {
  if [ -d /run/systemd/system ] && have systemctl; then INIT=systemd
  elif [ -d /etc/init.d ] && [ ! -d /run/systemd/system ]; then INIT=sysv
  elif have rc-service; then INIT=openrc
  else INIT=unknown; fi
}

detect_group() {
  if [ -z "$DAEMON" ]; then
    if getent passwd www-data >/dev/null 2>&1; then DAEMON=www-data
    elif getent passwd apache >/dev/null 2>&1; then DAEMON=apache
    else DAEMON=www-data; fi
  fi
}

detect_services() {
  if [ -x /etc/init.d/apache2 ] || [ -d /etc/apache2 ]; then SVC_APACHE=apache2
  else SVC_APACHE=httpd; fi
  if [ -x /etc/init.d/mysql ] || have mysql; then SVC_DB=mysql
  else SVC_DB=mariadb; fi
  case $INIT in
    systemd) RELOAD_APACHE="systemctl reload $SVC_APACHE" ;;
    *) RELOAD_APACHE="/etc/init.d/$SVC_APACHE reload" ;;
  esac
}

pkg_ok() {
  case $PKG in
    apt) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' ;;
    *) return 1 ;;
  esac
}

pkg_install() {
  case $PKG in
    apt) run_root apt-get update && run_root apt-get install -y "$@" ;;
    *) return 1 ;;
  esac
}

svc_start() {
  name=$1
  case $INIT in
    systemd) run_root systemctl enable "$name" 2>/dev/null || true; run_root systemctl start "$name" || true ;;
    *) [ -x "/etc/init.d/$name" ] && run_root "/etc/init.d/$name" start || true ;;
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
}

write_if_absent() {
  [ -e "$1" ] || write_dropin "$1"
}

write_etc_conf() {
  dest=/etc/stardust.conf
  [ -f "$dest" ] && return 0
  [ "$DRYRUN" -eq 1 ] && return 0
  as_root sh -c "cat > '$dest'" << 'EOF'
STARDUST_ROLE=$ROLE
STARDUST_ROOT=$STARDUST
EOF
}

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

gitea_conf_path() { return 1; }
gitea_installed() { return 1; }
maybe_gitea_defaults() { return 0; }
write_sudoers() { :; }

while [ $# -gt 0 ]; do
  case $1 in
    -n) DRYRUN=1 ;;
    -lh|--localhost) LOCALHOST=1 ;;
    -m) ROLE=$(normalize_role "$2"); shift ;;
    *) shift ;;
  esac
done

[ -z "$HUMAN" ] && HUMAN=$(whoami)
detect_os; detect_init; detect_group; detect_services
ROLE=$(normalize_role "$ROLE")

log_info "===================================================="
log_info "$PROG $STARDUST_VERSION — Running Fresh Stardust Orchestration..."
log_info "===================================================="

write_etc_conf

# --- Safe, Unredirected POSIX Compliant Sourcing Loop ---
if [ -d "$HERE/modules" ]; then
  for module in "$HERE/modules/"[0-9][0-9]-*.sh; do
    if [ -f "$module" ]; then
      # CRITICAL: Ignore the legacy file if it's still floating around
      if [ "$(basename "$module")" = "10-dependencies.sh" ]; then
        continue
      fi
      
      echo "▶️ Running module: $(basename "$module")"
      
      if ! . "$module"; then
        log_err "❌ Error: Module $(basename "$module") failed execution."
        exit 1
      fi
    fi
  done
else
  log_err "❌ Error: modules/ folder not found."
  exit 1
fi

log_info "Stardust orchestration loop completed!"
