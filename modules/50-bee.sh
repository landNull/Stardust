# modules/50-bee.sh
# App-Centric Worker: Backdrop CMS Bee Companion Command Line Interface
# Patched to safely bypass network actions during dry-run validations.

echo "🐝 STEP 50: Provisioning Backdrop CMS CLI (Bee)"
echo "-----------------------------------------------"

bee_install_core() {
  if ! command -v bee >/dev/null 2>&1; then
    install_prompt "Install Bee (Backdrop CMS CLI)? [Y/n]" "Y" "Bee handles rapid site profile deployments."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      
      # --- FIX: Intercept network operations if running under Dry-Run conditions ---
      if [ "$DRYRUN" -eq 1 ]; then
        echo "+ git clone $BEE_SRC $BEE_DST"
        echo "  ✓ Simulated Bee installation sequence complete (Dry-Run Mode)."
        return 0
      fi

      if [ ! -d "$BEE_DST" ]; then
        run_root git clone "$BEE_SRC" "$BEE_DST"
      fi
      
      if [ -d "$BEE_DST" ]; then
        if have composer; then
          (
            cd "$BEE_DST"
            run_root composer install --no-dev
            run_root ln -sf "$BEE_DST/bee" "$BEE_BIN"
          )
          echo "  ✓ Bee installation sequence complete."
        else
          echo "  ⚠️ Composer missing. Cannot auto-compile packages."
        fi
      else
        echo "❌ Error: Failed to execute Git source tracking download for Bee." >&2
        return 1
      fi
    fi
  else
    echo "  Bee CLI utility is already linked to execution paths."
  fi
}

bee_install_core
