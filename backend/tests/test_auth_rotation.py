"""refresh_token 회전/캡/정리 회귀 테스트 (DB 필요 — TEST_DATABASE_URL).

guard 대상:
- 캡: 활성 토큰 최신 5개만 유지 (역전 버그 = 최신 토큰 삭제 → 간헐 로그아웃)
- 정리: revoked/만료 토큰을 create 시 삭제 (bloat 방지)
"""
import os

import pytest

pytestmark = pytest.mark.skipif(
    not os.environ.get("TEST_DATABASE_URL"), reason="no test db")


def _reset(conn):
    cur = conn.cursor()
    cur.execute("DROP TABLE IF EXISTS refresh_tokens")
    cur.execute("""
        CREATE TABLE refresh_tokens (
            id SERIAL PRIMARY KEY,
            user_id INT,
            token_hash TEXT,
            expires_at TIMESTAMPTZ,
            created_at TIMESTAMPTZ DEFAULT now(),
            revoked BOOLEAN DEFAULT FALSE
        )
    """)
    cur.close()


def _patch(monkeypatch, conn):
    """auth.get_connection이 테스트 conn을 쓰게 — close()는 풀 반환 흉내(no-op)."""
    import api.routers.auth as auth

    class _Shim:
        def cursor(self, *a, **k):
            return conn.cursor(*a, **k)

        def commit(self):
            pass  # autocommit

        def close(self):
            pass  # 실제 conn 유지

        def __getattr__(self, n):
            return getattr(conn, n)

    monkeypatch.setattr(auth, "get_connection", lambda: _Shim())
    return auth


def test_cap_keeps_five_newest_active(db, monkeypatch):
    _reset(db)
    auth = _patch(monkeypatch, db)
    for _ in range(8):
        auth.create_refresh_token(1)
    cur = db.cursor()
    cur.execute("SELECT count(*) FROM refresh_tokens WHERE user_id=1 AND revoked=FALSE")
    assert cur.fetchone()[0] == 5  # 캡 최신 4개 + 직전 INSERT 1개


def test_create_purges_dead_rows(db, monkeypatch):
    _reset(db)
    auth = _patch(monkeypatch, db)
    cur = db.cursor()
    cur.execute("INSERT INTO refresh_tokens (user_id, token_hash, expires_at, revoked) "
                "VALUES (1, 'revoked_tok', now() + interval '1 day', TRUE)")
    cur.execute("INSERT INTO refresh_tokens (user_id, token_hash, expires_at, revoked) "
                "VALUES (1, 'expired_tok', now() - interval '1 day', FALSE)")
    auth.create_refresh_token(1)  # 정리 트리거
    cur.execute("SELECT count(*) FROM refresh_tokens "
                "WHERE token_hash IN ('revoked_tok', 'expired_tok')")
    assert cur.fetchone()[0] == 0
