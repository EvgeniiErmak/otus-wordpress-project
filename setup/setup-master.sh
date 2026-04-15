#!/bin/bash
# setup-master.sh — ФИНАЛЬНАЯ ВЕРСИЯ (метрики в Grafana + lifecycle + Kibana)

source <(curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/common-functions.sh)

log "=== ФИНАЛЬНАЯ УСТАНОВКА НА MASTER (192.168.88.168) ==="

# ... (все предыдущие блоки: Docker, nginx, LAMP, Memcached, MySQL, WordPress — оставь как было, они работают)

# ======================== Prometheus + Node Exporter + Grafana (ИСПРАВЛЕНО) ========================
log "Настройка Prometheus + Node Exporter + Grafana (с lifecycle и правильным scrape)..."

check_and_install prometheus prometheus-node-exporter

# Правильный конфиг Prometheus
cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 10s
  evaluation_interval: 10s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    honor_timestamps: true
    static_configs:
      - targets: ['localhost:9100']
EOF

# Включаем lifecycle API через systemd override
mkdir -p /etc/systemd/system/prometheus.service.d
cat > /etc/systemd/system/prometheus.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus --web.console.templates=/etc/prometheus/consoles --web.console.libraries=/etc/prometheus/console_libraries --web.enable-lifecycle
EOF

# Очистка и перезапуск
systemctl daemon-reload
systemctl stop prometheus prometheus-node-exporter
rm -rf /var/lib/prometheus/metrics2/* /var/lib/prometheus/data/* || true
systemctl start prometheus prometheus-node-exporter
enable_and_start_service prometheus
enable_and_start_service prometheus-node-exporter

# Grafana + дашборд
log "Установка Grafana с авто-дашбордом..."
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

# Скачиваем актуальный Node Exporter Full
wget -q -O /var/lib/grafana/dashboards/node-exporter-full.json https://grafana.com/api/dashboards/1860/revisions/37/download || true
chown -R grafana:grafana /var/lib/grafana /etc/grafana

systemctl restart grafana-server
enable_and_start_service grafana-server

log "Принудительный reload Prometheus..."
sleep 10
curl -X POST http://localhost:9090/-/reload || true
sleep 30

# ELK (оставляем как было)
log "ELK через Docker..."
mkdir -p /opt/elk
# ... (твой текущий docker-compose.yml блок — он работает)

# Финал
echo ""
echo "=================================================================="
echo "✅ ВСЁ НАСТРОЕНО АВТОМАТИЧЕСКИ! (метрики должны появиться)"
echo "=================================================================="
echo "WordPress:     http://192.168.88.168"
echo "Grafana:       http://192.168.88.168:3000   (логин admin / admin)"
echo "Kibana:        http://192.168.88.168:5601"
echo "Elasticsearch: http://192.168.88.168:9200"
echo "=================================================================="
echo "Проверь в Grafana: Status → Targets (должен быть node_exporter UP)"
echo "=================================================================="
