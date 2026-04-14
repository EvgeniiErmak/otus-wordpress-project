#!/bin/bash
# common-functions.sh — Общие функции для всех скриптов OTUS WordPress Project
# Idempotent, логирование, скачивание конфигов из GitHub

set -euo pipefail

LOG_FILE="/var/log/otus-wordpress-setup.log"
REPO_URL="https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_and_install() {
    local package=$1
    if dpkg -l | grep -q "^ii  $package " 2>/dev/null; then
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
    systemctl enable "$service" --now 2>/dev/null || true
    if systemctl is-active --quiet "$service"; then
        log "$service успешно запущен"
    else
        log "ВНИМАНИЕ: $service не запустился!"
    fi
}

setup_mysql_master() {
    log "Настройка MySQL Master..."
    download_config "configs/mysql/master.cnf" "/etc/mysql/mysql.conf.d/master.cnf"
    
    mysql -e "CREATE DATABASE IF NOT EXISTS wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || true
    mysql -e "CREATE USER IF NOT EXISTS 'wpuser'@'%' IDENTIFIED BY 'WpPassword2026Strong!';" || true
    mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'%';" || true
    mysql -e "CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED BY 'ReplPassword2026Strong!';" || true
    mysql -e "GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';" || true
    mysql -e "FLUSH PRIVILEGES;" || true
    
    systemctl restart mysql
    enable_and_start_service mysql
    log "MySQL Master настроен. Пользователи wpuser и repl созданы."
}

setup_mysql_slave() {
    log "Настройка MySQL Slave..."
    download_config "configs/mysql/slave.cnf" "/etc/mysql/mysql.conf.d/slave.cnf"
    systemctl restart mysql
    enable_and_start_service mysql
    log "MySQL Slave настроен."
}

install_wordpress_files() {
    log "Установка WordPress файлов..."
    WP_DIR="/var/www/html/wordpress"
    mkdir -p "$WP_DIR"
    cd /tmp
    curl -sSL https://wordpress.org/latest.tar.gz -o latest.tar.gz
    tar -xzf latest.tar.gz
    rsync -a wordpress/ "$WP_DIR/"
    chown -R www-data:www-data "$WP_DIR"
    chmod -R 755 "$WP_DIR"
    log "WordPress файлы установлены."
}

configure_wp_config() {
    log "Настройка wp-config.php с поддержкой Memcached..."
    download_config "configs/wordpress/wp-config.php" "/var/www/html/wordpress/wp-config.php"
    # Генерация солей
    curl -s https://api.wordpress.org/secret-key/1.1/salt > /tmp/salts.txt
    sed -i '/put your unique phrases here/r /tmp/salts.txt' /var/www/html/wordpress/wp-config.php
    sed -i '/put your unique phrases here/d' /var/www/html/wordpress/wp-config.php
    chown www-data:www-data /var/www/html/wordpress/wp-config.php
    log "wp-config.php настроен с Memcached."
}
