# OTUS WordPress Project — Enterprise High Availability Infrastructure

## Описание проекта

Проект представляет собой полностью автоматизированную высокодоступную инфраструктуру для размещения WordPress-сайта (личный блог / портфолио), реализованную в соответствии с принципами production-ready deployment и Infrastructure as Code (IaC).

Решение обеспечивает:

- отказоустойчивость backend-узлов;
- репликацию базы данных master-slave;
- балансировку нагрузки;
- централизованный сбор логов;
- мониторинг и визуализацию метрик;
- быстрое аварийное восстановление среды.

---

## Цели проекта

- Развертывание production-like WordPress-инфраструктуры
- Демонстрация навыков автоматизации Linux/DevOps/SRE
- Реализация полного disaster recovery сценария
- Минимизация RTO/RPO при сбоях инфраструктуры
- Подтверждение владения Infrastructure as Code подходом

---

## Архитектурная схема

### Master Node — 192.168.88.168

- **Nginx** — Reverse Proxy / Load Balancer
- **Apache + PHP 8.3 + WordPress** — Primary Backend
- **MySQL Master** — Primary Database
- **Memcached** — Shared Session Storage
- **Prometheus** — Metrics Collection
- **Node Exporter** — Host Metrics
- **Grafana** — Metrics Visualization
- **Elasticsearch** — Log Storage / Search
- **Kibana** — Log Visualization
- **Filebeat** — Log Shipping

---

### Slave Node — 192.168.88.167

- **Apache + PHP 8.3 + WordPress** — Secondary Backend
- **MySQL Slave** — Replicated Database
- **Memcached** — Shared Session Storage
- **Node Exporter** — Host Metrics
- **Filebeat** — Log Shipping

---

## Функциональные возможности

- Полностью автоматизированное развертывание инфраструктуры
- Повторяемые idempotent deployment scripts
- Автоматическая настройка MySQL Master-Slave репликации
- Автоматическая синхронизация WordPress файлов между backend-нодами
- Централизованный мониторинг всей инфраструктуры
- Централизованный сбор логов приложений и системы
- Disaster Recovery за 5–10 минут
- Полное восстановление инфраструктуры с нуля двумя командами

---

## Быстрый старт / Disaster Recovery

### Развертывание Master Node

`curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-master.sh | sudo bash`

---

### Развертывание Slave Node

`curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-slave.sh | sudo bash`

---

После выполнения двух команд инфраструктура полностью готова к эксплуатации.

---

## Доступы к сервисам

### WordPress

- **URL:** http://192.168.88.168
- **Username:** admin
- **Password:** AdminPassword2026Strong!

---

### Grafana

- **URL:** http://192.168.88.168:3000
- **Username:** admin
- **Password:** admin

---

### Prometheus

- **URL:** http://192.168.88.168:9090

---

### Kibana

- **URL:** http://192.168.88.168:5601

---

### Elasticsearch

- **URL:** http://192.168.88.168:9200

---

## База данных

### WordPress DB User

- **Username:** wpuser
- **Password:** WpPassword2026Strong!

---

### Replication User

- **Username:** repl
- **Password:** ReplPassword2026Strong!

---

## Эксплуатационные команды

### Slave Node

#### Принудительная синхронизация WordPress файлов

`/usr/local/bin/sync-wp-files.sh`

#### Проверка состояния репликации MySQL

`mysql -e "SHOW SLAVE STATUS\G;"`

---

### Master Node

#### Ручной запуск резервного копирования БД

`/usr/local/bin/backup-db.sh`

---

## Структура репозитория

```text
otus-wordpress-project/
├── README.md
├── configs/
│   ├── nginx/
│   ├── apache/
│   ├── mysql/
│   └── grafana/
│
├── setup/
│   ├── common-functions.sh
│   ├── setup-master.sh
│   └── setup-slave.sh
│
├── recovery/
│   ├── recovery-master.sh
│   └── recovery-slave.sh
│
├── scripts/
│   ├── backup-db.sh
│   └── sync-wp-files.sh
│
└── cron/
```

---

## Публикация изменений в GitHub

`cd ~/otus-wordpress-project && git add . && git commit -m "Update infrastructure automation" && git push origin main`

---

## Disaster Recovery Procedure

### Полное восстановление инфраструктуры

1. Поднять новый Master Node
2. Выполнить recovery-master.sh
3. Поднять новый Slave Node
4. Выполнить recovery-slave.sh
5. При необходимости восстановить БД вручную:

`mysql wordpress < backup.sql`

---

## SLA / RTO / RPO

### Recovery Time Objective (RTO)

- **5–10 минут**

### Recovery Point Objective (RPO)

- **До 5 минут потери данных**
  (зависит от момента последней синхронизации / репликации)

---

## Production Engineering Best Practices Implemented

- Infrastructure as Code
- Idempotent Provisioning
- Automated Disaster Recovery
- Horizontal Scaling Ready Architecture
- Centralized Monitoring
- Centralized Logging
- Database Replication
- Session Sharing Between Backends
- Automated File Synchronization
- Minimal Manual Intervention

---

## Итог

Данный проект демонстрирует построение production-like отказоустойчивой веб-инфраструктуры enterprise-уровня с использованием современных DevOps/SRE практик.

Решение готово к масштабированию, автоматическому восстановлению и дальнейшему развитию в сторону полноценного Kubernetes / Cloud Native deployment.

---

## Автор

**Evgenii Ermak**  
OTUS Final Project — Linux Administrator / DevOps Track
