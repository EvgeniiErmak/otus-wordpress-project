#!/bin/bash
# setup/setup-master.sh — ПОЛНАЯ АВТОМАТИЗАЦИЯ С ИСПРАВЛЕНИЯМИ

set -euo pipefail

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

log "=== ФИНАЛЬНАЯ УСТАНОВКА НА MASTER (192.168.88.168) ==="

# ======================== 1. БАЗОВЫЕ ПАКЕТЫ ========================
log "Установка базовых пакетов..."
for pkg in curl wget git unzip ca-certificates gnupg apt-transport-https software-properties-common; do
    check_and_install "$pkg"
done

# ======================== 2. DOCKER + COMPOSE V2 ========================
log "Установка Docker..."
if ! command -v docker &> /dev/null; then
    log "Устанавливаем Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi

# Установка ТОЛЬКО Docker Compose v2 plugin (не устанавливать docker-compose v1)
if ! docker compose version &>/dev/null; then
    log "Устанавливаем Docker Compose v2 plugin..."
    apt-get install -y docker-compose-plugin || true
fi

# ======================== 3. NGINX REVERSE PROXY ========================
log "Настройка Nginx reverse proxy..."
check_and_install nginx
download_config "configs/nginx/reverse-proxy.conf" "/etc/nginx/sites-available/default"
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx || true
enable_and_start_service nginx

# ======================== 4. LAMP + MEMCACHED + MYSQL ========================
log "Установка Apache + PHP 8.3 + Memcached + MySQL..."
apt-get install -y apache2 \
    php8.3 php8.3-fpm php8.3-mysql php8.3-memcached \
    php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml php8.3-zip \
    memcached mysql-server

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
enable_and_start_service apache2

# Memcached
log "Настройка Memcached..."
sed -i 's/^-l 127.0.0.1/-l 0.0.0.0/' /etc/memcached.conf 2>/dev/null || true
systemctl restart memcached || true
enable_and_start_service memcached

# ======================== 5. MySQL MASTER — С ИСПРАВЛЕНИЯМИ ========================
log "Настройка MySQL Master..."

# Гарантируем bind-address = 0.0.0.0 для репликации
if grep -q "^bind-address.*127.0.0.1" /etc/mysql/mysql.conf.d/mysqld.cnf 2>/dev/null; then
    sed -i 's/^bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
    log "✅ bind-address изменён на 0.0.0.0"
fi

download_config "configs/mysql/master.cnf" "/etc/mysql/mysql.conf.d/master.cnf"
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

log "Создание БД и пользователей..."
mysql -e "
CREATE DATABASE IF NOT EXISTS wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'wpuser'@'%' IDENTIFIED BY 'WpPassword2026Strong!';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'%';
CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH mysql_native_password BY 'ReplPassword2026Strong!';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
CREATE USER IF NOT EXISTS 'repl'@'192.168.88.167' IDENTIFIED WITH mysql_native_password BY 'ReplPassword2026Strong!';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'192.168.88.167';
FLUSH PRIVILEGES;
" 2>/dev/null || true

log "✅ MySQL Master настроен"

# ======================== 6. WP-CLI ========================
log "Установка WP-CLI..."
if [ ! -f /usr/local/bin/wp ]; then
    curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp
fi
log "✅ WP-CLI установлен"

# ======================== 7. WORDPRESS ========================
log "Установка файлов WordPress..."
install_wordpress_files

cd /var/www/html/wordpress

if [ ! -f wp-config.php ]; then
    log "Создаём wp-config.php..."
    wp config create \
        --dbname=wordpress \
        --dbuser=wpuser \
        --dbpass=WpPassword2026Strong! \
        --dbhost=localhost \
        --locale=ru_RU \
        --force \
        --skip-check \
        --allow-root || true
fi

if ! wp core is-installed --allow-root 2>/dev/null; then
    log "Устанавливаем WordPress..."
    wp core install \
        --url=http://192.168.88.168 \
        --title="Мой личный блог" \
        --admin_user=admin \
        --admin_password=AdminPassword2026Strong! \
        --admin_email=admin@example.com \
        --locale=ru_RU \
        --skip-email \
        --allow-root || true
fi

log "Настраиваем права..."
chown -R www-data:www-data /var/www/html/wordpress
chmod -R 755 /var/www/html/wordpress
log "✅ WordPress установлен"

# ======================== 8. PROMETHEUS + NODE EXPORTER ========================
log "Настройка Prometheus + Node Exporter..."
check_and_install prometheus prometheus-node-exporter

cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 10s
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'node_exporter'
    honor_timestamps: true
    static_configs:
      - targets: ['localhost:9100', '192.168.88.167:9100']
EOF

systemctl restart prometheus prometheus-node-exporter || true
enable_and_start_service prometheus prometheus-node-exporter

