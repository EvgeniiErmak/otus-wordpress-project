#!/bin/bash
# backup-db.sh — Потабличный бэкап БД со slave с позицией бинлога

BACKUP_DIR="/var/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/wordpress_full_${TIMESTAMP}.sql"
BINLOG_FILE="${BACKUP_DIR}/binlog_position_${TIMESTAMP}.txt"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

log "=== Создание потабличного бэкапа БД со slave ==="

# Получаем текущую позицию бинлога
mysql -e "SHOW MASTER STATUS\G" > "$BINLOG_FILE"

# Потабличный дамп
databases=$(mysql -e "SHOW DATABASES LIKE 'wordpress';" | grep wordpress)

if [ -n "$databases" ]; then
    mysqldump --single-transaction --quick --lock-tables=false \
        --databases wordpress \
        --tables $(mysql -e "SHOW TABLES FROM wordpress;" | tail -n +2 | tr '\n' ' ') \
        > "$BACKUP_FILE"
    
    log "✅ Бэкап создан: $BACKUP_FILE"
    log "📍 Позиция бинлога сохранена в $BINLOG_FILE"
else
    log "⚠️ База wordpress не найдена"
fi

# Оставляем только 3 последних бэкапа
find "$BACKUP_DIR" -name "wordpress_full_*.sql" -type f | sort -r | tail -n +4 | xargs rm -f 2>/dev/null || true
