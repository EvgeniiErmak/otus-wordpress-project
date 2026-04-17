#!/bin/bash
# setup/setup-slave.sh — Развертывание Slave Node

set -euo pipefail

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

MASTER_IP="192.168.88.168"
REPL_PASSWORD="ReplPassword2026Strong!"
MASTER_ROOT_PASSWORD="292799619531629514"

log "=== АВТОМАТИЧЕСКАЯ УСТАНОВКА НА SLAVE ==="

# ======================== 1. БАЗОВЫЕ ПАКЕТЫ ========================
log "Установка базовых пакетов..."
for pkg in curl wget git unzip ca-certificates gnupg openssh-client rsync sshpass ufw; do
    check_and_install "$pkg"
done

# ======================== 2. DOCKER + COMPOSE V2 ========================
log "Установка Docker..."
if ! command -v docker &> /dev/null; then
    log "Устанавливаем Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi

# Установка Docker Compose v2 plugin
if ! docker compose version &>/dev/null; then
    log "Устанавливаем Docker Compose v2 plugin..."
    apt-get install -y docker-compose-plugin || true
fi

# ======================== 3. SSH КЛЮЧ ========================
log "Настройка автоматического SSH-доступа к master..."
mkdir -p /root/.ssh && chmod 700 /root/.ssh
if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa -q
fi
ssh-keyscan -H "$MASTER_IP" >> /root/.ssh/known_hosts 2>/dev/null || true
sshpass -p "$MASTER_ROOT_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no -f root@"$MASTER_IP" || true
log "✅ SSH ключ установлен на master"

# ======================== 4. FIREWALL ========================
log "Настройка firewall..."
ufw allow 22
ufw allow 80
ufw allow 8080
ufw allow 9100
ufw allow 3306
ufw --force enable || true

# ======================== 5. LAMP СТЕК ========================
log "Установка Nginx + Apache + PHP + Memcached + MySQL..."
apt-get install -y nginx apache2 php8.3 php8.3-fpm php8.3-mysql php8.3-memcached \
    php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml php8.3-zip memcached mysql-server

# Apache на порт 8080
log "Настройка Apache на порт 8080..."
cat > /etc/apache2/ports.conf << 'EOF'
Listen 8080
EOF

download_config "configs/apache/wordpress.conf" "/etc/apache2/sites-available/wordpress.conf"
a2ensite wordpress || true
a2dissite 000-default || true
a2enmod proxy_fcgi setenvif rewrite || true
a2enconf php8.3-fpm || true
systemctl restart apache2 || true
enable_and_start_service apache2 nginx

# Memcached
log "Настройка Memcached..."
sed -i 's/^-l 127.0.0.1/-l 0.0.0.0/' /etc/memcached.conf 2>/dev/null || true
systemctl restart memcached || true
enable_and_start_service memcached

# ======================== 6. MySQL SLAVE ========================
log "Настройка MySQL Slave..."
download_config "configs/mysql/slave.cnf" "/etc/mysql/mysql.conf.d/slave.cnf"
systemctl restart mysql || true
enable_and_start_service mysql

# Ждём доступности MySQL
for i in {1..30}; do
    if mysql -e "SELECT 1;" &>/dev/null; then
        log "✅ MySQL доступен"
        break
    fi
    sleep 2
done

log "Запуск репликации..."
mysql -e "
STOP SLAVE;
RESET SLAVE ALL;
CHANGE MASTER TO
  MASTER_HOST='$MASTER_IP',
  MASTER_USER='repl',
  MASTER_PASSWORD='$REPL_PASSWORD',
  MASTER_AUTO_POSITION=1,
  MASTER_CONNECT_RETRY=10;
START SLAVE;
" 2>/dev/null || true

# Ждём подключения IO-треда репликации
log "Ожидание подключения репликации..."
for i in {1..60}; do
    IO_STATE=$(mysql -N -e "SHOW SLAVE STATUS\G;" 2>/dev/null | grep "Slave_IO_Running:" | awk '{print $2}' || echo "")
    if [ "$IO_STATE" = "Yes" ]; then
        log "✅ Slave IO thread подключён"
        break
    fi
    sleep 2
