#!/bin/sh
# stardust-install.sh — idempotent bootstrap for Stardust
# Same script on knarr (devel) and the VPS (test / live).
# Contract: artifacts/stardust-settings.json
#
# Detects package manager and init. Does not assume Devuan or systemd.
# Creates deploy + www-admin, ships crdir/newfeature/stardust, tunes
# PHP/MariaDB/Apache, writes logrotate + state. No PHP GUI.
# Does not wipe /srv/platforms or existing platform checkouts.
# Does not install nginx, Podman, or rewrite firewall/VPN.
#
# Usage:
#   stardust-install.sh [-n] [-m ROLE] [-u USER] [-g GROUP] [-a ADMIN]
#   stardust-install.sh -h
#
# ROLE: devel | test | live
#       knarr-devel, vps-test, vps-live still accepted as aliases.

set -eu

PROG=${0##*/}
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STARDUST_VERSION=0.3.0
if [ -f "$HERE/VERSION" ]; then
  STARDUST_VERSION=$(tr -d ' \n' < "$HERE/VERSION")
fi
if [ -d "$HERE/bin" ] && [ -d "$HERE/lib" ]; then
  BINDIR=$HERE/bin
  LIBSRC=$HERE/lib
  MANDIR=$HERE/man
  TUIDIR=$HERE/tui
else
  BINDIR=$HERE
  LIBSRC=$HERE/stardust-lib
  MANDIR=$HERE
  TUIDIR=$HERE/stardust-tui
fi
DRYRUN=0
DO_CSF=0
LOCALHOST=0
ROLE=devel
OWNER=deploy
ADMIN=www-admin
HUMAN=""
DAEMON=""
GROUP=""
PLATFORMS=/srv/platforms
STARDUST=/srv/stardust
CONF=""
BEE_SRC=https://github.com/backdrop-contrib/bee.git
BEE_DST=/usr/local/src/bee
BEE_BIN=/usr/local/bin/bee

PKG=unknown
INIT=unknown
OS_ID=unknown
SVC_APACHE=""
SVC_DB=""
RELOAD_APACHE=""

usage() {
  cat <<EOF
$PROG $STARDUST_VERSION — prepare any Stardust host (Apache + PHP + MariaDB + Bee)

WHAT THIS IS FOR
  One script for knarr and the VPS. Detects apt vs other managers and
  sysvinit vs systemd vs OpenRC. Creates users deploy and www-admin,
  the $STARDUST control plane, missing packages, PHP/MariaDB snippets,
  companion CLIs (crdir, newfeature, stardust, bee), and conf files.
  PHP: 30-stardust.ini every SAPI; 35-stardust-harden.ini FPM/apache2
  only; 35-stardust-cli.ini leaves Bee able to exec.
  Also: php-intl/bcmath/imagick/apcu, apache2-utils, mariadb-backup,
  msmtp-mta, unattended-upgrades (no auto-reboot), needrestart,
  logwatch, goaccess, etckeeper, smartmontools, irqbalance, haveged,
  moreutils, jq, pv, age.
  Leaves $PLATFORMS trees alone. No Aegir/BOA frontend.

USERS
  $OWNER      owns platforms and the control plane; limited sudo
  $ADMIN      extra login that writes the same 0770 trees
  operator    login that runs stardust day to day.
                 Default: the account that invoked this script
                 (SUDO_USER or USER), never a hard-coded name.
                 Override with -H. Groups: $GROUP, stardust, adm, $OWNER.
  $GROUP     Apache daemon group (www-data or apache).

  Passwords are not set. After the first run:
    sudo passwd $OWNER
    sudo passwd $ADMIN
    sudo passwd OPERATOR   # the login that ran this script, or -H NAME
  Drop SSH keys into each home's .ssh/authorized_keys yourself.

HOW TO RUN IT
  $PROG [-n] [-lh|--localhost] [-F] [-m devel|test|live] [-u owner] [-a admin] [-H human] [-g group]
  $PROG -h

  Run as a sudo-capable account. Do not type "sudo $PROG".

FLAGS
  -n         Dry run. Print the plan with a leading + and change nothing.
  -lh, --localhost
             Local dev box only (127.0.0.1). Skips CSF, WireGuard
             policy, and certbot. Installs dnsmasq (*.devel → 127.0.0.1).
             Role becomes devel. Apache and MariaDB stay on localhost.
  -m ROLE    devel (default), test, or live
  -u owner   Code owner (default: deploy)
  -a admin   File-admin login (default: www-admin)
  -H user    Daily operator (default: whoever ran this script)
  -g group   File group on every tree (default: www-admin)
  -F         Install/apply CSF. SSH is not world-open: only 10.8.0.0/24
             (WireGuard) and 192.168.1.0/24 (LAN). UDP 51820 stays open
             for the tunnel. HTTP 80 on devel; 80+443 on test/live.
             First enable uses CSF TESTING=1 so a lockout self-reverts.
  -h         This text

SAFE FIRST RUN
  laptop: $PROG -n --localhost
  knarr:  $PROG -n -m devel
  VPS:    $PROG -n -m test     (or -m live)

WHAT IT WILL NOT DO
  Touch files inside $PLATFORMS/<platform>
  Enable a catch-all vhost
  Rewrite an existing WireGuard interface (CSF only adds allow rules)
  Set or print account passwords
  Start a container runtime
EOF
}

as_root() {
  if [ "$(id -u)" -ne 0 ]; then
    sudo "$@"
  else
    "$@"
  fi
}

run_root() {
  if [ "$DRYRUN" -eq 1 ]; then
    printf '+'
    for a in "$@"; do
      printf ' %s' "$a"
    done
    printf '\n'
    return 0
  fi
  as_root "$@"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

normalize_role() {
  case $1 in
    devel|knarr-devel|localhost|dev) echo devel ;;
    test|vps-test) echo test ;;
    live|vps-live|prod|production) echo live ;;
    *) echo "" ;;
  esac
}

