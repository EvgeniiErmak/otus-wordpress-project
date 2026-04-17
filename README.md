# 🛡️ WordPress Sentinel — Enterprise High-Availability Infrastructure with Auto-Recovery

[![Linux](https://img.shields.io/badge/Linux-Ubuntu%2024.04-orange?style=for-the-badge&logo=linux)](https://ubuntu.com)
[![Nginx](https://img.shields.io/badge/Nginx-Reverse%20Proxy-green?style=for-the-badge&logo=nginx)](https://nginx.org)
[![Apache](https://img.shields.io/badge/Apache-Web%20Server-red?style=for-the-badge&logo=apache)](https://apache.org)
[![MySQL](https://img.shields.io/badge/MySQL-GTID%20Replication-blue?style=for-the-badge&logo=mysql)](https://mysql.com)
[![Grafana](https://img.shields.io/badge/Grafana-Observability-orange?style=for-the-badge&logo=grafana)](https://grafana.com)
[![ELK](https://img.shields.io/badge/ELK-Centralized%20Logging-yellow?style=for-the-badge)](https://elastic.co)
[![Prometheus](https://img.shields.io/badge/Prometheus-Metrics%20Collection-e6522c?style=for-the-badge&logo=prometheus)](https://prometheus.io)

> 🎯 **Production-ready инфраструктура** для WordPress с высокой доступностью, автоматическим восстановлением и централизованным мониторингом. Реализовано в стиле **Infrastructure as Code (IaC)**.

---

## 📋 Оглавление
- [🎯 Цели проекта](#-цели-проекта)
- [🏗 Архитектура](#-архитектура)
- [⚡ Быстрый старт](#-быстрый-старт)
- [🔐 Доступы](#-доступы)
- [📊 Мониторинг](#-мониторинг)
- [🛠 Проверка](#-проверка)
- [📁 Структура](#-структура)
- [🚨 Recovery](#-recovery)
- [⏱ SLA](#-sla)
- [🧠 Best Practices](#-best-practices)

---

## 🎯 Цели проекта

- ⚙️ Полная автоматизация (`curl | bash`)
- 🔁 Отказоустойчивость (GTID репликация)
- 📊 Централизованный мониторинг
- 📦 Централизованное логирование
- ⚡ Быстрое восстановление (5–10 минут)

---

## 🏗 Архитектура

```
MASTER (192.168.88.168)
 ├─ Nginx (LB)
 ├─ Apache + PHP + WordPress
 ├─ MySQL Master
 ├─ Memcached
 ├─ Prometheus + Grafana
 ├─ ELK Stack
 └─ Node Exporter

        ⇅ REPLICATION + RSYNC

SLAVE (192.168.88.167)
 ├─ Apache + PHP + WordPress
 ├─ MySQL Slave
 ├─ Memcached
 ├─ Node Exporter
 └─ Filebeat
```

---

## ⚡ Быстрый старт

```bash
# MASTER
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-master.sh | sudo bash

# SLAVE
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-slave.sh | sudo bash
```

---

## 🔐 Доступы

WordPress → http://192.168.88.168  
Grafana → http://192.168.88.168:3000  
Kibana → http://192.168.88.168:5601  
Prometheus → http://192.168.88.168:9090  
Elasticsearch → http://192.168.88.168:9200  

---

## 📊 Мониторинг

```bash
# Node Exporter
curl http://192.168.88.168:9100/metrics
curl http://192.168.88.167:9100/metrics

# Prometheus Targets
curl http://192.168.88.168:9090/api/v1/targets
```

---

## 🛠 Проверка

```bash
# MYSQL REPLICATION
mysql -e "SHOW SLAVE STATUS\G;" | grep Running

# WORDPRESS
curl -I http://192.168.88.168

# SERVICES
systemctl is-active nginx apache2 mysql
```

---

## 📁 Структура

```text
otus-wordpress-project/
├── configs/
├── setup/
├── recovery/
├── scripts/
└── cron/
```

---

## 🚨 Recovery

```bash
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-master.sh | sudo bash
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-slave.sh | sudo bash
```

---

## ⏱ SLA

- RTO: 5–10 минут  
- RPO: до 5 минут  

---

## 🧠 Best Practices

- IaC  
- Idempotent scripts  
- Auto recovery  
- Centralized logging  
- Monitoring  
- Replication  
- Zero manual steps  

---

## 🏁 Итог

Production-ready DevOps инфраструктура:

- 🔄 Авторазвертывание  
- 📈 Масштабируемость  
- 🔧 Самовосстановление  

---

## 👨‍💻 Автор

Evgenii Ermak  
https://github.com/EvgeniiErmak
