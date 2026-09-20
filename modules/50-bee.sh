#!/bin/sh
# ==============================================================================
# modules/50-bee.sh — Backdrop CMS Companion Command Line Interface (Bee)
# ==============================================================================
# Engineered with isolated subshells to allow safe brownfield overlays.
# Utilizes the secure global Composer instance deployed in Step 15.
# ==============================================================================

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
    
    # Case statement tracking wildcards smoothly within POSIX syntax boundaries
    case $CURRENT_VERSION in
      "${STABLE_SERIES}"*)
        echo "  ✅ SKIP: Stable Bee release ($CURRENT_VERSION) is already active. Preserving configuration."
        return 0 # Yield control back safely to loop without firing installs
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

    # Verify our Step 15 dependency manager is up and functional before calling it
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
      # --- INDEPENDENT FALLBACK CLONE INTERCEPT ---
      # If composer environment checks completely fail, run a manual repo deployment
      echo "  ⚠️ Composer binary missing on active scope. Attempting legacy clone build..."
      
      if [ ! -d "$BEE_DST" ]; then
        run_root git clone "$BEE_SRC" "$BEE_DST"
      fi

      if [ -d "$BEE_DST" ]; then
        # --- THE POSIX SUBSHELL WRAPPER BLOCK ---
        # Crucial Lesson: The parentheses ( ... ) spin up a temporary clone of the shell process.
        # When 'cd' runs inside the parentheses, it shifts paths *only* inside that bubble.
        # Once the closing parenthesis is hit, the shell snaps back to the original orchestrator path.
        # This completely prevents broken paths or broken subsequent module loads.
        (
          cd "$BEE_DST"
          # Run internal localized configuration adjustments safely
          run_root ln -sf "$BEE_DST/bee" "$BEE_BIN"
        )
        echo "  ✓ Bee alternative legacy clone successfully mapped to $BEE_BIN."
      else
        echo "  ❌ Error: Failed to clone alternative Bee repository storage tracker." >&2
        return 1
      fi
    fi
  fi
}

# Trigger module asset calculations
bee_install_stable
