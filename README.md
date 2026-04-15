# OTUS WordPress Project — Высоконагруженная инфраструктура (Личный блог)

## Архитектура (соответствует схеме)

**Master (192.168.88.168)**
- Nginx — Reverse Proxy + балансировка
- Apache + PHP 8.3 + WordPress (backend 1)
- MySQL Master
- Memcached (общее хранилище сессий)
- Prometheus + Node Exporter + Grafana (мониторинг)
- ELK Stack (Elasticsearch + Kibana + Filebeat) — централизованное логирование

**Slave (192.168.88.167)**
- Apache + PHP 8.3 + WordPress (backend 2)
- MySQL Slave (репликация)
- Memcached (общий)
- Node Exporter
- Filebeat (логи отправляются на master)

## Как полностью восстановить проект с нуля (автоматически)

### На Master сервере:
```bash
curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-master.sh | sudo bash

На Slave сервере:
Bashcurl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/recovery/recovery-slave.sh | sudo bash
Логины и пароли
WordPress
URL: http://192.168.88.168
Логин: admin
Пароль: AdminPassword2026Strong!
Grafana
URL: http://192.168.88.168:3000
Логин: admin
Пароль: admin
MySQL

wpuser / WpPassword2026Strong!
repl / ReplPassword2026Strong! (репликация)

Kibana
URL: http://192.168.88.168:5601
Elasticsearch
URL: http://192.168.88.168:9200
Полезные команды

Синхронизация файлов (на slave): /usr/local/bin/sync-wp-files.sh
Бэкап БД со slave: /usr/local/bin/backup-db.sh
Проверка репликации (на slave): mysql -e "SHOW SLAVE STATUS\G;"

Структура репозитория

otus-wordpress-project/
├── README.md
├── configs/                  # Все конфиги
│   ├── nginx/
│   ├── apache/
│   ├── mysql/
│   └── grafana/
├── setup/                    # Основные установочные скрипты
│   ├── common-functions.sh
│   ├── setup-master.sh
│   └── setup-slave.sh
├── recovery/                 # Точки входа (одна команда)
│   ├── recovery-master.sh
│   └── recovery-slave.sh
├── scripts/                  # Дополнительные скрипты
│   └── backup-db.sh
└── cron/                     # (если будут)