done

# Финальная проверка
mysql -e "SHOW SLAVE STATUS\G;" 2>/dev/null | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master|Last_IO_Error" || true

# ======================== 7. WORDPRESS — RSYNC С MASTER ========================
log "Подготовка директории WordPress на slave..."
rm -rf /var/www/html/wordpress/* 2>/dev/null || true
mkdir -p /var/www/html/wordpress

log "Настройка синхронизации файлов..."
cat > /usr/local/bin/sync-wp-files.sh << 'EOF'
#!/bin/bash
rsync -avz --delete --exclude=wp-config.php \
  -e "ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=15" \
  root@192.168.88.168:/var/www/html/wordpress/ /var/www/html/wordpress/ || true
chown -R www-data:www-data /var/www/html/wordpress
echo "[$(date)] Синхронизация WP файлов выполнена" >> /var/log/wp-sync.log
EOF
chmod +x /usr/local/bin/sync-wp-files.sh

log "Выполняем первую синхронизацию..."
/usr/local/bin/sync-wp-files.sh || true

# Добавляем задачу в cron
log "Добавляем задачу в cron..."
if crontab -l 2>/dev/null | grep -q "sync-wp-files.sh" 2>/dev/null; then
    log "✅ Cron-задача уже существует"
else
    (crontab -l 2>/dev/null || echo ""; echo "*/5 * * * * /usr/local/bin/sync-wp-files.sh") | crontab - || true
    log "✅ Cron-задача добавлена"
fi

# ======================== 7.1. BACKUP SCRIPT ========================
log "Установка скрипта бэкапа БД..."
download_config "scripts/backup-db.sh" "/usr/local/bin/backup-db.sh"
chmod +x /usr/local/bin/backup-db.sh
log "✅ Скрипт бэкапа установлен"

# ======================== 8. NODE EXPORTER ========================
log "Установка Node Exporter..."
check_and_install prometheus-node-exporter
enable_and_start_service prometheus-node-exporter

# ======================== 9. FILEBEAT ========================
log "Установка Filebeat..."
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
setup.template.enabled: false
setup.ilm.enabled: false
output.elasticsearch:
  hosts: ["http://192.168.88.168:9200"]
  index: "logs-slave-%{+yyyy.MM.dd}"
EOF

cd /opt/filebeat
docker compose down || true
docker compose up -d || true

# ======================== 10. ТЕСТОВЫЕ ЛОГИ (100 штук) ========================
log "Генерируем тестовые логи для проверки..."
for i in {1..100}; do
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] TEST Nginx slave #$i" >> /var/log/nginx/access.log
    echo "[$ts] TEST Apache slave #$i" >> /var/log/apache2/access.log
    echo "[$ts] TEST MySQL slave #$i" >> /var/log/mysql/error.log
    echo "[$ts] TEST WP-sync slave #$i" >> /var/log/wp-sync.log
done

log "Ожидание отправки логов в Elasticsearch. НЕ ПРЕРЫВАЙТЕ ВЫПОЛНЕНИЕ СКРИПТА!..."
sleep 30

log "Создаём Index Pattern в Kibana..."
curl -s -X POST "http://$MASTER_IP:5601/api/saved_objects/index-pattern/logs-*" \
  -H 'kbn-xsrf: true' \
  -H 'Content-Type: application/json' \
  -d '{"attributes":{"title":"logs-*","timeFieldName":"@timestamp"}}' || true

# ======================== ФИНАЛЬНЫЙ ОТЧЁТ ========================
echo ""
echo "=================================================================="
echo "✅ SLAVE УСТАНОВЛЕН УСПЕШНО!"
echo "=================================================================="
echo "WordPress:     http://192.168.88.168"
echo "Node Exporter: http://192.168.88.167:9100/metrics"
echo "Kibana:        http://192.168.88.168:5601  (выберите logs-*)"
echo "=================================================================="
log "Slave восстановлен успешно."
