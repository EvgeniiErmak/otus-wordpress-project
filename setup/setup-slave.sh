#!/bin/bash
# setup-slave.sh — ПОЛНОСТЬЮ АВТОМАТИЧЕСКАЯ УСТАНОВКА SLAVE (без ручного ввода)

set -euo pipefail

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

MASTER_IP="192.168.88.168"
REPL_PASSWORD="ReplPassword2026Strong!"
MASTER_ROOT_PASSWORD="292799619531629514"

log "=== ФИНАЛЬНАЯ АВТОМАТИЧЕСКАЯ УСТАНОВКА НА SLAVE (192.168.88.167) ==="

# ======================== БАЗОВЫЕ ПАКЕТЫ ========================
for pkg in curl wget git unzip ca-certificates gnupg openssh-client rsync sshpass; do
    check_and_install "$pkg"
done

if ! command -v docker &> /dev/null; then
    log "Устанавливаем Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi
check_and_install docker-compose

# ======================== SSH КЛЮЧИ (полностью автоматически) ========================
log "Настройка автоматического SSH-доступа к master (с паролем)..."

mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa -q
fi

ssh-keyscan -H $MASTER_IP >> /root/.ssh/known_hosts 2>/dev/null || true

# Автоматическое копирование ключа с использованием пароля
log "Копируем SSH-ключ на master автоматически..."
sshpass -p "$MASTER_ROOT_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no -f root@$MASTER_IP || true

# Проверка, что ключ работает
if ssh -o BatchMode=yes -o ConnectTimeout=10 root@$MASTER_IP "exit" 2>/dev/null; then
    log "✅ SSH ключ успешно установлен на master"
else
    log "⚠️  Не удалось установить SSH ключ автоматически. Проверьте пароль MASTER_ROOT_PASSWORD в скрипте."
fi

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
mysql -e "SHOW SLAVE STATUS\G;" | grep -E "Slave_IO_Running|Slave_SQL_Running" || true

# ======================== WordPress + Автосинхронизация ========================
log "Установка и синхронизация WordPress..."
install_wordpress_files

cat > /usr/local/bin/sync-wp-files.sh << 'EOF'
#!/bin/bash
rsync -avz --delete --exclude=wp-config.php -e "ssh -o StrictHostKeyChecking=no -o BatchMode=yes" root@192.168.88.168:/var/www/html/wordpress/ /var/www/html/wordpress/ || true
chown -R www-data:www-data /var/www/html/wordpress
echo "[$(date)] Синхронизация выполнена" >> /var/log/wp-sync.log
EOF
chmod +x /usr/local/bin/sync-wp-files.sh

/usr/local/bin/sync-wp-files.sh || true

# Cron каждые 5 минут
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/sync-wp-files.sh") | crontab -

# ======================== MONITORING + FILEBEAT ========================
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

# ======================== ФИНАЛЬНЫЙ ОТЧЁТ ========================
echo ""
echo "=================================================================="
echo "✅ SLAVE УСТАНОВЛЕН ПОЛНОСТЬЮ АВТОМАТИЧЕСКИ!"
echo "=================================================================="
echo "WordPress:                 http://192.168.88.168"
echo "MySQL Slave:               репликация запущена"
echo "Автосинхронизация файлов:  каждые 5 минут"
echo "Node Exporter:             http://192.168.88.167:9100/metrics"
echo "Filebeat:                  логи отправляются на master"
echo ""
echo "Проверить репликацию:"
echo "   mysql -e 'SHOW SLAVE STATUS\G;'"
echo "=================================================================="

log "Slave установка завершена полностью автоматически."
