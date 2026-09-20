# modules/50-bee.sh
# App-Centric Worker: Backdrop CMS Bee Companion Command Line Interface
# Refactored for absolute structural stability over bleeding-edge tracking.

echo "🐝 STEP 50: Provisioning Backdrop CMS CLI (Bee) via Stable Composer"
echo "------------------------------------------------------------------"

bee_install_stable() {
  if ! command -v bee >/dev/null 2>&1; then
    install_prompt "Install Bee utility globally via Composer? [Y/n]" "Y" "Installs bee package to system path structures."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      
      # Ensure dry-runs validate loop flows completely clean
      if [ "$DRYRUN" -eq 1 ]; then
        echo "+ COMPOSER_ALLOW_SUPERUSER=1 composer global require backdrop/bee:^1.0 --no-dev"
        echo "+ ln -sf /root/.composer/vendor/bin/bee $BEE_BIN"
        echo "  ✓ Simulated stable Bee Composer installation complete (Dry-Run Mode)."
        return 0
      fi

      if have composer; then
        echo "  ⚙️ Retrieving verified stable backdrop/bee package layer..."
        
        # Enforce strict production optimizations and prevent execution boundaries bleeding
        run_root env COMPOSER_ALLOW_SUPERUSER=1 composer global require "backdrop/bee:^1.0" --no-dev --optimize-autoloader
        
        # Build the system link explicitly out to the global execution path
        if [ -f /root/.composer/vendor/bin/bee ]; then
          run_root ln -sf /root/.composer/vendor/bin/bee "$BEE_BIN"
          echo "  ✓ Stable Bee CLI utility successfully linked to execution pathways."
        else
          echo "  ❌ Error: Global Composer bin path could not locate active bee execution tracks." >&2
          return 1
        fi
      else
        echo "  ❌ Error: Composer system package manager not found. Unable to guarantee stability rules." >&2
        return 1
      fi
    fi
  else
    echo "  Bee CLI utility is already registered on system paths."
  fi
}

bee_install_stable
