#!/bin/bash
# setup-slave.sh — Полная установка на otus-slave (192.168.88.167)
# Запуск: curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/setup-slave.sh | sudo bash

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

log "=== ФИНАЛЬНАЯ УСТАНОВКА НА SLAVE (192.168.88.167) ==="

apt-get update && apt-get upgrade -y

# Базовые пакеты
for pkg in curl wget apache2 php8.3 php8.3-fpm php8.3-mysql php8.3-memcached php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml php8.3-zip; do
    check_and_install "$pkg"
done

# Apache Backend
sed -i 's/Listen 80/Listen 8080/' /etc/apache2/ports.conf
download_config "configs/apache/wordpress.conf" "/etc/apache2/sites-available/wordpress.conf"
a2ensite wordpress.conf
a2dissite 000-default.conf
a2enmod proxy_fcgi setenvif rewrite
systemctl restart apache2
enable_and_start_service apache2

# WordPress структура
mkdir -p /var/www/html/wordpress
chown -R www-data:www-data /var/www/html/wordpress

# MySQL Slave
check_and_install mysql-server
setup_mysql_slave

# Node Exporter + Filebeat
check_and_install prometheus-node-exporter
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list
apt-get update
check_and_install filebeat

cat > /etc/filebeat/filebeat.yml << EOF
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/nginx/*.log
    - /var/log/apache2/*.log
    - /var/log/mysql/*.log
output.elasticsearch:
  hosts: ["192.168.88.168:9200"]
setup.kibana:
  host: "http://192.168.88.168:5601"
EOF

enable_and_start_service prometheus-node-exporter filebeat

# Скрипты
mkdir -p /usr/local/bin
cp scripts/sync-wp-files.sh /usr/local/bin/ 2>/dev/null || true
chmod +x /usr/local/bin/sync-wp-files.sh 2>/dev/null || true

log "=== УСТАНОВКА SLAVE ЗАВЕРШЕНА ==="
log "После настройки master запустите sync-wp-files.sh"
