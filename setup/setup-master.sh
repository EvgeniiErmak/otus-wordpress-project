#!/bin/bash
# setup-master.sh — Полная установка на otus-master (192.168.88.168)
# Запуск: curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/setup-master.sh | sudo bash
# Отвечает за: F (Nginx), B (Apache+PHP+WP), Memcached, MySQL Master, Prometheus+Grafana, ELK (частично), Mem

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

log "=== Начало установки на MASTER ==="

apt-get update && apt-get upgrade -y

# 1. Установка базовых пакетов
log "Установка базовых зависимостей..."
packages="curl wget git unzip apt-transport-https ca-certificates software-properties-common"
for pkg in $packages; do
    check_and_install "$pkg"
done

# 2. Nginx — Reverse Proxy + Load Balancer
log "Установка Nginx..."
check_and_install nginx
download_config "configs/nginx/reverse-proxy.conf" "/etc/nginx/sites-available/default"
rm -f /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx
enable_and_start_service nginx

# 3. Apache + PHP-FPM (Backend на порту 8080)
log "Установка Apache + PHP 8.3 для WordPress..."
check_and_install apache2 php8.3 php8.3-fpm php8.3-mysql php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml php8.3-zip libapache2-mod-php8.3

# Настраиваем Apache слушать 8080 (чтобы не конфликтовать с Nginx)
sed -i 's/Listen 80/Listen 8080/' /etc/apache2/ports.conf
sed -i 's/<VirtualHost \*:80>/<VirtualHost *:8080>/' /etc/apache2/sites-available/000-default.conf

# Включаем модули
a2enmod proxy_fcgi setenvif mpm_event
a2enconf php8.3-fpm
systemctl restart apache2
enable_and_start_service apache2

# 4. Memcached (общее хранилище сессий для обоих backend'ов)
log "Установка Memcached..."
check_and_install memcached
sed -i 's/-l 127.0.0.1/-l 0.0.0.0/' /etc/memcached.conf   # слушать все интерфейсы (для slave тоже)
systemctl restart memcached
enable_and_start_service memcached

# 5. MySQL Master (будет доработано в следующем этапе с репликацией)
log "Установка MySQL Server (Master)..."
check_and_install mysql-server
mysql_secure_installation --use-default-password <<< "Y
Y
Y
Y
Y" || true   # упрощённо; в проде лучше вручную

# Базовая настройка master (server-id, binlog) — будет в отдельном конфиге позже

# 6. WordPress (установка файлов)
log "Установка WordPress..."
WP_DIR="/var/www/html/wordpress"
mkdir -p "$WP_DIR"
cd /tmp
curl -sSL https://wordpress.org/latest.tar.gz | tar -xz
mv wordpress/* "$WP_DIR/"
chown -R www-data:www-data "$WP_DIR"
chmod -R 755 "$WP_DIR"

# Создаём wp-config.php с Memcached и DB (пароли позже)
# (полная настройка wp-config в следующем этапе)

# 7. Мониторинг: Prometheus + Grafana + Node Exporter
log "Установка Prometheus + Node Exporter + Grafana..."
check_and_install prometheus prometheus-node-exporter grafana

# Простая конфигурация Prometheus (добавит scrape для node_exporter)
cat > /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
EOF

enable_and_start_service prometheus
enable_and_start_service grafana-server
enable_and_start_service prometheus-node-exporter

# Автоматическая настройка дашборда в Grafana (provisioning)
mkdir -p /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards
download_config "configs/grafana/provisioning/datasources/prometheus.yml" "/etc/grafana/provisioning/datasources/prometheus.yml"  # будет в следующем этапе
systemctl restart grafana-server

# 8. ELK (частично: Elasticsearch + Kibana + Filebeat позже)
log "Установка Elasticsearch + Kibana (ELK базово)..."
# Добавляем репозиторий Elastic (официальный способ для Ubuntu 24.04)
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list
apt-get update
check_and_install elasticsearch kibana

# Базовый запуск (в проде — с security)
enable_and_start_service elasticsearch
enable_and_start_service kibana

log "=== Установка на MASTER завершена ==="
log "Доступы:"
log "WordPress: http://$(hostname -I | awk '{print $1}')/wordpress"
log "Grafana: http://$(hostname -I | awk '{print $1}'):3000 (admin/admin)"
log "Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
log "Kibana: http://$(hostname -I | awk '{print $1}'):5601"
log "Nginx (основной сайт): http://$(hostname -I | awk '{print $1}')"

# Рекомендация: после запуска выполните setup-slave на втором сервере
