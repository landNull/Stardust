#!/bin/sh
# ==============================================================================
# modules/45-deployment.sh — Binary Asset Distribution & Operational Bootstrapper
# ==============================================================================
# Distributes internal assets, registers cron maps, and links runtime libraries.
# ==============================================================================

echo "🚀 STEP 45: Shipping Internal Binaries, States, & Backup Task Schedules"
echo "----------------------------------------------------------------------"

install_tool() {
  src=$1
  dest=$2
  mode=${3:-0755}
  
  if [ ! -f "$src" ]; then
    echo "  note: skip tool placement for $dest (source track $src absent)"
    return 0
  fi
  # Run the native POSIX installer utility securely to lock permissions and ownership tracks in one pass
  run_root install -m "$mode" "$src" "$dest"
}

ship_tools() {
  # Distribute primary executable scripts down to core execution folders
  install_tool "$BINDIR/crdir" /usr/local/bin/crdir 0755
  install_tool "$BINDIR/newfeature" /usr/local/bin/newfeature 0755
  install_tool "$BINDIR/d7-migrate" /usr/local/bin/d7-migrate 0755
  install_tool "$BINDIR/stardust" /usr/local/bin/stardust 0755
  install_tool "$BINDIR/stardust-priv" /usr/local/sbin/stardust-priv 0750
  install_tool "$BINDIR/stardust-menu" /usr/local/bin/stardust-menu 0755
  
  # Distribute library tracking script parameters cleanly into storage planes
  if [ -d "$LIBSRC" ]; then
    run_root mkdir -p /usr/local/lib/stardust "$STARDUST/lib"
    for f in "$LIBSRC"/*.sh "$LIBSRC"/d7-catalog.txt; do
      [ -f "$f" ] || continue
      # Note the escaped evaluations ensuring file name basenames evaluate inside remote root scopes cleanly
      run_root install -m 0644 "$f" "/usr/local/lib/stardust/\$(basename "\$f")"
      run_root install -m 0644 "$f" "$STARDUST/lib/\$(basename "\$f")"
    done
  fi
  
  # Mirror the core installer straight to the local security operations pool
  install_tool "$HERE/install-stardust.sh" /usr/local/sbin/install-stardust.sh 0755
  
  if [ -x /usr/local/bin/stardust ]; then
    run_root ln -sfn /usr/local/bin/stardust "$STARDUST/bin/stardust"
  fi
}

write_cron() {
  dest=/etc/cron.d/stardust
  # Define task intervals explicitly avoiding layout bugs across timezone switches
  body="; Stardust Automation Engine Tasks
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
15 3 * * * $OWNER /usr/local/bin/stardust backup-all >/srv/stardust/state/backup-all.log 2>&1
7,22,37,52 * * * * $OWNER /usr/local/bin/stardust cron-all >/srv/stardust/state/cron-all.log 2>&1"

  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ write cron layout to $dest"
    return 0
  fi
  printf '%s\n' "$body" | write_dropin "$dest"
  as_root chmod 0644 "$dest" 2>/dev/null || true
}

write_state() {
  dest=$STARDUST/state/state.json
  [ -f "$dest" ] && echo "  state node database exists: $dest" && return 0
  [ "$DRYRUN" -eq 1 ] && echo "+ write state core to $dest" && return 0
  
  as_root mkdir -p "$(dirname "$dest")"
  as_root sh -c "cat > '$dest'" <<EOF
{"role":"$ROLE","platforms":[]}
EOF
  as_root chown "$OWNER:$GROUP" "$dest"
  as_root chmod 0660 "$dest"
}

bootstrap_deps() {
  echo "  ⚙️ Adjusting background processing dependencies and process loops..."
  
  # Loop to boot the specific localized PHP-FPM service variant matched on disk
  if have php-fpm || [ -x /etc/init.d/php-fpm ] || ls /etc/init.d/php*-fpm >/dev/null 2>&1; then
    for s in php8.2-fpm php8.3-fpm php8.4-fpm php7.4-fpm php-fpm; do
      if [ -x "/etc/init.d/$s" ] || [ -d "/lib/systemd/system/$s.service" ]; then
        svc_start "$s"
        break
      fi
    done
  fi

  # Boot performance monitors and hardware analysis tools cleanly
  for daemon in irqbalance haveged smartd smartmontools; do
    have "$daemon" && svc_start "$daemon"
  done
  
  # Register system directory safety mappings into the git global engine core
  if have git && [ "$DRYRUN" -eq 0 ]; then
    as_root git config --system --get safe.directory "$PLATFORMS" >/dev/null 2>&1 \
      || as_root git config --system --add safe.directory "$PLATFORMS" || true
    as_root -u "$OWNER" git config --global init.defaultBranch devel 2>/dev/null || true
  fi
}

# Run deployment cascade routines
ship_tools
write_cron
write_state
bootstrap_deps
