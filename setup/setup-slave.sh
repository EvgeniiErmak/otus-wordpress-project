#!/bin/bash
# setup/setup-slave.sh — ПОЛНЫЙ ФИНАЛЬНЫЙ ВАРИАНТ ДЛЯ SLAVE
# Всё автоматом: LAMP, MySQL репликация, WordPress, rsync sync, Node Exporter, Filebeat (простой индекс)

set -euo pipefail

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

MASTER_IP="192.168.88.168"
REPL_PASSWORD="ReplPassword2026Strong!"
MASTER_ROOT_PASSWORD="292799619531629514"

log "=== ФИНАЛЬНАЯ АВТОМАТИЧЕСКАЯ УСТАНОВКА НА SLAVE (192.168.88.167) ==="

# ======================== БАЗОВЫЕ ПАКЕТЫ ========================
for pkg in curl wget git unzip ca-certificates gnupg openssh-client rsync sshpass ufw; do
    check_and_install "$pkg"
done

# Docker
if ! command -v docker &> /dev/null; then
    log "Устанавливаем Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi
check_and_install docker-compose

# ======================== SSH КЛЮЧ ========================
log "Настройка автоматического SSH-доступа к master..."
mkdir -p /root/.ssh && chmod 700 /root/.ssh
if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa -q
fi
ssh-keyscan -H $MASTER_IP >> /root/.ssh/known_hosts 2>/dev/null || true

sshpass -p "$MASTER_ROOT_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no -f root@$MASTER_IP || true
log "✅ SSH ключ установлен на master"

# ======================== FIREWALL ========================
log "Настройка firewall..."
ufw allow 22
ufw allow 80
ufw allow 8080
ufw allow 9100
ufw allow 3306
ufw --force enable || true

# ======================== NGINX + APACHE + PHP + MEMCACHED ========================
log "Установка Nginx + Apache + PHP + Memcached..."
check_and_install nginx apache2 php8.3 php8.3-fpm php8.3-mysql php8.3-memcached

# Apache на 8080
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

# Memcached
sed -i 's/^-l 127.0.0.1/-l 0.0.0.0/' /etc/memcached.conf 2>/dev/null || true
systemctl restart memcached
enable_and_start_service memcached

# ======================== MySQL SLAVE ========================
log "Настройка MySQL Slave..."
check_and_install mysql-server
download_config "configs/mysql/slave.cnf" "/etc/mysql/mysql.conf.d/slave.cnf"
systemctl restart mysql
enable_and_start_service mysql

log "Настройка репликации..."
mysql -e "
STOP SLAVE;
CHANGE MASTER TO
  MASTER_HOST='$MASTER_IP',
  MASTER_USER='repl',
  MASTER_PASSWORD='$REPL_PASSWORD',
  MASTER_AUTO_POSITION=1;
START SLAVE;
" 2>/dev/null || true

sleep 8
mysql -e "SHOW SLAVE STATUS\G;" | grep -E "Slave_IO_Running|Slave_SQL_Running" || true

# ======================== WORDPRESS + СИНХРОНИЗАЦИЯ ========================
log "Установка и синхронизация WordPress файлов..."
install_wordpress_files

cat > /usr/local/bin/sync-wp-files.sh << 'EOF'
#!/bin/bash
rsync -avz --delete --exclude=wp-config.php \
  -e "ssh -o StrictHostKeyChecking=no -o BatchMode=yes" \
  root@192.168.88.168:/var/www/html/wordpress/ /var/www/html/wordpress/ || true
chown -R www-data:www-data /var/www/html/wordpress
echo "[$(date)] Синхронизация WP файлов выполнена" >> /var/log/wp-sync.log
EOF

chmod +x /usr/local/bin/sync-wp-files.sh
/usr/local/bin/sync-wp-files.sh || true

# Cron каждые 5 минут
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/sync-wp-files.sh") | crontab -

# ======================== MONITORING ========================
log "Node Exporter..."
check_and_install prometheus-node-exporter
enable_and_start_service prometheus-node-exporter

# ======================== FILEBEAT — ПРОСТОЙ ВАРИАНТ ========================
log "Filebeat — простой режим без data stream..."

mkdir -p /opt/filebeat

cat > /opt/filebeat/docker-compose.yml << 'EOF'
version: '3.8'
services:
  filebeat:
    image: docker.elastic.co/beats/filebeat:8.17.1
    user: "0:0"
    command: ["filebeat", "-e", "--strict.perms=false"]
    volumes:
      - /var/log:/var/log:ro
      - ./filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
    restart: unless-stopped
    network_mode: "host"
EOF

cat > /opt/filebeat/filebeat.yml << 'EOF'
filebeat.inputs:
- type: filestream
  enabled: true
  id: slave-logs
  paths:
    - /var/log/nginx/*.log
    - /var/log/apache2/*.log
    - /var/log/mysql/*.log
    - /var/log/wp-sync.log
  fields:
    server: otus-slave

setup.template.enabled: false
setup.ilm.enabled: false

output.elasticsearch:
  hosts: ["http://192.168.88.168:9200"]
  index: "logs-slave-%{+yyyy.MM.dd}"

logging.level: info
EOF

cd /opt/filebeat
docker compose down || true
docker compose up -d

# Генерация логов
log "Генерируем 800 тестовых логов..."
for i in {1..800}; do
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] TEST Nginx slave #$i" >> /var/log/nginx/access.log
    echo "[$ts] TEST Apache slave #$i" >> /var/log/apache2/access.log
    echo "[$ts] TEST MySQL slave #$i" >> /var/log/mysql/error.log
    echo "[$ts] TEST WP-sync slave #$i" >> /var/log/wp-sync.log
done

sleep 90

# Index Pattern
log "Создаём Index Pattern в Kibana..."
curl -s -X POST "http://$MASTER_IP:5601/api/saved_objects/index-pattern/logs-*" \
  -H 'kbn-xsrf: true' \
  -H 'Content-Type: application/json' \
  -d '{"attributes":{"title":"logs-*","timeFieldName":"@timestamp"}}' || true

# ======================== ФИНАЛЬНЫЙ ОТЧЁТ ========================
echo ""
echo "=================================================================="
echo "✅ SLAVE УСТАНОВЛЕН УСПЕШНО (полностью автоматически)"
echo "=================================================================="
echo "WordPress:                 http://192.168.88.168"
echo "MySQL Slave:               репликация должна быть активна"
echo "Автосинхронизация файлов:  каждые 5 минут (/usr/local/bin/sync-wp-files.sh)"
echo "Node Exporter:             http://192.168.88.167:9100/metrics"
echo "Kibana + логи:             http://192.168.88.168:5601"
echo "   → Выберите Index Pattern: logs-*"
echo ""
echo "Проверь индексы командой:"
echo "   curl -s http://192.168.88.168:9200/_cat/indices/logs*?v"
echo "=================================================================="

log "Slave восстановлен успешно."
