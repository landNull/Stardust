#!/bin/sh
# ==============================================================================
# modules/15-composer.sh — Cryptographically Verified Dependency Manager Engine
# ==============================================================================
# Engineered for strict POSIX shell compliance.
# Runs inline via the orchestrator to provide global package tracking for Bee.
# ==============================================================================

# Output execution milestone headers cleanly to stdout
echo "📦 STEP 15: Provisioning Hardened PHP Dependency Sub-Manager (Composer)"
echo "----------------------------------------------------------------------"

composer_install_hardened() {
  # --- IDEMPOTENCY GUARD: Check if binary is already mapped ---
  # 'command -v' is the safest POSIX method to audit executable tracks.
  # Redirecting to /dev/null ensures zero text clutter on the console screen.
  if ! command -v composer >/dev/null 2>&1; then
    
    # Prompt user for interaction. $ans is captured safely from standard inputs.
    install_prompt "Install Composer (PHP Package Sub-Manager)? [Y/n]" "Y" "Composer handles verified dependency tracks for system components."
    
    # POSIX string matching: Handles both uppercase and lowercase confirmations.
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      
      # --- DRYRUN INTERCEPT LAYER ---
      # Safely short-circuits execution if the user invoked a simulation run (-n).
      if [ "$DRYRUN" -eq 1 ]; then
        echo "+ fetch upstream installer.sig token verification hash"
        echo "+ verification check: php -r \"if (hash_file('SHA384', ...)) ...\""
        echo "+ php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer"
        echo "  ✓ Simulated secure Composer installation complete (Dry-Run Mode)."
        return 0 # Safe function breakout; preserves orchestrator loop execution.
      fi

      # --- STRUCTURAL BOUNDARY CHECK ---
      # Verify host packages required for installation are completely active.
      if have php && have curl; then
        echo "  🔒 Fetching cryptographically signed verification signature..."
        
        # Capture raw text string from remote endpoint securely.
        SIG_HASH=$(curl -sS https://github.io)
        
        # Defend against network drops: If signature is empty, abort to protect execution.
        if [ -z "$SIG_HASH" ]; then
          echo "  ❌ Error: Unable to fetch upstream public signature token. Aborting installation." >&2
          return 1 # Explicit failure signal propagated safely back to loop.
        fi

        echo "  🌐 Downloading core Composer setup package safely..."
        # 'as_root' escalates privileges if needed without creating a subshell environment
        as_root curl -sS https://getcomposer.org -o /tmp/composer-setup.php

        echo "  🛡️ Executing checksum verification mapping..."
        # POSIX backtick/subshell idiom executing raw code inside localized PHP engines
        LOCAL_HASH=$(php -r "echo hash_file('SHA384', '/tmp/composer-setup.php');")

        # --- CRYPTOGRAPHIC GUARD BLOCK ---
        # Match signatures exactly before passing code execution controls to a root file
        if [ "$SIG_HASH" = "$LOCAL_HASH" ]; then
          echo "  ✅ Checksum Match Verified. Compiling execution binary..."
          run_root php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
          as_root rm -f /tmp/composer-setup.php
        else
          echo "  ❌ CRITICAL SECURITY ALERT: Downloaded installer binary is corrupt or compromised!" >&2
          as_root rm -f /tmp/composer-setup.php
          return 1 # Drops out immediately to flag the security exception.
        fi

        # Force Composer updates to permanently route down the stable major release track.
        # '|| true' protects 'set -e' loops if an upstream timeout causes a minor exit code.
        run_root composer self-update --2 >/dev/null 2>&1 || true

        # --- SPEED TWEAKS & HARDENING: Inject system-wide configurations ---
        echo "  ⚙️ Applying system optimization parameters and policy filters..."
        
        # 1. Force the autoloader to convert PSR-4 rules into optimized raw classmaps.
        run_root composer config --global optimize-autoloader true
        
        # 2. Prevent environment updates from hanging on unsaved local edits mid-run.
        run_root composer config --global discard-changes true
        
        # 3. Enforce dynamic auditing to automatically block unsafe code assets.
        run_root composer config --global audit.abandoned report
        run_root composer config --global audit.policy block
        
        echo "  ✓ Hardened Composer engine initialized successfully."
      else
        echo "  ❌ Error: Prerequisites missing. Ensure PHP-CLI and Curl are mapped prior to Step 15." >&2
        return 1
      fi
    fi
  else
    # --- UPGRADE CASCADE TRACKER ---
    # If binary already exists, keep it safely updated to the latest v2 stream.
    echo "  Composer system binary is already registered on active paths."
    if [ "$DRYRUN" -eq 0 ]; then
      run_root composer self-update --2 >/dev/null 2>&1 || true
    fi
  fi
}

# Fire the isolated execution block
composer_install_hardened
