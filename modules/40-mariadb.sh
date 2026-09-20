# modules/40-mariadb.sh
# App-Centric Worker: MariaDB Relational Database Setup & Cluster Core

echo "🐬 STEP 40: Provisioning Database Layer (MariaDB)"
echo "------------------------------------------------"

mysql_install() {
  if ! pkg_ok mariadb-server && ! pkg_ok mysql-server; then
    install_prompt "Install MariaDB (Database Server)? [Y/n]" "Y" "MariaDB server engine provides SQL persistence nodes."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      case $PKG in apt) pkg_install mariadb-server ;; apk) pkg_install mariadb ;; dnf|yum) pkg_install mariadb-server ;; esac
    fi
  else
    echo "  MariaDB infrastructure packages already registered."
  fi
}

mysql_tune_storage() {
  echo "  ⚙️ Customizing transactional buffer sizes and InnoDB limits..."
  body="; Stardust SQL Parameter Overrides
[mysqld]
bind-address = 127.0.0.1
skip-networking = 0
innodb_buffer_pool_size = 2G
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 2
max_connections = 80
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci"

  if [ -d /etc/mysql/mariadb.conf.d ]; then
    printf '%s\n' "$body" | write_dropin /etc/mysql/mariadb.conf.d/90-stardust.cnf
  elif [ -d /etc/mysql/conf.d ]; then
    printf '%s\n' "$body" | write_dropin /etc/mysql/conf.d/90-stardust.cnf
  elif [ -d /etc/my.cnf.d ]; then
    printf '%s\n' "$body" | write_dropin /etc/my.cnf.d/90-stardust.cnf
  fi
}

mysql_install
mysql_tune_storage
