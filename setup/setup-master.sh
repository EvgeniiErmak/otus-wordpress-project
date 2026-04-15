#!/bin/bash
# setup-master.sh — Полная установка на MASTER с ELK через зеркало elasticrepo.serveradmin.ru

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

log "=== ФИНАЛЬНАЯ УСТАНОВКА НА MASTER (192.168.88.168) ==="

# Принудительно удаляем старый Elastic репозиторий
rm -f /etc/apt/sources.list.d/elastic*.list /etc/apt/sources.list.d/elasticrepo.list
log "Старые Elastic репозитории удалены"

apt-get update && apt-get upgrade -y

# Базовые пакеты
for pkg in curl wget git unzip ca-certificates software-properties-common gnupg adduser libfontconfig1 default-jdk; do
    check_and_install "$pkg"
done

# 1. Nginx Reverse Proxy
check_and_install nginx
download_config "configs/nginx/reverse-proxy.conf" "/etc/nginx/sites-available/default"
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx
enable_and_start_service nginx

# 2. Apache + PHP + Memcached + MySQL
log "Установка Apache, PHP, Memcached и MySQL..."
apt-get install -y apache2 php8.3 php8.3-fpm php8.3-mysql php8.3-memcached php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml php8.3-zip memcached mysql-server

# ports.conf
log "Исправляем /etc/apache2/ports.conf..."
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

# Memcached
log "Настройка Memcached..."
sed -i 's/^-l 127.0.0.1/-l 0.0.0.0/' /etc/memcached.conf 2>/dev/null || true
systemctl restart memcached
enable_and_start_service memcached

# MySQL Master
setup_mysql_master

# WordPress
install_wordpress_files
auto_install_wordpress

# Prometheus + Grafana
check_and_install prometheus prometheus-node-exporter
log "Установка Grafana через .deb..."
cd /tmp
wget -q https://dl.grafana.com/oss/release/grafana_11.5.2_amd64.deb -O grafana.deb
dpkg -i grafana.deb || apt-get install -f -y
rm -f grafana.deb

download_config "configs/grafana/provisioning/datasources/prometheus.yml" "/etc/grafana/provisioning/datasources/prometheus.yml"
systemctl daemon-reload
systemctl restart grafana-server
enable_and_start_service grafana-server

# ======================== ELK через зеркало elasticrepo.serveradmin.ru ========================
log "Установка ELK Stack через зеркало elasticrepo.serveradmin.ru..."

# Импорт ключа зеркала
wget -qO - http://elasticrepo.serveradmin.ru/elastic.asc | apt-key add -

# Добавление репозитория (для Ubuntu 24.04 — используем bookworm как ближайший)
echo "deb http://elasticrepo.serveradmin.ru bookworm main" | tee /etc/apt/sources.list.d/elasticrepo.list

apt-get update || log "WARNING: apt update с зеркалом Elastic завершился с предупреждением"

check_and_install elasticsearch kibana logstash filebeat

# Простая конфигурация ELK (без security для теста)
log "Настройка конфигурации ELK..."

cat > /etc/elasticsearch/elasticsearch.yml << 'EOF'
cluster.name: otus-elk
node.name: otus-master
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 0.0.0.0
http.port: 9200
xpack.security.enabled: false
cluster.initial_master_nodes: ["otus-master"]
EOF

cat > /etc/kibana/kibana.yml << 'EOF'
server.port: 5601
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://localhost:9200"]
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
enable_and_start_service kibana
enable_and_start_service logstash
enable_and_start_service filebeat

log "ELK установлен через зеркало elasticrepo.serveradmin.ru"

# ======================== ФИНАЛЬНЫЙ ВЫВОД ========================
echo ""
echo "=================================================================="
echo "✅ УСТАНОВКА НА MASTER ЗАВЕРШЕНА УСПЕШНО!"
echo "=================================================================="
echo "WordPress:"
echo "   URL:      http://192.168.88.168"
echo "   Логин:    admin"
echo "   Пароль:   AdminPassword2026Strong!"
echo ""
echo "Grafana:"
echo "   URL:      http://192.168.88.168:3000"
echo "   Логин:    admin"
echo "   Пароль:   admin"
echo ""
echo "Kibana (ELK):"
echo "   URL:      http://192.168.88.168:5601"
echo ""
echo "Elasticsearch: http://192.168.88.168:9200"
echo "MySQL wpuser: wpuser / WpPassword2026Strong!"
echo "=================================================================="
echo "Все компоненты (включая ELK) установлены."
echo "=================================================================="
