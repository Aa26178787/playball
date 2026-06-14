"""관리자 콘솔 API — X-Admin-Key 헤더 인증 (콘솔 UI = /static/admin/index.html)

전부 ADMIN_KEY env 검증 + log_admin_access 감사로그 (CLAUDE.md admin 규칙).
맛집 승인은 기존 stadiums 라우터(/stadiums/food-places/*) 재사용 — 여기 미중복.
"""
import os

from fastapi import APIRouter, Header, HTTPException, Request, Query

from api.security_log import log_admin_access
from database.connection import get_connection

router = APIRouter(prefix="/admin", tags=["admin"])

_ADMIN_KEY = os.environ.get("ADMIN_KEY", "")


def _client_ip(request: Request) -> str:
    return request.headers.get("x-real-ip") or (request.client.host if request.client else "?")


def _check(request: Request, x_admin_key: str | None, endpoint: str):
    ip = _client_ip(request)
    if not _ADMIN_KEY:
        log_admin_access(ip, endpoint, "check", "FAIL_NO_ENV")
        raise HTTPException(status_code=503, detail="admin 비활성")
    if x_admin_key != _ADMIN_KEY:
        log_admin_access(ip, endpoint, "check", "FAIL_WRONG_KEY")
        raise HTTPException(status_code=403, detail="forbidden")
    log_admin_access(ip, endpoint, "access", "OK")


def _conn():
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    return conn


@router.get("/overview")
def overview(request: Request, x_admin_key: str | None = Header(default=None)):
    _check(request, x_admin_key, "GET /admin/overview")
    conn = _conn()
    cur = conn.cursor()
    out = {}
    for key, sql in [
        ("users", "SELECT count(*) FROM users"),
        ("users_today", "SELECT count(*) FROM users WHERE created_at::date = CURRENT_DATE"),
        ("posts", "SELECT count(*) FROM posts"),
        ("comments", "SELECT count(*) FROM comments"),
        ("post_reports", "SELECT count(*) FROM post_reports"),
        ("insta_reports", "SELECT count(*) FROM insta_handle_reports"),
        ("food_pending", "SELECT count(*) FROM stadium_food_places WHERE status IN ('pending_vote','pending_admin')"),
        ("push_tokens", "SELECT count(*) FROM push_tokens"),
    ]:
        try:
            cur.execute(sql)
            out[key] = cur.fetchone()[0]
        except Exception:
            conn.rollback()
            out[key] = None
    cur.close()
    conn.close()
    return out


@router.get("/users")
def list_users(request: Request, q: str = "", limit: int = Query(50, le=200),
               x_admin_key: str | None = Header(default=None)):
    _check(request, x_admin_key, "GET /admin/users")
    conn = _conn()
    cur = conn.cursor()
    like = f"%{q}%"
    cur.execute("""
        SELECT u.id, u.email, u.nickname, u.created_at, COALESCE(u.phone_verified, FALSE),
               (SELECT count(*) FROM posts p WHERE p.user_id = u.id),
               (SELECT count(*) FROM comments c WHERE c.user_id = u.id)
        FROM users u
        WHERE (%s = '' OR u.email ILIKE %s OR u.nickname ILIKE %s)
        ORDER BY u.id DESC LIMIT %s
    """, (q, like, like, limit))
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {"users": [
        {"id": r[0], "email": r[1], "nickname": r[2],
         "created_at": str(r[3])[:19], "verified": r[4],
         "posts": r[5], "comments": r[6]} for r in rows]}


@router.delete("/users/{uid}")
def delete_user(uid: int, request: Request, x_admin_key: str | None = Header(default=None)):
    _check(request, x_admin_key, f"DELETE /admin/users/{uid}")
    conn = _conn()
    cur = conn.cursor()
    cur.execute("DELETE FROM users WHERE id = %s", (uid,))  # FK CASCADE/SET NULL 처리
    deleted = cur.rowcount
    conn.commit()
    cur.close()
    conn.close()
    if not deleted:
        raise HTTPException(status_code=404, detail="없는 유저")
    return {"deleted": uid}