detect_os() {
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    OS_ID=$(. /etc/os-release; echo "${ID:-unknown}")
  fi
  if have apt-get && have dpkg; then
    PKG=apt
  elif have apk; then
    PKG=apk
  elif have dnf; then
    PKG=dnf
  elif have yum; then
    PKG=yum
  else
    PKG=unknown
  fi
}

detect_init() {
  if [ -d /run/systemd/system ] && have systemctl; then
    INIT=systemd
  elif [ -d /etc/init.d ] && [ ! -d /run/systemd/system ]; then
    INIT=sysv
  elif have rc-service; then
    INIT=openrc
  elif [ -x /etc/init.d/apache2 ] || [ -x /etc/init.d/httpd ]; then
    INIT=sysv
  elif have systemctl; then
    INIT=systemd
  else
    INIT=unknown
  fi
}

detect_group() {
  if [ -z "$DAEMON" ]; then
    if getent passwd www-data >/dev/null 2>&1; then
      DAEMON=www-data
    elif getent passwd apache >/dev/null 2>&1; then
      DAEMON=apache
    else
      DAEMON=www-data
    fi
  fi
  if [ -z "$GROUP" ]; then
    GROUP=www-admin
  fi
}

detect_services() {
  SVC_APACHE=""
  SVC_DB=""
  if [ -x /etc/init.d/apache2 ] || [ -d /etc/apache2 ]; then
    SVC_APACHE=apache2
  elif [ -x /etc/init.d/httpd ] || [ -d /etc/httpd ]; then
    SVC_APACHE=httpd
  else
    SVC_APACHE=apache2
  fi
  if [ -x /etc/init.d/mysql ] || have mysql; then
    SVC_DB=mysql
  elif [ -x /etc/init.d/mariadb ]; then
    SVC_DB=mariadb
  else
    SVC_DB=mysql
  fi

  case $INIT in
    systemd)
      RELOAD_APACHE="systemctl reload $SVC_APACHE"
      ;;
    openrc)
      RELOAD_APACHE="rc-service $SVC_APACHE reload"
      ;;
    sysv|unknown)
      RELOAD_APACHE="/etc/init.d/$SVC_APACHE reload"
      ;;
  esac
}

pkg_ok() {
  case $PKG in
    apt)
      dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
      ;;
    apk)
      apk info -e "$1" >/dev/null 2>&1
      ;;
    dnf|yum)
      rpm -q "$1" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

pkg_install() {
  case $PKG in
    apt)
      run_root apt-get update
      run_root apt-get install -y "$@"
      ;;
    apk)
      run_root apk add --no-cache "$@"
      ;;
    dnf)
      run_root dnf install -y "$@"
      ;;
    yum)
      run_root yum install -y "$@"
      ;;
    *)
      echo "$PROG: no package manager detected; install Apache PHP MariaDB git sudo by hand" >&2
      return 1
      ;;
  esac
}

svc_start() {
  name=$1
  case $INIT in
    systemd)
      run_root systemctl enable "$name" 2>/dev/null || true
      run_root systemctl start "$name" || true
      ;;
    openrc)
      run_root rc-update add "$name" default 2>/dev/null || true
      run_root rc-service "$name" start || true
      ;;
    sysv|unknown)
      if [ -x "/etc/init.d/$name" ]; then
        run_root "/etc/init.d/$name" start || true
      fi
      ;;
  esac
}

pkg_list_for() {
  case $PKG in
    apt)
      echo "sudo apache2 mariadb-server git curl unzip rsync ca-certificates acl"
      echo "php php-cli php-mysql php-xml php-gd php-mbstring php-curl php-zip php-fpm"
      echo "php-intl php-bcmath php-imagick php-apcu"
      echo "libapache2-mod-php apache2-utils"
      echo "mariadb-backup msmtp-mta unattended-upgrades needrestart"
      echo "logwatch goaccess etckeeper smartmontools irqbalance haveged"
      echo "moreutils jq pv age"
      if [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = devel ]; then
        echo "dnsmasq"
      fi
      if [ "$LOCALHOST" -eq 0 ] && { [ "$ROLE" = test ] || [ "$ROLE" = live ]; }; then
        echo "certbot python3-certbot-apache"
      fi
      if [ "$LOCALHOST" -eq 0 ] && [ "$DO_CSF" -eq 1 ]; then
        echo "iptables perl libwww-perl liblwp-protocol-https-perl libgd-perl"
      fi
      ;;
    apk)
      echo "sudo apache2 mariadb mariadb-client git curl unzip rsync acl"
      echo "php php-cli php-mysqli php-xml php-gd php-mbstring php-curl php-zip apache2-proxy"
      echo "php-intl php-bcmath imagemagick jq rsync smartmontools haveged"
      if [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = devel ]; then
        echo "dnsmasq"
      fi
      ;;
    dnf|yum)
      echo "sudo httpd mariadb-server git curl unzip rsync ca-certificates acl"
      echo "php php-cli php-mysqlnd php-xml php-gd php-mbstring php-json php-intl php-bcmath"
      echo "httpd-tools mariadb-backup jq pv smartmontools irqbalance"
      if [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = devel ]; then
        echo "dnsmasq"
      fi
      if [ "$LOCALHOST" -eq 0 ] && { [ "$ROLE" = test ] || [ "$ROLE" = live ]; }; then
        echo "certbot python3-certbot-apache"
      fi
      ;;
  esac
}

ensure_group() {
  g=$1
  if getent group "$g" >/dev/null 2>&1; then
    echo "group ok: $g"
    return 0
  fi
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ groupadd $g"
    return 0
  fi
  if have groupadd; then
    run_root groupadd "$g"
  elif have addgroup; then
    run_root addgroup "$g"
  else
    echo "$PROG: cannot create group $g" >&2
    return 1
  fi
}

