"""DAU 측정 — 인증 요청의 user_id를 일별 기록 (관리자 통계용, 06-13).

미들웨어에서 Authorization JWT를 가볍게 디코드해 메모리 set에 적재,
60초마다 daily_active_users(user_id, active_date PK)로 flush (upsert).
실패는 전부 무음 — 통계가 본 요청을 방해하면 안 됨.
"""
import threading
import time
from datetime import datetime, timedelta, timezone

_pending: set[tuple[int, str]] = set()
_lock = threading.Lock()
_flusher_started = False


def _kst_today() -> str:
    return (datetime.now(timezone.utc) + timedelta(hours=9)).strftime('%Y-%m-%d')


def record_user(user_id: int):
    with _lock:
        _pending.add((user_id, _kst_today()))
    _ensure_flusher()


def record_from_auth_header(authorization: str | None):
    """'Bearer xxx' 헤더에서 user_id 추출 기록 (서명 검증 포함 — 위조 토큰 무시)"""
    if not authorization or not authorization.startswith('Bearer '):
        return
    try:
        from api.routers.auth import SECRET_KEY, ALGORITHM
        import jwt
        payload = jwt.decode(authorization[7:], SECRET_KEY, algorithms=[ALGORITHM])
        uid = int(payload.get('sub', 0))  # 토큰 payload: sub=str(user_id)
        if uid > 0:
            record_user(uid)
    except Exception:
        pass


def _flush():
    with _lock:
        if not _pending:
            return
        batch = list(_pending)
        _pending.clear()
    try:
        from database.connection import get_connection
        conn = get_connection()
        if not conn:
            return
        try:
            cur = conn.cursor()
            cur.executemany(
                """
                INSERT INTO daily_active_users (user_id, active_date)
                VALUES (%s, %s) ON CONFLICT DO NOTHING
                """,
                batch,
            )
            conn.commit()
            cur.close()
        finally:
            conn.close()
    except Exception:
        pass


def _ensure_flusher():
    global _flusher_started
    if _flusher_started:
        return
    _flusher_started = True

    def loop():
        while True:
            time.sleep(60)
            _flush()

    threading.Thread(target=loop, daemon=True).start()
