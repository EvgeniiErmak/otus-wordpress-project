#!/bin/bash
# setup-slave.sh — ИСПРАВЛЕНАЯ ВЕРСИЯ (решает ошибку с template)

set -euo pipefail
source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

MASTER_IP="192.168.88.168"
REPL_PASSWORD="ReplPassword2026Strong!"
MASTER_ROOT_PASSWORD="292799619531629514"

log "=== ФИНАЛЬНАЯ УСТАНОВКА SLAVE С ИСПРАВЛЕНИЕМ TEMPLATE ==="

# ... (все блоки до Filebeat — SSH, firewall, LAMP, MySQL, WordPress, sync, Node Exporter — оставь как было в предыдущей версии)

# ======================== FILEBEAT С ПРАВИЛЬНЫМ TEMPLATE ========================
log "Filebeat с исправленным template для custom index..."

mkdir -p /opt/filebeat
cat > /opt/filebeat/docker-compose.yml << 'EOF'
version: '3.8'
services:
  filebeat:
    image: docker.elastic.co/beats/filebeat:8.17.1
    user: "0:0"
    command: ["-e", "--strict.perms=false"]
    volumes:
      - /var/log:/var/log:ro
      - ./filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
    restart: unless-stopped
    network_mode: "host"
EOF

cat > /opt/filebeat/filebeat.yml << 'EOF'
filebeat.inputs:
- type: filestream
  enabled: true
  paths:
    - /var/log/nginx/*.log
    - /var/log/apache2/*.log
    - /var/log/mysql/*.log
    - /var/log/wp-sync.log

setup.template:
  enabled: true
  name: "logs-slave"
  pattern: "logs-slave-*"
  overwrite: true

output.elasticsearch:
  hosts: ["http://192.168.88.168:9200"]
  index: "logs-slave-%{+yyyy.MM.dd}"

logging.level: info
EOF

cd /opt/filebeat
docker compose down || true
docker compose up -d

# Генерируем много логов
log "Генерируем 400 тестовых логов..."
for i in {1..400}; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Test log Nginx slave #$i" >> /var/log/nginx/access.log
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Test log Apache slave #$i" >> /var/log/apache2/access.log
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Test log MySQL slave #$i" >> /var/log/mysql/error.log
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Test log WP sync slave #$i" >> /var/log/wp-sync.log
done

sleep 60

# Авто Index Pattern
log "Создаём Index Pattern в Kibana..."
curl -s -X POST "http://$MASTER_IP:5601/api/saved_objects/index-pattern/logs-*" \
  -H 'kbn-xsrf: true' \
  -H 'Content-Type: application/json' \
  -d '{"attributes":{"title":"logs-*","timeFieldName":"@timestamp"}}' > /dev/null || true

log "✅ Filebeat настроен с template + Index Pattern создан"

# ======================== ФИНАЛЬНЫЙ ОТЧЁТ ========================
echo ""
echo "=================================================================="
echo "✅ SLAVE УСТАНОВЛЕН С ИСПРАВЛЕНИЕМ TEMPLATE"
echo "=================================================================="
echo "Проверь индексы на master:"
echo "   curl -s http://192.168.88.168:9200/_cat/indices/logs*?v"
echo "Kibana: http://192.168.88.168:5601 → Discover → logs-*"
echo "Если индексов всё ещё нет — пришли вывод:"
echo "   docker logs \$(docker ps | grep filebeat | awk '{print \$1}') | tail -30"
echo "=================================================================="

log "Slave завершён успешно с исправлением template."
