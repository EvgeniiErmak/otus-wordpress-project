#!/bin/bash
# scripts/backup-db.sh — Потабличный бэкап БД со slave с позицией бинлога

BACKUP_DIR="/var/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/wordpress_full_${TIMESTAMP}.sql"
BINLOG_FILE="${BACKUP_DIR}/binlog_position_${TIMESTAMP}.txt"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

log "=== Создание потабличного бэкапа БД со slave ==="

# Получаем текущую позицию бинлога ДО бэкапа
log "📍 Получаем позицию бинлога..."
BINLOG_INFO=$(mysql -e "SHOW MASTER STATUS\G" 2>/dev/null | grep -E "File|Position")

if [ -n "$BINLOG_INFO" ]; then
    echo "$BINLOG_INFO" > "$BINLOG_FILE"
    # Вывод в stdout для автоматической проверки
    echo "📊 Binlog Position:"
    echo "$BINLOG_INFO"
else
    log "⚠️ Не удалось получить позицию бинлога"
    echo "⚠️ SHOW MASTER STATUS returned empty" > "$BINLOG_FILE"
fi

# Потабличный дамп базы wordpress
log "🗄 Создаём дамп таблиц..."
TABLES=$(mysql -N -e "SHOW TABLES FROM wordpress;" 2>/dev/null | tr '\n' ' ')

if [ -n "$TABLES" ]; then
    mysqldump --single-transaction --quick --lock-tables=false \
        --databases wordpress \
        --tables $TABLES > "$BACKUP_FILE" 2>/dev/null

    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    log "✅ Бэкап создан: $BACKUP_FILE (размер: $SIZE)"
    log "📍 Позиция бинлога сохранена в $BINLOG_FILE"
    
    # Финальный вывод для проверки
    echo "📦 BACKUP_OK: $BACKUP_FILE"
    echo "📊 BINLOG_INFO:"
    cat "$BINLOG_FILE"
else
    log "⚠️ База wordpress или таблицы не найдены"
    exit 1
fi

# Ротация: оставляем только 3 последних бэкапа
find "$BACKUP_DIR" -name "wordpress_full_*.sql" -type f -mtime +1 -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "binlog_position_*.txt" -type f -mtime +1 -delete 2>/dev/null || true

log "✅ Бэкап завершён успешно"