ensure_user() {
  # ensure_user NAME COMMENT
  name=$1
  comment=$2
  if id "$name" >/dev/null 2>&1; then
    echo "user ok: $name"
  else
    if [ "$DRYRUN" -eq 1 ]; then
      echo "+ useradd -m -s /bin/bash -c '$comment' -G $GROUP $name"
    elif have adduser && [ "$PKG" = apt ]; then
      run_root adduser --disabled-password --gecos "$comment" --ingroup "$GROUP" "$name"
    elif have useradd; then
      run_root useradd -m -s /bin/bash -c "$comment" -G "$GROUP" "$name"
    elif have adduser; then
      run_root adduser -D -s /bin/ash -G "$GROUP" "$name"
    else
      echo "$PROG: cannot create user $name" >&2
      return 1
    fi
  fi

  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ usermod -aG $GROUP $name"
    return 0
  fi

  if have usermod; then
    run_root usermod -aG "$GROUP" "$name" 2>/dev/null || true
  elif have adduser; then
    run_root adduser "$name" "$GROUP" 2>/dev/null || true
  fi

  home=$(getent passwd "$name" 2>/dev/null | cut -d: -f6)
  if [ -z "$home" ]; then
    home=/home/$name
  fi
  run_root mkdir -p "$home/.ssh"
  run_root chmod 0700 "$home/.ssh"
  run_root chown -R "$name:$name" "$home/.ssh"
  if [ ! -f "$home/.ssh/authorized_keys" ]; then
    if [ "$DRYRUN" -eq 0 ]; then
      as_root touch "$home/.ssh/authorized_keys"
      as_root chmod 0600 "$home/.ssh/authorized_keys"
      as_root chown "$name:$name" "$home/.ssh/authorized_keys"
    else
      echo "+ touch $home/.ssh/authorized_keys"
    fi
  fi
}

write_sudoers() {
  dest=$1
  body=$2
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ write $dest"
    printf '%s\n' "$body" | sed 's/^/+ /'
    return 0
  fi
  tmp=$(mktemp)
  printf '%s\n' "$body" > "$tmp"
  as_root install -m 0440 "$tmp" "$dest"
  rm -f "$tmp"
  if have visudo; then
    as_root visudo -cf "$dest" >/dev/null 2>&1 || {
      echo "$PROG: $dest failed visudo; removing" >&2
      as_root rm -f "$dest"
      return 1
    }
  fi
  echo "sudoers: $dest"
}

user_conf() {
  name=$1
  home=$(getent passwd "$name" 2>/dev/null | cut -d: -f6)
  if [ -z "$home" ]; then
    home=/home/$name
  fi
  dest=$home/.stardust.conf
  if [ -f "$dest" ]; then
    echo "conf exists: $dest (not overwritten)"
    return 0
  fi
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ write $dest"
    return 0
  fi
  as_root sh -c "cat > '$dest'" <<EOF
# Stardust config — generated by $PROG
# role=$ROLE host=$HOSTN os=$OS_ID pkg=$PKG init=$INIT user=$name

STARDUST_ROLE=$ROLE
STARDUST_ROOT=$STARDUST
PLATFORMS=$PLATFORMS
OWNER=$OWNER
ADMIN=$ADMIN
HUMAN=$HUMAN
DAEMON=$DAEMON
GROUP=$GROUP
DIR_MODE=0770
BEE=$(command -v bee 2>/dev/null || echo $BEE_BIN)
APACHE_SERVICE=$SVC_APACHE
DB_SERVICE=$SVC_DB
APACHE_RELOAD="$RELOAD_APACHE"
DB_HOST=127.0.0.1
DB_PREFIX=bd_
EOF
  as_root chown "$name:$name" "$dest"
  as_root chmod 0600 "$dest"
  echo "wrote $dest"
}

install_tool() {
  src=$1
  dest=$2
  mode=${3:-0755}
  if [ ! -f "$src" ]; then
    echo "note: skip $dest (no $src next to installer)"
    return 0
  fi
  run_root install -m "$mode" "$src" "$dest"
  echo "installed $dest"
}

write_dropin() {
  dest=$1
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ write $dest"
    return 0
  fi
  dir=$(dirname "$dest")
  as_root mkdir -p "$dir"
  tmp=$(mktemp)
  cat > "$tmp"
  as_root install -m 0644 "$tmp" "$dest"
  rm -f "$tmp"
  echo "wrote $dest"
}

