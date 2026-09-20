#!/bin/sh
# ==============================================================================
# modules/20-apache2.sh — Web Server Provisioning, Tuning, & Hardening Node
# ==============================================================================
# Written strictly to conform with POSIX standard syntax layouts.
# Executed inline by install-stardust.sh; avoids mutating shell global state.
# ==============================================================================

echo "🌐 STEP 20: Provisioning Web Server Layer (Apache2)"
echo "--------------------------------------------------"

apache_install() {
  # --- IDEMPOTENCY GUARD ---
  # Check if apache2 or httpd are already registered in the package tracking index.
  # This prevents the script from wasting bandwidth or breaking active configurations.
  if ! pkg_ok apache2 && ! pkg_ok httpd; then
    install_prompt "Install Apache2 (Web Server)? [Y/n]" "Y" "Apache2 is required for local site rendering structures."
    
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      # Handle cross-distribution translation maps using the global $PKG variable
      case $PKG in 
        apt|apk) pkg_install apache2 ;; 
        dnf|yum) pkg_install httpd ;; 
      esac
    fi
  else
    echo "  Apache2 package is already installed on this system partition."
  fi
}

apache_tune_speed() {
  echo "  ⚙️ Applying high-performance thread parameters (mpm_event)..."
  
  # Ensure target configuration tracking folder boundaries physically exist
  run_root mkdir -p /etc/apache2/mods-enabled

  # --- POSIX STRING LOOP ENFORCEMENT ---
  # Iterate over explicit space-separated strings cleanly.
  # This pattern is preferred in standard /bin/sh over bash arrays.
  for mod in mpm_event proxy_fcgi setenvif deflate expires cache headers; do
    # Verify the target module metadata exists before pulling symlink triggers
    [ -f "/etc/apache2/mods-available/${mod}.load" ] && run_root ln -sf "../mods-available/${mod}.load" "/etc/apache2/mods-enabled/${mod}.load"
    [ -f "/etc/apache2/mods-available/${mod}.conf" ] && run_root ln -sf "../mods-available/${mod}.conf" "/etc/apache2/mods-enabled/${mod}.conf"
  done

  # Check for compatible Linux systems before writing performance configurations
  if [ "$PKG" = "apt" ] || [ "$PKG" = "dnf" ] || [ "$PKG" = "yum" ]; then
    apache_perf_conf="/etc/apache2/conf-available/stardust-perf.conf"
    
    # Store clean configuration layout string mapping direct memory properties
    body="<IfModule mpm_event_module>
  StartServers 2
  MinSpareThreads 25
  MaxSpareThreads 75
  ThreadLimit 64
  ThreadsPerChild 25
  MaxRequestWorkers 150
  MaxConnectionsPerChild 1000
</IfModule>
<IfModule mod_deflate.c>
  AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript application/javascript
</IfModule>
<IfModule mod_expires.c>
  ExpiresActive On
  ExpiresDefault \"access plus 1 month\"
</IfModule>"

    # Safe pass-off using POSIX printf to handle multi-line strings cleanly into helper pipes
    printf '%s\n' "$body" | write_dropin "$apache_perf_conf"
    
    # Enable configuration via a relative path symlink mapping rule
    run_root mkdir -p /etc/apache2/conf-enabled
    run_root ln -sf "../conf-available/stardust-perf.conf" /etc/apache2/conf-enabled/stardust-perf.conf
  fi
}

apache_tune_security() {
  echo "  ⚙️ Stripping upstream server identity signatures..."
  apache_h_conf="/etc/apache2/conf-available/stardust-harden.conf"
  
  body="ServerTokens Prod
ServerSignature Off
TraceEnable Off
Timeout 30
KeepAlive On
KeepAliveTimeout 5
MaxKeepAliveRequests 100"
  
  if [ -d /etc/apache2/conf-available ]; then
    printf '%s\n' "$body" | write_dropin "$apache_h_conf"
    # 'have' checks if a2enconf binary exists before execution to prevent a 'set -e' crash
    have a2enconf && run_root a2enconf stardust-harden >/dev/null 2>&1 || true
  fi
}

# Run the execution blocks sequentially
apache_install
apache_tune_speed
apache_tune_security
