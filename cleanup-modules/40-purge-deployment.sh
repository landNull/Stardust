# cleanup-modules/40-purge-deployment.sh
# Worker Module: Destroys cron jobs, configuration overrides, and linked binaries

echo "  Stopping core service engines..."
if [ "$DRYRUN" -eq 1 ]; then
  echo "+ rm -f /etc/cron.d/stardust"
  echo "+ rm -rf $STARDUST"
else
  [ -f /etc/cron.d/stardust ] && as_root rm -f /etc/cron.d/stardust
  [ -d "$STARDUST" ] && as_root rm -rf "$STARDUST"
  echo "  ✓ Core distribution binaries removed safely."
fi
