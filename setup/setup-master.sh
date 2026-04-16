#!/bin/bash
# setup/setup-master.sh — ИСПРАВЛЕННЫЙ ФИНАЛЬНЫЙ ВАРИАНТ (WordPress авто + ELK работает)

set -euo pipefail

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

log "=== ФИНАЛЬНАЯ УСТАНОВКА НА MASTER (192.168.88.168) ==="

# Базовые пакеты
for pkg in curl wget git unzip ca-certificates gnupg; do
    check_and_install "$pkg"
done

# Docker
if ! command -v docker &> /dev/null; then
    log "Устанавливаем Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi
check_and_install docker-compose

# Nginx
log "Настройка Nginx reverse proxy..."
check_and_install nginx
download_config "configs/nginx/reverse-proxy.conf" "/etc/nginx/sites-available/default"
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx
enable_and_start_service nginx

# LAMP + Memcached
log "Установка LAMP + Memcached..."
apt-get install -y apache2 php8.3 php8.3-fpm php8.3-mysql php8.3-memcached \
    php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml php8.3-zip memcached mysql-server

# Apache на 8080
log "Настройка Apache..."
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

# Memcached
log "Настройка Memcached..."
sed -i 's/^-l 127.0.0.1/-l 0.0.0.0/' /etc/memcached.conf 2>/dev/null || true
systemctl restart memcached
enable_and_start_service memcached

# MySQL Master
log "Настройка MySQL Master..."
download_config "configs/mysql/master.cnf" "/etc/mysql/mysql.conf.d/master.cnf"
systemctl restart mysql
enable_and_start_service mysql

log "Создание пользователей..."
mysql -e "
CREATE DATABASE IF NOT EXISTS wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'wpuser'@'%' IDENTIFIED WITH mysql_native_password BY 'WpPassword2026Strong!';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'%';
CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH mysql_native_password BY 'ReplPassword2026Strong!';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;
"

sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf 2>/dev/null || true
ufw allow 3306 || true

# ======================== WORDPRESS — АВТОМАТИЧЕСКАЯ УСТАНОВКА ========================
log "Установка WordPress файлов..."
mkdir -p /var/www/html/wordpress
install_wordpress_files

cd /var/www/html/wordpress

log "Создаём wp-config.php..."
wp config create --dbname=wordpress --dbuser=wpuser --dbpass=WpPassword2026Strong! \
  --dbhost=localhost --locale=ru_RU --allow-root --skip-check || true

log "Автоматическая установка WordPress..."
wp core install --url="http://192.168.88.168" \
  --title="Мой личный блог" \
  --admin_user="admin" \
  --admin_password="AdminPassword2026Strong!" \
  --admin_email="admin@example.com" \
  --locale=ru_RU \
  --allow-root || true

chown -R www-data:www-data /var/www/html/wordpress
log "✅ WordPress установлен автоматически"

# ======================== PROMETHEUS + GRAFANA ========================
log "Настройка Prometheus + Node Exporter + Grafana..."
check_and_install prometheus prometheus-node-exporter

cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 10s
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
EOF

systemctl restart prometheus
enable_and_start_service prometheus prometheus-node-exporter

# Grafana
log "Установка Grafana..."
if ! dpkg -l | grep -q grafana; then
    wget -q https://dl.grafana.com/oss/release/grafana_11.5.2_amd64.deb
    dpkg -i grafana_11.5.2_amd64.deb || apt-get install -f -y
fi
systemctl restart grafana-server
enable_and_start_service grafana-server

download_config "configs/grafana/provisioning/datasources/prometheus.yml" "/etc/grafana/provisioning/datasources/prometheus.yml"
systemctl restart grafana-server

# ======================== ELK ========================
log "ELK через Docker..."
mkdir -p /opt/elk

cat > /opt/elk/docker-compose.yml << 'EOF'
version: '3.8'
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.17.1
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - network.host=0.0.0.0
    ports:
      - "9200:9200"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - esdata:/usr/share/elasticsearch/data
    restart: unless-stopped

  kibana:
    image: docker.elastic.co/kibana/kibana:8.17.1
    container_name: kibana
    ports:
      - "5601:5601"
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - SERVER_PUBLICBASEURL=http://192.168.88.168:5601
    depends_on:
      - elasticsearch
    restart: unless-stopped

  filebeat:
    image: docker.elastic.co/beats/filebeat:8.17.1
    container_name: filebeat
    user: "0:0"
    command: ["filebeat", "-e", "--strict.perms=false"]
    volumes:
      - /var/log:/var/log:ro
      - ./filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
    network_mode: "host"
    restart: unless-stopped

volumes:
  esdata:
EOF

cat > /opt/elk/filebeat.yml << 'EOF'
filebeat.inputs:
- type: filestream
  enabled: true
  paths:
    - /var/log/nginx/*.log
    - /var/log/apache2/*.log
    - /var/log/mysql/*.log

output.elasticsearch:
  hosts: ["http://localhost:9200"]
  index: "logs-master-%{+yyyy.MM.dd}"
EOF

cd /opt/elk
docker compose down || true
docker compose up -d
log "✅ ELK запущен (Elasticsearch + Kibana + Filebeat)"

# ======================== ФИНАЛЬНЫЙ ОТЧЁТ ========================
echo ""
echo "=================================================================="
echo "✅ MASTER УСТАНОВЛЕН УСПЕШНО!"
echo "=================================================================="
echo "WordPress:     http://192.168.88.168"
echo "   Логин:      admin"
echo "   Пароль:     AdminPassword2026Strong!"
echo ""
echo "Grafana:       http://192.168.88.168:3000   (admin / admin)"
echo "Kibana:        http://192.168.88.168:5601"
echo "Elasticsearch: http://192.168.88.168:9200"
echo "MySQL wpuser:  wpuser / WpPassword2026Strong!"
echo ""
echo "ELK должен работать — проверь Kibana в браузере"
echo "=================================================================="

log "Master восстановлен успешно."