@router.get("/posts")
def list_posts(request: Request, q: str = "", limit: int = Query(50, le=200),
               x_admin_key: str | None = Header(default=None)):
    _check(request, x_admin_key, "GET /admin/posts")
    conn = _conn()
    cur = conn.cursor()
    like = f"%{q}%"
    cur.execute("""
        SELECT p.id, p.title, p.category, COALESCE(u.nickname, '(탈퇴)'),
               p.created_at, p.views, p.likes,
               (SELECT count(*) FROM comments c WHERE c.post_id = p.id),
               (SELECT count(*) FROM post_reports r WHERE r.post_id = p.id)
        FROM posts p LEFT JOIN users u ON u.id = p.user_id
        WHERE (%s = '' OR p.title ILIKE %s OR p.content ILIKE %s)
        ORDER BY p.id DESC LIMIT %s
    """, (q, like, like, limit))
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {"posts": [
        {"id": r[0], "title": r[1], "category": r[2], "nickname": r[3],
         "created_at": str(r[4])[:19], "views": r[5], "likes": r[6],
         "comments": r[7], "reports": r[8]} for r in rows]}


@router.delete("/posts/{pid}")
def delete_post(pid: int, request: Request, x_admin_key: str | None = Header(default=None)):
    _check(request, x_admin_key, f"DELETE /admin/posts/{pid}")
    conn = _conn()
    cur = conn.cursor()
    cur.execute("DELETE FROM comments WHERE post_id = %s", (pid,))
    cur.execute("DELETE FROM post_reports WHERE post_id = %s", (pid,))
    cur.execute("DELETE FROM posts WHERE id = %s", (pid,))
    deleted = cur.rowcount
    conn.commit()
    cur.close()
    conn.close()
    if not deleted:
        raise HTTPException(status_code=404, detail="없는 게시글")
    return {"deleted": pid}


@router.get("/posts/{pid}/comments")
def list_comments(pid: int, request: Request, x_admin_key: str | None = Header(default=None)):
    _check(request, x_admin_key, f"GET /admin/posts/{pid}/comments")
    conn = _conn()
    cur = conn.cursor()
    cur.execute("""
        SELECT c.id, COALESCE(u.nickname, '(탈퇴)'), c.content, c.created_at
        FROM comments c LEFT JOIN users u ON u.id = c.user_id
        WHERE c.post_id = %s ORDER BY c.id
    """, (pid,))
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {"comments": [
        {"id": r[0], "nickname": r[1], "content": r[2],
         "created_at": str(r[3])[:19]} for r in rows]}


@router.delete("/comments/{cid}")
def delete_comment(cid: int, request: Request, x_admin_key: str | None = Header(default=None)):
    _check(request, x_admin_key, f"DELETE /admin/comments/{cid}")
    conn = _conn()
    cur = conn.cursor()
    cur.execute("DELETE FROM comments WHERE id = %s", (cid,))
    deleted = cur.rowcount
    conn.commit()
    cur.close()
    conn.close()
    if not deleted:
        raise HTTPException(status_code=404, detail="없는 댓글")
    return {"deleted": cid}


@router.get("/reports")
def list_reports(request: Request, x_admin_key: str | None = Header(default=None)):
    _check(request, x_admin_key, "GET /admin/reports")
    conn = _conn()
    cur = conn.cursor()
    cur.execute("""
        SELECT r.id, r.post_id, p.title, r.reason,
               COALESCE(u.nickname, '(탈퇴)'), r.created_at
        FROM post_reports r
        LEFT JOIN posts p ON p.id = r.post_id
        LEFT JOIN users u ON u.id = r.user_id
        ORDER BY r.id DESC LIMIT 100
    """)
    post_reports = [
        {"id": r[0], "post_id": r[1], "post_title": r[2] or "(삭제됨)",
         "reason": r[3], "reporter": r[4], "created_at": str(r[5])[:19]}
        for r in cur.fetchall()]
    cur.execute("""
        SELECT r.id, r.player_id, pl.name, r.handle, r.created_at
        FROM insta_handle_reports r
        LEFT JOIN players pl ON pl.id = r.player_id
        ORDER BY r.id DESC LIMIT 100
    """)
    insta_reports = [
        {"id": r[0], "player_id": r[1], "player": r[2] or "?",
         "handle": r[3], "created_at": str(r[4])[:19]}
        for r in cur.fetchall()]
    cur.close()
    conn.close()
    return {"post_reports": post_reports, "insta_reports": insta_reports}


