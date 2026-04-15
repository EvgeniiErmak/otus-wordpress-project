#!/bin/bash
# setup-master.sh — Полная установка ELK 9.3.3 прямыми .deb с официального сайта (ничего не исключено)

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

log "=== ФИНАЛЬНАЯ УСТАНОВКА НА MASTER (192.168.88.168) ==="

rm -f /etc/apt/sources.list.d/elastic*.list
apt-get update && apt-get upgrade -y

for pkg in curl wget git unzip ca-certificates software-properties-common gnupg adduser libfontconfig1 default-jdk; do
    check_and_install "$pkg"
done

# 1. Nginx
check_and_install nginx
download_config "configs/nginx/reverse-proxy.conf" "/etc/nginx/sites-available/default"
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx
enable_and_start_service nginx

# 2. Apache + PHP + Memcached + MySQL
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

# ======================== ELK 9.3.3 — ПРЯМЫЕ .DEB С ОФИЦИАЛЬНОГО CDN ========================
log "Установка ELK 9.3.3 прямыми .deb с artifacts.elastic.co..."

cd /tmp

log "Скачиваем Elasticsearch 9.3.3..."
wget --continue --timeout=180 --show-progress -q https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-9.3.3-amd64.deb -O elasticsearch-9.3.3-amd64.deb
dpkg -i elasticsearch-9.3.3-amd64.deb || apt-get install -f -y

log "Скачиваем Kibana 9.3.3..."
wget --continue --timeout=180 --show-progress -q https://artifacts.elastic.co/downloads/kibana/kibana-9.3.3-amd64.deb -O kibana-9.3.3-amd64.deb
dpkg -i kibana-9.3.3-amd64.deb || apt-get install -f -y

log "Скачиваем Logstash 9.3.3..."
wget --continue --timeout=180 --show-progress -q https://artifacts.elastic.co/downloads/logstash/logstash-9.3.3-amd64.deb -O logstash-9.3.3-amd64.deb
dpkg -i logstash-9.3.3-amd64.deb || apt-get install -f -y

log "Скачиваем Filebeat 9.3.3..."
wget --continue --timeout=180 --show-progress -q https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-9.3.3-amd64.deb -O filebeat-9.3.3-amd64.deb
dpkg -i filebeat-9.3.3-amd64.deb || apt-get install -f -y

# Системные настройки
echo "vm.max_map_count=262144" > /etc/sysctl.d/99-elasticsearch.conf
sysctl -p /etc/sysctl.d/99-elasticsearch.conf

# Жёсткая очистка
log "Жёсткая очистка lock-файлов и данных..."
systemctl stop elasticsearch kibana logstash filebeat || true
rm -rf /var/lib/elasticsearch/nodes/* /var/lib/elasticsearch/*.lock /var/log/elasticsearch/* || true
chown -R elasticsearch:elasticsearch /var/lib/elasticsearch /var/log/elasticsearch

# Конфиги
log "Настройка конфигов ELK 9.3.3..."
cat > /etc/elasticsearch/elasticsearch.yml << 'EOF'
cluster.name: otus-elk
node.name: otus-master
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 0.0.0.0
http.port: 9200
xpack.security.enabled: false
discovery.type: single-node
node.max_local_storage_nodes: 1
EOF

cat > /etc/kibana/kibana.yml << 'EOF'
server.port: 5601
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://localhost:9200"]
xpack.security.enabled: false
EOF

cat > /etc/filebeat/filebeat.yml << 'EOF'
filebeat.inputs:
- type: filestream
  enabled: true
  paths:
    - /var/log/nginx/*.log
    - /var/log/apache2/*.log
    - /var/log/mysql/*.log
output.elasticsearch:
  hosts: ["localhost:9200"]
  index: "logs-%{+yyyy.MM.dd}"
EOF

systemctl daemon-reload
enable_and_start_service elasticsearch
enable_and_start_service kibana || true
enable_and_start_service logstash || true
enable_and_start_service filebeat || true

log "ELK 9.3.3 установлен"

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