ship_tools() {
  install_tool "$BINDIR/crdir" /usr/local/bin/crdir 0755
  install_tool "$BINDIR/newfeature" /usr/local/bin/newfeature 0755
  install_tool "$BINDIR/stardust" /usr/local/bin/stardust 0755
  install_tool "$BINDIR/stardust-priv" /usr/local/sbin/stardust-priv 0750
  install_tool "$BINDIR/stardust-menu" /usr/local/bin/stardust-menu 0755
  if [ -x "$TUIDIR/stardust-tui" ]; then
    install_tool "$TUIDIR/stardust-tui" /usr/local/bin/stardust-tui 0755
  elif [ -d "$TUIDIR" ] && [ -f "$TUIDIR/main.go" ] && command -v go >/dev/null 2>&1; then
    echo "building stardust-tui"
    (cd "$TUIDIR" && GOPROXY=https://proxy.golang.org,direct go build -o stardust-tui .) && \
      install_tool "$TUIDIR/stardust-tui" /usr/local/bin/stardust-tui 0755
  else
    echo "stardust-tui binary absent (optional; use stardust-menu)"
  fi
  install_tool "$HERE/stardust-install.sh" /usr/local/sbin/stardust-install.sh 0755
  if [ -d "$LIBSRC" ]; then
    run_root mkdir -p /usr/local/lib/stardust "$STARDUST/lib"
    for f in "$LIBSRC"/*.sh; do
      [ -f "$f" ] || continue
      run_root install -m 0644 "$f" "/usr/local/lib/stardust/$(basename "$f")"
      run_root install -m 0644 "$f" "$STARDUST/lib/$(basename "$f")"
    done
    echo "installed stardust-lib from $LIBSRC"
  fi
  if [ -f "$MANDIR/crdir.1" ]; then
    run_root mkdir -p /usr/local/share/man/man1
    run_root install -m 0644 "$MANDIR/crdir.1" /usr/local/share/man/man1/crdir.1
    echo "installed man crdir"
  fi
  if [ -f "$MANDIR/stardust.1" ]; then
    run_root mkdir -p /usr/local/share/man/man1
    run_root install -m 0644 "$MANDIR/stardust.1" /usr/local/share/man/man1/stardust.1
    echo "installed man stardust"
  fi
  if [ -x /usr/local/bin/stardust ]; then
    run_root ln -sfn /usr/local/bin/stardust "$STARDUST/bin/stardust"
  fi
}

tune_php_fpm() {
  # One pool as www-data. Event MPM. Do not create per-product pools.
  pool=""
  for d in /etc/php/*/fpm/pool.d; do
    [ -d "$d" ] || continue
    pool=$d/stardust.conf
    break
  done
  if [ -z "$pool" ]; then
    echo "note: no php-fpm pool.d — skip FPM"
    return 0
  fi
  body="; Stardust — single pool, user $DAEMON
[stardust]
user = $DAEMON
group = $GROUP
listen = /run/php/stardust-fpm.sock
listen.owner = $DAEMON
listen.group = $DAEMON
pm = ondemand
pm.max_children = 20
pm.process_idle_timeout = 10s
"
  printf '%s\n' "$body" | write_dropin "$pool"
  if have a2enmod; then
    run_root a2dismod mpm_prefork >/dev/null 2>&1 || true
    run_root a2enmod mpm_event >/dev/null 2>&1 || true
    run_root a2enmod proxy_fcgi setenvif >/dev/null 2>&1 || true
  fi
  echo "php-fpm pool $pool (Event MPM). Confirm sites use SetHandler proxy:unix:/run/php/stardust-fpm.sock|fcgi://localhost/"
}

tune_extras() {
  # Security updates only; never reboot this host from apt.
  if [ -d /etc/apt/apt.conf.d ]; then
    printf '%s\n' \
      'Unattended-Upgrade::Automatic-Reboot "false";' \
      'Unattended-Upgrade::Mail "";' \
      | write_dropin /etc/apt/apt.conf.d/52stardust-unattended
  fi
  if have etckeeper && [ ! -d /etc/.git ]; then
    if [ "$DRYRUN" -eq 1 ]; then
      echo "+ etckeeper init"
    else
      as_root etckeeper init 2>/dev/null || true
      echo "etckeeper: /etc is a git repo"
    fi
  fi
  for s in haveged irqbalance smartd smartmontools; do
    [ -x "/etc/init.d/$s" ] || continue
    svc_start "$s"
  done
  if have msmtp || have msmtp-mta; then
    echo "note: copy /etc/msmtprc for NOTIFY= mail (msmtp-mta is installed)"
  fi
  echo "extras: apache2-utils php-intl/bcmath/imagick/apcu mariadb-backup logwatch goaccess age jq pv"
}

tune_php() {
  # Shared limits on every SAPI. Hardening and live OPcache only on FPM/apache2.
  # CLI must keep exec/passthru so Bee, cron, and site-check work.
  shared="; Stardust PHP — shared (8-core / 32G and small VPS)
memory_limit = 256M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 120
max_input_vars = 3000
date.timezone = UTC
allow_url_include = Off
expose_php = Off
opcache.enable = 1
opcache.memory_consumption = 256
opcache.max_accelerated_files = 16000
opcache.interned_strings_buffer = 16
"
  if [ "$ROLE" = live ] || [ "$ROLE" = test ]; then
    opc_web="opcache.validate_timestamps = 0
opcache.revalidate_freq = 0
"
  else
    opc_web="opcache.validate_timestamps = 1
opcache.revalidate_freq = 2
"
  fi
  web="; Stardust PHP — FPM / apache2 only (not CLI)
disable_functions = passthru,popen,proc_open,proc_close,dl,pcntl_exec,pcntl_fork
allow_url_fopen = On
session.cookie_httponly = 1
session.use_strict_mode = 1
$opc_web"
  if [ "$ROLE" = live ] || [ "$ROLE" = test ]; then
    web="${web}session.cookie_secure = 1
"
  fi
  cli="; Stardust PHP — CLI only
; do not set disable_functions here — Bee needs the process functions
opcache.enable_cli = 0
opcache.validate_timestamps = 1
"
  written=0
  if [ -d /etc/php ]; then
    for d in /etc/php/*/apache2/conf.d /etc/php/*/cli/conf.d /etc/php/*/fpm/conf.d; do
      [ -d "$d" ] || continue
      printf '%s\n' "$shared" | write_dropin "$d/30-stardust.ini"
      case $d in
        */cli/conf.d)
          printf '%s\n' "$cli" | write_dropin "$d/35-stardust-cli.ini"
          ;;
        *)
          printf '%s\n' "$web" | write_dropin "$d/35-stardust-harden.ini"
          ;;
      esac
      written=1
    done
  fi
  if [ "$written" -eq 0 ] && [ -d /etc/php.d ]; then
    printf '%s\n' "$shared" | write_dropin /etc/php.d/30-stardust.ini
    written=1
    echo "note: single /etc/php.d — FPM harden not split; check php --ini"
  fi
  if [ "$written" -eq 0 ]; then
    echo "note: no PHP conf.d found; set memory_limit by hand"
  else
    echo "PHP: shared 30-stardust.ini; FPM/apache harden 35-stardust-harden.ini; CLI 35-stardust-cli.ini"
  fi
}

