import psycopg2
from psycopg2 import pool

DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "dbname": "playball",
    "user": "playball_user",
    "password": "playball1234",
}

_pool: pool.ThreadedConnectionPool | None = None


def _get_pool() -> pool.ThreadedConnectionPool:
    global _pool
    if _pool is None:
        _pool = pool.ThreadedConnectionPool(minconn=5, maxconn=20, **DB_CONFIG)
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
