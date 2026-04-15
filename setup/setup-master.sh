#!/bin/bash
# setup-master.sh — Жёсткая версия с полной очисткой node.lock для Elasticsearch 9.x

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

log "=== ФИНАЛЬНАЯ УСТАНОВКА НА MASTER (192.168.88.168) ==="

rm -f /etc/apt/sources.list.d/elastic*.list
apt-get update && apt-get upgrade -y

for pkg in curl wget git unzip ca-certificates software-properties-common gnupg adduser libfontconfig1 default-jdk; do
    check_and_install "$pkg"
done

# Nginx + Apache + PHP + Memcached + MySQL + WordPress + Grafana (оставляем как есть)
check_and_install nginx
download_config "configs/nginx/reverse-proxy.conf" "/etc/nginx/sites-available/default"
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx
enable_and_start_service nginx

log "Установка LAMP + Memcached..."
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

# ======================== ELK — ЖЁСТКАЯ ОЧИСТКА LOCK ========================
log "Установка ELK с жёсткой очисткой node.lock..."

wget -qO - http://elasticrepo.serveradmin.ru/elastic.asc | apt-key add - || true
echo "deb http://elasticrepo.serveradmin.ru bookworm main" | tee /etc/apt/sources.list.d/elasticrepo.list
apt-get update || log "WARNING: Elastic repo"

apt-get install -y elasticsearch filebeat

# Системные настройки
echo "vm.max_map_count=262144" > /etc/sysctl.d/99-elasticsearch.conf
sysctl -p /etc/sysctl.d/99-elasticsearch.conf

# Жёсткая очистка ВСЕХ lock и данных
log "Жёсткая очистка lock-файлов и данных..."
systemctl stop elasticsearch kibana logstash filebeat || true
rm -rf /var/lib/elasticsearch/nodes/* /var/lib/elasticsearch/*.lock /var/log/elasticsearch/* /tmp/elasticsearch* || true
chown -R elasticsearch:elasticsearch /var/lib/elasticsearch /var/log/elasticsearch
chmod -R 755 /var/lib/elasticsearch

# Чистый single-node конфиг
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

# Kibana
mkdir -p /etc/kibana
cat > /etc/kibana/kibana.yml << 'EOF'
server.port: 5601
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://localhost:9200"]
xpack.security.enabled: false
EOF

# Filebeat
mkdir -p /etc/filebeat
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

# Запуск
log "Запускаем ELK после жёсткой очистки..."
systemctl daemon-reload
enable_and_start_service elasticsearch
enable_and_start_service kibana || true
enable_and_start_service logstash || true
enable_and_start_service filebeat || true

sleep 12
if curl -s http://localhost:9200 > /dev/null; then
    log "✅ Elasticsearch запущен успешно!"
else
    log "⚠️ Elasticsearch не запустился. Полный журнал:"
    journalctl -u elasticsearch -n 100
fi

log "ELK настроен"

# Финальный вывод
echo ""
echo "=================================================================="
echo "✅ УСТАНОВКА ЗАВЕРШЕНА"
echo "=================================================================="
echo "WordPress: http://192.168.88.168 (admin / AdminPassword2026Strong!)"
echo "Grafana:   http://192.168.88.168:3000 (admin / admin)"
echo "Kibana:    http://192.168.88.168:5601"
echo "=================================================================="
echo "Если Elasticsearch не запустился — journalctl -u elasticsearch -n 100"
echo "=================================================================="