tune_vps() {
  # RoseHosting KVM + NVMe (test/live). Skip laptop and knarr devel.
  # ip_forward stays 1 — WireGuard needs it. Do not disable IPv6 here.
  if [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = devel ]; then
    echo "VPS harden skipped (localhost/devel)"
    return 0
  fi
  sysctl_body="# Stardust VPS (RoseHosting KVM) — do not set ip_forward=0 (WG)
vm.swappiness = 10
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5
net.core.somaxconn = 1024
net.core.netdev_max_backlog = 2048
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.ip_forward = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.suid_dumpable = 0
kernel.randomize_va_space = 2
"
  if grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    sysctl_body="${sysctl_body}net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
"
  fi
  printf '%s\n' "$sysctl_body" | write_dropin /etc/sysctl.d/60-stardust.conf
  if [ "$DRYRUN" -eq 0 ] && have sysctl; then
    as_root sysctl --system >/dev/null 2>&1 || as_root sysctl -p /etc/sysctl.d/60-stardust.conf >/dev/null 2>&1 || true
  fi
  printf '%s\n' \
    "www-data soft nofile 65535" \
    "www-data hard nofile 65535" \
    "deploy soft nofile 65535" \
    "deploy hard nofile 65535" \
    | write_dropin /etc/security/limits.d/stardust.conf
  apache_h="# Stardust VPS Apache
ServerTokens Prod
ServerSignature Off
TraceEnable Off
Timeout 30
KeepAlive On
KeepAliveTimeout 5
MaxKeepAliveRequests 100
"
  if [ -d /etc/apache2/conf-available ]; then
    printf '%s\n' "$apache_h" | write_dropin /etc/apache2/conf-available/stardust-harden.conf
    if have a2enconf; then
      run_root a2enconf stardust-harden >/dev/null 2>&1 || true
    fi
  fi
  echo "VPS harden: sysctl 60-stardust, limits, Apache tokens/timeouts (RoseHosting KVM/NVMe)"
  echo "note: Rose weekly snapshots are not a CMS backup — keep stardust backup-all + offsite"
}

tune_mysql() {
  body="# Stardust MariaDB — bind local, modest buffer
[mysqld]
bind-address = 127.0.0.1
skip-networking = 0
innodb_buffer_pool_size = 2G
innodb_log_file_size = 256M
# root stays unix_socket (Debian default). Do not SET PASSWORD for root.
innodb_flush_log_at_trx_commit = 2
max_connections = 80
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
"
  if [ -d /etc/mysql/mariadb.conf.d ]; then
    printf '%s\n' "$body" | write_dropin /etc/mysql/mariadb.conf.d/90-stardust.cnf
  elif [ -d /etc/mysql/conf.d ]; then
    printf '%s\n' "$body" | write_dropin /etc/mysql/conf.d/90-stardust.cnf
  elif [ -d /etc/my.cnf.d ]; then
    printf '%s\n' "$body" | write_dropin /etc/my.cnf.d/90-stardust.cnf
  else
    echo "note: no MariaDB conf.d; set bind-address = 127.0.0.1 by hand"
  fi
}

