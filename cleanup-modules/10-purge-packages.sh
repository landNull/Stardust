# cleanup-modules/10-purge-packages.sh
# Worker Module: Non-interactive deep purge engine for system packages and libraries

echo "📦 STEP 10: Finalizing Core System Package Audits"
echo "-------------------------------------------------"

APT_PACKAGES="apache2 mariadb-server php-fpm php-cli php-mysql php-xml php-gd php-mbstring php-curl php-zip php-intl php-bcmath php-imagick php-apcu apache2-utils mariadb-backup msmtp-mta unattended-upgrades needrestart logwatch goaccess etckeeper smartmontools irqbalance haveged moreutils jq pv age dnsmasq"

purge_package_framework() {
  if [ "$PURGE_ALL" -eq 1 ]; then
    echo "🚨 Purge flag detected! Executing automated deep-cleansing sequence..."
    if [ "$DRYRUN" -eq 1 ]; then
      echo "+ DEBIAN_FRONTEND=noninteractive apt-get purge -y -o Dpkg::Options::=\"--force-confold\" $APT_PACKAGES"
      echo "+ DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y"
      echo "+ rm -rf /usr/local/bin/bee /usr/local/src/bee"
      echo "+ rm -f /usr/local/bin/gitea"
    else
      echo "  Stopping active daemon service handles safely via discovered service manager..."
      case $INIT in
        systemd)
          as_root systemctl stop "$SVC_APACHE" "$SVC_DB" gitea 2>/dev/null || true
          ;;
        openrc)
          as_root rc-service "$SVC_APACHE" stop 2>/dev/null || true
          as_root rc-service "$SVC_DB" stop 2>/dev/null || true
          as_root rc-service gitea stop 2>/dev/null || true
          ;;
        sysv|*)
          [ -x "/etc/init.d/$SVC_APACHE" ] && as_root "/etc/init.d/$SVC_APACHE" stop 2>/dev/null || true
          [ -x "/etc/init.d/$SVC_DB" ] && as_root "/etc/init.d/$SVC_DB" stop 2>/dev/null || true
          [ -x "/etc/init.d/gitea" ] && as_root "/etc/init.d/gitea" stop 2>/dev/null || true
          ;;
      esac

      echo "  Purging system repository packages via apt (Non-interactive Mode)..."
      as_root env DEBIAN_FRONTEND=noninteractive apt-get purge -y \
        -o Dpkg::Options::="--force-confold" \
        -o Dpkg::Options::="--force-confmiss" \
        $APT_PACKAGES
      
      echo "  Executing dynamic dependency autoremove and purge cascade..."
      as_root env DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
      as_root env DEBIAN_FRONTEND=noninteractive apt-get clean
      
      echo "  Deleting manual scripted binary installations..."
      as_root rm -rf /usr/local/bin/bee /usr/local/src/bee
      as_root rm -f /usr/local/bin/gitea
      echo "  ✓ Environment successfully scrubbed back to a pristine vanilla baseline."
    fi
  else
    echo "  ⚙️ Core engines preserved (Soft-removal mode)."
  fi
}

purge_package_framework
