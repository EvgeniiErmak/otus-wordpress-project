#!/bin/bash
# setup-master.sh — ПОЛНАЯ УСТАНОВКА НА MASTER (финальная версия)
# Запуск одной командой: curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/setup-master.sh | sudo bash

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

log "=== ФИНАЛЬНАЯ УСТАНОВКА НА MASTER (192.168.88.168) ==="

apt-get update && apt-get upgrade -y

# Базовые пакеты
for pkg in curl wget git unzip ca-certificates software-properties-common; do
    check_and_install "$pkg"
done

# 1. Nginx Reverse Proxy + Load Balancer
check_and_install nginx
download_config "configs/nginx/reverse-proxy.conf" "/etc/nginx/sites-available/default"
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx
enable_and_start_service nginx

# 2. Apache + PHP + Memcached + MySQL
log "Установка Apache, PHP, Memcached и MySQL..."
apt-get install -y apache2 php8.3 php8.3-fpm php8.3-mysql php8.3-memcached php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml php8.3-zip memcached mysql-server

# ports.conf
log "Исправляем /etc/apache2/ports.conf..."
cat > /etc/apache2/ports.conf << 'EOF'
Listen 8080

<IfModule ssl_module>
    Listen 443
</IfModule>

<IfModule mod_gnutls.c>
    Listen 443
</IfModule>
EOF

download_config "configs/apache/wordpress.conf" "/etc/apache2/sites-available/wordpress.conf"
a2ensite wordpress.conf
a2dissite 000-default.conf
a2enmod proxy_fcgi setenvif rewrite
a2enconf php8.3-fpm
systemctl restart apache2
enable_and_start_service apache2

# Memcached
log "Настройка Memcached..."
sed -i 's/^-l 127.0.0.1/-l 0.0.0.0/' /etc/memcached.conf 2>/dev/null || true
systemctl restart memcached
enable_and_start_service memcached

# MySQL Master
setup_mysql_master

# WordPress (файлы + автоматическая установка)
install_wordpress_files
auto_install_wordpress

# 5. Мониторинг: Prometheus + Grafana
check_and_install prometheus prometheus-node-exporter
log "Установка Grafana (официальный репозиторий)..."
apt-get install -y apt-transport-https software-properties-common wget gnupg
wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
apt-get update
check_and_install grafana

download_config "configs/grafana/provisioning/datasources/prometheus.yml" "/etc/grafana/provisioning/datasources/prometheus.yml"
systemctl daemon-reload
systemctl restart grafana-server
enable_and_start_service grafana-server

# 6. ELK (базово)
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list
apt-get update
check_and_install elasticsearch kibana filebeat
enable_and_start_service elasticsearch kibana

# 7. Скрипты и cron
mkdir -p /usr/local/bin
cp scripts/sync-wp-files.sh /usr/local/bin/ 2>/dev/null || true
cp backup/backup-db.sh /usr/local/bin/ 2>/dev/null || true
chmod +x /usr/local/bin/*.sh 2>/dev/null || true
crontab cron/jobs 2>/dev/null || true

# ======================== ФИНАЛЬНЫЙ ВЫВОД ДОСТУПОВ ========================
echo ""
echo "=================================================================="
echo "✅ УСТАНОВКА MASTER ЗАВЕРШЕНА УСПЕШНО!"
echo "=================================================================="
echo "WordPress (автоматически установлен):"
echo "   URL:      http://192.168.88.168"
echo "   Логин:    admin"
echo "   Пароль:   AdminPassword2026Strong!"
echo ""
echo "Grafana:"
echo "   URL:      http://192.168.88.168:3000"
echo "   Логин:    admin"
echo "   Пароль:   admin"
echo ""
echo "MySQL (root):"
echo "   Пароль:   (установлен по умолчанию MySQL 8.0 — проверьте /etc/mysql/debian.cnf)"
echo ""
echo "Memcached:    работает на 0.0.0.0:11211"
echo "Nginx + Apache: работают (балансировка включена)"
echo "=================================================================="
echo "Для восстановления slave сервера запустите recovery-slave.sh"
echo "=================================================================="