tune_logrotate() {
  body="$STARDUST/state/tasks.log
$STARDUST/state/backup-all.log
$STARDUST/state/cron-all.log
$STARDUST/backups/*/*/*/*.log
/var/log/apache2/*.log
{
  weekly
  rotate 8
  missingok
  notifempty
  compress
  sharedscripts
  postrotate
    if [ -x /etc/init.d/$SVC_APACHE ]; then /etc/init.d/$SVC_APACHE reload >/dev/null 2>&1 || true; fi
  endscript
}
"
  if [ -d /etc/logrotate.d ]; then
    printf '%s\n' "$body" | write_dropin /etc/logrotate.d/stardust
  fi
}

write_cron() {
  dest=/etc/cron.d/stardust
  body="# Stardust — nightly backup + per-site Bee cron
# m h dom mon dow user command
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
15 3 * * * $OWNER /usr/local/bin/stardust backup-all >/srv/stardust/state/backup-all.log 2>&1
7,22,37,52 * * * * $OWNER /usr/local/bin/stardust cron-all >/srv/stardust/state/cron-all.log 2>&1
"
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ write $dest"
    return 0
  fi
  printf '%s\n' "$body" | write_dropin "$dest"
  as_root chmod 0644 "$dest" 2>/dev/null || true
  echo "cron $dest (backup 03:15, bee cron :07/:22/:37/:52)"
}

write_state() {
  dest=$STARDUST/state/state.json
  if [ -f "$dest" ]; then
    echo "state exists: $dest"
    return 0
  fi
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ write $dest"
    return 0
  fi
  as_root sh -c "cat > '$dest'" <<EOF
{"role":"$ROLE","platforms":[]}
EOF
  as_root chown "$OWNER:$GROUP" "$dest"
  as_root chmod 0660 "$dest"
  echo "wrote $dest"
}

write_etc_conf() {
  dest=/etc/stardust.conf
  if [ -f "$dest" ]; then
    echo "conf exists: $dest (not overwritten)"
    return 0
  fi
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ write $dest"
    return 0
  fi
  as_root sh -c "cat > '$dest'" <<EOF
# System-wide Stardust defaults (per-user ~/.stardust.conf overrides)
STARDUST_ROLE=$ROLE
STARDUST_ROOT=$STARDUST
PLATFORMS=$PLATFORMS
OWNER=$OWNER
ADMIN=$ADMIN
HUMAN=$HUMAN
DAEMON=$DAEMON
GROUP=$GROUP
DIR_MODE=0770
BEE=$BEE_BIN
APACHE_SERVICE=$SVC_APACHE
DB_SERVICE=$SVC_DB
APACHE_RELOAD="$RELOAD_APACHE"
DB_HOST=127.0.0.1
DB_PREFIX=bd_
KEEP_BACKUPS=7
NOTIFY=
HOOKS=$STARDUST/hooks
EOF
  as_root chmod 0644 "$dest"
  echo "wrote $dest"
}

csf_set() {
  # csf_set KEY VALUE — replace KEY = in /etc/csf/csf.conf
  key=$1
  val=$2
  conf=/etc/csf/csf.conf
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ csf $key = $val"
    return 0
  fi
  [ -f "$conf" ] || return 1
  as_root sed -i "s|^${key} = .*|${key} = \"$val\"|" "$conf"
}

setup_csf() {
  if [ "$LOCALHOST" -eq 1 ]; then
    echo "localhost: skip CSF / WireGuard firewall policy"
    return 0
  fi
  policy=$STARDUST/state/csf-policy.txt
  tcp_in="80"
  if [ "$ROLE" = test ] || [ "$ROLE" = live ]; then
    tcp_in="80,443"
  fi
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ write $policy (SSH via WG/LAN only, UDP 51820, TCP $tcp_in)"
  else
    as_root sh -c "cat > '$policy'" <<EOF
# Stardust CSF policy — remote admin only over WireGuard
# SSH is not in TCP_IN. Allow SSH from these sources in csf.allow:
#   10.8.0.0/24     WireGuard
#   192.168.1.0/24  knarr LAN
TCP_IN=$tcp_in
UDP_IN=51820
TCP6_IN=
UDP6_IN=51820
TESTING=1
RESTRICT_SYSLOG=3
EOF
    as_root chown "$OWNER:$GROUP" "$policy"
    echo "wrote $policy"
  fi

  if [ "$DO_CSF" -eq 0 ]; then
    echo "note: CSF not applied (pass -F to install/apply)"
    return 0
  fi

  if ! have csf && [ ! -x /usr/sbin/csf ]; then
    if [ "$DRYRUN" -eq 1 ]; then
      echo "+ download + install CSF from download.configserver.com"
    else
      work=$(as_root mktemp -d)
      as_root wget -q -O "$work/csf.tgz" https://download.configserver.com/csf.tgz || {
        echo "$PROG: could not fetch CSF tarball; install CSF by hand then re-run -F" >&2
        return 1
      }
      as_root tar -xzf "$work/csf.tgz" -C "$work"
      if [ -x "$work/csf/install.sh" ]; then
        as_root sh "$work/csf/install.sh"
      fi
    fi
  fi

  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ apply CSF policy TCP_IN=$tcp_in UDP_IN=51820 TESTING=1"
    echo "+ csf.allow 10.8.0.0/24 and 192.168.1.0/24"
    return 0
  fi

  if [ ! -f /etc/csf/csf.conf ]; then
    echo "$PROG: CSF conf missing after install" >&2
    return 1
  fi

  csf_set TCP_IN "$tcp_in"
  csf_set UDP_IN "51820"
  csf_set TCP_OUT "20,21,22,25,53,80,110,113,443,587,993,995,9418"
  csf_set UDP_OUT "53,113,123,51820"
  csf_set TESTING "1"
  csf_set RESTRICT_SYSLOG "3"
  # Drop 22 from the public inbound list if a stock install put it back.
  if grep -q 'TCP_IN = ".*22' /etc/csf/csf.conf; then
    csf_set TCP_IN "$tcp_in"
  fi

  for src in 10.8.0.0/24 192.168.1.0/24; do
    if ! grep -q "$src" /etc/csf/csf.allow 2>/dev/null; then
      as_root sh -c "echo '$src # Stardust SSH/WG' >> /etc/csf/csf.allow"
    fi
  done

  if have csf; then
    as_root csf -r || true
  fi
  echo "CSF applied with TESTING=1. After you confirm WG SSH still works:"
  echo "  sudo sed -i 's/^TESTING = .*/TESTING = \"0\"/' /etc/csf/csf.conf && sudo csf -r"
}

# Long flags getopts cannot see.
NEWARGS=""
for arg in "$@"; do
  case $arg in
    --localhost|-lh)
      LOCALHOST=1
      ROLE=devel
      DO_CSF=0
      ;;
    --human)
      # next token consumed below if present as --human=NAME form
      ;;
    --human=*)
      HUMAN=${arg#--human=}
      ;;
    *)
      NEWARGS="$NEWARGS $arg"
      ;;
  esac
done
# shellcheck disable=SC2086
eval set -- $NEWARGS

while getopts 'nFm:u:g:a:H:h' opt; do
  case $opt in
    n) DRYRUN=1 ;;
    F) DO_CSF=1 ;;
    m) ROLE=$OPTARG ;;
    u) OWNER=$OPTARG ;;
    a) ADMIN=$OPTARG ;;
    H) HUMAN=$OPTARG ;;
    g) GROUP=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

if [ "$LOCALHOST" -eq 1 ]; then
  ROLE=devel
  DO_CSF=0
fi

if [ -z "$HUMAN" ]; then
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    HUMAN=$SUDO_USER
  elif [ "$(id -u)" -ne 0 ] && [ -n "${USER:-}" ] && [ "$USER" != root ]; then
    HUMAN=$USER
  fi
fi
if [ "$HUMAN" = "$OWNER" ] || [ "$HUMAN" = "$ADMIN" ]; then
  HUMAN=""
fi
if [ -z "$HUMAN" ]; then
  echo "note: no extra operator user (pass -H NAME if you want one besides $OWNER / $ADMIN)"
else
  echo "operator account: $HUMAN"
fi

