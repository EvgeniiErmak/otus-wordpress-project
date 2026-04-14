#!/bin/bash
# recovery/recovery-master.sh — Полное восстановление master "с нуля"
# Одна команда: curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-master.sh | sudo bash

set -euo pipefail
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/recovery.log; }

log "=== ПОЛНОЕ ВОССТАНОВЛЕНИЕ MASTER ==="
apt-get update && apt-get upgrade -y
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/setup-master.sh | bash

log "Master восстановлен."
log "Если есть бэкап — восстановите БД: mysql wordpress < /var/backups/wordpress_*.sql"
log "Затем выполните: /usr/local/bin/sync-wp-files.sh"