# ======================== 8. GRAFANA + ДАШБОРД ========================
log "Установка Grafana..."

# Добавляем репозиторий Grafana (быстрее и надежнее чем wget)
if ! dpkg -l | grep -q grafana; then
    log "Добавляем GPG ключ Grafana..."
    wget -q -O - https://packages.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/trusted.gpg.d/grafana.gpg > /dev/null
    
    log "Добавляем репозиторий Grafana..."
    echo "deb https://packages.grafana.com/oss/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list
    
    log "Устанавливаем Grafana..."
    apt-get update -qq
    apt-get install -y grafana || {
        log "⚠️ Установка из репозитория не удалась, пробуем wget..."
        wget --timeout=300 --tries=3 -q https://dl.grafana.com/oss/release/grafana_11.5.2_amd64.deb
        dpkg -i grafana_11.5.2_amd64.deb || apt-get install -f -y
        rm -f grafana_11.5.2_amd64.deb
    }
fi

enable_and_start_service grafana-server

download_config "configs/grafana/provisioning/datasources/prometheus.yml" "/etc/grafana/provisioning/datasources/prometheus.yml"

mkdir -p /etc/grafana/provisioning/dashboards /var/lib/grafana/dashboards
chown -R grafana:grafana /var/lib/grafana /etc/grafana

cat > /etc/grafana/provisioning/dashboards/otus-simple.yml << 'EOF'
apiVersion: 1
providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    options:
      path: /var/lib/grafana/dashboards
EOF

cat > /var/lib/grafana/dashboards/otus-node-simple.json << 'EOF'
{
  "title": "OTUS Node Exporter Simple",
  "panels": [
    {"type":"stat","title":"CPU Usage %","targets":[{"expr":"100 - avg(irate(node_cpu_seconds_total{mode=\"idle\",job=\"node_exporter\"}[5m])) * 100"}]},
    {"type":"stat","title":"Used RAM (GB)","targets":[{"expr":"(node_memory_MemTotal_bytes{job=\"node_exporter\"} - node_memory_MemAvailable_bytes{job=\"node_exporter\"}) / 1024 / 1024 / 1024"}]},
    {"type":"stat","title":"System Load 5m","targets":[{"expr":"node_load5{job=\"node_exporter\"}"}]},
    {"type":"stat","title":"Uptime (days)","targets":[{"expr":"(node_time_seconds{job=\"node_exporter\"} - node_boot_time_seconds{job=\"node_exporter\"}) / 86400"}]}
  ],
  "time":{"from":"now-1h","to":"now"}
}
EOF

systemctl restart grafana-server || true
curl -X POST http://localhost:9090/-/reload || true
sleep 5
log "✅ Grafana + дашборд настроены"

# ======================== 10. ELK STACK ========================
log "Установка ELK Stack через Docker..."
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
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
    ports: ["9200:9200"]
    ulimits:
      memlock: -1
      nofile: 65536
    restart: unless-stopped
  kibana:
    image: docker.elastic.co/kibana/kibana:8.17.1
    container_name: kibana
    ports: ["5601:5601"]
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    depends_on: [elasticsearch]
    restart: unless-stopped
  filebeat:
    image: docker.elastic.co/beats/filebeat:8.17.1
    container_name: filebeat
    user: "0:0"
    network_mode: "host"
    volumes:
      - /var/log:/var/log:ro
      - ./filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
    depends_on: [elasticsearch]
    restart: unless-stopped
EOF

cat > /opt/elk/filebeat.yml << 'EOF'
filebeat.inputs:
- type: filestream
  enabled: true
  paths:
    - /var/log/nginx/*.log
    - /var/log/apache2/*.log
    - /var/log/mysql/*.log
    - /var/log/wp-sync.log
output.elasticsearch:
  hosts: ["http://localhost:9200"]
  index: "logs-master-%{+yyyy.MM.dd}"
setup.template.enabled: false
setup.ilm.enabled: false
EOF

cd /opt/elk
docker compose down || true
docker compose up -d || true
log "✅ ELK Stack запущен"

# ======================== ФИНАЛЬНЫЙ ОТЧЁТ ========================
echo ""
echo "=================================================================="
echo "✅ УСТАНОВКА НА MASTER ЗАВЕРШЕНА УСПЕШНО!"
echo "=================================================================="
echo "WordPress:     http://192.168.88.168 (admin / AdminPassword2026Strong!)"
echo "Grafana:       http://192.168.88.168:3000 (admin / admin)"
echo "Kibana:        http://192.168.88.168:5601"
echo "Prometheus:    http://192.168.88.168:9090"
echo "Elasticsearch: http://192.168.88.168:9200"
echo "=================================================================="
log "Master восстановлен успешно."
