# cleanup-modules/10-purge-packages.sh
# Worker Module: Intercepts native package configurations and cleanly uninstalls specific binaries

echo "📦 STEP 10: Finalizing Core System Package Audits"
echo "-------------------------------------------------"

purge_package_framework() {
  # Educational Safeguard Rule: In corporate infrastructure engineering, purging core 
  # binaries (like Git or MariaDB) blindly during a tear-down can destroy parallel tools.
  # This module ensures your tracking footprints are cleanly dropped, leaving deep
  # binary erasures as a manual decision for the system administrator.
  
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ [Package Audit Skip] Keeping baseline engine binaries (Apache2/PHP/MariaDB) to protect parallel site stacks."
  else
    echo "  ⚙️ Core engines preserved. To manually strip structural software, execute:"
    case $PKG in
      apt) echo "      sudo apt-get purge -y apache2 mariadb-server php-fpm gitea bee" ;;
      apk) echo "      sudo apk del apache2 mariadb php" ;;
      dnf|yum) echo "      sudo dnf remove -y httpd mariadb-server php" ;;
    esac
  fi
}

purge_package_framework