ROLE=$(normalize_role "$ROLE")
if [ -z "$ROLE" ]; then
  echo "$PROG: unknown role. Use devel, test, or live." >&2
  exit 2
fi

detect_os
detect_init
detect_group
detect_services

HOSTN=$(hostname 2>/dev/null || echo unknown)
echo "$PROG role=$ROLE localhost=$LOCALHOST host=$HOSTN os=$OS_ID pkg=$PKG init=$INIT owner=$OWNER admin=$ADMIN human=$HUMAN group=$GROUP dryrun=$DRYRUN"

# --- packages ----------------------------------------------------------
PKGS=$(pkg_list_for | tr '\n' ' ')
need=""
for p in $PKGS; do
  if [ "$DRYRUN" -eq 1 ]; then
    need="$need $p"
    continue
  fi
  if pkg_ok "$p"; then
    echo "package ok: $p"
  else
    need="$need $p"
  fi
done

if [ -n "$need" ]; then
  echo "packages to consider:$need"
  # shellcheck disable=SC2086
  pkg_install $need || {
    echo "$PROG: some packages are not in this distro; install the rest by hand" >&2
  }
fi

# --- users / groups ----------------------------------------------------
ensure_group "$GROUP"
ensure_group "$OWNER"
ensure_group stardust
# $GROUP is www-admin — humans + www-data user go in it below
ensure_user "$OWNER" "Stardust deploy"
ensure_user "$ADMIN" "Stardust web admin"
if [ -n "$HUMAN" ]; then
  ensure_user "$HUMAN" "Stardust operator"
fi

# operator (-H or the invoking login) writes 0770 trees, reads apache logs
if [ "$DRYRUN" -eq 1 ]; then
  [ -n "$HUMAN" ] && echo "+ usermod -aG $GROUP,stardust,adm,$OWNER $HUMAN"
  echo "+ usermod -aG $GROUP,stardust $ADMIN"
  echo "+ usermod -aG $GROUP,stardust $OWNER"
else
  if [ -n "$HUMAN" ]; then
    for g in "$GROUP" stardust adm "$OWNER"; do
      getent group "$g" >/dev/null 2>&1 || continue
      run_root usermod -aG "$g" "$HUMAN" 2>/dev/null || true
    done
  fi
  run_root usermod -aG "$GROUP,stardust" "$ADMIN" 2>/dev/null || true
  run_root usermod -aG "$GROUP,stardust" "$OWNER" 2>/dev/null || true
  # Apache must be in www-admin so 0770 www-data:www-admin works
  if id "$DAEMON" >/dev/null 2>&1; then
    run_root usermod -aG "$GROUP" "$DAEMON" 2>/dev/null || true
  fi
fi

# --- sudoers (limited, same on knarr and VPS) -------------------------
# deploy: dirs, ownership, Apache site tools, service reload, Bee link.
# www-admin: dirs and ownership under /srv only — no a2ensite, no pkg.
# One helper. No NOPASSWD chown/rm/mysql for the human.
SUDO_PRIV="# Stardust — priv helper on $HOSTN
Defaults:$OWNER !requiretty
Defaults:$ADMIN !requiretty
$OWNER ALL=(root) NOPASSWD: /usr/local/sbin/stardust-priv
$ADMIN ALL=(root) NOPASSWD: /usr/local/sbin/stardust-priv
$OWNER ALL=(root) NOPASSWD: /usr/sbin/a2ensite, /usr/sbin/a2dissite, /usr/sbin/a2enmod
$ADMIN ALL=($OWNER) NOPASSWD: /usr/local/bin/bee, /usr/bin/git, /usr/local/bin/crdir
"
if [ -n "$HUMAN" ]; then
  SUDO_PRIV="${SUDO_PRIV}Defaults:$HUMAN !requiretty
$HUMAN ALL=(root) NOPASSWD: /usr/local/sbin/stardust-priv
$HUMAN ALL=($OWNER) NOPASSWD: /usr/local/bin/bee, /usr/bin/git, /usr/local/bin/crdir
"
fi

SUDO_DEPLOY="$SUDO_PRIV"
SUDO_ADMIN="# Stardust — $ADMIN extra (see stardust-priv)
"
SUDO_HUMAN="# Stardust — $HUMAN extra (see stardust-priv)
"

if [ -d /etc/sudoers.d ]; then
  write_sudoers /etc/sudoers.d/stardust-deploy "$SUDO_DEPLOY"
  write_sudoers /etc/sudoers.d/stardust-www-admin "$SUDO_ADMIN"
  if [ -n "$HUMAN" ]; then
    write_sudoers /etc/sudoers.d/stardust-human "$SUDO_HUMAN"
  fi
else
  echo "note: /etc/sudoers.d missing; add the limited sudo rules by hand"
fi

# umask 002 so new files in setgid trees stay group-writable
PROFILE=/etc/profile.d/stardust.sh
PROFILE_BODY="# Stardust: PATH + group-writable files for $OWNER, $ADMIN, $HUMAN
export PATH=\"/usr/local/bin:/srv/stardust/bin:\$PATH\"
case \$(id -un) in
  $OWNER|$ADMIN|$HUMAN)
    umask 002
    ;;
esac
"
if [ "$DRYRUN" -eq 1 ]; then
  echo "+ write $PROFILE"
else
  tmp=$(mktemp)
  printf '%s\n' "$PROFILE_BODY" > "$tmp"
  as_root install -m 0644 "$tmp" "$PROFILE"
  rm -f "$tmp"
  echo "profile: $PROFILE"
fi

# --- dirs --------------------------------------------------------------
run_root mkdir -p \
  "$STARDUST/backups" \
  "$STARDUST/bin" \
  "$STARDUST/state" \
  "$STARDUST/state/locks" \
  "$STARDUST/state/secrets" \
  "$STARDUST/hooks" \
  "$STARDUST/hooks/pre-upgrade.d" \
  "$STARDUST/hooks/post-check.d" \
  "$PLATFORMS"

