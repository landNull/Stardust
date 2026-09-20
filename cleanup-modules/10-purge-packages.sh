# cleanup-modules/10-purge-packages.sh
# Worker Module: Intercepts native package configurations and cleanly uninstalls specific binaries

echo "📦 STEP 10: Finalizing Core System Package Audits"
echo "-------------------------------------------------"

# Define the precise list of apt packages installed by phase 1
APT_PACKAGES="apache2 mariadb-server php-fpm php-cli php-mysql php-xml php-gd php-mbstring php-curl php-zip php-intl php-bcmath php-imagick php-apcu apache2-utils mariadb-backup msmtp-mta unattended-upgrades needrestart logwatch goaccess etckeeper smartmontools irqbalance haveged moreutils jq pv age dnsmasq"

purge_package_framework() {
  if [ "$PURGE_ALL" -eq 1 ]; then
    echo "🚨 Purge flag detected! Stripping core engines and software dependencies..."
    
    if [ "$DRYRUN" -eq 1 ]; then
      echo "+ apt-get purge -y $APT_PACKAGES && apt-get autoremove -y"
      echo "+ rm -rf /usr/local/bin/bee /usr/local/src/bee"
      echo "+ rm -f /usr/local/bin/gitea"
    else
      # 1. Stop active daemons before uninstalling to prevent hanging process states
      echo "  Stopping background application listeners..."
      as_root /etc/init.d/apache2 stop >/dev/null 2>&1 || true
      as_root /etc/init.d/mysql stop >/dev/null 2>&1 || true
      as_root /etc/init.d/gitea stop >/dev/null 2>&1 || true

      # 2. Force purge apt-managed software environments
      echo "  Purging system repository packages via apt..."
      as_root apt-get purge -y $APT_PACKAGES >/dev/null 2>&1 || true
      as_root apt-get autoremove -y >/dev/null 2>&1 || true
      
      # 3. Wipe out structural manual download folders and compiled paths
      echo "  Deleting manual scripted binary installations..."
      as_root rm -rf /usr/local/bin/bee /usr/local/src/bee
      as_root rm -f /usr/local/bin/gitea
      
      echo "  ✓ Environment successfully scrubbed back to native OS baseline."
    fi
  else
    echo "  ⚙️ Core engines preserved (Soft-removal mode)."
    echo "      To manually strip structural software, re-run with: cleanup-stardust.sh -p"
  fi
}

purge_package_framework
