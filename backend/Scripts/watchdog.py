#!/usr/bin/env python3
"""외부 watchdog — systemd 서비스 / API / 백업 신선도 점검 후 이상 시 이메일.
스케줄러 내부 _health_check 는 '자기 자신의 죽음'을 감지 못하므로(프로세스 다운 시
체크 코드도 안 돎) 외부 cron 에서 독립 감시. 문제별 1시간 쿨다운으로 스팸 방지.
cron: */10 * * * * python3 /home/ubuntu/playball/backend/Scripts/watchdog.py >> /home/ubuntu/backups/watchdog.log 2>&1
"""
import subprocess, os, glob, time, json, urllib.request, smtplib, re
from email.message import EmailMessage
from datetime import datetime, timezone

ENV_FILE   = "/etc/systemd/system/playball.service.d/email.conf"
BACKUP_DIR = "/home/ubuntu/backups"
STATE      = "/home/ubuntu/backups/.watchdog_state.json"
COOLDOWN   = 3600  # 문제별 알림 쿨다운(초)


def load_env():
    creds = {}
    try:
        with open(ENV_FILE) as f:
            for line in f:
                m = re.match(r'\s*Environment=(.*)$', line)
                if not m:
                    continue
                kv = m.group(1).strip().strip('"')
                if '=' in kv:
                    k, v = kv.split('=', 1)
                    creds[k.strip()] = v.strip()
    except Exception:
        pass
    return creds


def check():
    problems = []
    for svc in ("playball", "playball-scheduler"):
        r = subprocess.run(["systemctl", "is-active", svc], capture_output=True, text=True)
        state = r.stdout.strip()
        if state != "active":
            problems.append(f"서비스 {svc} 비활성 ({state})")
    try:
        with urllib.request.urlopen("http://localhost:8000/games/today", timeout=10) as resp:
            if resp.status != 200:
                problems.append(f"API 비정상 status={resp.status}")
    except Exception as e:
        problems.append(f"API 응답 실패: {e}")
    files = sorted(glob.glob(f"{BACKUP_DIR}/playball_*.sql.gz"))
    if not files:
        problems.append("백업 파일 없음")
    else:
        latest = files[-1]
        age_h = (time.time() - os.path.getmtime(latest)) / 3600
        size = os.path.getsize(latest)
        if age_h > 26:
            problems.append(f"최근 백업 {age_h:.0f}시간 경과 ({os.path.basename(latest)})")
        if size < 100000:
            problems.append(f"최근 백업 크기 이상 {size}B ({os.path.basename(latest)})")
    return problems


def cooldown_ok(key):
    try:
        st = json.load(open(STATE))
    except Exception:
        st = {}
    now = time.time()
    if now - st.get(key, 0) < COOLDOWN:
        return False
    st[key] = now
    try:
        json.dump(st, open(STATE, "w"))
    except Exception:
        pass
    return True


def alert(problems, creds):
    key = "|".join(sorted(problems))
    if not cooldown_ok(key):
        return
    ts = datetime.now(timezone.utc).isoformat()
    body = "PlayBall watchdog 이상 감지:\n\n" + "\n".join(f"- {p}" for p in problems)
    user, pw = creds.get("EMAIL_USER"), creds.get("EMAIL_PASS")
    admin = creds.get("ADMIN_EMAIL", user)
    if not user or not pw:
        print(f"{ts} [WATCHDOG] (메일 미설정) {body}")
        return
    msg = EmailMessage()
    msg["Subject"] = "[PlayBall] watchdog 경보"
    msg["From"] = user
    msg["To"] = admin
    msg.set_content(body)
    try:
        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as s:
            s.login(user, pw)
            s.send_message(msg)
        print(f"{ts} [WATCHDOG] 알림 발송 ({len(problems)}건)")
    except Exception as e:
        print(f"{ts} [WATCHDOG] 발송 실패: {e}")


if __name__ == "__main__":
    probs = check()
    if probs:
        alert(probs, load_env())
    else:
        print(f"{datetime.now(timezone.utc).isoformat()} ok")
