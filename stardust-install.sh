#!/bin/sh
# stardust-install.sh — Idempotent bootstrap for Stardust (Apache2 + PHP + MariaDB + Bee + Gitea)
# Same script on a devel workstation and a remote test/live host.
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
#       devel, vps-test, vps-live still accepted as aliases.

set -eu

PROG=${0##*/}
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STARDUST_VERSION=0.4.0
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
CSF_ALLOW="10.8.0.0/24 192.168.1.0/24"
BEE_SRC=https://github.com/backdrop-contrib/bee.git
BEE_DST=/usr/local/src/bee
BEE_BIN=/usr/local/bin/bee

PKG=unknown
INIT=unknown
OS_ID=unknown
SVC_APACHE=""
SVC_DB=""
RELOAD_APACHE=""

# --- Helper Functions ---

usage() {
  cat <<EOF
$PROG $STARDUST_VERSION — Prepare any Stardust host (Apache2 + PHP + MariaDB + Bee + Gitea)

WHAT THIS IS FOR:
  One script for any host. Detects apt vs. other package managers and sysvinit vs. systemd vs. OpenRC.
  Creates users deploy and www-admin, the $STARDUST control plane, missing packages,
  PHP/MariaDB snippets, companion CLIs (crdir, newfeature, stardust, bee), and conf files.
  PHP: 30-stardust.ini every SAPI; 35-stardust-harden.ini FPM/apache2 only; 35-stardust-cli.ini leaves Bee able to exec.
  Also: php-intl/bcmath/imagick/apcu, apache2-utils, mariadb-backup, msmtp-mta,
  unattended-upgrades (no auto-reboot), needrestart, logwatch, goaccess, etckeeper,
  smartmontools, irqbalance, haveged, moreutils, jq, pv, age.
  Leaves $PLATFORMS trees alone. No Aegir/BOA frontend.

USERS:
  $OWNER     owns platforms and the control plane; limited sudo
  $ADMIN     extra login that writes the same 0770 trees
  operator   login that runs stardust day to day.
                Default: the account that invoked this script (SUDO_USER or USER), never a hard-coded name.
                Override with -H.
  Groups: $GROUP, stardust, adm, $OWNER.
  $GROUP     Apache daemon group (www-data or apache).

  Passwords are not set. After the first run:
    sudo passwd $OWNER
    sudo passwd $ADMIN
    sudo passwd OPERATOR   # the login that ran this script, or -H NAME
  Drop SSH keys into each home's .ssh/authorized_keys yourself.

HOW TO RUN IT:
  $PROG [-n] [-lh|--localhost] [-F] [-m devel|test|live] [-u owner] [-a admin] [-H human] [-g group]
  $PROG -h

  Run as a sudo-capable account. Do not type "sudo $PROG".

FLAGS:
  -n         Dry run. Print the plan with a leading + and change nothing.
  -lh, --localhost
             Local dev box only (127.0.0.1). Skips CSF, WireGuard policy, and certbot.
             Installs dnsmasq (*.devel → 127.0.0.1). Role becomes devel.
             Apache and MariaDB stay on localhost.
  -m ROLE    devel (default), test, or live
  -u owner   Code owner (default: deploy)
  -a admin   File-admin login (default: www-admin)
  -H user    Daily operator (default: whoever ran this script)
  -g group   File group on every tree (default: www-admin)
  -F         Install/apply CSF. SSH is not world-open: only 10.8.0.0/24 (WireGuard)
             and 192.168.1.0/24 (LAN). UDP 51820 stays open for the tunnel.
             HTTP 80 on devel; 80+443 on test/live.
             First enable uses CSF TESTING=1 so a lockout self-reverts.
  -h         This text

SAFE FIRST RUN:
  laptop:  $PROG -n --localhost
  devel:   $PROG -n -m devel
  VPS:     $PROG -n -m test     (or -m live)

WHAT IT WILL NOT DO:
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
    devel|localhost|dev) echo devel ;;
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
      echo "$PROG: no package manager detected; install packages by hand" >&2
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

# --- Interactive Prompt Function ---
install_prompt() {
  q=$1
  def=${2:-}
  help=${3:-}
  while :; do
    if [ -n "$help" ]; then
      printf '%s (? help)\n' "$q" >&2
    else
      printf '%s\n' "$q" >&2
    fi
    if [ -n "$def" ]; then
      printf '> [%s]: ' "$def" >&2
    else
      printf '> ' >&2
    fi
    IFS= read -r ans || ans=
    case $ans in
      \?|help|HELP)
        printf '\n%s\n\n' "$help" >&2
        printf 'Enter to return to the question... ' >&2
        IFS= read -r _ || true
        continue
        ;;
    esac
    [ -n "$ans" ] || ans=$def
    printf '%s\n' "$ans"
    return 0
  done
}

