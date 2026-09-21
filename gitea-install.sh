#!/bin/bash
# Standalone leftover. Source of truth is apps/gitea/install.sh
# (install-stardust.sh STEP 60). Prefer that: prompts, sha256,
# sysvinit/systemd/openrc, never rewrites app.ini, never fetches
# the Gitea homepage.
#
# Automated Gitea installation script for Linux (SysVinit or systemd)

set -e

# --- CONFIGURE VERSION ---
GITEA_VERSION="1.27.3"
ARCH="amd64" # Options: amd64, arm64, 386, arm-5, etc.

echo "============================================="
echo " Starting Gitea v${GITEA_VERSION} Installation"
echo "============================================="

# --- DETECT INIT SYSTEM ---
INIT_SYSTEM=""
if [ -d /run/systemd/system ]; then
    INIT_SYSTEM="systemd"
elif [ -f /etc/init.d/cron ] && [ ! -d /run/systemd/system ]; then
    INIT_SYSTEM="sysvinit"
else
    echo "Unsupported init system. Exiting."
    exit 1
fi
echo "--> Detected init system: ${INIT_SYSTEM}"

# --- INSTALL PREREQUISITES ---
echo "--> Installing System Prerequisites (git, sqlite)..."
if [ -x "$(command -v apt-get)" ]; then
    sudo apt-get update && sudo apt-get install -y git sqlite3 wget
elif [ -x "$(command -v dnf)" ]; then
    sudo dnf install -y git sqlite wget
else
    echo "Package manager not recognized. Please ensure 'git' and 'wget' are installed manually."
    exit 1
fi

# --- CREATE GITEA USER ---
echo "--> Creating dedicated system user 'git'..."
if ! id "git" &>/dev/null; then
    sudo useradd --system --shell /bin/bash --comment "Git Version Control" --create-home git
else
    echo "User 'git' already exists, skipping creation."
fi

# --- CREATE DIRECTORIES ---
echo "--> Building Gitea directory structure..."
sudo mkdir -p /var/lib/gitea/{custom,data,log}
sudo chown -R git:git /var/lib/gitea/
sudo chmod -R 750 /var/lib/gitea/

sudo mkdir -p /etc/gitea
sudo chown root:git /etc/gitea
sudo chmod 770 /etc/gitea

# --- DOWNLOAD GITEA BINARY ---
echo "--> Downloading Gitea binary..."
wget -O /tmp/gitea "https://dl.gitea.io/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-${ARCH}"
sudo mv /tmp/gitea /usr/local/bin/gitea
sudo chmod +x /usr/local/bin/gitea

# --- INSTALL INIT SCRIPT BASED ON DETECTED SYSTEM ---
if [ "$INIT_SYSTEM" = "systemd" ]; then
    echo "--> Configuring systemd service..."
    sudo tee /etc/systemd/system/gitea.service > /dev/null <<EOF
[Unit]
Description=Gitea (Self-Hosted Git Service)
After=network.target

[Service]
RestartSec=2s
Type=simple
User=git
Group=git
WorkingDirectory=/var/lib/gitea
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=always
Environment=USER=git HOME=/var/lib/gitea GITEA_WORK_DIR=/var/lib/gitea

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable gitea --now
elif [ "$INIT_SYSTEM" = "sysvinit" ]; then
    echo "--> Configuring SysVinit service..."
    sudo tee /etc/init.d/gitea > /dev/null <<'EOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          gitea
# Required-Start:    $network $remote_fs $syslog
# Required-Stop:     $network $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Gitea (Git with a cup of tea)
# Description:       Self-hosted Git service
### END INIT INFO

GITEA_USER="git"
GITEA_BIN="/usr/local/bin/gitea"
GITEA_WORK_DIR="/var/lib/gitea"
GITEA_CONFIG="/etc/gitea/app.ini"
PIDFILE="/var/run/gitea.pid"

. /lib/init/vars.sh
. /lib/lsb/init-functions

do_start() {
    start-stop-daemon --start --quiet --pidfile "$PIDFILE" \
        --chuid "$GITEA_USER" --chdir "$GITEA_WORK_DIR" \
        --exec "$GITEA_BIN" -- web --config "$GITEA_CONFIG" \
        --background --make-pidfile --pidfile "$PIDFILE"
    return $?
}

do_stop() {
    start-stop-daemon --stop --quiet --pidfile "$PIDFILE" \
        --exec "$GITEA_BIN"
    rm -f "$PIDFILE"
    return $?
}

case "$1" in
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    restart)
        do_stop
        sleep 1
        do_start
        ;;
    status)
        start-stop-daemon --status --pidfile "$PIDFILE" --exec "$GITEA_BIN"
        ;;
    *)
        echo "Usage: /etc/init.d/gitea {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
EOF

    sudo chmod +x /etc/init.d/gitea
    sudo update-rc.d gitea defaults
    sudo service gitea start
fi

# --- FINAL STATUS CHECK ---
echo "============================================="
echo " Gitea installation sequence complete!"
echo "============================================="

if [ "$INIT_SYSTEM" = "systemd" ]; then
    sudo systemctl status gitea --no-pager
else
    sudo service gitea status
fi

echo ""
echo "👉 Next step: Open your browser and navigate to http://YOUR_SERVER_IP:3000 to finish setup."
