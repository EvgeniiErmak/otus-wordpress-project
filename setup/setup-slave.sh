#!/bin/bash
# setup-slave.sh — Полная установка Slave сервера (192.168.88.167)

set -euo pipefail

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

log "=== ФИНАЛЬНАЯ УСТАНОВКА НА SLAVE (192.168.88.167) ==="

# Базовые пакеты
for pkg in curl wget git unzip ca-certificates gnupg; do
    check_and_install "$pkg"
done

if ! command -v docker &> /dev/null; then
    log "Устанавливаем Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi
check_and_install docker-compose

# ======================== NGINX ========================
log "Настройка Nginx reverse proxy..."
check_and_install nginx
download_config "configs/nginx/reverse-proxy.conf" "/etc/nginx/sites-available/default"
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx
enable_and_start_service nginx

# ======================== LAMP ========================
log "Установка LAMP на slave..."
apt-get install -y apache2 php8.3 php8.3-fpm php8.3-mysql php8.3-memcached \
    php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml php8.3-zip memcached

log "Исправляем ports.conf..."
cat > /etc/apache2/ports.conf << 'EOF'
Listen 8080
EOF

download_config "configs/apache/wordpress.conf" "/etc/apache2/sites-available/wordpress.conf"
a2ensite wordpress.conf
a2dissite 000-default.conf
a2enmod proxy_fcgi setenvif rewrite
a2enconf php8.3-fpm
systemctl restart apache2
enable_and_start_service apache2

log "Настройка Memcached..."
sed -i 's/^-l 127.0.0.1/-l 0.0.0.0/' /etc/memcached.conf 2>/dev/null || true
systemctl restart memcached
enable_and_start_service memcached

# ======================== MySQL SLAVE ========================
log "Настройка MySQL Slave..."
check_and_install mysql-server

download_config "configs/mysql/slave.cnf" "/etc/mysql/mysql.conf.d/slave.cnf"

# Запуск MySQL
systemctl restart mysql
enable_and_start_service mysql

log "Настройка репликации от Master..."
mysql -e "
CHANGE MASTER TO
  MASTER_HOST='192.168.88.168',
  MASTER_USER='repl',
  MASTER_PASSWORD='ReplPassword2026Strong!',
  MASTER_AUTO_POSITION=1;
START SLAVE;
SHOW SLAVE STATUS\G;
"

log "✅ MySQL Slave настроен и запущен репликация"

# ======================== WordPress файлы (синхронизация) ========================
log "Установка WordPress файлов на slave..."
install_wordpress_files

# Создаём скрипт синхронизации с master
cat > /usr/local/bin/sync-wp-files.sh << 'EOF'
#!/bin/bash
rsync -avz --delete --exclude=wp-config.php root@192.168.88.168:/var/www/html/wordpress/ /var/www/html/wordpress/
chown -R www-data:www-data /var/www/html/wordpress
EOF
chmod +x /usr/local/bin/sync-wp-files.sh

# Запускаем синхронизацию один раз
/usr/local/bin/sync-wp-files.sh

log "✅ WordPress файлы синхронизированы с master"

# ======================== MONITORING ========================
log "Установка Node Exporter на slave..."
check_and_install prometheus-node-exporter
enable_and_start_service prometheus-node-exporter

# ======================== FILEBEAT (логи в ELK master) ========================
log "Установка Filebeat на slave..."
mkdir -p /opt/filebeat
cat > /opt/filebeat/docker-compose.yml << 'EOF'
version: '3.8'
services:
  filebeat:
    image: docker.elastic.co/beats/filebeat:8.17.1
    command: ["-e", "--strict.perms=false"]
    volumes:
      - /var/log:/var/log:ro
      - ./filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
    restart: unless-stopped
EOF

cat > /opt/filebeat/filebeat.yml << 'EOF'
filebeat.inputs:
- type: filestream
  enabled: true
  paths:
    - /var/log/nginx/*.log
    - /var/log/apache2/*.log
    - /var/log/mysql/*.log

output.elasticsearch:
  hosts: ["http://192.168.88.168:9200"]
  index: "logs-slave-%{+yyyy.MM.dd}"
EOF

cd /opt/filebeat
docker compose up -d

log "✅ Filebeat запущен (логи отправляются на master)"

# ======================== ФИНАЛЬНЫЙ ОТЧЁТ ========================
echo ""
echo "=================================================================="
echo "✅ SLAVE СЕРВЕР УСТАНОВЛЕН УСПЕШНО!"
echo "=================================================================="
echo "IP Slave: 192.168.88.167"
echo ""
echo "WordPress доступен через master: http://192.168.88.168"
echo "MySQL Slave: подключён к master (репликация активна)"
echo "Memcached: общий с master"
echo "Node Exporter: http://192.168.88.167:9100/metrics"
echo "Filebeat: отправляет логи на Elasticsearch master"
echo ""
echo "Для синхронизации файлов с master выполняйте:"
echo "   /usr/local/bin/sync-wp-files.sh"
echo ""
echo "Проверьте репликацию на master командой:"
echo "   mysql -e 'SHOW SLAVE STATUS\G;'   (на slave сервере)"
echo "=================================================================="

log "Slave установка завершена успешно."
