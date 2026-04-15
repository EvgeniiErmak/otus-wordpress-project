#!/bin/bash
# recovery-slave.sh — Полное восстановление Slave сервера

set -euo pipefail

echo "=== ПОЛНОЕ ВОССТАНОВЛЕНИЕ SLAVE ==="

apt-get update && apt-get upgrade -y

curl -sSL https://raw.githubusercontent.com/EvgeniiErmak/otus-wordpress-project/main/setup/setup-slave.sh | sudo bash

echo "Slave восстановлен успешно!"
