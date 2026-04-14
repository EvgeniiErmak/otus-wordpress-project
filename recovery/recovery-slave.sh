#!/bin/bash
# recovery/recovery-slave.sh — Полное восстановление slave "с нуля"

set -euo pipefail
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/recovery.log; }

log "=== ПОЛНОЕ ВОССТАНОВЛЕНИЕ SLAVE ==="
apt-get update && apt-get upgrade -y
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/setup-slave.sh | bash

log "Slave восстановлен."
log "Настройте репликацию на master: CHANGE MASTER TO ... и START SLAVE;"
