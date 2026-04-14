#!/bin/bash
# backup/backup-db.sh — Бэкап БД со slave (потаблично + позиция бинлога)
# Рекомендуется запускать по cron: 0 3 * * * /usr/local/bin/backup-db.sh
# Логи и данные мониторинга НЕ бэкапятся (по ТЗ)

set -euo pipefail

BACKUP_DIR="/var/backups/wordpress-db"
DATE=$(date +%Y%m%d_%H%M)
LOG_FILE="/var/log/wordpress-backup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

mkdir -p "$BACKUP_DIR"

log "=== Начало бэкапа БД со SLAVE ==="

# Потабличный дамп (более надёжный для больших БД)
mysqldump -h 127.0.0.1 -u root -p'RootPassword2026Strong!' \
    --single-transaction --quick --lock-tables=false \
    --databases wordpress > "$BACKUP_DIR/wordpress_full_$DATE.sql" || {
    log "Ошибка полного дампа"
    exit 1
}

# Получаем позицию бинлога со slave (для восстановления)
mysql -h 127.0.0.1 -u root -p'RootPassword2026Strong!' -e "SHOW SLAVE STATUS\G" > "$BACKUP_DIR/slave_status_$DATE.txt"

log "Бэкап завершён: $BACKUP_DIR/wordpress_full_$DATE.sql"
log "Позиция бинлога сохранена."
