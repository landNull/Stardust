#!/bin/sh
# purge-gitea.sh - Completely purge Gitea from Stardust / starhq.knarr
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (or via sudo)." >&2
        exit 1
        fi

        echo "==> [1/7] Terminating Gitea processes and services..."
        # Stop SysVinit service if active
        if [ -x /etc/init.d/gitea ]; then
            /etc/init.d/gitea stop 2>/dev/null || true
                if command -v update-rc.d >/dev/null 2>&1; then
                        update-rc.d -f gitea remove 2>/dev/null || true
                            fi
                            fi

                            # Kill any remaining processes under the git user or gitea binary
                            pkill -u git 2>/dev/null || true
                            pkill -f "^/usr/local/bin/gitea" 2>/dev/null || true
                            pkill -f "^gitea web" 2>/dev/null || true

                            echo "==> [2/7] Removing service files, binaries, and CLI tools..."
                            rm -f /etc/init.d/gitea
                            rm -f /run/gitea.pid /var/run/gitea.pid
                            rm -f /usr/local/bin/gitea /usr/local/bin/gitea.bak /usr/bin/gitea
                            rm -f /usr/local/bin/tea /tmp/tea /tmp/gitea

                            echo "==> [3/7] Cleaning Gitea application, configuration, and repository paths..."
                            rm -rf /etc/gitea
                            rm -rf /var/lib/gitea /var/lib/git /srv/gitea
                            rm -rf /var/log/gitea
                            rm -f /srv/stardust/state/secrets/gitea*
                            rm -f /etc/ssh/ssh_config.d/50-stardust-gitea.conf

                            echo "==> [4/7] Removing Apache reverse proxy configurations..."
                            if [ -f /etc/apache2/sites-available/stardust-gitea.conf ]; then
                                if command -v a2dissite >/dev/null 2>&1; then
                                        a2dissite stardust-gitea.conf 2>/dev/null || true
                                            fi
                                                rm -f /etc/apache2/sites-available/stardust-gitea.conf
                                                    rm -f /etc/apache2/sites-enabled/stardust-gitea.conf
                                                        if [ -x /etc/init.d/apache2 ]; then
                                                                /etc/init.d/apache2 reload 2>/dev/null || true
                                                                    fi
                                                                    fi

                                                                    echo "==> [5/7] Dropping Gitea database and MariaDB credentials..."
                                                                    if command -v mariadb >/dev/null 2>&1; then
                                                                        mariadb -e "DROP DATABASE IF EXISTS gitea;" 2>/dev/null || true
                                                                            mariadb -e "DROP USER IF EXISTS 'gitea'@'localhost';" 2>/dev/null || true
                                                                                mariadb -e "DROP USER IF EXISTS 'gitea'@'127.0.0.1';" 2>/dev/null || true
                                                                                    mariadb -e "FLUSH PRIVILEGES;" 2>/dev/null || true
                                                                                    fi

                                                                                    echo "==> [6/7] Removing system user 'git' and mail spools..."
                                                                                    # Remove git user and dedicated git group
                                                                                    deluser --remove-home git 2>/dev/null || userdel -r -f git 2>/dev/null || true
                                                                                    delgroup git 2>/dev/null || groupdel git 2>/dev/null || true
                                                                                    rm -rf /home/git
                                                                                    rm -f /var/mail/git /var/spool/mail/git

                                                                                    echo "==> [7/7] Cleaning Stardust Git template settings..."
                                                                                    if [ -f /etc/stardust.conf ]; then
                                                                                        sed -i '/STARDUST_GIT_TEMPLATE/d' /etc/stardust.conf
                                                                                        fi
                                                                                        for user_conf in /home/*/.stardust.conf /root/.stardust.conf /srv/stardust/home/.stardust.conf; do
                                                                                            if [ -f "$user_conf" ]; then
                                                                                                    sed -i '/STARDUST_GIT_TEMPLATE/d' "$user_conf"
                                                                                                        fi
                                                                                                        done

                                                                                                        echo "=========================================================="
                                                                                                        echo " Gitea has been completely purged from this system."
                                                                                                        echo " Verifying clean slate:"
                                                                                                        echo "   getent passwd git: $(getent passwd git || echo 'clean (none)')"
                                                                                                        echo "   getent group git:  $(getent group git || echo 'clean (none)')"
                                                                                                        echo "   which gitea:       $(command -v gitea || echo 'clean (none)')"
                                                                                                        echo "=========================================================="
                                                                                                        
