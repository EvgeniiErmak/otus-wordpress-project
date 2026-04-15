#!/bin/bash
# recovery-slave.sh — Восстановление slave-сервера (192.168.88.167)

set -euo pipefail

echo "=== ПОЛНОЕ ВОССТАНОВЛЕНИЕ SLAVE (192.168.88.167) ==="

# Базовые пакеты
apt-get update
apt-get install -y curl wget git mysql-server

# Настройка MySQL Slave
cat > /etc/mysql/mysql.conf.d/slave.cnf << 'EOF'
[mysqld]
server-id = 2
read_only = ON
relay-log = /var/log/mysql/relay-bin.log
log-bin = /var/log/mysql/mysql-bin.log
gtid_mode = ON
enforce_gtid_consistency = ON
EOF

systemctl restart mysql

# Создание пользователя для репликации (выполняется на master, но здесь для удобства)
echo "На slave выполните после настройки master:"
echo "CHANGE MASTER TO MASTER_HOST='192.168.88.168', MASTER_USER='repl', MASTER_PASSWORD='ReplPassword2026Strong!', MASTER_AUTO_POSITION=1;"
echo "START SLAVE;"

echo ""
echo "Slave сервер восстановлен."
echo "Теперь настройте репликацию с master."
