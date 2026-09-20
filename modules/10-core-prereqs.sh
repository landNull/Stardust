#!/bin/sh
# ==============================================================================
# modules/10-core-prereqs.sh — Shared Prerequisites, Groups, Accounts, and Users
# ==============================================================================
# Engineered for strict POSIX compliance.
# Fixes short-circuit syntax drops and builds out missing user configuration maps.
# ==============================================================================

echo "👥 STEP 10: Provisioning Platform Prerequisites and Core Accounts"
echo "------------------------------------------------------------------"

prereqs_install_packages() {
  echo "  ⚙️ Syncing system toolsets..."
  case $PKG in
    apt)
      # Deploys standard terminal processing modules natively
      pkg_install git curl unzip rsync acl msmtp-mta unattended-upgrades needrestart logwatch goaccess etckeeper smartmontools irqbalance haveged moreutils jq pv age
      
      # --- FIX: Standardized explicit structured block syntax prevents short-circuit drops ---
      if [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = "devel" ]; then
        pkg_install dnsmasq
      fi
      if [ "$LOCALHOST" -eq 0 ]; then
        if [ "$ROLE" = "test" ] || [ "$ROLE" = "live" ]; then
          pkg_install certbot python3-certbot-apache
        fi
      fi
      if [ "$LOCALHOST" -eq 0 ] && [ "$DO_CSF" -eq 1 ]; then
        pkg_install iptables perl libwww-perl liblwp-protocol-https-perl libgd-perl
      fi
      ;;
      
    apk)
      pkg_install git curl unzip rsync acl jq smartmontools haveged
      if [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = "devel" ]; then
        pkg_install dnsmasq
      fi
      ;;
      
    dnf|yum)
      pkg_install git jq pv smartmontools irqbalance
      if [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = "devel" ]; then
        pkg_install dnsmasq
      fi
      if [ "$LOCALHOST" -eq 0 ]; then
        if [ "$ROLE" = "test" ] || [ "$ROLE" = "live" ]; then
          pkg_install certbot python3-certbot-apache
        fi
      fi
      ;;
  esac
}

# --- FIX: Re-integrated the missing user_conf utility into the prerequisite space ---
user_conf() {
  target_user=$1
  
  # POSIX cut filter maps the 6th configuration column to read the home folder pathway
  user_home=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)
  [ -z "$user_home" ] && user_home="/home/$target_user"
  
  user_dest="$user_home/.stardust.conf"
  [ -f "$user_dest" ] && echo "  user configuration layout active: $user_dest" && return 0
  [ "$DRYRUN" -eq 1 ] && echo "+ write configuration metadata node to $user_dest" && return 0
  
  # Build out matching environmental configuration metrics for user profiles natively
  as_root mkdir -p "$(dirname "$user_dest")"
  as_root sh -c "cat > '$user_dest'" <<EOF
# Stardust Workspace Parameters
STARDUST_ROLE=$ROLE
STARDUST_ROOT=$STARDUST
PLATFORMS=$PLATFORMS
OWNER=$OWNER
ADMIN=$ADMIN
GROUP=$GROUP
BEE=\$(command -v bee 2>/dev/null || echo $BEE_BIN)
EOF
  as_root chown "$target_user:$target_user" "$user_dest"
  as_root chmod 0600 "$user_dest"
}

prereqs_enforce_security() {
  echo "  ⚙️ Constructing security user profiles and account partitions..."
  
  # Ensure target groups are mapped into the active OS database safely
  for g in "$GROUP" stardust adm; do
    if ! getent group "$g" >/dev/null 2>&1; then
      if [ "$DRYRUN" -eq 1 ]; then 
        echo "+ groupadd $g"
      else 
        have groupadd && run_root groupadd "$g" || run_root addgroup "$g"
      fi
    fi
  done

  # Process the master deployment account identities sequentially
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
    
    # Append group memberships securely across distributions
    if [ "$DRYRUN" -eq 1 ]; then 
      echo "+ usermod -aG $GROUP $uname"
    else 
      have usermod && run_root usermod -aG "$GROUP" "$uname" 2>/dev/null || run_root adduser "$uname" "$GROUP" 2>/dev/null || true
    fi
    
    uhome=$(getent passwd "$uname" 2>/dev/null | cut -d: -f6)
    [ -z "$uhome" ] && uhome="/home/$uname"
    
    run_root mkdir -p "$uhome/.ssh" 
    run_root chmod 0700 "$uhome/.ssh" 
    run_root chown -R "$uname:$GROUP" "$uhome/.ssh"
    
    if [ ! -f "$uhome/.ssh/authorized_keys" ] && [ "$DRYRUN" -eq 0 ]; then
      as_root touch "$uhome/.ssh/authorized_keys" 
      as_root chmod 0600 "$uhome/.ssh/authorized_keys" 
      as_root chown "$uname:$GROUP" "$uhome/.ssh/authorized_keys"
    fi
  done

  # Deploy passwordless root execution sudo configurations safely
  if [ -d /etc/sudoers.d ]; then
    write_sudoers /etc/sudoers.d/stardust-deploy <<EOF
$OWNER ALL=(ALL) NOPASSWD: /usr/local/bin/stardust, /usr/local/bin/crdir, /usr/local/bin/newfeature, /usr/local/sbin/stardust-priv
EOF
    write_sudoers /etc/sudoers.d/stardust-admin <<EOF
$ADMIN ALL=(ALL) NOPASSWD: /usr/local/bin/stardust, /usr/local/bin/crdir, /usr/local/bin/newfeature, /usr/local/sbin/stardust-priv
EOF
  fi

  # Call our newly added user configuration engine mapping parameters to the accounts
  for user_profile in "$OWNER" "$ADMIN" "$HUMAN"; do
    if [ -n "$user_profile" ]; then
      user_conf "$user_profile"
    fi
  done
}

# Execute internal orchestration targets
prereqs_install_packages
prereqs_enforce_security

# --- THE POSIX ANCHOR ---
# Force the completed module to return a clean '0' success code back up to the loop
return 0