@router.delete("/reports/post/{rid}")
def resolve_post_report(rid: int, request: Request, x_admin_key: str | None = Header(default=None)):
    _check(request, x_admin_key, f"DELETE /admin/reports/post/{rid}")
    conn = _conn()
    cur = conn.cursor()
    cur.execute("DELETE FROM post_reports WHERE id = %s", (rid,))
    conn.commit()
    cur.close()
    conn.close()
    return {"resolved": rid}


@router.delete("/reports/insta/{rid}")
def resolve_insta_report(rid: int, request: Request, x_admin_key: str | None = Header(default=None)):
    _check(request, x_admin_key, f"DELETE /admin/reports/insta/{rid}")
    conn = _conn()
    cur = conn.cursor()
    cur.execute("DELETE FROM insta_handle_reports WHERE id = %s", (rid,))
    conn.commit()
    cur.close()
    conn.close()
    return {"resolved": rid}


# ── 통계: DAU/가입 추이 (06-13) ──────────────────────────────────────────────

@router.get("/stats")
def admin_stats(request: Request, x_admin_key: str | None = Header(default=None)):
    """일별 DAU(30일) + 주/월 활성 + 가입 추이(30일) + 기능 사용량"""
    _check(request, x_admin_key, "GET /admin/stats")
    conn = _conn()
    cur = conn.cursor()
    out = {}
    try:
        cur.execute("""
            SELECT active_date, count(DISTINCT user_id)
            FROM daily_active_users
            WHERE active_date >= CURRENT_DATE - 29
            GROUP BY active_date ORDER BY active_date
        """)
        out["dau"] = [{"date": str(r[0]), "count": r[1]} for r in cur.fetchall()]
        cur.execute("""
            SELECT count(DISTINCT user_id) FROM daily_active_users
            WHERE active_date >= CURRENT_DATE - 6
        """)
        out["wau"] = cur.fetchone()[0]
        cur.execute("""
            SELECT count(DISTINCT user_id) FROM daily_active_users
            WHERE active_date >= CURRENT_DATE - 29
        """)
        out["mau"] = cur.fetchone()[0]
        cur.execute("""
            SELECT created_at::date, count(*)
            FROM users WHERE created_at >= CURRENT_DATE - 29
            GROUP BY 1 ORDER BY 1
        """)
        out["signups"] = [{"date": str(r[0]), "count": r[1]} for r in cur.fetchall()]
        # 기능 사용량 (전체 누적)
        for key, sql in [
            ("predictions", "SELECT count(*) FROM game_predictions"),
            ("visits", "SELECT count(*) FROM user_stadium_visits"),
            ("posts", "SELECT count(*) FROM posts"),
            ("points_users", "SELECT count(DISTINCT user_id) FROM point_ledger"),
        ]:
            try:
                cur.execute(sql)
                out[key] = cur.fetchone()[0]
            except Exception:
                conn.rollback()
                out[key] = None
    finally:
        cur.close()
        conn.close()
    return out


# ── app_config 편집: 배너/버전/시즌 단계 (06-13) ─────────────────────────────

_EDITABLE_CONFIG = ("banner", "min_version", "latest_version", "season_phase")


@router.get("/config")
def get_admin_config(request: Request, x_admin_key: str | None = Header(default=None)):
    _check(request, x_admin_key, "GET /admin/config")
    conn = _conn()
    cur = conn.cursor()
    cur.execute("SELECT key, value FROM app_config WHERE key = ANY(%s)", (list(_EDITABLE_CONFIG),))
    cfg = {k: v for k, v in cur.fetchall()}
    cur.close()
    conn.close()
    return {"config": cfg}


