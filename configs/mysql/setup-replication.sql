-- configs/mysql/setup-replication.sql
-- SQL-скрипт для настройки репликации master → slave

CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED BY 'ReplPassword2026Strong!';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';

FLUSH PRIVILEGES;

SHOW MASTER STATUS\G
