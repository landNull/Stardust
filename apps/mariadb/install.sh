#!/bin/sh
# modules/40-mariadb.sh — bind 127.0.0.1, utf8mb4, modest InnoDB
# Root stays unix_socket. Site DBs are bd_* created later by stardust-priv.

echo "STEP 40: MariaDB drop-in"

tune_mysql
