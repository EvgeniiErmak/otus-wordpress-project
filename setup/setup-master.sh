#!/bin/bash
# setup/setup-master.sh — МАКСИМАЛЬНО ПОЛНЫЙ ВАРИАНТ С ДАШБОРДОМ GRAFANA

set -euo pipefail

echo "[$(date '+%Y-%m-%d %H:%M:%S')] === ФИНАЛЬНАЯ УСТАНОВКА НА MASTER (192.168.88.168) ==="

# 1. БАЗОВЫЕ ПАКЕТЫ
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Установка базовых пакетов..."
apt-get update -qq
apt-get install -y curl wget git unzip ca-certificates gnupg apt-transport-https software-properties-common

# 2. DOCKER
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Установка Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi
apt-get install -y docker-compose-plugin

# 3. NGINX REVERSE PROXY
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Установка и настройка Nginx..."
apt-get install -y nginx
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/configs/nginx/reverse-proxy.conf -o /etc/nginx/sites-available/default
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx
systemctl enable nginx
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Nginx успешно запущен"

# 4. LAMP + MEMCACHED + MYSQL
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Установка Apache + PHP 8.3 + Memcached + MySQL..."
apt-get install -y apache2 \
    php8.3 php8.3-fpm php8.3-mysql php8.3-memcached \
    php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml php8.3-zip \
    memcached mysql-server

# Apache на 8080
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Настройка Apache на порт 8080..."
cat > /etc/apache2/ports.conf << 'EOF'
Listen 8080
EOF
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/configs/apache/wordpress.conf -o /etc/apache2/sites-available/wordpress.conf
a2ensite wordpress
a2dissite 000-default
a2enmod proxy_fcgi setenvif rewrite
a2enconf php8.3-fpm
systemctl restart apache2
systemctl enable apache2
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Apache успешно запущен"

# Memcached
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Настройка Memcached..."
sed -i 's/-l 127.0.0.1/-l 0.0.0.0/' /etc/memcached.conf
systemctl restart memcached
systemctl enable memcached

# MySQL Master
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Настройка MySQL Master..."
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/configs/mysql/master.cnf -o /etc/mysql/mysql.conf.d/master.cnf
systemctl restart mysql

mysql -e "
CREATE DATABASE IF NOT EXISTS wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'wpuser'@'%' IDENTIFIED BY 'WpPassword2026Strong!';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'%';
CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH mysql_native_password BY 'ReplPassword2026Strong!';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;
"

# WP-CLI
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Установка WP-CLI..."
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# WordPress
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Установка WordPress..."
mkdir -p /var/www/html/wordpress
cd /var/www/html/wordpress

if [ ! -f wp-config-sample.php ]; then
    wget -q https://ru.wordpress.org/latest-ru_RU.tar.gz
    tar -xzf latest-ru_RU.tar.gz --strip-components=1
    rm latest-ru_RU.tar.gz
fi

wp config create \
    --dbname=wordpress \
    --dbuser=wpuser \
    --dbpass=WpPassword2026Strong! \
    --dbhost=localhost \
    --locale=ru_RU \
    --force \
    --skip-check \
    --allow-root

wp core install \
    --url=http://192.168.88.168 \
    --title="Мой личный блог" \
    --admin_user=admin \
    --admin_password=AdminPassword2026Strong! \
    --admin_email=admin@example.com \
    --locale=ru_RU \
    --skip-email \
    --allow-root

chown -R www-data:www-data /var/www/html/wordpress
chmod -R 755 /var/www/html/wordpress

echo "[$(date '+%Y-%m-%d %H:%M:%S')] WordPress установлен полностью автоматически!"

# Prometheus + Node Exporter
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Установка Prometheus + Node Exporter..."
apt-get install -y prometheus prometheus-node-exporter
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/configs/prometheus/prometheus.yml -o /etc/prometheus/prometheus.yml
systemctl restart prometheus prometheus-node-exporter
systemctl enable prometheus prometheus-node-exporter

# Grafana + ДАШБОРД
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Установка Grafana..."
if ! dpkg -l | grep -q grafana; then
    wget -q https://dl.grafana.com/oss/release/grafana_11.5.2_amd64.deb
    dpkg -i grafana_11.5.2_amd64.deb || apt-get install -f -y
fi
systemctl enable --now grafana-server

curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/configs/grafana/provisioning/datasources/prometheus.yml -o /etc/grafana/provisioning/datasources/prometheus.yml

# Создаём простой дашборд Node Exporter
mkdir -p /etc/grafana/provisioning/dashboards
cat > /etc/grafana/provisioning/dashboards/node-exporter.json << 'EOF'
{
  "title": "OTUS Node Exporter Simple",
  "tags": ["node-exporter"],
  "panels": [
    {
      "title": "CPU Usage",
      "type": "stat",
      "targets": [{ "expr": "100 - (avg by (instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)" }]
    },
    {
      "title": "Memory Usage",
      "type": "stat",
      "targets": [{ "expr": "node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes" }]
    },
    {
      "title": "Load Average",
      "type": "stat",
      "targets": [{ "expr": "node_load1" }]
    }
  ]
}
EOF

systemctl restart grafana-server

# ELK Stack
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Установка ELK Stack..."
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
    ports:
      - "9200:9200"
    ulimits:
      memlock: -1
      nofile: 65536
    restart: unless-stopped

  kibana:
    image: docker.elastic.co/kibana/kibana:8.17.1
    container_name: kibana
    ports:
      - "5601:5601"
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    depends_on:
      - elasticsearch
    restart: unless-stopped

  filebeat:
    image: docker.elastic.co/beats/filebeat:8.17.1
    container_name: filebeat
    user: "0:0"
    network_mode: "host"
    volumes:
      - /var/log:/var/log:ro
      - ./filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
    depends_on:
      - elasticsearch
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
docker compose up -d

# ФИНАЛЬНЫЙ ОТЧЁТ
echo ""
echo "=================================================================="
echo "✅ УСТАНОВКА НА MASTER ЗАВЕРШЕНА УСПЕШНО!"
echo "=================================================================="
echo "WordPress:     http://192.168.88.168"
echo "   Логин:      admin"
echo "   Пароль:     AdminPassword2026Strong!"
echo ""
echo "Nginx:         http://192.168.88.168"
echo "Grafana:       http://192.168.88.168:3000   (admin / admin) — дашборд OTUS Node Exporter Simple"
echo "Kibana:        http://192.168.88.168:5601"
echo "Elasticsearch: http://192.168.88.168:9200"
echo ""
echo "MySQL:"
echo "   wpuser / WpPassword2026Strong!"
echo "   repl  / ReplPassword2026Strong!"
echo "=================================================================="

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Master восстановлен успешно."
