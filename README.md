# 🚀 WordPress High-Availability: Отказоустойчивый кластер с автоматическим восстановлением и мониторингом

![Linux](https://img.shields.io/badge/Linux-Ubuntu%2024.04-orange?style=for-the-badge&logo=linux)
![Nginx](https://img.shields.io/badge/Nginx-Reverse%20Proxy-green?style=for-the-badge&logo=nginx)
![Apache](https://img.shields.io/badge/Apache-Web%20Server-red?style=for-the-badge&logo=apache)
![MySQL](https://img.shields.io/badge/MySQL-Replication-blue?style=for-the-badge&logo=mysql)
![Grafana](https://img.shields.io/badge/Grafana-Monitoring-orange?style=for-the-badge&logo=grafana)
![ELK](https://img.shields.io/badge/ELK-Logging-yellow?style=for-the-badge)

---

## 📌 Описание проекта

Production-ready инфраструктура для WordPress с высокой доступностью, автоматическим восстановлением и централизованным мониторингом.  
💡 Реализовано в стиле **Infrastructure as Code (IaC)** с полной автоматизацией.

---

## 🎯 Цели проекта

- ⚙️ Полная автоматизация развертывания  
- 🔁 Отказоустойчивость и репликация MySQL master-slave  
- 📊 Мониторинг и централизованное логирование  
- 🔥 Быстрое аварийное восстановление (Disaster Recovery)  
- 🧠 Демонстрация DevOps/SRE практик  

---

## 🏗 Архитектура

### 🟢 Master Node — `192.168.88.168`

- 🌐 Nginx — балансировка нагрузки (reverse proxy)  
- 🧩 Apache + PHP 8.3 + WordPress  
- 🗄 MySQL Master (GTID-based репликация)  
- ⚡ Memcached (общее хранилище сессий)  
- 📊 Prometheus + Grafana (мониторинг)  
- 📈 Node Exporter: http://192.168.88.168:9100/metrics  
- 📦 ELK Stack (Elasticsearch + Kibana + Filebeat)  

---

### 🔵 Slave Node — `192.168.88.167`

- 🧩 Apache + PHP 8.3 + WordPress (rsync синхронизация)  
- 🗄 MySQL Slave (репликация с master)  
- ⚡ Memcached  
- 📈 Node Exporter: http://192.168.88.167:9100/metrics  
- 📦 Filebeat (логирование)  

---

## ⚡ Быстрый старт

### 🟢 Развертывание Master Node

```bash
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-master.sh | sudo bash
```

### 🔵 Развертывание Slave Node

```bash
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-slave.sh | sudo bash
```

---

## 🔐 Доступы

### 🌍 WordPress
- URL: http://192.168.88.168  
- Login: `admin`  
- Password: `AdminPassword2026Strong!`  

### 📊 Grafana
- URL: http://192.168.88.168:3000  
- Login: `admin`  
- Password: `admin`  

### 🔎 Kibana
- URL: http://192.168.88.168:5601  

### 📈 Prometheus
- URL: http://192.168.88.168:9090  

### 🗄 Elasticsearch
- URL: http://192.168.88.168:9200  

### 📊 Node Exporter
- Master: http://192.168.88.168:9100/metrics  
- Slave: http://192.168.88.167:9100/metrics  

---

## 🛠 Проверка системы

### 🔵 Slave Node

```bash
mysql -e "SHOW SLAVE STATUS\G;" | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master"
/usr/local/bin/backup-db.sh 2>&1 | grep -E "BACKUP_OK|BINLOG_INFO|File:|Position:"
ls -lh /var/backups/wordpress_full_*.sql 2>/dev/null | tail -1
cat /var/backups/binlog_position_*.txt 2>/dev/null | tail -5
/usr/local/bin/sync-wp-files.sh && echo "✅ Rsync OK"
crontab -l | grep sync-wp-files
docker compose -f /opt/filebeat/docker-compose.yml ps
echo "stats" | nc -q1 127.0.0.1 11211 | head -3
curl -s http://localhost:9100/metrics | grep -q "node_boot_time" && echo "✅ Node Exporter OK"
```

---

### 🟢 Master Node

```bash
curl -sI http://192.168.88.168 | head -1 | grep "200 OK" && echo "✅ WP доступен"
mysql -e "SHOW SLAVE HOSTS;"
/usr/local/bin/backup-db.sh 2>&1 | grep -E "File:|Position:|BACKUP_OK"
curl -s http://localhost:9090/api/v1/targets | grep -o '"health":"up"' | wc -l
curl -s http://localhost:9200/_cat/indices/logs*?v | head -5
curl -s http://admin:admin@localhost:3000/api/search?query=OTUS | grep -q "title" && echo "✅ Grafana OK"
systemctl is-active apache2 nginx mysql memcached prometheus-node-exporter
```

---

## 🔗 Проверка связности

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 root@192.168.88.168 "echo OK"
nc -zv 192.168.88.168 3306
rsync -avz --dry-run -e ssh root@192.168.88.168:/var/www/html/wordpress/ /tmp/test/
```

---

## 📁 Структура проекта

```text
otus-wordpress-project/
├── README.md
├── configs/
├── setup/
├── recovery/
├── scripts/
└── cron/
```

---

## 🚨 Disaster Recovery

```bash
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-master.sh | sudo bash
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-slave.sh | sudo bash
```

---

## ⏱ SLA

- ⚡ RTO: 5–10 минут  
- 💾 RPO: до 5 минут  

---

## 🧠 Best Practices

- Infrastructure as Code  
- Idempotent scripts  
- Automated recovery  
- Centralized logging (ELK)  
- Monitoring stack  
- MySQL replication  
- Session sharing  
- Zero manual steps  

---

## 🏁 Итог

Enterprise-ready инфраструктура:

- 🔄 Быстрое развертывание  
- 📈 Масштабируемость  
- 🔧 Автовосстановление  
- ☁️ Готовность к cloud/k8s  

---

## 👨‍💻 Автор

Evgenii Ermak  
OTUS — Linux Administrator / DevOps Track
