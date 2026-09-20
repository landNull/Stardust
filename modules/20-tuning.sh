# modules/20-tuning.sh
# Worker: Performance Tuning & Optimization Engine

echo "⚙️ PHASE 2: Performance Tuning & Optimization"
echo "----------------------------------------"

tune_apache2() {
  echo "  ⚙ Configuring Apache modules safely..."
  run_root mkdir -p /etc/apache2/mods-enabled

  for mod in mpm_event proxy_fcgi setenvif deflate expires cache headers; do
    if [ -f "/etc/apache2/mods-available/${mod}.load" ]; then
      run_root ln -sf "../mods-available/${mod}.load" "/etc/apache2/mods-enabled/${mod}.load"
    fi
    if [ -f "/etc/apache2/mods-available/${mod}.conf" ]; then
      run_root ln -sf "../mods-available/${mod}.conf" "/etc/apache2/mods-enabled/${mod}.conf"
    fi
  done

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

    if [ "$DRYRUN" -eq 1 ]; then
      echo "+ write $apache_perf_conf"
    else
      run_root mkdir -p "/etc/apache2/conf-available"
      printf '%s\n' "$body" | as_root sh -c "cat > '$apache_perf_conf'"
      echo "wrote $apache_perf_conf"
    fi
    
    run_root mkdir -p /etc/apache2/conf-enabled
    run_root ln -sf "../conf-available/stardust-perf.conf" /etc/apache2/conf-enabled/stardust-perf.conf
  fi
  echo "Apache2 tuned for performance via manual symlinks."
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
    if [ -x /etc/init.d/\$SVC_APACHE ]; then /etc/init.d/\$SVC_APACHE reload >/dev/null 2>&1 || true; fi
  endscript
}
"
  if [ -d /etc/logrotate.d ]; then
    printf '%s\n' "$body" | write_dropin /etc/logrotate.d/stardust
  fi
}

# Fire tuning parameters
tune_php
tune_apache2
tune_mysql
tune_vps
tune_extras
tune_logrotate

