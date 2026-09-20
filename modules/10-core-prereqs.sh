# modules/10-core-prereqs.sh
# App-Centric Worker: Shared Prerequisites, Groups, Accounts, and System Users

echo "👥 STEP 10: Provisioning Platform Prerequisites and Core Accounts"
echo "------------------------------------------------------------------"

prereqs_install_packages() {
  echo "  ⚙️ Syncing system toolsets..."
  case $PKG in
    apt)
      pkg_install git curl unzip rsync acl msmtp-mta unattended-upgrades needrestart logwatch goaccess etckeeper smartmontools irqbalance haveged moreutils jq pv age
      [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = "devel" ] && pkg_install dnsmasq
      [ "$LOCALHOST" -eq 0 ] && { [ "$ROLE" = "test" ] || [ "$ROLE" = "live" ]; } && pkg_install certbot python3-certbot-apache
      [ "$LOCALHOST" -eq 0 ] && [ "$DO_CSF" -eq 1 ] && pkg_install iptables perl libwww-perl liblwp-protocol-https-perl libgd-perl
      ;;
    apk)
      pkg_install git curl unzip rsync acl jq smartmontools haveged
      [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = "devel" ] && pkg_install dnsmasq
      ;;
    dnf|yum)
      pkg_install git jq pv smartmontools irqbalance
      [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = "devel" ] && pkg_install dnsmasq
      [ "$LOCALHOST" -eq 0 ] && { [ "$ROLE" = "test" ] || [ "$ROLE" = "live" ]; } && pkg_install certbot python3-certbot-apache
      ;;
  esac
}

prereqs_enforce_security() {
  echo "  ⚙️ Constructing security user profiles..."
  for g in "$GROUP" stardust adm; do
    if ! getent group "$g" >/dev/null 2>&1; then
      if [ "$DRYRUN" -eq 1 ]; then echo "+ groupadd $g"; else have groupadd && run_root groupadd "$g" || run_root addgroup "$g"; fi
    fi
  done

  for u in "$OWNER:Stardust code owner" "$ADMIN:Stardust file admin"; do
    uname="${u%%:*}"
    ucomment="${u##*:}"
    if ! id "$uname" >/dev/null 2>&1; then
      if [ "$DRYRUN" -eq 1 ]; then
        echo "+ useradd -m -G $GROUP $uname"
      else
        if [ "$PKG" = "apt" ] && have adduser; then
          run_root adduser --disabled-password --gecos "$ucomment" --ingroup "$GROUP" "$uname"
        elif have useradd; then
          run_root useradd -m -s /bin/bash -c "$ucomment" -G "$GROUP" "$uname"
        else
          run_root adduser -D -s /bin/ash -G "$GROUP" "$uname"
        fi
      fi
    fi
    [ "$DRYRUN" -eq 1 ] && echo "+ usermod -aG $GROUP $uname" || { have usermod && run_root usermod -aG "$GROUP" "$uname" 2>/dev/null || run_root adduser "$uname" "$GROUP" 2>/dev/null || true; }
    
    uhome=$(getent passwd "$uname" 2>/dev/null | cut -d: -f6 || echo "/home/$uname")
    run_root mkdir -p "$uhome/.ssh" && run_root chmod 0700 "$uhome/.ssh" && run_root chown -R "$uname:$GROUP" "$uhome/.ssh"
    if [ ! -f "$uhome/.ssh/authorized_keys" ] && [ "$DRYRUN" -eq 0 ]; then
      as_root touch "$uhome/.ssh/authorized_keys" && as_root chmod 0600 "$uhome/.ssh/authorized_keys" && as_root chown "$uname:$GROUP" "$uhome/.ssh/authorized_keys"
    fi
  done

  write_sudoers /etc/sudoers.d/stardust-deploy <<EOF
$OWNER ALL=(ALL) NOPASSWD: /usr/local/bin/stardust, /usr/local/bin/crdir, /usr/local/bin/newfeature, /usr/local/sbin/stardust-priv
EOF
  write_sudoers /etc/sudoers.d/stardust-admin <<EOF
$ADMIN ALL=(ALL) NOPASSWD: /usr/local/bin/stardust, /usr/local/bin/crdir, /usr/local/bin/newfeature, /usr/local/sbin/stardust-priv
EOF

  for user_profile in "$OWNER" "$ADMIN" "$HUMAN"; do
    [ -n "$user_profile" ] && user_conf "$user_profile"
  done
}

prereqs_install_packages
prereqs_enforce_security