# --- Dependency Installation Functions ---
install_apache2() {
  if ! pkg_ok apache2 && ! pkg_ok httpd; then
    install_prompt "Install Apache2 (Web Server)? [Y/n]" "Y" \
      "Apache2 is a high-performance web server. It will be configured for speed and security."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      case $PKG in
        apt) pkg_install apache2 ;;
        apk) pkg_install apache2 ;;
        dnf|yum) pkg_install httpd ;;
        *) echo "Unsupported package manager. Install Apache2 manually." >&2; return 1 ;;
      esac
    fi
  else
    echo "Apache2 is already installed."
  fi
  tune_apache2
}

tune_apache2() {
  # Enable performance modules
  if have a2enmod; then
    run_root a2enmod mpm_event
    run_root a2enmod proxy_fcgi
    run_root a2enmod setenvif
    run_root a2enmod deflate
    run_root a2enmod expires
    run_root a2enmod cache
    run_root a2enmod headers
  fi

  # Write performance config
  apache_perf_conf="/etc/apache2/conf-available/stardust-perf.conf"
  if [ "$PKG" = "apt" ] || [ "$PKG" = "dnf" ] || [ "$PKG" = "yum" ]; then
    body="<IfModule mpm_event_module>
  StartServers 2
  MinSpareThreads 25
  MaxSpareThreads 75
  ThreadLimit 64
  ThreadsPerChild 25
  MaxRequestWorkers 150
  MaxConnectionsPerChild 1000
</IfModule>

<IfModule mod_deflate.c>
  AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript application/javascript
</IfModule>

<IfModule mod_expires.c>
  ExpiresActive On
  ExpiresDefault \"access plus 1 month\"
</IfModule>"

    write_dropin "$apache_perf_conf"
    if have a2enconf; then
      run_root a2enconf stardust-perf >/dev/null 2>&1 || true
    fi
  fi
  echo "Apache2 tuned for performance."
}

install_php() {
  if ! pkg_ok php; then
    install_prompt "Install PHP (Hypertext Preprocessor)? [Y/n]" "Y" \
      "PHP is a server-side scripting language for dynamic web content. It is required for Backdrop CMS."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      case $PKG in
        apt)
          pkg_install php php-cli php-mysql php-xml php-gd php-mbstring php-curl php-zip php-fpm php-intl php-bcmath php-imagick php-apcu
          ;;
        apk)
          pkg_install php php-cli php-mysqli php-xml php-gd php-mbstring php-curl php-zip apache2-proxy php-intl php-bcmath imagemagick
          ;;
        dnf|yum)
          pkg_install php php-cli php-mysqlnd php-xml php-gd php-mbstring php-json php-intl php-bcmath
          ;;
        *)
          echo "Unsupported package manager. Install PHP manually." >&2
          return 1
          ;;
      esac
    fi
  else
    echo "PHP is already installed."
  fi
  tune_php
}

tune_php() {
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

  if [ "$ROLE" = "live" ] || [ "$ROLE" = "test" ]; then
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
$opc_web
"

  if [ "$ROLE" = "live" ] || [ "$ROLE" = "test" ]; then
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
    echo "PHP tuned for performance and security."
  fi
}