@router.post("/config")
def set_admin_config(body: dict, request: Request,
                     x_admin_key: str | None = Header(default=None)):
    """{key, value} — value=null이면 키 삭제(배너 해제). /app-config 캐시 즉시 무효화"""
    _check(request, x_admin_key, "POST /admin/config")
    key = (body or {}).get("key")
    value = (body or {}).get("value")
    if key not in _EDITABLE_CONFIG:
        raise HTTPException(status_code=400, detail=f"key는 {_EDITABLE_CONFIG} 중 하나")
    import json
    conn = _conn()
    cur = conn.cursor()
    if value is None:
        cur.execute("DELETE FROM app_config WHERE key = %s", (key,))
    else:
        cur.execute("""
            INSERT INTO app_config (key, value) VALUES (%s, %s)
            ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value
        """, (key, json.dumps(value)))
    conn.commit()
    cur.close()
    conn.close()
    try:
        from api.cache import cache_delete_prefix
        cache_delete_prefix('api.routers.app_config.get_app_config')
        cache_delete_prefix('api.routers.bootstrap.home_bootstrap')
    except Exception:
        pass
    log_admin_access(_client_ip(request), "POST /admin/config", f"{key}", "OK")
    return {"key": key, "value": value}


# ── 공지 푸시 발송 (06-13) ───────────────────────────────────────────────────

@router.post("/broadcast")
def broadcast_push(body: dict, request: Request,
                   x_admin_key: str | None = Header(default=None)):
    """{title, body} — 전체 push_tokens에 발송 + 인앱 알림함 저장"""
    _check(request, x_admin_key, "POST /admin/broadcast")
    title = ((body or {}).get("title") or "").strip()
    content = ((body or {}).get("body") or "").strip()
    if not title or not content:
        raise HTTPException(status_code=400, detail="title/body 필수")
    conn = _conn()
    cur = conn.cursor()
    cur.execute("SELECT DISTINCT user_id, token FROM push_tokens")
    targets = cur.fetchall()
    cur.close()
    conn.close()
    from api.fcm_service import _send
    _send([tuple(t) for t in targets], f"📢 {title}", content,
          {"type": "notice"}, "notice", None)
    log_admin_access(_client_ip(request), "POST /admin/broadcast", title[:40], "OK")
    return {"sent_users": len({t[0] for t in targets})}


# ── 시스템 상태 보드 (06-13) ─────────────────────────────────────────────────

@router.get("/health")
def admin_health(request: Request, x_admin_key: str | None = Header(default=None)):
    _check(request, x_admin_key, "GET /admin/health")
    conn = _conn()
    cur = conn.cursor()
    out = {}
    for key, sql in [
        ("scheduler_heartbeat", "SELECT value FROM app_config WHERE key='scheduler_heartbeat'"),
        ("roster_crawl_last", "SELECT max(change_date)::text FROM player_roster_changes"),
        ("games_updated_last", "SELECT max(updated_at)::text FROM games"),
        ("notifications_today",
         "SELECT count(*) FROM user_notifications WHERE created_at::date = CURRENT_DATE"),
        ("dau_today",
         "SELECT count(*) FROM daily_active_users WHERE active_date = (CURRENT_DATE + INTERVAL '9 hours')::date"),
    ]:
        try:
            cur.execute(sql)
            row = cur.fetchone()
            out[key] = row[0] if row else None
        except Exception:
            conn.rollback()
            out[key] = None
    # 최근 admin 명령
    try:
        cur.execute("""
            SELECT id, command, status, COALESCE(result,''), created_at::text
            FROM admin_commands ORDER BY id DESC LIMIT 5
        """)
        out["commands"] = [
            {"id": r[0], "command": r[1], "status": r[2], "result": r[3], "at": r[4][:19]}
            for r in cur.fetchall()]
    except Exception:
        conn.rollback()
        out["commands"] = []
    cur.close()
    conn.close()
    # 백업 최근 파일 (서버 로컬)
    try:
        import glob
        backups = sorted(glob.glob('/home/ubuntu/backups/*.gz'), key=os.path.getmtime)
        if backups:
            latest = backups[-1]
            out["backup_last"] = {
                "file": os.path.basename(latest),
                "mtime": __import__('datetime').datetime.fromtimestamp(
                    os.path.getmtime(latest)).isoformat()[:19],
                "size_mb": round(os.path.getsize(latest) / 1048576, 1),
            }
        else:
            out["backup_last"] = None
    except Exception:
        out["backup_last"] = None
    return out


