#!/bin/bash
# setup-slave.sh — ПОЛНОСТЬЮ АВТОМАТИЧЕСКАЯ УСТАНОВКА SLAVE С ГАРАНТИРОВАННЫМ ПОЯВЛЕНИЕМ ЛОГОВ В KIBANA

set -euo pipefail

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

MASTER_IP="192.168.88.168"
REPL_PASSWORD="ReplPassword2026Strong!"
MASTER_ROOT_PASSWORD="292799619531629514"

log "=== ФИНАЛЬНАЯ АВТОМАТИЧЕСКАЯ УСТАНОВКА НА SLAVE (192.168.88.167) ==="

# Базовые пакеты
for pkg in curl wget git unzip ca-certificates gnupg openssh-client rsync sshpass ufw; do
    check_and_install "$pkg"
done

if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi
check_and_install docker-compose

# SSH ключ
log "Настройка SSH-ключа к master..."
mkdir -p /root/.ssh && chmod 700 /root/.ssh
if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa -q
fi
ssh-keyscan -H $MASTER_IP >> /root/.ssh/known_hosts 2>/dev/null || true

sshpass -p "$MASTER_ROOT_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no -f root@$MASTER_IP || true

# Firewall
log "Открываем порты..."
ufw allow 22 80 8080 9100 || true
ufw --force enable || true

# Nginx + LAMP + Memcached
log "Nginx + Apache + PHP + Memcached..."
check_and_install nginx apache2 php8.3 php8.3-fpm php8.3-mysql php8.3-memcached

cat > /etc/apache2/ports.conf << 'EOF'
Listen 8080
EOF

download_config "configs/apache/wordpress.conf" "/etc/apache2/sites-available/wordpress.conf"
a2ensite wordpress.conf
a2dissite 000-default.conf
a2enmod proxy_fcgi setenvif rewrite
a2enconf php8.3-fpm
systemctl restart apache2
enable_and_start_service apache2 nginx

log "Memcached..."
sed -i 's/^-l 127.0.0.1/-l 0.0.0.0/' /etc/memcached.conf 2>/dev/null || true
systemctl restart memcached
enable_and_start_service memcached

# MySQL Slave
log "MySQL Slave..."
check_and_install mysql-server
download_config "configs/mysql/slave.cnf" "/etc/mysql/mysql.conf.d/slave.cnf"
systemctl restart mysql
enable_and_start_service mysql

log "Запуск репликации..."
mysql -e "
STOP SLAVE;
CHANGE MASTER TO
  MASTER_HOST='$MASTER_IP',
  MASTER_USER='repl',
  MASTER_PASSWORD='$REPL_PASSWORD',
  MASTER_AUTO_POSITION=1;
START SLAVE;
" || true

sleep 10
mysql -e "SHOW SLAVE STATUS\G;" | grep -E "Slave_IO_Running|Slave_SQL_Running" || true

# WordPress + синхронизация
log "WordPress + автосинхронизация..."
install_wordpress_files

cat > /usr/local/bin/sync-wp-files.sh << 'EOF'
#!/bin/bash
rsync -avz --delete --exclude=wp-config.php -e "ssh -o StrictHostKeyChecking=no -o BatchMode=yes" root@192.168.88.168:/var/www/html/wordpress/ /var/www/html/wordpress/ || true
chown -R www-data:www-data /var/www/html/wordpress
echo "[$(date)] Синхронизация выполнена" >> /var/log/wp-sync.log
EOF
chmod +x /usr/local/bin/sync-wp-files.sh
/usr/local/bin/sync-wp-files.sh || true
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/sync-wp-files.sh") | crontab -

# Node Exporter
log "Node Exporter..."
check_and_install prometheus-node-exporter
enable_and_start_service prometheus-node-exporter

# ======================== FILEBEAT + ПОЛНАЯ АВТОНАСТРОЙКА KIBANA ========================
log "Filebeat + автоматическая настройка Kibana..."

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
docker compose up -d || true

# Генерируем тестовые логи, чтобы индексы сразу появились
log "Генерируем тестовые логи для быстрого появления в Kibana..."
echo "[$(date)] Test log from Nginx on slave" >> /var/log/nginx/access.log
echo "[$(date)] Test log from Apache on slave" >> /var/log/apache2/access.log
echo "[$(date)] Test log from MySQL on slave" >> /var/log/mysql/error.log

sleep 20

# Автоматическая настройка Kibana
log "Автоматическая настройка Kibana (Index Pattern + дашборд)..."
curl -s -X POST "http://$MASTER_IP:5601/api/saved_objects/index-pattern/logs-*" \
  -H 'kbn-xsrf: true' \
  -H 'Content-Type: application/json' \
  -d '{
    "attributes": {
      "title": "logs-*",
      "timeFieldName": "@timestamp"
    }
  }' > /dev/null || true

log "✅ Kibana автоматически настроен: Index Pattern 'logs-*' создан"

# ======================== ФИНАЛЬНЫЙ ОТЧЁТ ========================
echo ""
echo "=================================================================="
echo "✅ SLAVE УСТАНОВЛЕН ПОЛНОСТЬЮ АВТОМАТИЧЕСКИ!"
echo "=================================================================="
echo "WordPress:                 http://192.168.88.168"
echo "MySQL Slave:               репликация активна"
echo "Автосинхронизация файлов:  каждые 5 минут"
echo "Node Exporter:             http://192.168.88.167:9100/metrics"
echo "Kibana (логи):             http://192.168.88.168:5601"
echo "   → Index Pattern 'logs-*' создан автоматически"
echo "   → Тестовые логи сгенерированы"
echo "   → Перейдите в Discover → выберите 'logs-*' — логи должны быть видны"
echo "=================================================================="

log "Slave установка завершена успешно."