install_mariadb() {
  if ! pkg_ok mariadb-server && ! pkg_ok mysql-server; then
    install_prompt "Install MariaDB (Database Server)? [Y/n]" "Y" \
      "MariaDB is a relational database server, a fork of MySQL. It is required for Backdrop CMS."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      case $PKG in
        apt) pkg_install mariadb-server ;;
        apk) pkg_install mariadb ;;
        dnf|yum) pkg_install mariadb-server ;;
        *) echo "Unsupported package manager. Install MariaDB manually." >&2; return 1 ;;
      esac
    fi
  else
    echo "MariaDB is already installed."
  fi
  tune_mysql
}

tune_mysql() {
  body="; Stardust MariaDB — bind local, modest buffer
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
  echo "MariaDB tuned for performance and security."
}

install_git() {
  if ! pkg_ok git; then
    install_prompt "Install Git (Version Control System)? [Y/n]" "Y" \
      "Git is a distributed version control system. It is required for managing Backdrop CMS platforms."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      pkg_install git
    fi
  else
    echo "Git is already installed."
  fi
}

install_bee() {
  if ! command -v bee >/dev/null 2>&1; then
    install_prompt "Install Bee (Backdrop CMS CLI)? [Y/n]" "Y" \
      "Bee is a command-line tool for managing Backdrop CMS sites. It is required for Stardust operations."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      if [ ! -d "$BEE_DST" ]; then
        run_root git clone "$BEE_SRC" "$BEE_DST"
      fi
      if [ -d "$BEE_DST" ]; then
        if have composer; then
          # FIX: cd locally first, then run composer inside run_root wrapped in a subshell
          cd "$BEE_DST"
          run_root composer install --no-dev
          run_root ln -sf "$BEE_DST/bee" "$BEE_BIN"
          echo "Bee installed to $BEE_BIN."
        else
          echo "Composer is not installed. Bee dependencies cannot be installed automatically."
          echo "Install Composer manually from https://getcomposer.org and run:"
          echo "  cd $BEE_DST && composer install --no-dev"
          echo "  ln -s $BEE_DST/bee $BEE_BIN"
        fi
      else
        error "Failed to clone Bee repository."
      fi
    fi
  else
    echo "Bee is already installed at $(command -v bee)."
  fi
}


install_gitea() {
  if ! gitea_installed; then
    install_prompt "Install Gitea (Self-hosted Git Service)? [Y/n]" "Y" \
      "Gitea is a lightweight, self-hosted Git service for managing repositories. It is optional but recommended for Stardust workflows."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      case $PKG in
        apt)
          pkg_install gitea
          ;;
        dnf|yum)
          pkg_install gitea
          ;;
        *)
          echo "Unsupported package manager. Install Gitea manually from https://gitea.io."
          return 1
          ;;
      esac
      svc_start gitea
      echo "Gitea installed. Configure it at http://$(hostname):3000."
    fi
  else
    echo "Gitea is already installed."
  fi
  maybe_gitea_defaults
}

