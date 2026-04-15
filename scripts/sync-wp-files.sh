#!/bin/bash
# sync-wp-files.sh — Синхронизация wp-content между master и slave

RSYNC_OPTS="-avz --delete --exclude=wp-config.php --exclude=cache"

echo "[$(date)] === Синхронизация WordPress файлов master → slave ==="

rsync $RSYNC_OPTS /var/www/html/wordpress/wp-content/uploads/ root@192.168.88.167:/var/www/html/wordpress/wp-content/uploads/
rsync $RSYNC_OPTS /var/www/html/wordpress/wp-content/plugins/ root@192.168.88.167:/var/www/html/wordpress/wp-content/plugins/
rsync $RSYNC_OPTS /var/www/html/wordpress/wp-content/themes/  root@192.168.88.167:/var/www/html/wordpress/wp-content/themes/

echo "[$(date)] Синхронизация завершена."
