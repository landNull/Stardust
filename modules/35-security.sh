#!/bin/sh
# ==============================================================================
# modules/35-security.sh — System Access, Group Allocations & Security Sudo Rules
# ==============================================================================
# Deploys security boundaries safely across variable permission layers.
# ==============================================================================

echo "👥 STEP 35: Provisioning System User Groups and Access Constraints"
echo "--------------------------------------------------------"

ensure_group() {
  g=$1
  # 'getent' query monitors system files to inspect if the group already exists
  if getent group "$g" >/dev/null 2>&1; then
    echo "  group ok: $g"
    return 0
  fi
  
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ groupadd $g"
    return 0
  fi
  
  # Cross-platform compatibility checks selecting available group creation binaries
  if have groupadd; then     run_root groupadd "$g"
  elif have addgroup; then   run_root addgroup "$g"
  else
    echo "$PROG: unable to finalize group allocations for $g" >&2
    return 1
  fi
}

ensure_user() {
  name=$1
  comment=${2:-"Stardust Operator Track"}
  
  if id "$name" >/dev/null 2>&1; then
    echo "  user verification verified: $name"
  else
    if [ "$DRYRUN" -eq 1 ]; then
      echo "+ useradd -m -s /bin/bash -c '$comment' -G $GROUP $name"
    elif have adduser && [ "$PKG" = "apt" ]; then
      run_root adduser --disabled-password --gecos "$comment" --ingroup "$GROUP" "$name"
    elif have useradd; then
      run_root useradd -m -s /bin/bash -c "$comment" -G "$GROUP" "$name"
    elif have adduser; then
      run_root useradd -m -s /bin/bash -G "$GROUP" "$name"
    fi
  fi

  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ usermod -aG $GROUP $name"
    return 0
  fi

  # Safe append: Inject the user into secondary system group pools securely
  if have usermod; then     run_root usermod -aG "$GROUP" "$name" 2>/dev/null || true
  elif have adduser; then   run_root adduser "$name" "$GROUP" 2>/dev/null || true
  fi

  # --- Home Directory Slicing Parameter ---
  # Extract the sixth column from passwd parameters to find the true home path safely
  home=$(getent passwd "$name" 2>/dev/null | cut -d: -f6)
  [ -z "$home" ] && home="/home/$name"

  # Provision safe SSH access boundaries natively
  run_root mkdir -p "$home/.ssh"
  run_root chmod 0700 "$home/.ssh"
  run_root chown -R "$name:$name" "$home/.ssh"
  
  if [ ! -f "$home/.ssh/authorized_keys" ]; then
    if [ "$DRYRUN" -eq 0 ]; then
      as_root touch "$home/.ssh/authorized_keys"
      as_root chmod 0600 "$home/.ssh/authorized_keys"
      as_root chown "$name:$name" "$home/.ssh/authorized_keys"
    else
      echo "+ touch $home/.ssh/authorized_keys"
    fi
  fi
}

user_conf() {
  name=$1
  home=$(getent passwd "$name" 2>/dev/null | cut -d: -f6)
  [ -z "$home" ] && home="/home/$name"
  
  dest="$home/.stardust.conf"
  [ -f "$dest" ] && echo "  user config partition active: $dest (skipping override)" && return 0
  [ "$DRYRUN" -eq 1 ] && echo "+ write $dest" && return 0
  
  # Inject an environment configuration file for the user profile tracking state
  as_root sh -c "cat > '$dest'" <<EOF
# Stardust User Level Blueprint
STARDUST_ROLE=$ROLE
STARDUST_ROOT=$STARDUST
PLATFORMS=$PLATFORMS
OWNER=$OWNER
ADMIN=$ADMIN
GROUP=$GROUP
BEE=\$(command -v bee 2>/dev/null || echo $BEE_BIN)
EOF
  as_root chown "$name:$name" "$dest"
  as_root chmod 0600 "$dest"
}

# Execute profile security constraints
ensure_group "$GROUP"
ensure_group stardust
ensure_group adm
ensure_user "$OWNER" "Stardust code asset controller"
ensure_user "$ADMIN" "Stardust systems runtime admin"

# Deploys isolated passwordless execution maps directly into the safe sudoers partition tree
write_sudoers /etc/sudoers.d/stardust-deploy <<EOF
$OWNER ALL=(ALL) NOPASSWD: /usr/local/bin/stardust, /usr/local/bin/crdir, /usr/local/bin/newfeature, /usr/local/sbin/stardust-priv
EOF

write_sudoers /etc/sudoers.d/stardust-admin <<EOF
$ADMIN ALL=(ALL) NOPASSWD: /usr/local/bin/stardust, /usr/local/bin/crdir, /usr/local/bin/newfeature, /usr/local/sbin/stardust-priv
EOF

user_conf "$OWNER"
[ "$OWNER" != "$ADMIN" ] && user_conf "$ADMIN"
