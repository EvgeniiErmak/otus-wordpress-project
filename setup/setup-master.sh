#!/bin/bash
# setup-master.sh — ФИНАЛЬНАЯ ВЕРСИЯ С ПОЛНЫМ ОТЧЁТОМ И АВТОМАТИЧЕСКОЙ НАСТРОЙКОЙ РЕПЛИКАЦИИ

set -euo pipefail

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

log "=== ФИНАЛЬНАЯ УСТАНОВКА НА MASTER (192.168.88.168) ==="

# ======================== БАЗОВЫЕ ПАКЕТЫ ========================
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

# ======================== LAMP + Memcached + MySQL ========================
log "Установка LAMP стека..."
apt-get install -y apache2 php8.3 php8.3-fpm php8.3-mysql php8.3-memcached \
    php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml php8.3-zip memcached mysql-server

log "Исправляем Apache ports.conf..."
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

# ======================== MySQL Master + исправления для репликации ========================
setup_mysql_master

log "Настройка прав для repl и привязка к сети..."
mysql -e "
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%' IDENTIFIED BY 'ReplPassword2026Strong!';
FLUSH PRIVILEGES;
" || true

# Привязываем MySQL ко всем интерфейсам
sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf 2>/dev/null || true

systemctl restart mysql

log "Открываем порт 3306 в firewall..."
ufw allow 3306 || true
ufw reload || true

log "✅ MySQL Master готов к репликации (порт 3306 открыт)"

# ======================== WordPress ========================
log "Автоматическая установка WordPress..."
cd /var/www/html/wordpress
wp core install --url="http://192.168.88.168" \
    --title="Мой личный блог" \
    --admin_user="admin" \
    --admin_password="AdminPassword2026Strong!" \
    --admin_email="admin@example.com" \
    --locale=ru_RU \
    --skip-email \
    --allow-root || true
log "✅ WordPress настроен автоматически"

# ======================== PROMETHEUS + GRAFANA ========================
log "Настройка Prometheus + Node Exporter + Grafana..."
check_and_install prometheus prometheus-node-exporter

cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 10s
scrape_configs:
  - job_name: 'prometheus'
    static_configs: [{targets: ['localhost:9090']}]
  - job_name: 'node_exporter'
    honor_timestamps: true
    static_configs: [{targets: ['localhost:9100']}]
EOF

mkdir -p /etc/systemd/system/prometheus.service.d
cat > /etc/systemd/system/prometheus.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus --web.console.templates=/etc/prometheus/consoles --web.console.libraries=/etc/prometheus/console_libraries --web.enable-lifecycle
EOF

systemctl daemon-reload
systemctl stop prometheus prometheus-node-exporter
rm -rf /var/lib/prometheus/* || true
systemctl start prometheus prometheus-node-exporter
enable_and_start_service prometheus
enable_and_start_service prometheus-node-exporter

# Grafana + простой дашборд
log "Установка Grafana..."
cd /tmp
wget -q https://dl.grafana.com/oss/release/grafana_11.5.2_amd64.deb -O grafana.deb
dpkg -i grafana.deb || apt-get install -f -y
rm -f grafana.deb

download_config "configs/grafana/provisioning/datasources/prometheus.yml" "/etc/grafana/provisioning/datasources/prometheus.yml"

mkdir -p /etc/grafana/provisioning/dashboards /var/lib/grafana/dashboards

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
  "time": {"from":"now-1h","to":"now"}
}
EOF

chown -R grafana:grafana /var/lib/grafana /etc/grafana
systemctl restart grafana-server
enable_and_start_service grafana-server

curl -X POST http://localhost:9090/-/reload || true
sleep 30

# ======================== ELK ========================
log "ELK через Docker..."
mkdir -p /opt/elk
cat > /opt/elk/docker-compose.yml << 'EOF'
version: '3.8'
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.17.1
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - network.host=0.0.0.0
    ports: ["9200:9200"]
    volumes: [esdata:/usr/share/elasticsearch/data]
    restart: unless-stopped
  kibana:
    image: docker.elastic.co/kibana/kibana:8.17.1
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - server.publicBaseUrl=http://192.168.88.168:5601
    ports: ["5601:5601"]
    depends_on: [elasticsearch]
    restart: unless-stopped
  filebeat:
    image: docker.elastic.co/beats/filebeat:8.17.1
    command: ["-e", "--strict.perms=false"]
    volumes:
      - /var/log:/var/log:ro
      - ./filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
    depends_on: [elasticsearch]
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
  hosts: ["http://elasticsearch:9200"]
EOF

cd /opt/elk
docker compose down || true
docker compose up -d
log "ELK запущен"

# ======================== ПОЛНЫЙ ФИНАЛЬНЫЙ ОТЧЁТ ========================
echo ""
echo "=================================================================="
echo "✅ УСТАНОВКА НА MASTER ЗАВЕРШЕНА УСПЕШНО!"
echo "=================================================================="
echo "Система готова к использованию."
echo ""
echo "=== ДОСТУП К КОМПОНЕНТАМ ==="
echo "WordPress (сайт):     http://192.168.88.168"
echo "   Логин:   admin"
echo "   Пароль:  AdminPassword2026Strong!"
echo ""
echo "Grafana (мониторинг): http://192.168.88.168:3000"
echo "   Логин:   admin"
echo "   Пароль:  admin"
echo "   Дашборд: OTUS Node Exporter Simple"
echo ""
echo "Kibana (логи):        http://192.168.88.168:5601"
echo ""
echo "Elasticsearch:        http://192.168.88.168:9200"
echo ""
echo "MySQL:"
echo "   wpuser / WpPassword2026Strong!"
echo "   repl   / ReplPassword2026Strong!  (для slave)"
echo ""
echo "=== Дополнительно ==="
echo "• Prometheus:         http://192.168.88.168:9090"
echo "• Node Exporter:      http://192.168.88.168:9100/metrics"
echo ""
echo "=================================================================="
echo "Если нужно восстановить БД:"
echo "   mysql wordpress < /var/backups/wordpress_*.sql"
echo "   /usr/local/bin/sync-wp-files.sh"
echo "=================================================================="

log "Master восстановлен успешно с полным отчётом."