@router.post("/commands")
def enqueue_command(body: dict, request: Request,
                    x_admin_key: str | None = Header(default=None)):
    """수동 작업 큐 등록 — scheduler가 30초 내 소비. command: recrawl_roster|recrawl_rankings|recrawl_today_games"""
    _check(request, x_admin_key, "POST /admin/commands")
    command = (body or {}).get("command")
    if command not in ("recrawl_roster", "recrawl_rankings", "recrawl_today_games"):
        raise HTTPException(status_code=400, detail="지원하지 않는 명령")
    conn = _conn()
    cur = conn.cursor()
    cur.execute("INSERT INTO admin_commands (command, status) VALUES (%s, 'pending') RETURNING id",
                (command,))
    cmd_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    conn.close()
    log_admin_access(_client_ip(request), "POST /admin/commands", command, "OK")
    return {"id": cmd_id, "command": command}


# ── 포인트 수동 지급 (06-13) ─────────────────────────────────────────────────

@router.post("/points")
def grant_points(body: dict, request: Request,
                 x_admin_key: str | None = Header(default=None)):
    """{user_id, points(±), memo} — 원장 reason='admin' (음수 = 회수)"""
    _check(request, x_admin_key, "POST /admin/points")
    user_id = (body or {}).get("user_id")
    points = (body or {}).get("points")
    memo = ((body or {}).get("memo") or "").strip()[:80]
    if not isinstance(user_id, int) or not isinstance(points, int) or points == 0:
        raise HTTPException(status_code=400, detail="user_id/points 확인")
    import uuid
    from api.points import award
    conn = _conn()
    cur = conn.cursor()
    award(cur, user_id, 'admin', f"{uuid.uuid4().hex[:12]}:{memo}", points=points)
    conn.commit()
    cur.close()
    conn.close()
    log_admin_access(_client_ip(request), "POST /admin/points",
                     f"user={user_id} pts={points}", "OK")
    return {"user_id": user_id, "points": points}


# ── 댓글 검색 (06-13 — 삭제는 기존 DELETE /comments/{cid}) ───────────────────

@router.get("/comments")
def list_comments(request: Request, q: str = "", limit: int = Query(50, le=200),
                  x_admin_key: str | None = Header(default=None)):
    _check(request, x_admin_key, "GET /admin/comments")
    conn = _conn()
    cur = conn.cursor()
    like = f"%{q}%"
    cur.execute("""
        SELECT c.id, c.post_id, LEFT(c.content, 80), COALESCE(u.nickname, '(탈퇴)'),
               c.created_at
        FROM comments c LEFT JOIN users u ON u.id = c.user_id
        WHERE (%s = '' OR c.content ILIKE %s)
        ORDER BY c.id DESC LIMIT %s
    """, (q, like, limit))
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {"comments": [
        {"id": r[0], "post_id": r[1], "content": r[2], "author": r[3],
         "created_at": str(r[4])[:19]} for r in rows]}


# ── 인스타 핸들 즉석 수정 (06-13) ────────────────────────────────────────────

@router.put("/players/{pid}/insta")
def set_insta_handle(pid: int, body: dict, request: Request,
                     x_admin_key: str | None = Header(default=None)):
    """{handle: 'xxx' | null} — null이면 핸들 제거"""
    _check(request, x_admin_key, f"PUT /admin/players/{pid}/insta")
    handle = (body or {}).get("handle")
    if handle is not None:
        handle = handle.strip().lstrip('@') or None
    conn = _conn()
    cur = conn.cursor()
    cur.execute("UPDATE players SET insta_handle = %s WHERE id = %s RETURNING name", (handle, pid))
    row = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="없는 선수")
    log_admin_access(_client_ip(request), f"PUT /admin/players/{pid}/insta", str(handle), "OK")
    return {"player_id": pid, "name": row[0], "handle": handle}


