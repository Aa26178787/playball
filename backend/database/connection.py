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
        with _pool_lock:
            if _pool is None:
                maxconn = int(os.environ.get('DB_POOL_MAX', '20'))
                minconn = min(3, maxconn)
                _pool = pool.ThreadedConnectionPool(
                    minconn=minconn, maxconn=maxconn, **DB_CONFIG
                )
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
    def __init__(self, conn, owner_pool=None):
        self._conn = conn
        self._owner_pool = owner_pool or _get_pool()
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
            # 반납 전 rollback — 커밋 안 한 열린/aborted 트랜잭션을 정리해
            # 풀에 'idle in transaction' 상태로 되돌아가는 것 방지(누수/락 위생).
            # 커밋된 작업은 영향 없음(rollback no-op), 미커밋분은 어차피 비영속.
            try:
                self._conn.rollback()
            except Exception:
                pass
            try:
                self._owner_pool.putconn(self._conn)
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

    def __del__(self):
        # 안전망: 명시 close() 누락(예외/조기 return)으로 이 래퍼가 스코프를 벗어나면
        # CPython refcount가 여기서 close()(rollback+풀반납)를 호출 → 커넥션 누수 방지.
        # 정상 경로는 _closed=True라 no-op. get_connection 322개 사용처 전역 retrofit.
        # ⚠️ CPython 결정적 GC 전제(서버=CPython). 부분초기화/셧다운엔 close()가 자체 try로 흡수.
        try:
            self.close()
        except Exception:
            pass


def get_connection() -> _PooledConn | None:
    """Return a pooled DB connection. Call conn.close() to return it to the pool."""
    try:
        owner_pool = _get_pool()
        return _PooledConn(owner_pool.getconn(), owner_pool)
    except pool.PoolError as e:
        if 'exhausted' in str(e).lower():
            print("[DB] 풀 고갈: 활성 연결을 유지하고 요청을 거절합니다")
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
