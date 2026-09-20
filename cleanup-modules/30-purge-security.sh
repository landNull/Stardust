# cleanup-modules/30-purge-security.sh
# Worker Module: Drops custom sudoers privileges and manages Stardust system users

echo "👥 STEP 30: Purging System Users & Security Policies"
echo "----------------------------------------------------"

purge_sudoers() {
  for slice in stardust-deploy stardust-admin; do
    local target="/etc/sudoers.d/$slice"
    if [ -f "$target" ]; then
      if [ "$DRYRUN" -eq 1 ]; then
        echo "+ rm -f $target"
      else
        as_root rm -f "$target"
        echo "  ✓ Removed sudoers drop-in: $target"
      fi
    fi
  done
}

purge_user() {
  local username="$1"
  if id "$username" >/dev/null 2>&1; then
    # We do NOT run a destructive 'userdel -r' automatically because the user 
    # might own active files or assets outside of the /srv/stardust root.
    if [ "$DRYRUN" -eq 1 ]; then
      echo "+ userdel $username (Keeps home directory safe)"
    else
      as_root userdel "$username" 2>/dev/null || true
      echo "  ✓ Offboarded user system login access: $username"
    fi
  fi
}

purge_group() {
  local groupname="$1"
  if getent group "$groupname" >/dev/null 2>&1; then
    if [ "$DRYRUN" -eq 1 ]; then
      echo "+ groupdel $groupname"
    else
      as_root groupdel "$groupname" 2>/dev/null || true
      echo "  ✓ Removed platform tracking group: $groupname"
    fi
  fi
}

# Fire execution stack in reverse order of creation
purge_sudoers
purge_user "$ADMIN"
purge_user "$OWNER"
purge_group "stardust"
