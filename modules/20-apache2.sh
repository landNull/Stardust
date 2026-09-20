# modules/20-apache2.sh
# App-Centric Worker: Apache2 Installation, Tuning, and Security Hardening

echo "🌐 STEP 20: Provisioning Web Server Layer (Apache2)"
echo "--------------------------------------------------"

apache_install() {
  if ! pkg_ok apache2 && ! pkg_ok httpd; then
    install_prompt "Install Apache2 (Web Server)? [Y/n]" "Y" "Apache2 is required for local site rendering structures."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      case $PKG in apt|apk) pkg_install apache2 ;; dnf|yum) pkg_install httpd ;; esac
    fi
  else
    echo "  Apache2 package is already installed."
  fi
}

apache_tune_speed() {
  echo "  ⚙️ Applying high-performance thread parameters (mpm_event)..."
  run_root mkdir -p /etc/apache2/mods-enabled
  for mod in mpm_event proxy_fcgi setenvif deflate expires cache headers; do
    [ -f "/etc/apache2/mods-available/${mod}.load" ] && run_root ln -sf "../mods-available/${mod}.load" "/etc/apache2/mods-enabled/${mod}.load"
    [ -f "/etc/apache2/mods-available/${mod}.conf" ] && run_root ln -sf "../mods-available/${mod}.conf" "/etc/apache2/mods-enabled/${mod}.conf"
  done

  if [ "$PKG" = "apt" ] || [ "$PKG" = "dnf" ] || [ "$PKG" = "yum" ]; then
    apache_perf_conf="/etc/apache2/conf-available/stardust-perf.conf"
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
    printf '%s\n' "$body" | write_dropin "$apache_perf_conf"
    run_root mkdir -p /etc/apache2/conf-enabled
    run_root ln -sf "../conf-available/stardust-perf.conf" /etc/apache2/conf-enabled/stardust-perf.conf
  fi
}

apache_tune_security() {
  echo "  ⚙️ Stripping server signatures..."
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
    have a2enconf && run_root a2enconf stardust-harden >/dev/null 2>&1 || true
  fi
}

apache_install
apache_tune_speed
apache_tune_security