gitea_conf_path() {
  for f in \
    /etc/gitea/app.ini \
    /var/lib/gitea/custom/conf/app.ini \
    /etc/gitea/conf/app.ini \
    /home/git/gitea/custom/conf/app.ini
  do
    if [ -f "$f" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

gitea_installed() {
  have gitea && return 0
  [ -x /usr/local/bin/gitea ] && return 0
  [ -x /usr/bin/gitea ] && return 0
  gitea_conf_path >/dev/null && return 0
  return 1
}

maybe_gitea_defaults() {
  if [ "$LOCALHOST" -ne 1 ] && [ "$ROLE" != "devel" ]; then
    return 0
  fi
  if stardust_git_configured; then
    echo "Git template already set — skip Gitea/Stardust git prompts"
    return 0
  fi
  if ! gitea_installed; then
    echo "Gitea not found on this host — skip git template (set STARDUST_GIT_TEMPLATE later)"
    return 0
  fi
  gc=$(gitea_conf_path || true)
  echo "Gitea present${gc:+ ($gc)}"
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ prompt STARDUST_GIT_TEMPLATE (Gitea seen, no existing Stardust git config)"
    return 0
  fi
  if [ ! -t 0 ]; then
    echo "no TTY — not prompting for git template"
    return 0
  fi
  host_def=gitea-starhq
  if [ -f "$HOME/.ssh/config" ]; then
    h=$(awk 'tolower($1)=="host" && $2 !~ /[*?]/ { if ($2 ~ /gitea|github|gitlab|git/) { print $2; exit } }' "$HOME/.ssh/config" 2>/dev/null || true)
    [ -n "$h" ] && host_def=$h
  fi
  host=$(install_prompt "Git SSH host — name in git@HOST:org/repo.git" "$host_def" \
    "Accept the scanned default. This is usually a Host line in ~/.ssh/config. Empty host skips git template. Type ? here for this text again.")
  owner=$(install_prompt "Git owner/org — first path after the colon" "" \
    "On Gitea this is the organization or your username. Template becomes git@HOST:OWNER/%s.git (%s = platform name).")
  if [ -z "$owner" ]; then
    echo "no owner — leave STARDUST_GIT_TEMPLATE empty"
    return 0
  fi
  tpl="git@${host}:${owner}/%s.git"
  dest=/etc/stardust.conf
  if [ -f "$dest" ] && grep -q '^STARDUST_GIT_TEMPLATE=' "$dest"; then
    as_root sed -i "s|^STARDUST_GIT_TEMPLATE=.*|STARDUST_GIT_TEMPLATE=$tpl|" "$dest"
  elif [ -f "$dest" ]; then
    as_root sh -c "printf 'STARDUST_GIT_TEMPLATE=%s\n' '$tpl' >> '$dest'"
  fi
  echo "wrote STARDUST_GIT_TEMPLATE=$tpl"
  echo "Gitea app.ini was not changed (already installed)"
}

stardust_git_configured() {
  for f in "$HOME/.stardust.conf" /etc/stardust.conf; do
    [ -f "$f" ] || continue
    val=$(sed -n 's/^STARDUST_GIT_TEMPLATE=//p' "$f" | tail -n 1)
    case $val in
      ''|*YOURORG*|*git.example*) ;;
      *) return 0 ;;
    esac
  done
  return 1
}

install_extras() {
  echo "Installing extras (logwatch, goaccess, etc.)..."
  case $PKG in
    apt)
      pkg_install apache2-utils mariadb-backup msmtp-mta unattended-upgrades needrestart logwatch goaccess etckeeper smartmontools irqbalance haveged moreutils jq pv age
      if [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = "devel" ]; then
        pkg_install dnsmasq
      fi
      if [ "$LOCALHOST" -eq 0 ] && { [ "$ROLE" = "test" ] || [ "$ROLE" = "live" ]; }; then
        pkg_install certbot python3-certbot-apache
      fi
      if [ "$LOCALHOST" -eq 0 ] && [ "$DO_CSF" -eq 1 ]; then
        pkg_install iptables perl libwww-perl liblwp-protocol-https-perl libgd-perl
      fi
      ;;
    apk)
      pkg_install apache2-utils mariadb-client mariadb-backup git curl unzip rsync acl php-intl php-bcmath imagemagick jq smartmontools haveged
      if [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = "devel" ]; then
        pkg_install dnsmasq
      fi
      ;;
    dnf|yum)
      pkg_install httpd-tools mariadb-backup jq pv smartmontools irqbalance
      if [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = "devel" ]; then
        pkg_install dnsmasq
      fi
      if [ "$LOCALHOST" -eq 0 ] && { [ "$ROLE" = "test" ] || [ "$ROLE" = "live" ]; }; then
        pkg_install certbot python3-certbot-apache
      fi
      ;;
  esac
}

