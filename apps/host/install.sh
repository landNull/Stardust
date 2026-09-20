#!/bin/sh
# modules/10-core-prereqs.sh — packages, identities, sudoers, control-plane dirs
# Sourced by install-stardust.sh. Uses helpers from the orchestrator.

echo "STEP 10: packages, users, groups, sudoers, /srv layout"

# --- packages ----------------------------------------------------------
PKGS=$(pkg_list_for | tr '\n' ' ')
need=""
for p in $PKGS; do
  if [ "$DRYRUN" -eq 1 ]; then
    need="$need $p"
    continue
  fi
  if pkg_ok "$p"; then
    echo "package ok: $p"
  else
    need="$need $p"
  fi
done

if [ -n "$need" ]; then
  echo "packages to consider:$need"
  # shellcheck disable=SC2086
  pkg_install $need || {
    echo "$PROG: some packages are not in this distro; install the rest by hand" >&2
  }
fi

# --- users / groups ----------------------------------------------------
ensure_group "$GROUP"
ensure_group "$OWNER"
ensure_group stardust
ensure_user "$OWNER" "Stardust deploy"
ensure_user "$ADMIN" "Stardust web admin"
if [ -n "$HUMAN" ]; then
  ensure_user "$HUMAN" "Stardust operator"
fi

if [ "$DRYRUN" -eq 1 ]; then
  [ -n "$HUMAN" ] && echo "+ usermod -aG $GROUP,stardust,adm,$OWNER $HUMAN"
  echo "+ usermod -aG $GROUP,stardust $ADMIN"
  echo "+ usermod -aG $GROUP,stardust $OWNER"
else
  if [ -n "$HUMAN" ]; then
    for g in "$GROUP" stardust adm "$OWNER"; do
      getent group "$g" >/dev/null 2>&1 || continue
      run_root usermod -aG "$g" "$HUMAN" 2>/dev/null || true
    done
  fi
  run_root usermod -aG "$GROUP,stardust" "$ADMIN" 2>/dev/null || true
  run_root usermod -aG "$GROUP,stardust" "$OWNER" 2>/dev/null || true
  if id "$DAEMON" >/dev/null 2>&1; then
    run_root usermod -aG "$GROUP" "$DAEMON" 2>/dev/null || true
  fi
fi

# --- sudoers (limited; same on every host) -------------------------
# User binaries refuse sudo. Only stardust-priv is the root helper.
SUDO_PRIV="# Stardust — priv helper on $HOSTN
Defaults:$OWNER !requiretty
Defaults:$ADMIN !requiretty
$OWNER ALL=(root) NOPASSWD: /usr/local/sbin/stardust-priv
$ADMIN ALL=(root) NOPASSWD: /usr/local/sbin/stardust-priv
$OWNER ALL=(root) NOPASSWD: /usr/sbin/a2ensite, /usr/sbin/a2dissite, /usr/sbin/a2enmod
$ADMIN ALL=($OWNER) NOPASSWD: /usr/local/bin/bee, /usr/bin/git, /usr/local/bin/crdir
"
if [ -n "$HUMAN" ]; then
  SUDO_PRIV="${SUDO_PRIV}Defaults:$HUMAN !requiretty
$HUMAN ALL=(root) NOPASSWD: /usr/local/sbin/stardust-priv
$HUMAN ALL=($OWNER) NOPASSWD: /usr/local/bin/bee, /usr/bin/git, /usr/local/bin/crdir
"
fi

SUDO_DEPLOY="$SUDO_PRIV"
SUDO_ADMIN="# Stardust — $ADMIN extra (see stardust-priv)
"
SUDO_HUMAN="# Stardust — $HUMAN extra (see stardust-priv)
"

if [ -d /etc/sudoers.d ]; then
  write_sudoers /etc/sudoers.d/stardust-deploy "$SUDO_DEPLOY"
  write_sudoers /etc/sudoers.d/stardust-www-admin "$SUDO_ADMIN"
  if [ -n "$HUMAN" ]; then
    write_sudoers /etc/sudoers.d/stardust-human "$SUDO_HUMAN"
  fi
else
  echo "note: /etc/sudoers.d missing; add the limited sudo rules by hand"
fi

PROFILE=/etc/profile.d/stardust.sh
PROFILE_BODY="# Stardust: PATH + group-writable files for $OWNER, $ADMIN, $HUMAN
export PATH=\"/usr/local/bin:/srv/stardust/bin:\$PATH\"
case \$(id -un) in
  $OWNER|$ADMIN|$HUMAN)
    umask 002
    ;;
esac
"
if [ "$DRYRUN" -eq 1 ]; then
  echo "+ write $PROFILE"
else
  tmp=$(mktemp)
  printf '%s\n' "$PROFILE_BODY" > "$tmp"
  as_root install -m 0644 "$tmp" "$PROFILE"
  rm -f "$tmp"
  echo "profile: $PROFILE"
fi

# --- dirs --------------------------------------------------------------
run_root mkdir -p \
  "$STARDUST/backups" \
  "$STARDUST/bin" \
  "$STARDUST/state" \
  "$STARDUST/state/locks" \
  "$STARDUST/state/secrets" \
  "$STARDUST/hooks" \
  "$STARDUST/hooks/pre-upgrade.d" \
  "$STARDUST/hooks/post-check.d" \
  "$PLATFORMS"

run_root chown "$OWNER:$GROUP" "$STARDUST" "$STARDUST/backups" "$STARDUST/bin" "$STARDUST/state"
run_root chmod 2770 "$STARDUST" "$STARDUST/backups" "$STARDUST/bin" "$STARDUST/state"
run_root chown "$OWNER:stardust" "$STARDUST/state/secrets"
run_root chmod 0750 "$STARDUST/state/secrets"
if have setfacl; then
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ setfacl default u:$OWNER g:$GROUP u:$DAEMON on $PLATFORMS $STARDUST"
  else
    as_root setfacl -m "u:${OWNER}:rwx,g:${GROUP}:rwx,u:${DAEMON}:rwx,o::---" \
      "$PLATFORMS" "$STARDUST" "$STARDUST/backups" 2>/dev/null || true
    as_root setfacl -d -m "u:${OWNER}:rwx,g:${GROUP}:rwx,u:${DAEMON}:rwx,o::---" \
      "$PLATFORMS" "$STARDUST" "$STARDUST/backups" 2>/dev/null || true
    as_root setfacl -b "$STARDUST/state/secrets" 2>/dev/null || true
    as_root setfacl -m "u:${OWNER}:rwx,g:stardust:r-x,o::---" "$STARDUST/state/secrets" 2>/dev/null || true
    as_root setfacl -d -m "u:${OWNER}:rw,g:stardust:r,o::---" "$STARDUST/state/secrets" 2>/dev/null || true
    echo "ACL default on $PLATFORMS and $STARDUST (secrets: deploy:stardust only)"
  fi
else
  echo "note: setfacl missing — install the acl package"
fi

if [ "$DRYRUN" -eq 1 ]; then
  echo "+ # leave $PLATFORMS contents untouched"
elif [ -d "$PLATFORMS" ]; then
  echo "platforms root exists: $PLATFORMS (contents not changed)"
fi
