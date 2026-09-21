#!/bin/sh
# modules/45-deployment.sh — ship CLIs, state, cron, /etc/stardust.conf
# Leaves /srv/platforms trees alone.

echo "STEP 45: ship tools, state, cron, host conf"

ship_tools

if [ "$DRYRUN" -eq 1 ]; then
  echo "+ git config --global --add safe.directory $PLATFORMS as $OWNER"
elif have git; then
  as_root -u "$OWNER" git config --global --add safe.directory "$PLATFORMS" 2>/dev/null || true
  as_root -u "$OWNER" git config --global --add safe.directory "$PLATFORMS/*" 2>/dev/null || true
  echo "git safe.directory $PLATFORMS for $OWNER"
fi

tune_logrotate
write_state
write_cron
write_etc_conf
bootstrap_deps

svc_start "$SVC_APACHE"
svc_start "$SVC_DB"
if [ "$SVC_DB" = mysql ] && [ "$INIT" != systemd ]; then
  if [ -x /etc/init.d/mariadb ]; then
    svc_start mariadb
  fi
fi

user_conf "$OWNER"
if [ -n "$ADMIN" ]; then
  user_conf "$ADMIN"
fi
if [ -n "$HUMAN" ]; then
  user_conf "$HUMAN"
fi
