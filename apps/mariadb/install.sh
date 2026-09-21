#!/bin/sh
# modules/40-mariadb.sh — bind 127.0.0.1, utf8mb4, modest InnoDB
# Root stays unix_socket. Site DBs are bd_* created later by stardust-priv.
# Secure step = Debian mariadb-secure-installation minus SET PASSWORD.

echo "STEP 40: MariaDB drop-in + Debian-secure (no root password)"

tune_mysql
secure_mysql
