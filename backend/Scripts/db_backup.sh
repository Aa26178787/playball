#!/usr/bin/env bash
# PlayBall DB 일일 백업 (cron). gzip + 7일 보관.
# 설치: chmod +x; crontab -e 에 → 0 4 * * * /home/ubuntu/playball/backend/scripts/db_backup.sh >> /home/ubuntu/backups/backup.log 2>&1
set -euo pipefail

BACKUP_DIR="/home/ubuntu/backups"
RETAIN_DAYS=7
mkdir -p "$BACKUP_DIR"

TS=$(date +%Y%m%d_%H%M%S)
FILE="$BACKUP_DIR/playball_$TS.sql.gz"

sudo -u postgres pg_dump playball | gzip > "$FILE"

# 보관기간 초과 백업 제거
find "$BACKUP_DIR" -name 'playball_*.sql.gz' -mtime +"$RETAIN_DAYS" -delete

echo "$(date -Is) backup ok: $FILE ($(du -h "$FILE" | cut -f1))"
