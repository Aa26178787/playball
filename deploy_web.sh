#!/usr/bin/env bash
# Flutter 웹 PWA 빌드+배포 (/app/) — 앱 수정 시 웹 동반 반영용
# 사용: bash deploy_web.sh   (Git Bash)
set -e
KEY="C:\\Users\\qq772\\Downloads\\ssh-key-2026-03-28 (2).key"
SRV="ubuntu@168.107.36.158"
cd "$(dirname "$0")/app"

echo "== flutter build web =="
# --pwa-strategy=none: 서비스워커 비활성 (베타 중 캐시된 깨진 빌드 문제 근절, 매 로드 최신)
MSYS_NO_PATHCONV=1 flutter build web --release --base-href "/app/" --no-web-resources-cdn --pwa-strategy=none

echo "== 압축/전송 =="
cd build
tar czf /tmp/playball_web.tgz web
scp -i "$KEY" /tmp/playball_web.tgz "$SRV:/tmp/"

echo "== 서버 배치 =="
ssh -i "$KEY" -o ConnectTimeout=15 "$SRV" \
  "sudo tar xzf /tmp/playball_web.tgz -C /tmp && sudo rsync -a --delete /tmp/web/ /var/www/playball_web/ && sudo chown -R www-data:www-data /var/www/playball_web && echo WEB_DEPLOYED"
echo "== 완료: https://playball.duckdns.org/app/ =="
