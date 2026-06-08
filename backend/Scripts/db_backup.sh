#!/usr/bin/env bash
# PlayBall DB 일일 백업 (cron). gzip + 7일 보관 + 빈 덤프 가드.
# 설치: chmod +x; crontab -e →
#   0 3 * * * /home/ubuntu/playball/backend/Scripts/db_backup.sh >> /home/ubuntu/backups/backup.log 2>&1
# 주의: 파이프 $? 는 gzip 종료코드라 pg_dump 실패를 못 잡음(기존 backup.sh 빈 덤프 사고).
#       → PIPESTATUS[0]로 pg_dump 실제 종료코드 + 산출물 최소크기 검증.
set -uo pipefail

BACKUP_DIR="/home/ubuntu/backups"
RETAIN_DAYS=7
MIN_BYTES=100000   # 100KB 미만이면 빈/실패 덤프로 간주
mkdir -p "$BACKUP_DIR"

TS=$(date +%Y%m%d_%H%M%S)
FILE="$BACKUP_DIR/playball_$TS.sql.gz"

sudo -u postgres pg_dump playball | gzip > "$FILE"
rc=${PIPESTATUS[0]}

SIZE=$(stat -c%s "$FILE" 2>/dev/null || echo 0)
if [ "$rc" -ne 0 ] || [ "$SIZE" -lt "$MIN_BYTES" ]; then
    echo "$(date -Is) BACKUP FAILED (pg_dump rc=$rc, size=${SIZE}B) — 삭제" >&2
    rm -f "$FILE"
    exit 1
fi

find "$BACKUP_DIR" -name 'playball_*.sql.gz' -mtime +"$RETAIN_DAYS" -delete
echo "$(date -Is) backup ok: $FILE ($(du -h "$FILE" | cut -f1))"
