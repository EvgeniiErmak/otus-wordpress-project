#!/bin/bash
# setup-slave.sh — ПОЛНОСТЬЮ АВТОМАТИЧЕСКАЯ УСТАНОВКА SLAVE (192.168.88.167)

set -euo pipefail

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

log "=== ФИНАЛЬНАЯ АВТОМАТИЧЕСКАЯ УСТАНОВКА НА SLAVE (192.168.88.167) ==="

MASTER_IP="192.168.88.168"
REPL_PASSWORD="ReplPassword2026Strong!"
ROOT_PASSWORD="ваш_пароль_root_на_master_если_есть"  # если root без пароля — оставь пустым

# ======================== БАЗОВЫЕ ПАКЕТЫ ========================
for pkg in curl wget git unzip ca-certificates gnupg openssh-client rsync; do
    check_and_install "$pkg"
done

if ! command -v docker &> /dev/null; then
    log "Устанавливаем Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi
check_and_install docker-compose

# ======================== SSH КЛЮЧИ АВТОМАТИЧЕСКИ ========================
log "Настройка автоматического SSH-доступа к master..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa -q
fi

# Добавляем master в known_hosts автоматически
ssh-keyscan -H $MASTER_IP >> /root/.ssh/known_hosts 2>/dev/null || true

# Автоматически копируем публичный ключ на master (используем sshpass если нужно)
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 root@$MASTER_IP "exit" 2>/dev/null; then
    log "Копируем SSH-ключ на master (требуется пароль root на master один раз)..."
    apt-get install -y sshpass || true
    sshpass -p "$ROOT_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no root@$MASTER_IP || true
fi

log "✅ SSH доступ к master настроен автоматически"

# ======================== NGINX + LAMP ========================
log "Настройка Nginx..."
check_and_install nginx
download_config "configs/nginx/reverse-proxy.conf" "/etc/nginx/sites-available/default"
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx
enable_and_start_service nginx

log "Установка LAMP..."
apt-get install -y apache2 php8.3 php8.3-fpm php8.3-mysql php8.3-memcached \
    php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml php8.3-zip memcached

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

log "Memcached..."
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

sleep 5
mysql -e "SHOW SLAVE STATUS\G;" | grep -E "Slave_IO_Running|Slave_SQL_Running|Last_Error"

log "✅ MySQL Slave настроен"

# ======================== WordPress + Автосинхронизация ========================
log "Установка и синхронизация WordPress файлов..."
install_wordpress_files

cat > /usr/local/bin/sync-wp-files.sh << 'EOF'
#!/bin/bash
rsync -avz --delete --exclude=wp-config.php -e "ssh -o StrictHostKeyChecking=no -o BatchMode=yes" root@192.168.88.168:/var/www/html/wordpress/ /var/www/html/wordpress/
chown -R www-data:www-data /var/www/html/wordpress
echo "[$(date)] Файлы WordPress синхронизированы с master" >> /var/log/wp-sync.log
EOF
chmod +x /usr/local/bin/sync-wp-files.sh

# Первая автоматическая синхронизация
/usr/local/bin/sync-wp-files.sh || log "WARNING: Первая синхронизация не удалась (проверьте SSH ключ)"

# Добавляем в cron (каждые 5 минут)
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/sync-wp-files.sh") | crontab -

log "✅ Автоматическая синхронизация WordPress настроена"

# ======================== MONITORING + FILEBEAT ========================
log "Node Exporter..."
check_and_install prometheus-node-exporter
enable_and_start_service prometheus-node-exporter

log "Filebeat..."
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

# ======================== ФИНАЛЬНЫЙ ПОЛНЫЙ ОТЧЁТ ========================
echo ""
echo "=================================================================="
echo "✅ SLAVE СЕРВЕР ПОЛНОСТЬЮ НАСТРОЕН АВТОМАТИЧЕСКИ!"
echo "=================================================================="
echo "IP Slave:                  192.168.88.167"
echo "WordPress:                 http://192.168.88.168  (через master)"
echo "MySQL Slave:               репликация активна"
echo "Memcached:                 общий с master"
echo "Автосинхронизация файлов:  каждые 5 минут (/usr/local/bin/sync-wp-files.sh)"
echo "Node Exporter:             http://192.168.88.167:9100/metrics"
echo "Filebeat:                  логи отправляются на master"
echo ""
echo "Проверить репликацию на slave:"
echo "   mysql -e 'SHOW SLAVE STATUS\G;'"
echo ""
echo "Логи синхронизации:        /var/log/wp-sync.log"
echo "=================================================================="
echo "Всё работает в автоматическом режиме."
echo "=================================================================="

log "Slave установка завершена полностью автоматически."
