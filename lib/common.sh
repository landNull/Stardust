# shellcheck shell=sh
# Shared helpers. Sourced by /usr/local/bin/stardust — not run alone.

load_conf() {
  for f in \
    "${STARDUST_CONF:-}" \
    "$HOME/.stardust.conf" \
    /etc/stardust.conf
  do
    if [ -n "$f" ] && [ -f "$f" ]; then
      # shellcheck disable=SC1090
      . "$f"
      return 0
    fi
  done
  return 0
}

load_conf

STARDUST_ROOT=${STARDUST_ROOT:-/srv/stardust}
PLATFORMS=${PLATFORMS:-/srv/platforms}
OWNER=${OWNER:-deploy}
ADMIN=${ADMIN:-www-admin}
HUMAN=${HUMAN:-}
DAEMON=${DAEMON:-www-data}
GROUP=${GROUP:-www-admin}
DIR_MODE=${DIR_MODE:-0770}

PRIV=${PRIV:-/usr/local/sbin/stardust-priv}

priv() {
  if [ -x "$PRIV" ]; then
    as_root "$PRIV" "$@"
  else
    return 1
  fi
}

# PHP-writable trees: www-data:www-admin + setgid + default ACL
chown_files() {
  if priv chown-files "$@"; then
    priv setacl "$@" || true
    return 0
  fi
  run_root chown -R "$DAEMON:$GROUP" "$@"
}

# code / backups / control plane: deploy:www-admin
chown_code() {
  if priv chown-code "$@"; then
    priv setacl "$@" || true
    return 0
  fi
  run_root chown -R "$OWNER:$GROUP" "$@"
}

chown_secret() {
  if priv chown-secret "$@"; then
    priv setacl-secret "$@" || true
    return 0
  fi
  run_root chown -R "$OWNER:stardust" "$@"
  run_root chmod 0640 "$@"
}
BEE=${BEE:-bee}
APACHE_RELOAD=${APACHE_RELOAD:-/etc/init.d/apache2 reload}
STARDUST_ROLE=${STARDUST_ROLE:-devel}
DB_HOST=${DB_HOST:-127.0.0.1}
DB_PREFIX=${DB_PREFIX:-bd_}
KEEP_BACKUPS=${KEEP_BACKUPS:-7}
NOTIFY=${NOTIFY:-}
HOOKS=${HOOKS:-$STARDUST_ROOT/hooks}

