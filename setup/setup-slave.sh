#!/bin/bash
# setup-slave.sh — Полная установка на otus-slave (192.168.88.167)
# Запуск: curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/setup-slave.sh | sudo bash

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

log "=== Начало установки на SLAVE ==="

apt-get update && apt-get upgrade -y

# 1. Базовые пакеты
packages="curl wget git unzip apache2 php8.3 php8.3-fpm php8.3-mysql php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml php8.3-zip"
for pkg in $packages; do
    check_and_install "$pkg"
done

# 2. Apache + PHP (backend на 8080)
sed -i 's/Listen 80/Listen 8080/' /etc/apache2/ports.conf
download_config "configs/apache/wordpress.conf" "/etc/apache2/sites-available/wordpress.conf"
a2ensite wordpress.conf
a2dissite 000-default.conf
a2enmod proxy_fcgi setenvif
systemctl restart apache2
enable_and_start_service apache2

# 3. WordPress файлы (копируются с master позже через sync)
log "Создаём структуру WordPress..."
mkdir -p /var/www/html/wordpress
chown -R www-data:www-data /var/www/html/wordpress

# 4. MySQL Slave
log "Установка MySQL (Slave)..."
check_and_install mysql-server

download_config "configs/mysql/slave.cnf" "/etc/mysql/conf.d/slave.cnf"
systemctl restart mysql

# 5. Node Exporter для мониторинга
log "Установка Node Exporter..."
check_and_install prometheus-node-exporter
enable_and_start_service prometheus-node-exporter

# 6. Filebeat для отправки логов в ELK (централизованное логирование)
log "Установка Filebeat..."
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list
apt-get update
check_and_install filebeat

# Простая конфигурация Filebeat (логи nginx + apache + mysql)
cat > /etc/filebeat/filebeat.yml << EOF
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/nginx/*.log
    - /var/log/apache2/*.log
    - /var/log/mysql/*.log

output.elasticsearch:
  hosts: ["192.168.88.168:9200"]   # master
  username: "elastic"              # в проде настройте security
  password: "changeme"

setup.kibana:
  host: "http://192.168.88.168:5601"
EOF

enable_and_start_service filebeat

# 7. Memcached клиент (для сессий WordPress)
check_and_install php8.3-memcached

log "=== Установка на SLAVE завершена ==="
log "Теперь на master запустите скрипт синхронизации файлов."
log "После этого настройте MySQL репликацию вручную или через следующий этап."
