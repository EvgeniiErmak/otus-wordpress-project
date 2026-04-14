#!/bin/bash
# recovery/recovery-master.sh — Полное восстановление master "с нуля"
# Одна команда: curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-master.sh | sudo bash

set -euo pipefail

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/recovery.log
}

log "=== Начало полного восстановления MASTER ==="

# Обновление и базовые пакеты
apt-get update && apt-get upgrade -y

# Запуск основного setup
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/setup-master.sh | bash

# Дополнительная настройка репликации и WP (будет доработано)
log "Master восстановлен. Теперь настройте репликацию и запустите sync-wp-files.sh"
