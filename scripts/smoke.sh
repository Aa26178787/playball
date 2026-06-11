#!/bin/bash
# 배포 후 스모크 테스트 (메가D) — 서버에서 실행: bash ~/playball/scripts/smoke.sh
# 감지 대상: API 다운 / scheduler 미재시작·정지 / git 미pull / 핵심 엔드포인트 5xx
# 종료코드 0 = 전부 통과, 1 = 실패 있음
set -u
BASE="http://localhost:8000"
FAIL=0

ok()   { echo "  PASS  $1"; }
bad()  { echo "  FAIL  $1"; FAIL=1; }

echo "== PlayBall smoke =="

# 1) 서비스 활성
for svc in playball playball-scheduler; do
    if [ "$(systemctl is-active $svc)" = "active" ]; then ok "systemd $svc active"
    else bad "systemd $svc NOT active"; fi
done

# 2) scheduler 심장박동 — 최근 3분 내 저널 로그 (30초 사이클이라 3분 무로그 = 멈춤)
if sudo journalctl -u playball-scheduler --since "3 min ago" -q | grep -q .; then
    ok "scheduler 최근 3분 로그 있음"
else
    bad "scheduler 3분간 로그 없음 (멈춤/크래시 의심)"
fi

# 3) git 동기화 — 서버 HEAD == origin/main
cd ~/playball
git fetch origin main -q 2>/dev/null
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)
if [ "$LOCAL" = "$REMOTE" ]; then ok "git HEAD == origin/main (${LOCAL:0:7})"
else bad "git 미pull: HEAD=${LOCAL:0:7} origin=${REMOTE:0:7}"; fi

# 4) 핵심 엔드포인트 (200 기대)
check() {
    local path="$1" expect="${2:-200}"
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$BASE$path")
    if [ "$code" = "$expect" ]; then ok "GET $path -> $code"
    else bad "GET $path -> $code (기대 $expect)"; fi
}
check /games/today
check /teams/rankings
check /players/rankings
check /user/points/leaderboard
check /app-config
check /s/g/1
check /widget/live-scores

# 5) HTTPS 외부 경로 (nginx 경유)
for url in "https://playball.duckdns.org/games/today" "https://playball.duckdns.org/app/"; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url")
    if [ "$code" = "200" ]; then ok "$url -> $code"
    else bad "$url -> $code"; fi
done

echo "===================="
if [ "$FAIL" = "0" ]; then echo "ALL PASS"; else echo "SMOKE FAILED"; fi
exit $FAIL
