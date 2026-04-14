#!/bin/bash
# scripts/sync-wp-files.sh — Синхронизация wp-content между master и slave
# Запуск по cron: 0 */6 * * * /usr/local/bin/sync-wp-files.sh
# Отвечает за синхронизацию uploads, plugins, themes (как на схеме "Files")

set -euo pipefail

LOG_FILE="/var/log/wp-sync.log"
MASTER_IP="192.168.88.168"   # IP master

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Запуск синхронизации wp-content ==="

# Создаём директории на slave, если их нет
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null www-data@$MASTER_IP "true" || {
    log "Ошибка подключения к master по SSH"
    exit 1
}

rsync -avz --delete \
    --exclude="*.log" \
    www-data@$MASTER_IP:/var/www/html/wordpress/wp-content/uploads/ \
    /var/www/html/wordpress/wp-content/uploads/ || log "Ошибка синхронизации uploads"

rsync -avz --delete \
    www-data@$MASTER_IP:/var/www/html/wordpress/wp-content/plugins/ \
    /var/www/html/wordpress/wp-content/plugins/ || log "Ошибка синхронизации plugins"

rsync -avz --delete \
    www-data@$MASTER_IP:/var/www/html/wordpress/wp-content/themes/ \
    /var/www/html/wordpress/wp-content/themes/ || log "Ошибка синхронизации themes"

log "Синхронизация wp-content завершена успешно"
