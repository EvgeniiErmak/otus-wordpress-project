#!/bin/bash
# backup/backup-db.sh — Бэкап БД со slave (потаблично + позиция бинлога)

BACKUP_DIR="/var/backups/wordpress-db"
DATE=$(date +%Y%m%d_%H%M)
LOG_FILE="/var/log/wordpress-backup.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

mkdir -p "$BACKUP_DIR"

log "=== Бэкап БД со SLAVE ==="

mysqldump -h127.0.0.1 -u root -p'RootPassword2026Strong!' \
    --single-transaction --quick --lock-tables=false \
    wordpress > "$BACKUP_DIR/wordpress_full_$DATE.sql" || log "Ошибка дампа!"

mysql -h127.0.0.1 -uroot -p'RootPassword2026Strong!' -e "SHOW SLAVE STATUS\G" > "$BACKUP_DIR/slave_status_$DATE.txt"

log "Бэкап завершён: $BACKUP_DIR/wordpress_full_$DATE.sql"