# --- Existing Functions (Unchanged) ---
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
  name=$1
  comment=${2:-"Stardust Operator"}
  if id "$name" >/dev/null 2>&1; then
    echo "user ok: $name"
  else
    if [ "$DRYRUN" -eq 1 ]; then
      echo "+ useradd -m -s /bin/bash -c '$comment' -G $GROUP $name"
    elif have adduser && [ "$PKG" = "apt" ]; then
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
  
  # FIX: Read the multi-line heredoc from stdin instead of $2
  body=$(cat)
  
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
# role=$ROLE host=$HOSTNAME os=$OS_ID pkg=$PKG init=$INIT user=$name

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

write_if_absent() {
  dest=$1
  if [ -e "$dest" ]; then
    echo "exists: $dest (unchanged)"
    return 0
  fi
  write_dropin "$dest"
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

ship_tools() {
  install_tool "$BINDIR/crdir" /usr/local/bin/crdir 0755
  install_tool "$BINDIR/newfeature" /usr/local/bin/newfeature 0755
  install_tool "$BINDIR/d7-migrate" /usr/local/bin/d7-migrate 0755
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
    for f in "$LIBSRC"/*.sh "$LIBSRC"/d7-catalog.txt; do
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
  if [ -f "$MANDIR/d7-migrate.1" ]; then
    run_root mkdir -p /usr/local/share/man/man1
    run_root install -m 0644 "$MANDIR/d7-migrate.1" /usr/local/share/man/man1/d7-migrate.1
    echo "installed man d7-migrate"
  fi
  DOCSRC=""
  [ -d "$HERE/docs" ] && DOCSRC=$HERE/docs
  if [ -n "$DOCSRC" ]; then
    run_root mkdir -p /usr/local/share/stardust/docs "$STARDUST/docs"
    for f in "$DOCSRC"/*.txt "$DOCSRC"/*.md; do
      [ -f "$f" ] || continue
      run_root install -m 0644 "$f" "/usr/local/share/stardust/docs/$(basename "$f")"
      run_root install -m 0644 "$f" "$STARDUST/docs/$(basename "$f")"
    done
    echo "installed docs from $DOCSRC"
  fi
  if [ -x /usr/local/bin/stardust ]; then
    run_root ln -sfn /usr/local/bin/stardust "$STARDUST/bin/stardust"
  fi
}

tune_extras() {
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

tune_vps() {
  if [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = "devel" ]; then
    echo "VPS harden skipped (localhost/devel)"
    return 0
  fi
  sysctl_body="; Stardust VPS — do not set ip_forward=0 (WireGuard)
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
  apache_h="; Stardust VPS Apache
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
  echo "VPS harden: sysctl 60-stardust, limits, Apache tokens/timeouts"
  echo "note: provider disk snapshots are not a CMS backup — keep backup-all + offsite"
}

tune_logrotate() {
  body="$STARDUST/state/tasks.log
$STARDUST/state/backup-all.log
$STARDUST/state/cron-all.log
$STARDUST/backups/*/*/*/*.log
/var/log/apache2/*.log {
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
  body="; Stardust — nightly backup + per-site Bee cron
; m h dom mon dow user command
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
{\"role\":\"$ROLE\",\"platforms\":[]}
EOF
  as_root chown "$OWNER:$GROUP" "$dest"
  as_root chmod 0660 "$dest"
  echo "wrote $dest"
}

bootstrap_deps() {
  echo "Bootstrapping extras (skip when config already exists)..."
  if have php-fpm || [ -x /etc/init.d/php-fpm ] || ls /etc/init.d/php*-fpm >/dev/null 2>&1; then
    for s in php8.2-fpm php8.3-fpm php8.4-fpm php7.4-fpm php-fpm; do
      if [ -x "/etc/init.d/$s" ] || [ -d "/lib/systemd/system/$s.service" ]; then
        svc_start "$s"
        break
      fi
    done
  fi
  if have mysql || have mariadb; then
    if [ "$DRYRUN" -eq 0 ]; then
      if mysql -N -e "SELECT 1" >/dev/null 2>&1; then
        echo "mariadb: local socket OK"
      else
        echo "note: mariadb not answering on the unix socket yet — start it, then re-run"
      fi
    fi
  fi
  if have etckeeper; then
    if [ -d /etc/.git ]; then
      echo "etckeeper: /etc already a repo (unchanged)"
    elif [ "$DRYRUN" -eq 1 ]; then
      echo "+ etckeeper init"
    else
      as_root etckeeper init >/dev/null 2>&1 || true
      as_root etckeeper commit -m "stardust first run" >/dev/null 2>&1 || true
      echo "etckeeper: initialized /etc"
    fi
  fi
  if have needrestart && [ -d /etc/needrestart/conf.d ]; then
    printf '%s\n' '$nrconf{restart} = "l";' \
      | write_if_absent /etc/needrestart/conf.d/stardust.conf
  fi
  if have logwatch; then
    printf '%s\n' \
      "Detail = Low" \
      "MailTo = root" \
      | write_if_absent /etc/logwatch/conf/logwatch.conf
  fi
  if have goaccess && [ ! -f /etc/goaccess/goaccess.conf ]; then
    echo "note: goaccess installed — run: goaccess /var/log/apache2/access.log"
  fi
  if have smartd || [ -x /etc/init.d/smartd ] || [ -x /etc/init.d/smartmontools ]; then
    svc_start smartd 2>/dev/null || svc_start smartmontools 2>/dev/null || true
  fi
  if have irqbalance || [ -x /etc/init.d/irqbalance ]; then
    svc_start irqbalance
  fi
  if have haveged || [ -x /etc/init.d/haveged ]; then
    svc_start haveged
  fi
  age_key=$STARDUST/state/secrets/age.key
  if have age-keygen; then
    if [ -f "$age_key" ]; then
      echo "age: $age_key exists (unchanged)"
    elif [ "$DRYRUN" -eq 1 ]; then
      echo "+ age-keygen -o $age_key"
    else
      as_root mkdir -p "$STARDUST/state/secrets"
      as_root age-keygen -o "$age_key" >/dev/null
      as_root chown "$OWNER:stardust" "$age_key"
      as_root chmod 0640 "$age_key"
      echo "age: wrote $age_key"
    fi
  fi
  if have msmtp || have msmtp-mta; then
    if [ -f /etc/msmtprc ]; then
      echo "msmtp: /etc/msmtprc exists (unchanged)"
    else
      printf '%s\n' \
        "# Stardust msmtp — fill host/user/password, then: chmod 0640 /etc/msmtprc" \
        "defaults" \
        "auth           on" \
        "tls            on" \
        "tls_starttls   on" \
        "logfile        /var/log/msmtp.log" \
        "account        default" \
        "host           mail.example" \
        "port           587" \
        "from           stardust@example" \
        "user           stardust@example" \
        "password       CHANGE-ME" \
        | write_if_absent /etc/msmtprc.example
      if [ "$DRYRUN" -eq 0 ] && [ -t 0 ]; then
        nmail=$(install_prompt "NOTIFY email — where backup/fail mail goes (empty skip)" "" \
          "Stardust can mail after backup-all or a failed site-check.
This only sets NOTIFY= in /etc/stardust.conf.
You still copy /etc/msmtprc.example to /etc/msmtprc and put real SMTP there.")
        if [ -n "$nmail" ] && [ -f /etc/stardust.conf ]; then
          if grep -q '^NOTIFY=' /etc/stardust.conf; then
            as_root sed -i "s|^NOTIFY=.*|NOTIFY=$nmail|" /etc/stardust.conf
          else
            as_root sh -c "printf 'NOTIFY=%s\n' '$nmail' >> /etc/stardust.conf"
          fi
          echo "NOTIFY=$nmail — copy /etc/msmtprc.example to /etc/msmtprc and edit SMTP"
        fi
      else
        echo "msmtp: wrote /etc/msmtprc.example (not live until you copy it)"
      fi
    fi
  fi
  if have git && [ "$DRYRUN" -eq 0 ]; then
    as_root git config --system --get safe.directory "$PLATFORMS" >/dev/null 2>&1 \
      || as_root git config --system --add safe.directory "$PLATFORMS" || true
    as_root -u "$OWNER" git config --global init.defaultBranch devel 2>/dev/null || true
  fi
  if [ "$LOCALHOST" -eq 0 ] && { [ "$ROLE" = "test" ] || [ "$ROLE" = "live" ]; }; then
    if have certbot; then
      echo "certbot: installed — obtain certs after site-add, not during install"
    fi
  fi
}

# --- Main Script Logic ---
# Parse command-line arguments
while [ $# -gt 0 ]; do
  case $1 in
    -n) DRYRUN=1 ;;
    -lh|--localhost) LOCALHOST=1 ;;
    -F) DO_CSF=1 ;;
    -m) ROLE=$(normalize_role "${2:-}"); shift ;;
    -u) OWNER=${2:-}; shift ;;
    -a) ADMIN=${2:-}; shift ;;
    -H) HUMAN=${2:-}; shift ;;
    -g) GROUP=${2:-}; shift ;;
    -h) usage; exit 0 ;;
    *) echo "$PROG: unknown flag $1" >&2; exit 1 ;;
  esac
  shift
done

# Set HUMAN to the current user if not specified
if [ -z "$HUMAN" ]; then
  HUMAN=${SUDO_USER:-$(whoami)}
fi

# Detect OS and init system
detect_os
detect_init
detect_group
detect_services

# Normalize role
ROLE=$(normalize_role "$ROLE")

# Print welcome message
echo "$PROG $STARDUST_VERSION — Starting Stardust installation..."
echo "Role: $ROLE"
echo "User: $HUMAN"
echo "Owner: $OWNER"
echo "Admin: $ADMIN"
echo "Group: $GROUP"
echo "Platforms: $PLATFORMS"
echo "Stardust: $STARDUST"
echo

# Install dependencies in order
install_apache2
install_php
install_mariadb
install_git
install_bee
install_gitea
install_extras

# Tune all apps for performance and security
tune_php
tune_apache2
tune_mysql
tune_vps
tune_extras
tune_logrotate

# Create users and groups
ensure_group "$GROUP"
ensure_group stardust
ensure_group adm
ensure_user "$OWNER" "Stardust code owner"
ensure_user "$ADMIN" "Stardust file admin"

# Write sudoers files
write_sudoers /etc/sudoers.d/stardust-deploy <<EOF
# Stardust sudoers — deploy user
$OWNER ALL=(ALL) NOPASSWD: /usr/local/bin/stardust, /usr/local/bin/crdir, /usr/local/bin/newfeature, /usr/local/sbin/stardust-priv
EOF

write_sudoers /etc/sudoers.d/stardust-admin <<EOF
# Stardust sudoers — admin user
$ADMIN ALL=(ALL) NOPASSWD: /usr/local/bin/stardust, /usr/local/bin/crdir, /usr/local/bin/newfeature, /usr/local/sbin/stardust-priv
EOF

# Write user configurations
user_conf "$OWNER"
if [ "$OWNER" != "$ADMIN" ]; then
  user_conf "$ADMIN"
fi
if [ "$HUMAN" != "$OWNER" ] && [ "$HUMAN" != "$ADMIN" ]; then
  user_conf "$HUMAN"
fi

# Ship Stardust tools
ship_tools

# Write configurations
write_cron
write_state
write_etc_conf

# Bootstrap dependencies
bootstrap_deps

# Final message
echo
echo "Stardust installation complete!"
echo "Next steps:"
echo "1. Set passwords for users: sudo passwd $OWNER, sudo passwd $ADMIN"
if [ -n "$HUMAN" ] && [ "$HUMAN" != "$OWNER" ] && [ "$HUMAN" != "$ADMIN" ]; then
  echo "   sudo passwd $HUMAN"
fi
echo "2. Configure Gitea at http://$(hostname):3000 (if installed)"
echo "3. Run 'stardust doctor' to verify the installation"
