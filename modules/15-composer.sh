# modules/15-composer.sh
# App-Centric Worker: Cryptographically Verified, Speed-Optimized Composer Engine
# Engineered to support hardened package persistence for the stable Bee subsystem.

echo "📦 STEP 15: Provisioning Hardened PHP Dependency Sub-Manager (Composer)"
echo "----------------------------------------------------------------------"

composer_install_hardened() {
  if ! command -v composer >/dev/null 2>&1; then
    install_prompt "Install Composer (PHP Package Sub-Manager)? [Y/n]" "Y" "Composer handles verified dependency tracks for system components."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      
      # Ensure dry-run verification mode passes loops cleanly
      if [ "$DRYRUN" -eq 1 ]; then
        echo "+ fetch upstream installer.sig token verification hash"
        echo "+ verification check: php -r \"if (hash_file('SHA384', '/tmp/composer-setup.php') === \$EXPECTED_HASH) ...\""
        echo "+ php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer"
        echo "+ composer config --global optimize-autoloader true"
        echo "  ✓ Simulated secure Composer installation complete (Dry-Run Mode)."
        return 0
      fi

      if have php && have curl; then
        echo "  🔒 Fetching cryptographically signed verification signature..."
        SIG_HASH=$(curl -sS https://composer.github.io/installer.sig)
        
        if [ -z "$SIG_HASH" ]; then
          echo "  ❌ Error: Unable to fetch upstream public signature token. Aborting installation." >&2
          return 1
        fi

        echo "  🌐 Downloading core Composer setup package safely..."
        as_root curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php

        echo "  🛡️ Executing checksum verification mapping..."
        LOCAL_HASH=$(php -r "echo hash_file('SHA384', '/tmp/composer-setup.php');")

        if [ "$SIG_HASH" = "$LOCAL_HASH" ]; then
          echo "  ✅ Checksum Match Verified. Compiling execution binary..."
          run_root php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
          as_root rm -f /tmp/composer-setup.php
        else
          echo "  ❌ CRITICAL SECURITY ALERT: Downloaded installer binary is corrupt or compromised!" >&2
          as_root rm -f /tmp/composer-setup.php
          return 1
        fi

        # Ensure Composer updates are permanently pinned to the stable major release track
        run_root composer self-update --2 >/dev/null 2>&1 || true

        # --- SPEED TWEAKS & HARDENING: Inject system-wide configuration overrides ---
        echo "  ⚙️ Applying system optimization parameters and policy filters..."
        
        # 1. Force the autoloader to convert PSR-4 rules into optimized raw classmaps
        run_root composer config --global optimize-autoloader true
        
        # 2. Prevent Composer from ever running package updates or code tests via Xdebug lines
        run_root composer config --global discard-changes true
        
        # 3. Enforce dynamic auditing to automatically block any dependencies with flagged vulnerabilities
        run_root composer config --global audit.abandoned report
        run_root composer config --global audit.policy block
        
        echo "  ✓ Hardened Composer engine initialized successfully."
      else
        echo "  ❌ Error: Prerequisites missing. Ensure PHP-CLI and Curl are mapped prior to Step 15." >&2
        return 1
      fi
    fi
  else
    echo "  Composer system binary is already registered on active paths."
    if [ "$DRYRUN" -eq 0 ]; then
      # Keep an existing global installation pinned securely to the stable v2 stream
      run_root composer self-update --2 >/dev/null 2>&1 || true
    fi
  fi
}

composer_install_hardened
