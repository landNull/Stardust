# cleanup-modules/40-purge-deployment.sh
# Control-plane trees, shipped CLIs, man pages, host conf.

echo "STEP 40: control plane and shipped tools"
echo "---------------------------------------"

do_rm /etc/cron.d/stardust
do_rm /etc/stardust.conf

echo "  shipped CLIs..."
do_rm /usr/local/bin/crdir
do_rm /usr/local/bin/newfeature
do_rm /usr/local/bin/d7-migrate
do_rm /usr/local/bin/stardust
do_rm /usr/local/bin/stardust-menu
do_rm /usr/local/bin/stardust-tui
do_rm /usr/local/sbin/stardust-priv
do_rm /usr/local/sbin/install-stardust.sh
do_rm /usr/local/sbin/stardust-install.sh
do_rm /usr/local/lib/stardust
do_rm /usr/local/share/stardust
do_rm /usr/local/share/man/man1/crdir.1
do_rm /usr/local/share/man/man1/stardust.1
do_rm /usr/local/share/man/man1/d7-migrate.1

echo "  /srv trees..."
do_rm "$STARDUST"
do_rm "$PLATFORMS"

echo "  control plane removed"
