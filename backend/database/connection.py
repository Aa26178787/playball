import os
import psycopg2
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
    "password": "playball1234",
}

_pool: pool.ThreadedConnectionPool | None = None


def _get_pool() -> pool.ThreadedConnectionPool:
    global _pool
    if _pool is None:
        maxconn = int(os.environ.get('DB_POOL_MAX', '20'))
        minconn = min(3, maxconn)
        _pool = pool.ThreadedConnectionPool(minconn=minconn, maxconn=maxconn, **DB_CONFIG)
    return _pool


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
        conn = _get_pool().getconn()
        return _PooledConn(conn)
    except Exception as e:
        print(f"DB 연결 오류: {e}")
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
