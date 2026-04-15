# 🚀 OTUS WordPress Project — Enterprise High Availability Infrastructure

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
- 🔁 Отказоустойчивость и репликация  
- 📊 Мониторинг и логирование  
- 🔥 Быстрое аварийное восстановление  
- 🧠 Демонстрация DevOps/SRE практик  

---

## 🏗 Архитектура

### 🟢 Master Node — `192.168.88.168`

- 🌐 Nginx — балансировка нагрузки
- 🧩 Apache + PHP 8.3 + WordPress
- 🗄 MySQL Master
- ⚡ Memcached
- 📊 Prometheus + Grafana
- 📈 Node Exporter
- 📦 ELK Stack (Elasticsearch + Kibana + Filebeat)

---

### 🔵 Slave Node — `192.168.88.167`

- 🧩 Apache + PHP 8.3 + WordPress
- 🗄 MySQL Slave (репликация)
- ⚡ Memcached
- 📈 Node Exporter
- 📦 Filebeat

---

## ⚡ Быстрый старт (1 команда = готовый сервер)

### 🟢 Развертывание Master Node

```bash
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-master.sh | sudo bash
```

---

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

---

### 📊 Grafana
- URL: http://192.168.88.168:3000  
- Login: `admin`  
- Password: `admin`

---

### 🔎 Kibana
- URL: http://192.168.88.168:5601  

---

### 📈 Prometheus
- URL: http://192.168.88.168:9090  

---

### 🗄 Elasticsearch
- URL: http://192.168.88.168:9200  

---

## 🛠 Полезные команды

### 🔵 Slave Node

#### 🔄 Синхронизация WordPress

```bash
/usr/local/bin/sync-wp-files.sh
```

#### 📡 Проверка репликации MySQL

```bash
mysql -e "SHOW SLAVE STATUS\G;"
```

---

### 🟢 Master Node

#### 💾 Backup базы данных

```bash
/usr/local/bin/backup-db.sh
```

---

## 📁 Структура проекта

```text
otus-wordpress-project/
├── README.md
├── configs/
│   ├── nginx/
│   ├── apache/
│   ├── mysql/
│   └── grafana/
├── setup/
│   ├── common-functions.sh
│   ├── setup-master.sh
│   └── setup-slave.sh
├── recovery/
│   ├── recovery-master.sh
│   └── recovery-slave.sh
├── scripts/
│   ├── backup-db.sh
│   └── sync-wp-files.sh
└── cron/
```

---

## 🚨 Disaster Recovery

```bash
# MASTER
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-master.sh | sudo bash

# SLAVE
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-slave.sh | sudo bash
```

---

## ⏱ SLA

- ⚡ RTO: **5–10 минут**
- 💾 RPO: **до 5 минут потери данных**

---

## 🧠 Best Practices

- ✅ Infrastructure as Code  
- ✅ Idempotent scripts  
- ✅ Automated Recovery  
- ✅ Centralized Logging  
- ✅ Monitoring stack  
- ✅ DB Replication  
- ✅ Session sharing  
- ✅ Zero manual steps  

---

## 🏁 Итог

Готовая **enterprise-инфраструктура уровня production**, которую можно:

- 🔄 Развернуть с нуля за минуты  
- 📈 Масштабировать  
- 🔧 Автоматически восстановить  
- ☁️ Перенести в облако / Kubernetes  

---

## 👨‍💻 Автор

**Evgenii Ermak**  
OTUS — Linux Administrator / DevOps Track
