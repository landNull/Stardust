#!/bin/sh
# modules/50-bee.sh — Bee from backdrop-contrib git, not Composer
# Contract: /usr/local/bin/bee -> /usr/local/src/bee/bee

echo "STEP 50: Bee CLI"

if [ "$DRYRUN" -eq 1 ]; then
  echo "+ # install Bee to $BEE_BIN if missing"
elif have bee; then
  echo "bee ok: $(command -v bee)"
else
  run_root mkdir -p /usr/local/src
  if [ ! -d "$BEE_DST/.git" ]; then
    run_root git clone --depth 1 "$BEE_SRC" "$BEE_DST"
  fi
  if [ -f "$BEE_DST/bee" ]; then
    run_root ln -sfn "$BEE_DST/bee" "$BEE_BIN"
    run_root chmod 0755 "$BEE_DST/bee"
    echo "bee installed: $BEE_BIN"
  else
    echo "$PROG: cloned Bee but $BEE_DST/bee not found; check upstream layout" >&2
  fi
fi
