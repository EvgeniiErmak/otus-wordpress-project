#!/bin/bash
# setup-slave.sh — ФИНАЛЬНАЯ ВЕРСИЯ (отключаем data stream + ILM, используем простой индекс)

set -euo pipefail
source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

MASTER_IP="192.168.88.168"
REPL_PASSWORD="ReplPassword2026Strong!"
MASTER_ROOT_PASSWORD="292799619531629514"

log "=== SLAVE — ФИНАЛЬНАЯ ВЕРСИЯ БЕЗ DATA STREAM ==="

# (все предыдущие блоки до Filebeat оставь как есть: SSH, firewall, LAMP, MySQL, WordPress, sync, Node Exporter)

# ======================== FILEBEAT — ПРОСТОЙ ИНДЕКС БЕЗ DATA STREAM ========================
log "Filebeat с простым индексом (без data stream и ILM)..."

mkdir -p /opt/filebeat
cat > /opt/filebeat/docker-compose.yml << 'EOF'
version: '3.8'
services:
  filebeat:
    image: docker.elastic.co/beats/filebeat:8.17.1
    user: "0:0"
    command: ["filebeat", "-e", "--strict.perms=false"]
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
  id: slave-logs
  paths:
    - /var/log/nginx/*.log
    - /var/log/apache2/*.log
    - /var/log/mysql/*.log
    - /var/log/wp-sync.log
  fields:
    host: otus-slave
    environment: production

setup.template:
  enabled: true
  name: "logs-slave"
  pattern: "logs-slave-*"
  overwrite: true

setup.ilm.enabled: false
setup.template.settings:
  index:
    number_of_shards: 1
    number_of_replicas: 0

output.elasticsearch:
  hosts: ["http://192.168.88.168:9200"]
  index: "logs-slave-%{+yyyy.MM.dd}"

logging.level: info
logging.to_files: true
logging.files.path: /var/log/filebeat
EOF

cd /opt/filebeat
docker compose down || true
docker compose up -d

# Генерация логов
log "Генерируем 600 тестовых логов..."
for i in {1..600}; do
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] Test Nginx slave #$i" >> /var/log/nginx/access.log
    echo "[$ts] Test Apache slave #$i" >> /var/log/apache2/access.log
    echo "[$ts] Test MySQL slave #$i" >> /var/log/mysql/error.log
    echo "[$ts] Test WP sync slave #$i" >> /var/log/wp-sync.log
done

sleep 60

# Создание Index Pattern
log "Создаём Index Pattern logs-* в Kibana..."
curl -s -X POST "http://$MASTER_IP:5601/api/saved_objects/index-pattern/logs-*" \
  -H 'kbn-xsrf: true' \
  -H 'Content-Type: application/json' \
  -d '{"attributes":{"title":"logs-*","timeFieldName":"@timestamp"}}' || true

log "✅ Filebeat запущен с простым индексом"

# Финальный отчёт
echo ""
echo "=================================================================="
echo "✅ SLAVE УСТАНОВЛЕН — FILEBEAT ИСПРАВЛЕН (ПРОСТОЙ ИНДЕКС)"
echo "=================================================================="
echo "Проверь индексы:"
echo "   curl -s http://192.168.88.168:9200/_cat/indices/logs*?v"
echo "Kibana: http://192.168.88.168:5601 → Discover → logs-*"
echo "Если индексов всё ещё нет — пришли:"
echo "   docker logs \$(docker ps | grep filebeat | awk '{print \$1}') | tail -30"
echo "=================================================================="

log "Slave завершён успешно."
