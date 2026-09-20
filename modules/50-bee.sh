# modules/50-bee.sh
# App-Centric Worker: Backdrop CMS Bee Companion Command Line Interface
# Refactored to allow safe, idempotent installations on existing brownfield servers.

echo "🐝 STEP 50: Provisioning Backdrop CMS CLI (Bee)"
echo "-----------------------------------------------"

bee_install_stable() {
  # Establish target constraints matching our stability directive
  STABLE_SERIES="1."

  # --- Short-Circuit Check for Existing Servers ---
  if have bee; then
    echo "  🔍 Detected existing 'bee' binary on system path. Auditing version..."
    
    # Capture standard error and output safely without risking shell crashes
    CURRENT_VERSION=$(bee version 2>/dev/null || echo "unknown")
    
    case $CURRENT_VERSION in
      "${STABLE_SERIES}"*)
        echo "  ✅ SKIP: Stable Bee release ($CURRENT_VERSION) is already active. Preserving configuration."
        return 0
        ;;
      *)
        echo "  ⚠️ Version mismatch or unreadable tag ($CURRENT_VERSION). Enforcing standard stable overlay..."
        ;;
    esac
  fi

  # --- Standard Installation Cascade ---
  install_prompt "Install/Update Bee utility globally via Composer? [Y/n]" "Y" "Installs bee package to system path structures."
  if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
    
    # Ensure dry-run simulation traces loops smoothly
    if [ "$DRYRUN" -eq 1 ]; then
      echo "+ COMPOSER_ALLOW_SUPERUSER=1 composer global require backdrop/bee:^1.0 --no-dev"
      echo "+ ln -sf /root/.composer/vendor/bin/bee $BEE_BIN"
      echo "  ✓ Simulated stable Bee Composer installation/alignment complete (Dry-Run Mode)."
      return 0
    fi

    if have composer; then
      echo "  ⚙️ Retrieving verified stable backdrop/bee package layer..."
      
      # Enforce production flags and prevent environmental cross-contamination
      run_root env COMPOSER_ALLOW_SUPERUSER=1 composer global require "backdrop/bee:^1.0" --no-dev --optimize-autoloader
      
      # Anchor the target binary back out to global paths smoothly
      if [ -f /root/.composer/vendor/bin/bee ]; then
        run_root ln -sf /root/.composer/vendor/bin/bee "$BEE_BIN"
        echo "  ✓ Stable Bee CLI utility successfully integrated."
      else
        echo "  ❌ Error: Global Composer bin folder path could not locate active bee execution tracks." >&2
        return 1
      fi
    else
      echo "  ❌ Error: Composer system package manager not found. Unable to guarantee stability hooks." >&2
      return 1
    fi
  fi
}

bee_install_stable
