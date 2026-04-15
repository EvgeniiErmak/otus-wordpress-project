# OTUS WordPress Project — Высоконагруженная инфраструктура

**Тема проекта:** Личный блог / портфолио  
**Инфраструктура:** Master + Slave (Ubuntu 24.04 LTS)  
**Цель:** Полностью автоматизированное развертывание и восстановление двухсерверной среды с балансировкой нагрузки, репликацией БД, мониторингом и централизованным логированием.

---

## Архитектура проекта

### Master Server (192.168.88.168)

- Nginx — Reverse Proxy и балансировщик нагрузки  
- Apache + PHP 8.3 + WordPress — основной backend  
- MySQL Master  
- Memcached — общее хранилище сессий  
- Prometheus + Node Exporter + Grafana — мониторинг  
- ELK Stack:
  - Elasticsearch
  - Kibana
  - Filebeat

### Slave Server (192.168.88.167)

- Apache + PHP 8.3 + WordPress — резервный backend  
- MySQL Slave — репликация с Master  
- Memcached  
- Node Exporter  
- Filebeat  

---

## Полное восстановление проекта с нуля

### Развертывание Master

`curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-master.sh | sudo bash`

### Развертывание Slave

`curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-slave.sh | sudo bash`

После выполнения этих двух команд инфраструктура будет полностью развернута и готова к работе.

---

## Доступы и учетные данные

### WordPress

- URL: http://192.168.88.168  
- Логин: admin  
- Пароль: AdminPassword2026Strong!  

### Grafana

- URL: http://192.168.88.168:3000  
- Логин: admin  
- Пароль: admin  

### MySQL

- WordPress User: wpuser  
- Password: WpPassword2026Strong!  

- Replication User: repl  
- Password: ReplPassword2026Strong!  

### Kibana

- URL: http://192.168.88.168:5601  

### Elasticsearch

- URL: http://192.168.88.168:9200  

### Prometheus

- URL: http://192.168.88.168:9090  

---

## Полезные команды

### На Slave сервере

Принудительная синхронизация файлов WordPress:

`/usr/local/bin/sync-wp-files.sh`

Проверка состояния репликации MySQL:

`mysql -e "SHOW SLAVE STATUS\G;"`

### На Master сервере

Ручной запуск резервного копирования БД:

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
├── setup/
│   ├── common-functions.sh
│   ├── setup-master.sh
│   └── setup-slave.sh
├── recovery/
│   ├── recovery-master.sh
│   └── recovery-slave.sh
├── scripts/
│   └── backup-db.sh
└── cron/
```

---

## Публикация проекта в GitHub

`cd ~/otus-wordpress-project && git add . && git commit -m "Final project delivery - full automation" && git push origin main`

---

## Особенности реализации

- Полная автоматизация развертывания одной командой  
- Idempotent-скрипты (безопасный повторный запуск)  
- Автоматическая настройка MySQL Master-Slave репликации  
- Автоматическая синхронизация WordPress файлов каждые 5 минут  
- Автоматическая передача SSH-ключей между серверами  
- Автоматическое создание Grafana Dashboard  
- Централизованное логирование через ELK Stack  
- Общее Memcached-хранилище для сессий между backend-узлами  

---

## План аварийного восстановления

1. Поднять новый Master сервер  
2. Выполнить:  
   `curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-master.sh | sudo bash`

3. Поднять новый Slave сервер  
4. Выполнить:  
   `curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-slave.sh | sudo bash`

5. При необходимости восстановить БД вручную:  
   `mysql wordpress < backup.sql`

---

## RTO / Время восстановления

**Полное восстановление инфраструктуры:** 5–10 минут

---

## Итог

Проект реализует production-like высокодоступную WordPress-инфраструктуру с:

- Балансировкой нагрузки  
- Репликацией БД  
- Централизованным логированием  
- Мониторингом  
- Автоматическим восстановлением  
- Полной инфраструктурой как код (IaC-подход)
