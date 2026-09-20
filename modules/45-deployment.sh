# modules/40-deployment.sh
# Worker: File System Distribution & Initial Bootstrap Execution

install_tool() {
  src=$1
  dest=$2
  mode=${3:-0755}
  if [ ! -f "$src" ]; then
    echo "note: skip $dest (no $src next to installer)"
    return 0
  fi
  run_root install -m "$mode" "$src" "$dest"
  echo "installed $dest"
}

ship_tools() {
  install_tool "$BINDIR/crdir" /usr/local/bin/crdir 0755
  install_tool "$BINDIR/newfeature" /usr/local/bin/newfeature 0755
  install_tool "$BINDIR/d7-migrate" /usr/local/bin/d7-migrate 0755
  install_tool "$BINDIR/stardust" /usr/local/bin/stardust 0755
  install_tool "$BINDIR/stardust-priv" /usr/local/sbin/stardust-priv 0750
  install_tool "$BINDIR/stardust-menu" /usr/local/bin/stardust-menu 0755
  if [ -x "$TUIDIR/stardust-tui" ]; then
    install_tool "$TUIDIR/stardust-tui" /usr/local/bin/stardust-tui 0755
  elif [ -d "$TUIDIR" ] && [ -f "$TUIDIR/main.go" ] && command -v go >/dev/null 2>&1; then
    echo "building stardust-tui"
    (cd "$TUIDIR" && GOPROXY=https://golang.org,direct go build -o stardust-tui .) && install_tool "$TUIDIR/stardust-tui" /usr/local/bin/stardust-tui 0755
  else
    echo "stardust-tui binary absent (optional; use stardust-menu)"
  fi
  install_tool "$HERE/install-stardust.sh" /usr/local/sbin/install-stardust.sh 0755
  if [ -d "$LIBSRC" ]; then
    run_root mkdir -p /usr/local/lib/stardust "$STARDUST/lib"
    for f in "$LIBSRC"/*.sh "$LIBSRC"/d7-catalog.txt; do
      [ -f "$f" ] || continue
      run_root install -m 0644 "$f" "/usr/local/lib/stardust/\$(basename "\$f")"
      run_root install -m 0644 "$f" "$STARDUST/lib/\$(basename "\$f")"
    done
    echo "installed stardust-lib from $LIBSRC"
  fi
  if [ -f "$MANDIR/crdir.1" ]; then
    run_root mkdir -p /usr/local/share/man/man1
    run_root install -m 0644 "$MANDIR/crdir.1" /usr/local/share/man/man1/crdir.1
    echo "installed man crdir"
  fi
  if [ -f "$MANDIR/stardust.1" ]; then
    run_root mkdir -p /usr/local/share/man/man1
    run_root install -m 0644 "$MANDIR/stardust.1" /usr/local/share/man/man1/stardust.1
    echo "installed man stardust"
  fi
  if [ -f "$MANDIR/d7-migrate.1" ]; then
    run_root mkdir -p /usr/local/share/man/man1
    run_root install -m 0644 "$MANDIR/d7-migrate.1" /usr/local/share/man/man1/d7-migrate.1
    echo "installed man d7-migrate"
  fi
  DOCSRC=""
  [ -d "$HERE/docs" ] && DOCSRC=$HERE/docs
  if [ -n "$DOCSRC" ]; then
    run_root mkdir -p /usr/local/share/stardust/docs "$STARDUST/docs"
    for f in "$DOCSRC"/*.txt "$DOCSRC"/*.md; do
      [ -f "$f" ] || continue
      run_root install -m 0644 "$f" "/usr/local/share/stardust/docs/\$(basename "\$f")"
      run_root install -m 0644 "$f" "$STARDUST/docs/\$(basename "\$f")"
    done
    echo "installed docs from $DOCSRC"
  fi
  if [ -x /usr/local/bin/stardust ]; then
    run_root ln -sfn /usr/local/bin/stardust "$STARDUST/bin/stardust"
  fi
}

write_cron() {
  dest=/etc/cron.d/stardust
  body="; Stardust — nightly backup + per-site Bee cron
; m h dom mon dow user command
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
15 3 * * * $OWNER /usr/local/bin/stardust backup-all >/srv/stardust/state/backup-all.log 2>&1
7,22,37,52 * * * * $OWNER /usr/local/bin/stardust cron-all >/srv/stardust/state/cron-all.log 2>&1
"
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ write $dest"
    return 0
  fi
  printf '%s\n' "$body" | write_dropin "$dest"
  as_root chmod 0644 "$dest" 2>/dev/null || true
  echo "cron $dest (backup 03:15, bee cron :07/:22/:37/:52)"
}

write_state() {
  dest=$STARDUST/state/state.json
  if [ -f "$dest" ]; then
    echo "state exists: $dest"
    return 0
  fi
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ write $dest"
    return 0
  fi
  as_root sh -c "cat > '$dest'" <<EOF
{"role":"$ROLE","platforms":[]}
EOF
  as_root chown "$OWNER:$GROUP" "$dest"
  as_root chmod 0660 "$dest"
  echo "wrote $dest"
}

bootstrap_deps() {
  echo "Bootstrapping extras (skip when config already exists)..."
  if have php-fpm || [ -x /etc/init.d/php-fpm ] || ls /etc/init.d/php*-fpm >/dev/null 2>&1; then
    for s in php8.2-fpm php8.3-fpm php8.4-fpm php7.4-fpm php-fpm; do
      if [ -x "/etc/init.d/$s" ] || [ -d "/lib/systemd/system/$s.service" ]; then
        svc_start "$s"
        break
      fi
    done
  fi
  if have mysql || have mariadb; then
    if [ "$DRYRUN" -eq 0 ]; then
      if mysql -N -e "SELECT 1" >/dev/null 2>&1; then
        echo "mariadb: local socket OK"
      else
        echo "note: mariadb not answering on the unix socket yet — start it, then re-run"
      fi
    fi
  fi
  if have etckeeper; then
    if [ -d /etc/.git ]; then
      echo "etckeeper: /etc already a repo (unchanged)"
    elif [ "$DRYRUN" -eq 1 ]; then
      echo "+ etckeeper init"
    else
      as_root etckeeper init >/dev/null 2>&1 || true
      as_root etckeeper commit -m "stardust first run" >/dev/null 2>&1 || true
      echo "etckeeper: initialized /etc"
    fi
  fi
  if have needrestart && [ -d /etc/needrestart/conf.d ]; then
    printf '%s\n' '\$nrconf{restart} = "l";' | write_if_absent /etc/needrestart/conf.d/stardust.conf
  fi
  if have logwatch; then
    printf '%s\n' "Detail = Low" "MailTo = root" | write_if_absent /etc/logwatch/conf/logwatch.conf
  fi
  if have goaccess && [ ! -f /etc/goaccess/goaccess.conf ]; then
    echo "note: goaccess installed — run: goaccess /var/log/apache2/access.log"
  fi
  if have smartd || [ -x /etc/init.d/smartd ] || [ -x /etc/init.d/smartmontools ]; then
    svc_start smartd 2>/dev/null || svc_start smartmontools 2>/dev/null || true
  fi
  if have irqbalance || [ -x /etc/init.d/irqbalance ]; then
    svc_start irqbalance
  fi
  if have haveged || [ -x /etc/init.d/haveged ]; then
    svc_start haveged
  fi
  age_key=$STARDUST/state/secrets/age.key
  if have age-keygen; then
    if [ -f "$age_key" ]; then
      echo "age: $age_key exists (unchanged)"
    elif [ "$DRYRUN" -eq 1 ]; then
      echo "+ age-keygen -o $age_key"
    else
      as_root mkdir -p "$STARDUST/state/secrets"
      as_root age-keygen -o "$age_key" >/dev/null
      as_root chown "$OWNER:stardust" "$age_key"
      as_root chmod 0640 "$age_key"
      echo "age: wrote $age_key"
    fi
  fi
  if have msmtp || have msmtp-mta; then
    if [ -f /etc/msmtprc ]; then
      echo "msmtp: /etc/msmtprc exists (unchanged)"
    else
      printf '%s\n' \
        "# Stardust msmtp — fill host/user/password, then: chmod 0640 /etc/msmtprc" \
        "defaults" "auth           on" "tls            on" "tls_starttls   on" \
        "logfile        /var/log/msmtp.log" "account        default" \
        "host           mail.example" "port           587" \
        "from           stardust@example" "user           stardust@example" \
        "password       CHANGE-ME" | write_if_absent /etc/msmtprc.example
      if [ "$DRYRUN" -eq 0 ] && [ -t 0 ]; then
        nmail=$(install_prompt "NOTIFY email — where backup/fail mail goes (empty skip)" "" "Stardust can mail after backup-all or a failed site-check.\nThis only sets NOTIFY= in /etc/stardust.conf.\nYou still copy /etc/msmtprc.example to /etc/msmtprc and put real SMTP there.")
        if [ -n "$nmail" ] && [ -f /etc/stardust.conf ]; then
          if grep -q '^NOTIFY=' /etc/stardust.conf; then
            as_root sed -i "s|^NOTIFY=.*|NOTIFY=\$nmail|" /etc/stardust.conf
          else
            as_root sh -c "printf 'NOTIFY=%s\n' '\$nmail' >> /etc/stardust.conf"
          fi
          echo "NOTIFY=\$nmail — copy /etc/msmtprc.example to /etc/msmtprc and edit SMTP"
        fi
      else
        echo "msmtp: wrote /etc/msmtprc.example (not live until you copy it)"
      fi
    fi
  fi
  if have git && [ "$DRYRUN" -eq 0 ]; then
    as_root git config --system --get safe.directory "$PLATFORMS" >/dev/null 2>&1 \
      || as_root git config --system --add safe.directory "$PLATFORMS" || true
    as_root -u "$OWNER" git config --global init.defaultBranch devel 2>/dev/null || true
  fi
  if [ "$LOCALHOST" -eq 0 ] && { [ "$ROLE" = "test" ] || [ "$ROLE" = "live" ]; }; then
    if have certbot; then
      echo "certbot: installed — obtain certs after site-add, not during install"
    fi
  fi
}

# Run delivery steps
ship_tools
write_cron
write_state
write_etc_conf
bootstrap_deps