run_root chown "$OWNER:$GROUP" "$STARDUST" "$STARDUST/backups" "$STARDUST/bin" "$STARDUST/state"
run_root chmod 2770 "$STARDUST" "$STARDUST/backups" "$STARDUST/bin" "$STARDUST/state"
run_root chown "$OWNER:stardust" "$STARDUST/state/secrets"
run_root chmod 0750 "$STARDUST/state/secrets"
if have setfacl; then
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ setfacl default u:$OWNER g:$GROUP u:$DAEMON on $PLATFORMS $STARDUST"
  else
    as_root setfacl -m "u:${OWNER}:rwx,g:${GROUP}:rwx,u:${DAEMON}:rwx,o::---" \
      "$PLATFORMS" "$STARDUST" "$STARDUST/backups" 2>/dev/null || true
    as_root setfacl -d -m "u:${OWNER}:rwx,g:${GROUP}:rwx,u:${DAEMON}:rwx,o::---" \
      "$PLATFORMS" "$STARDUST" "$STARDUST/backups" 2>/dev/null || true
    as_root setfacl -b "$STARDUST/state/secrets" 2>/dev/null || true
    as_root setfacl -m "u:${OWNER}:rwx,g:stardust:r-x,o::---" "$STARDUST/state/secrets" 2>/dev/null || true
    as_root setfacl -d -m "u:${OWNER}:rw,g:stardust:r,o::---" "$STARDUST/state/secrets" 2>/dev/null || true
    echo "ACL default on $PLATFORMS and $STARDUST (secrets: deploy:stardust only)"
  fi
else
  echo "note: setfacl missing — install the acl package"
fi

if [ "$DRYRUN" -eq 1 ]; then
  echo "+ # leave $PLATFORMS contents untouched"
elif [ -d "$PLATFORMS" ]; then
  echo "platforms root exists: $PLATFORMS (contents not changed)"
fi

# --- Bee ---------------------------------------------------------------
if [ "$DRYRUN" -eq 1 ]; then
  echo "+ # install Bee to $BEE_BIN if missing"
elif have bee; then
  echo "bee ok: $(command -v bee)"
else
  run_root mkdir -p /usr/local/src
  if [ ! -d "$BEE_DST/.git" ]; then
    run_root git clone --depth 1 "$BEE_SRC" "$BEE_DST"
  fi
  if [ -f "$BEE_DST/bee" ]; then
    run_root ln -sfn "$BEE_DST/bee" "$BEE_BIN"
    run_root chmod 0755 "$BEE_DST/bee"
    echo "bee installed: $BEE_BIN"
  else
    echo "$PROG: cloned Bee but $BEE_DST/bee not found; check upstream layout" >&2
  fi
fi

ship_tools
if [ "$DRYRUN" -eq 1 ]; then
  echo "+ git config --global --add safe.directory $PLATFORMS as $OWNER"
elif have git; then
  as_root -u "$OWNER" git config --global --add safe.directory "$PLATFORMS" 2>/dev/null || true
  as_root -u "$OWNER" git config --global --add safe.directory "$PLATFORMS/*" 2>/dev/null || true
  echo "git safe.directory $PLATFORMS for $OWNER"
fi
tune_php
tune_php_fpm
tune_mysql
tune_extras
tune_vps
tune_logrotate
write_state
write_cron
write_etc_conf
setup_csf

if [ "$DRYRUN" -eq 1 ]; then
  echo "+ a2enmod rewrite headers expires"
elif have a2enmod; then
  run_root a2enmod rewrite >/dev/null 2>&1 || true
  run_root a2enmod headers >/dev/null 2>&1 || true
  run_root a2enmod expires >/dev/null 2>&1 || true
fi

if [ "$LOCALHOST" -eq 1 ]; then
  if [ -d /etc/apache2 ]; then
    printf '%s\n' "Listen 127.0.0.1:80" | write_dropin /etc/apache2/conf-available/stardust-localhost.conf
    if have a2enconf; then
      run_root a2enconf stardust-localhost >/dev/null 2>&1 || true
    fi
  fi
  echo "localhost: Apache should listen on 127.0.0.1 only (disable stock Listen 80 if it still binds all addresses)"
fi

# dnsmasq: local + knarr devel only. Never on VPS test/live (public DNS).
if [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = devel ]; then
  if [ "$LOCALHOST" -eq 1 ]; then
    dns_ip=127.0.0.1
  else
    dns_ip=192.168.1.120
  fi
  if [ -d /etc/dnsmasq.d ] || [ "$DRYRUN" -eq 1 ]; then
    printf '%s\n' "address=/devel/${dns_ip}" | write_dropin /etc/dnsmasq.d/stardust.conf
  fi
  svc_start dnsmasq
else
  echo "VPS $ROLE: skip dnsmasq (use public DNS / Cloudflare)"
fi

svc_start "$SVC_APACHE"
svc_start "$SVC_DB"
if [ "$SVC_DB" = mysql ] && [ "$INIT" != systemd ]; then
  if [ -x /etc/init.d/mariadb ]; then
    svc_start mariadb
  fi
fi

user_conf "$OWNER"
user_conf "$ADMIN"
if [ -n "$HUMAN" ]; then
  user_conf "$HUMAN"
fi

echo "done."
echo "set passwords: sudo passwd $OWNER && sudo passwd $ADMIN"
if [ -n "$HUMAN" ]; then
  echo "               sudo passwd $HUMAN"
  echo "refresh groups: exec su - $HUMAN"
fi
echo "check host:    stardust doctor"
echo "list sites:    stardust list"
echo "Bee: bee --root=$PLATFORMS/<platform>/web --site=<product> <cmd>"
echo "reload apache with: $RELOAD_APACHE"
