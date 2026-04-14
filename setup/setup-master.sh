#!/bin/bash
# setup-master.sh — Полная установка на otus-master (192.168.88.168)
# Запуск: curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/setup-master.sh | sudo bash

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

log "=== ФИНАЛЬНАЯ УСТАНОВКА НА MASTER (192.168.88.168) ==="

apt-get update && apt-get upgrade -y

# Базовые пакеты
for pkg in curl wget git unzip ca-certificates software-properties-common; do
    check_and_install "$pkg"
done

# 1. Nginx — Reverse Proxy + Load Balancer
check_and_install nginx
download_config "configs/nginx/reverse-proxy.conf" "/etc/nginx/sites-available/default"
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx
enable_and_start_service nginx

# 2. Apache + PHP + Memcached (Backend)
check_and_install apache2 php8.3 php8.3-fpm php8.3-mysql php8.3-memcached php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml php8.3-zip memcached
sed -i 's/Listen 80/Listen 8080/' /etc/apache2/ports.conf
download_config "configs/apache/wordpress.conf" "/etc/apache2/sites-available/wordpress.conf"
a2ensite wordpress.conf
a2dissite 000-default.conf
a2enmod proxy_fcgi setenvif rewrite
systemctl restart apache2
enable_and_start_service apache2

# Memcached слушает все интерфейсы
sed -i 's/-l 127.0.0.1/-l 0.0.0.0/' /etc/memcached.conf
systemctl restart memcached
enable_and_start_service memcached

# 3. MySQL Master
check_and_install mysql-server
setup_mysql_master

# 4. WordPress
install_wordpress_files
configure_wp_config

# 5. Мониторинг: Prometheus + Grafana + Node Exporter
check_and_install prometheus prometheus-node-exporter grafana
download_config "configs/grafana/provisioning/datasources/prometheus.yml" "/etc/grafana/provisioning/datasources/prometheus.yml"
systemctl restart grafana-server prometheus prometheus-node-exporter
enable_and_start_service grafana-server prometheus prometheus-node-exporter

# 6. ELK (Elasticsearch + Kibana + Filebeat)
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

log "=== УСТАНОВКА MASTER ЗАВЕРШЕНА УСПЕШНО ==="
log "WordPress: http://192.168.88.168"
log "Grafana: http://192.168.88.168:3000 (admin / admin)"
log "Kibana: http://192.168.88.168:5601"
log "Prometheus: http://192.168.88.168:9090"
