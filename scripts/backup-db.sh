#!/bin/bash
# backup-db.sh — Бэкап БД со slave с позицией бинлога

BACKUP_DIR="/var/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/wordpress_${DATE}.sql"

mkdir -p $BACKUP_DIR

echo "=== Создание бэкапа БД со slave ==="

# Бэкап со slave
mysqldump -u wpuser -p'WpPassword2026Strong!' --single-transaction --master-data=2 wordpress > "$BACKUP_FILE"

# Сохранение позиции бинлога
echo "Бэкап создан: $BACKUP_FILE"
echo "Позиция бинлога сохранена внутри файла (MASTER_DATA=2)"

ls -lh "$BACKUP_FILE"
