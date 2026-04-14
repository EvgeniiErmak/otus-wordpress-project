#!/bin/bash
# common-functions.sh — Общие утилиты для всех скриптов проекта
# Используется в setup, backup, recovery скриптах.
# Автор: для OTUS WordPress Project

set -euo pipefail

LOG_FILE="/var/log/otus-wordpress-setup.log"
REPO_URL="https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_and_install() {
    local package=$1
    if dpkg -l | grep -q "^ii  $package "; then
        log "Пакет $package уже установлен — пропускаем."
    else
        log "Устанавливаем пакет $package..."
        apt-get install -y "$package"
    fi
}

download_config() {
    local remote_path=$1
    local local_path=$2
    log "Скачиваем конфиг: $remote_path → $local_path"
    mkdir -p "$(dirname "$local_path")"
    curl -sSL "$REPO_URL/$remote_path" -o "$local_path"
}

generate_password() {
    openssl rand -hex 16
}

enable_and_start_service() {
    local service=$1
    systemctl enable "$service" --now || true
    systemctl is-active --quiet "$service" && log "$service запущен" || log "Ошибка запуска $service!"
}

# Проверка запуска от root
if [[ $EUID -ne 0 ]]; then
    echo "Скрипт должен запускаться от root (sudo bash)"
    exit 1
fi

log "=== common-functions загружены ==="