# ── 계정 정지 (06-13 — 삭제 외 운영 수단) ────────────────────────────────────

@router.post("/users/{uid}/suspend")
def suspend_user(uid: int, body: dict, request: Request,
                 x_admin_key: str | None = Header(default=None)):
    """{days: N} — N일 정지. days=0 = 해제"""
    _check(request, x_admin_key, f"POST /admin/users/{uid}/suspend")
    days = (body or {}).get("days")
    if not isinstance(days, int) or days < 0 or days > 3650:
        raise HTTPException(status_code=400, detail="days 0~3650")
    conn = _conn()
    cur = conn.cursor()
    if days == 0:
        cur.execute("UPDATE users SET suspended_until = NULL WHERE id = %s RETURNING id", (uid,))
    else:
        cur.execute(
            "UPDATE users SET suspended_until = now() + (%s * INTERVAL '1 day') WHERE id = %s RETURNING id",
            (days, uid))
    row = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="없는 유저")
    log_admin_access(_client_ip(request), f"POST /admin/users/{uid}/suspend", f"days={days}", "OK")
    return {"user_id": uid, "days": days}


# ── 알림 발송 내역 / 보안 로그 (06-13) ───────────────────────────────────────

@router.get("/notifications")
def list_notifications(request: Request, limit: int = Query(50, le=200),
                       x_admin_key: str | None = Header(default=None)):
    _check(request, x_admin_key, "GET /admin/notifications")
    conn = _conn()
    cur = conn.cursor()
    cur.execute("""
        SELECT id, user_id, type, LEFT(title, 60), created_at
        FROM user_notifications ORDER BY id DESC LIMIT %s
    """, (limit,))
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {"notifications": [
        {"id": r[0], "user_id": r[1], "type": r[2], "title": r[3],
         "created_at": str(r[4])[:19]} for r in rows]}


@router.get("/seclog")
def security_log_tail(request: Request, lines: int = Query(60, le=300),
                      x_admin_key: str | None = Header(default=None)):
    _check(request, x_admin_key, "GET /admin/seclog")
    path = os.path.join(os.environ.get("LOG_DIR", "/home/ubuntu/playball/logs"), "security.log")
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            tail = f.readlines()[-lines:]
        return {"lines": [ln.rstrip() for ln in tail]}
    except FileNotFoundError:
        return {"lines": []}


# ── 기능 킬스위치 토글 (app_config.kill_switches) ────────────────────────────

# 토글 가능한 기능 목록 (UI 라벨용) — 클라 AppConfig.enabled(키)와 1:1.
# OFF 시 앱/웹에서 해당 섹션 숨김(graceful). 추가 시 클라에도 AppConfig.enabled(키) 가드 필수.
FEATURES = {
    "points":      "포인트/승부예측 (게임카드 팬투표·마이페이지 포인트·출석)",
    "prediction":  "AI 승리 예측 바",
    "community":   "커뮤니티",
    "win_prob":    "라이브 승률 그래프 (경기상세 중계탭)",
    "bullpen":     "불펜 피로도 신호등 (경기상세 로스터)",
    "pitch_zone":  "피칭 디자인·존 히트맵 (선수상세)",
    "highlights":  "하이라이트 (경기상세)",
    "weather":     "구장 날씨 (경기상세)",
    "share":       "공유 카드 (선수·직관 이미지 공유)",
    "narrative":   "AI 한줄평·오늘의 MVP·라이브 상황 캡션 (경기상세)",
}


