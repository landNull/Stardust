# cleanup-modules/20-purge-tuning.sh
# Worker Module: Reverts OS kernel modifications, PHP configs, and web server performance drops

echo "⚙️ STEP 20: Purging Performance Tuning & Configurations"
echo "--------------------------------------------------------"

purge_apache_tuning() {
  local perf_conf="/etc/apache2/conf-available/stardust-perf.conf"
  local harden_conf="/etc/apache2/conf-available/stardust-harden.conf"
  
  if [ "$DRYRUN" -eq 1 ]; then
    [ -f "$perf_conf" ] && echo "+ rm -f /etc/apache2/conf-enabled/stardust-perf.conf && rm -f $perf_conf"
    [ -f "$harden_conf" ] && echo "+ rm -f /etc/apache2/conf-enabled/stardust-harden.conf && rm -f $harden_conf"
  else
    as_root rm -f /etc/apache2/conf-enabled/stardust-perf.conf /etc/apache2/conf-available/stardust-perf.conf
    as_root rm -f /etc/apache2/conf-enabled/stardust-harden.conf /etc/apache2/conf-available/stardust-harden.conf
    echo "  ✓ Dropped custom Apache performance configs."
  fi
}

purge_php_tuning() {
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ Scanning /etc/php for 30-stardust.ini, 35-stardust-cli.ini, and 35-stardust-harden.ini to remove"
  else
    # Automatically locate all nested ini drop-ins across FPM, CLI, and Apache SAPIs
    find /etc/php /etc/php.d -type f \( -name "30-stardust.ini" -o -name "35-stardust-*.ini" \) 2>/dev/null | while read -r ini_file; do
      as_root rm -f "$ini_file"
    done
    echo "  ✓ Cleared out Stardust runtime variables from PHP engine."
  fi
}

purge_mysql_tuning() {
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ Scanning /etc/mysql /etc/my.cnf.d for 90-stardust.cnf to remove"
  else
    find /etc/mysql /etc/my.cnf.d -type f -name "90-stardust.cnf" 2>/dev/null | while read -r cnf_file; do
      as_root rm -f "$cnf_file"
    done
    echo "  ✓ Restored default engine buffers for MariaDB."
  fi
}

purge_sysctl_tuning() {
  local sysctl_conf="/etc/sysctl.d/60-stardust.conf"
  local limits_conf="/etc/security/limits.d/stardust.conf"
  local logrotate_conf="/etc/logrotate.d/stardust"
  local unattended_conf="/etc/apt/apt.conf.d/52stardust-unattended"

  if [ "$DRYRUN" -eq 1 ]; then
    [ -f "$sysctl_conf" ] && echo "+ rm -f $sysctl_conf && sysctl --system"
    [ -f "$limits_conf" ] && echo "+ rm -f $limits_conf"
    [ -f "$logrotate_conf" ] && echo "+ rm -f $logrotate_conf"
    [ -f "$unattended_conf" ] && echo "+ rm -f $unattended_conf"
  else
    [ -f "$sysctl_conf" ] && as_root rm -f "$sysctl_conf" && as_root sysctl --system >/dev/null 2>&1 || true
    [ -f "$limits_conf" ] && as_root rm -f "$limits_conf"
    [ -f "$logrotate_conf" ] && as_root rm -f "$logrotate_conf"
    [ -f "$unattended_conf" ] && as_root rm -f "$unattended_conf"
    echo "  ✓ Successfully restored system core limits and background parameters."
  fi
}

# Fire execution pipeline
purge_apache_tuning
purge_php_tuning
purge_mysql_tuning
purge_sysctl_tuning
