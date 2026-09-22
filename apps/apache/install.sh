#!/bin/sh
# modules/20-apache2.sh — rewrite/headers/expires, localhost bind
# Apache packages are installed in 10-core-prereqs. This phase only tunes.
# DNS wildcards moved to apps/dnsmasq/install.sh (STEP 25).

echo "STEP 20: Apache modules, localhost bind"

if [ "$DRYRUN" -eq 1 ]; then
  echo "+ a2enmod rewrite headers expires"
elif have a2enmod; then
  run_root a2enmod rewrite >/dev/null 2>&1 || true
  run_root a2enmod headers >/dev/null 2>&1 || true
  run_root a2enmod expires >/dev/null 2>&1 || true
fi

if [ "$LOCALHOST" -eq 1 ]; then
  if [ -d /etc/apache2 ]; then
    printf '%s\n' "Listen 127.0.0.1:80" | write_dropin /etc/apache2/conf-available/stardust-localhost.conf
    if have a2enconf; then
      run_root a2enconf stardust-localhost >/dev/null 2>&1 || true
    fi
  fi
  echo "localhost: Apache should listen on 127.0.0.1 only (disable stock Listen 80 if it still binds all addresses)"
fi
