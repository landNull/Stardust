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
      echo "+ DEBIAN_FRONTEND=noninteractive apt-get purge -y -o Dpkg::Options::=\"--force-confnew\" $APT_PACKAGES"
      echo "+ apt-get autoremove -y"
      echo "+ rm -rf /usr/local/bin/bee /usr/local/src/bee"
      echo "+ rm -f /usr/local/bin/gitea"
    else
      # 1. FIX: Do NOT hide stdout/stderr entirely here during service teardowns.
      # If a daemon is stuck, we need to see it fail rather than masking a hang.
      echo "  Stopping background application listeners..."
      as_root /etc/init.d/apache2 stop || true
      as_root /etc/init.d/mysql stop || true
      as_root /etc/init.d/gitea stop || true

      # 2. Force apt-get into a completely silent, non-interactive posture
      # FIX: Removed the invalid 'confbp' flag and applied standard POSIX overrides
      echo "  Purging system repository packages via apt (Non-interactive Mode)..."
      as_root env DEBIAN_FRONTEND=noninteractive apt-get purge -y \
        -o Dpkg::Options::="--force-confold" \
        -o Dpkg::Options::="--force-confmiss" \
        $APT_PACKAGES
      
      echo "  Cleaning up trailing dependency artifacts..."
      as_root env DEBIAN_FRONTEND=noninteractive apt-get autoremove -y --purge
      as_root env DEBIAN_FRONTEND=noninteractive apt-get clean
      
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
