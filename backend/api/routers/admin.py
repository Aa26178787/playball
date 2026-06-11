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


# ── 기능 킬스위치 토글 (app_config.kill_switches) ────────────────────────────

# 토글 가능한 기능 목록 (UI 라벨용) — 클라 AppConfig.enabled(키)와 1:1
FEATURES = {
    "points": "포인트/승부예측 (게임카드 팬투표·마이페이지 포인트·출석)",
    "prediction": "AI 승리 예측 바",
    "community": "커뮤니티",
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
