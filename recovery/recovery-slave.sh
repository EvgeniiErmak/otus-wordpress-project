#!/bin/bash
# recovery/recovery-slave.sh — Полное восстановление slave "с нуля"

set -euo pipefail

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/recovery.log
}

log "=== Начало полного восстановления SLAVE ==="

apt-get update && apt-get upgrade -y

curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/setup-slave.sh | bash

log "Slave восстановлен. Выполните настройку MySQL репликации на master."
