import os
import threading
from psycopg2 import pool

DB_CONFIG = {
    "host": "localhost",
    # PgBouncer 포트 (6432) → PostgreSQL 5432로 중계
    # 목적: 1000명 동시접속 시 connection pool 고갈 방지
    #   - PgBouncer: 클라이언트 최대 1000 소켓 수용
    #   - PostgreSQL: 실제 20개 연결만 유지 (transaction pool mode)
    # 삭제/변경 금지: 5432로 되돌리면 동시접속 폭증 시 DB pool 즉시 고갈
    # PgBouncer 설정: /etc/pgbouncer/pgbouncer.ini
    "port": 6432,
    "dbname": "playball",
    "user": "playball_user",
    # env 필수 (systemd Environment=DB_PASSWORD / 로컬은 export). 미설정 시 빈값 → 인증 실패로 명시 (평문 fallback 금지)
    "password": os.environ.get("DB_PASSWORD", ""),
}

_pool: pool.ThreadedConnectionPool | None = None
_pool_lock = threading.Lock()


def _get_pool() -> pool.ThreadedConnectionPool:
    global _pool
    if _pool is None:
        maxconn = int(os.environ.get('DB_POOL_MAX', '20'))
        minconn = min(3, maxconn)
        _pool = pool.ThreadedConnectionPool(minconn=minconn, maxconn=maxconn, **DB_CONFIG)
    return _pool


def _reset_pool():
    global _pool
    with _pool_lock:
        if _pool is not None:
            try:
                _pool.closeall()
            except Exception:
                pass
            _pool = None


class _PooledConn:
    """Wraps a pooled psycopg2 connection. close() returns to pool instead of dropping."""
    def __init__(self, conn):
        self._conn = conn
        self._closed = False

    def cursor(self, *args, **kwargs):
        return self._conn.cursor(*args, **kwargs)

    def commit(self):
        return self._conn.commit()

    def rollback(self):
        return self._conn.rollback()

    def close(self):
        if not self._closed:
            self._closed = True
            try:
                _get_pool().putconn(self._conn)
            except Exception:
                pass

    def __getattr__(self, name):
        return getattr(self._conn, name)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, *_):
        if exc_type:
            self.rollback()
        self.close()


def get_connection() -> _PooledConn | None:
    """Return a pooled DB connection. Call conn.close() to return it to the pool."""
    try:
        return _PooledConn(_get_pool().getconn())
    except pool.PoolError as e:
        if 'exhausted' in str(e).lower():
            print(f"[DB] 풀 고갈 감지 → 풀 재생성")
            _reset_pool()
            try:
                return _PooledConn(_get_pool().getconn())
            except Exception as e2:
                print(f"[DB] 풀 재생성 후 연결 실패: {e2}")
                return None
        print(f"[DB] 연결 오류: {e}")
        return None
    except Exception as e:
        print(f"[DB] 연결 오류: {e}")
        return None


def test_connection():
    conn = get_connection()
    if conn:
        print("DB 연결 성공!")
        conn.close()
    else:
        print("DB 연결 실패!")


if __name__ == "__main__":
    test_connection()