@router.get("/feature-flags")
def get_feature_flags(request: Request, x_admin_key: str | None = Header(default=None)):
    _check(request, x_admin_key, "GET /admin/feature-flags")
    conn = _conn()
    cur = conn.cursor()
    cur.execute("SELECT value FROM app_config WHERE key = 'kill_switches'")
    row = cur.fetchone()
    cur.close()
    conn.close()
    ks = row[0] if row and isinstance(row[0], dict) else {}
    return {"features": [
        {"key": k, "label": label, "enabled": ks.get(k) is not False}
        for k, label in FEATURES.items()
    ]}


@router.post("/feature-flags")
def set_feature_flag(body: dict, request: Request,
                     x_admin_key: str | None = Header(default=None)):
    """{feature, enabled} — kill_switches JSONB 갱신. 클라 전파 = /app-config 캐시 60초 내."""
    _check(request, x_admin_key, "POST /admin/feature-flags")
    feature = (body or {}).get("feature")
    enabled = (body or {}).get("enabled")
    if feature not in FEATURES or not isinstance(enabled, bool):
        raise HTTPException(status_code=400, detail="feature/enabled 확인")
    import json
    conn = _conn()
    cur = conn.cursor()
    cur.execute("SELECT value FROM app_config WHERE key = 'kill_switches'")
    row = cur.fetchone()
    ks = row[0] if row and isinstance(row[0], dict) else {}
    if enabled:
        ks.pop(feature, None)  # 명시 false만 비활성 — 켜면 키 제거
    else:
        ks[feature] = False
    if row:
        cur.execute("UPDATE app_config SET value = %s WHERE key = 'kill_switches'",
                    (json.dumps(ks),))
    else:
        cur.execute("INSERT INTO app_config (key, value) VALUES ('kill_switches', %s)",
                    (json.dumps(ks),))
    conn.commit()
    cur.close()
    conn.close()
    # /app-config 캐시 즉시 무효화 (60초 대기 제거) — 키 = "{module}.{fn}:{args}:..."
    try:
        from api.cache import cache_delete_prefix
        cache_delete_prefix('api.routers.app_config.get_app_config')
    except Exception:
        pass
    log_admin_access(_client_ip(request), "POST /admin/feature-flags",
                     f"{feature}={enabled}", "OK")
    return {"feature": feature, "enabled": enabled, "kill_switches": ks}


# ── 서비스 복구 (API 프로세스 직접 실행) ──────────────────────────────────────
# 큐(admin_commands)는 scheduler 프로세스가 소비 → API 메모리의 캐시/풀은 못 건드림.
# 캐시 오염·풀 고갈·날씨 cold 등 "기능이 죽었을 때" API 프로세스서 즉시 복구.
@router.post("/maintenance")
def run_maintenance(body: dict, request: Request,
                    x_admin_key: str | None = Header(default=None)):
    """{action} — clear_cache | reset_db_pool | rewarm_weather | all"""
    _check(request, x_admin_key, "POST /admin/maintenance")
    action = (body or {}).get("action")
    valid = ("clear_cache", "reset_db_pool", "rewarm_weather", "all")
    if action not in valid:
        raise HTTPException(status_code=400, detail=f"action 확인: {valid}")
    done = []
    if action in ("clear_cache", "all"):
        try:
            from api.cache import cache_delete_prefix
            n = cache_delete_prefix('')  # 빈 prefix = 전 키 삭제
            done.append(f"API 캐시 {n}건 클리어")
        except Exception as e:
            done.append(f"캐시 클리어 실패: {e}")
    if action in ("reset_db_pool", "all"):
        try:
            from database.connection import _reset_pool
            _reset_pool()
            done.append("DB 커넥션 풀 재생성")
        except Exception as e:
            done.append(f"풀 리셋 실패: {e}")
    if action in ("rewarm_weather", "all"):
        try:
            from api import weather_service
            weather_service._cache.clear()
            done.append("날씨 캐시 비움 (다음 요청 시 재워밍)")
        except Exception as e:
            done.append(f"날씨 리워밍 실패: {e}")
    log_admin_access(_client_ip(request), "POST /admin/maintenance", str(action), "OK")
    return {"action": action, "results": done}