run_hooks() {
  name=$1
  shift
  dir=$HOOKS/${name}.d
  [ -d "$dir" ] || return 0
  for h in "$dir"/*; do
    [ -x "$h" ] || continue
    if [ "${DRYRUN:-0}" -eq 1 ]; then
      echo "+ hook $h $*"
    else
      echo "hook $h"
      "$h" "$@" || note "hook $h exited $?"
    fi
  done
}

bee_yes() {
  bee=$(bee_bin)
  if [ "${DRYRUN:-0}" -eq 1 ]; then
    echo "+ $bee -y $*"
    return 0
  fi
  if as_root -u "$OWNER" "$bee" -y "$@"; then
    return 0
  fi
  printf 'y\n' | as_root -u "$OWNER" "$bee" "$@"
}

notify_fail() {
  msg=$1
  if have logger; then
    logger -t stardust -- "$msg" || true
  fi
  if [ -n "$NOTIFY" ] && have mail; then
    printf '%s\n' "$msg" | mail -s "stardust: $msg" "$NOTIFY" || true
  fi
}

in_group() {
  echo " $(id -nG 2>/dev/null) " | grep -q " $1 "
}

# Missing required groups -> return 1 and print usermod for self or admin.
check_operator_groups() {
  me=$(id -un)
  need="$GROUP stardust"
  nice="adm $OWNER"
  miss_need=""
  miss_nice=""
  for g in $need; do
    [ -n "$g" ] || continue
    if ! getent group "$g" >/dev/null 2>&1; then
      miss_need="$miss_need $g"
      continue
    fi
    in_group "$g" || miss_need="$miss_need $g"
  done
  for g in $nice; do
    [ -n "$g" ] || continue
    getent group "$g" >/dev/null 2>&1 || continue
    in_group "$g" || miss_nice="$miss_nice $g"
  done
  if [ -z "$miss_need" ] && [ -z "$miss_nice" ]; then
    return 0
  fi
  echo "$PROG: user $me is missing group membership" >&2
  if [ -n "$miss_need" ]; then
    echo "$PROG: required:$miss_need" >&2
  fi
  if [ -n "$miss_nice" ]; then
    echo "$PROG: recommended:$miss_nice" >&2
  fi
  all=$(echo "$miss_need $miss_nice" | tr -s ' ' | sed 's/^ //;s/ $//')
  echo "$PROG: add yourself (if you have sudo):" >&2
  echo "  sudo usermod -aG $(echo "$all" | tr ' ' ',') $me" >&2
  echo "  then a new login shell (exec bash / exec zsh do NOT refresh groups):" >&2
  echo "    exec su - $me" >&2
  echo "    # or: newgrp $GROUP" >&2
  echo "    # or log out and back in" >&2
  echo "$PROG: or ask an admin to run that usermod for $me" >&2
  [ -n "$miss_need" ] && return 1
  return 0
}

have() { command -v "$1" >/dev/null 2>&1; }
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; }
note() { printf '  note  %s\n' "$1"; }

# Root only when needed. Prefer sudo -n (NOPASSWD). Password prompt
# only if no silent path exists.
as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return $?
  fi
  if [ "${1:-}" = "-u" ]; then
    tgt=$2
    shift 2
    if [ "$(id -un)" = "$tgt" ]; then
      "$@"
      return $?
    fi
    if have sudo && sudo -n -u "$tgt" true >/dev/null 2>&1; then
      sudo -n -u "$tgt" "$@"
      return $?
    fi
    sudo -u "$tgt" "$@"
    return $?
  fi
  if have sudo && sudo -n true >/dev/null 2>&1; then
    sudo -n "$@"
    return $?
  fi
  sudo "$@"
}

run() {
  if [ "${DRYRUN:-0}" -eq 1 ]; then
    printf '+'
    for a in "$@"; do
      printf ' %s' "$a"
    done
    printf '\n'
    return 0
  fi
  "$@"
}

run_root() {
  if [ "${DRYRUN:-0}" -eq 1 ]; then
    printf '+'
    for a in "$@"; do
      printf ' %s' "$a"
    done
    printf '\n'
    return 0
  fi
  as_root "$@"
}

bee_bin() {
  if have "$BEE"; then
    command -v "$BEE"
  elif have bee; then
    command -v bee
  else
    echo "$PROG: bee not on PATH" >&2
    exit 1
  fi
}

need_crdir() {
  if have crdir; then
    command -v crdir
  else
    echo "$PROG: crdir not on PATH" >&2
    exit 1
  fi
}

slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9.-' '-' | sed 's/^-*//;s/-*$//'
}

db_name() {
  product=$1
  role=${2:-$STARDUST_ROLE}
  n="${DB_PREFIX}${product}_${role}"
  printf '%s' "$n" | tr -c 'a-z0-9_' '_' | cut -c1-64
}

resolve_site() {
  # sets root web platform product or exits
  platform=$(slug "${1:-}")
  product=$(slug "${2:-}")
  if [ -z "$platform" ] || [ -z "$product" ]; then
    echo "usage: $PROG $cmd PLATFORM PRODUCT" >&2
    exit 2
  fi
  root=$PLATFORMS/$platform
  web=$root/web
  if [ ! -d "$root" ]; then
    echo "$PROG: no platform $root" >&2
    exit 1
  fi
  if [ ! -d "$web" ]; then
    echo "$PROG: $web missing" >&2
    exit 1
  fi
}

stamp() {
  date +%Y%m%d-%H%M%S
}

backup_dir() {
  platform=$1
  product=$2
  role=${3:-$STARDUST_ROLE}
  echo "$STARDUST_ROOT/backups/$platform/$product/$role"
}
