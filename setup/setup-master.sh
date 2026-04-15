#!/bin/bash
# setup-master.sh — Docker-based ELK (быстро, стабильно, без тяжёлых .deb)

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

log "=== ФИНАЛЬНАЯ УСТАНОВКА НА MASTER (192.168.88.168) ==="

# Базовые пакеты + Docker
for pkg in curl wget git unzip ca-certificates gnupg; do
    check_and_install "$pkg"
done

# Установка Docker (если нет)
if ! command -v docker &> /dev/null; then
    log "Устанавливаем Docker..."
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker root
    systemctl enable --now docker
fi

check_and_install docker-compose

# Nginx + Apache + PHP + Memcached + MySQL + WordPress + Grafana (остаются как есть)
check_and_install nginx
download_config "configs/nginx/reverse-proxy.conf" "/etc/nginx/sites-available/default"
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx
enable_and_start_service nginx

log "Установка Apache, PHP, Memcached и MySQL..."
apt-get install -y apache2 php8.3 php8.3-fpm php8.3-mysql php8.3-memcached php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml php8.3-zip memcached mysql-server

log "Исправляем ports.conf..."
cat > /etc/apache2/ports.conf << 'EOF'
Listen 8080
<IfModule ssl_module>
    Listen 443
</IfModule>
<IfModule mod_gnutls.c>
    Listen 443
</IfModule>
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

setup_mysql_master
install_wordpress_files
auto_install_wordpress

# Grafana + авто-дашборд
check_and_install prometheus prometheus-node-exporter
log "Grafana..."
cd /tmp
wget -q https://dl.grafana.com/oss/release/grafana_11.5.2_amd64.deb -O grafana.deb
dpkg -i grafana.deb || apt-get install -f -y
rm -f grafana.deb
download_config "configs/grafana/provisioning/datasources/prometheus.yml" "/etc/grafana/provisioning/datasources/prometheus.yml"

mkdir -p /etc/grafana/provisioning/dashboards /var/lib/grafana/dashboards
cat << 'EOF' > /etc/grafana/provisioning/dashboards/node-exporter.yml
apiVersion: 1
providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards
EOF
wget -q -O /var/lib/grafana/dashboards/node-exporter-full.json https://grafana.com/api/dashboards/1860/revisions/1/download || true
chown -R grafana:grafana /var/lib/grafana
systemctl daemon-reload
systemctl restart grafana-server
enable_and_start_service grafana-server

# ======================== ELK через Docker (быстро и стабильно) ========================
log "Установка ELK через Docker (Elasticsearch 8.17.1 + Kibana + Filebeat)..."

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
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - esdata:/usr/share/elasticsearch/data
    ports:
      - "9200:9200"
    restart: unless-stopped

  kibana:
    image: docker.elastic.co/kibana/kibana:8.17.1
    container_name: kibana
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - xpack.security.enabled=false
    ports:
      - "5601:5601"
    depends_on:
      - elasticsearch
    restart: unless-stopped

  filebeat:
    image: docker.elastic.co/beats/filebeat:8.17.1
    container_name: filebeat
    command: ["-e", "--strict.perms=false"]
    volumes:
      - /var/log:/var/log:ro
      - ./filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
    depends_on:
      - elasticsearch
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
  index: "logs-%{+yyyy.MM.dd}"
EOF

cd /opt/elk
docker compose up -d

log "ELK запущен через Docker (8.17.1)"

# Финальный вывод
echo ""
echo "=================================================================="
echo "✅ УСТАНОВКА ЗАВЕРШЕНА!"
echo "=================================================================="
echo "WordPress:     http://192.168.88.168      admin / AdminPassword2026Strong!"
echo "Grafana:       http://192.168.88.168:3000  admin / admin"
echo "Kibana:        http://192.168.88.168:5601"
echo "Elasticsearch: http://192.168.88.168:9200"
echo "=================================================================="
echo "Все компоненты (включая полный ELK) запущены автоматически."
echo "=================================================================="
