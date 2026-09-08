"""_PooledConn 누수 안전망 테스트 (DB 불요 — 가짜 conn/pool)."""
import gc
from psycopg2 import pool
import database.connection as c


class _FakeConn:
    def __init__(self):
        self.rolled = 0

    def rollback(self):
        self.rolled += 1


class _FakePool:
    def __init__(self):
        self.returned = []

    def putconn(self, conn):
        self.returned.append(conn)


def _install_fake_pool():
    fake = _FakePool()
    c._pool = fake          # _get_pool()는 _pool이 None 아니면 그대로 반환
    return fake


def teardown_function(_):
    c._pool = None          # 실 풀 lazy 재생성되도록 복원


def test_del_returns_leaked_connection():
    """close() 호출 없이 스코프를 벗어난 커넥션도 __del__이 rollback+반납."""
    fake = _install_fake_pool()
    fc = _FakeConn()

    def leak():
        _ = c._PooledConn(fc)   # 의도적으로 close() 안 함 (누수 시나리오)

    leak()
    gc.collect()
    assert fc in fake.returned          # 풀로 반납됨
    assert fc.rolled == 1               # 반납 전 rollback 1회


def test_explicit_close_then_del_no_double():
    """명시 close() 후 __del__은 no-op (이중 반납 금지)."""
    fake = _install_fake_pool()
    fc = _FakeConn()
    pc = c._PooledConn(fc)
    pc.close()
    del pc
    gc.collect()
    assert fake.returned.count(fc) == 1
    assert fc.rolled == 1


def test_context_manager_closes_once():
    """with 블록 종료 시 1회만 반납, 이후 __del__ no-op."""
    fake = _install_fake_pool()
    fc = _FakeConn()
    with c._PooledConn(fc):
        pass
    gc.collect()
    assert fake.returned.count(fc) == 1


def test_exhausted_pool_does_not_close_active_connections():
    class ExhaustedPool:
        closed = False

        def getconn(self):
            raise pool.PoolError('connection pool exhausted')

        def closeall(self):
            self.closed = True

    fake = ExhaustedPool()
    c._pool = fake

    assert c.get_connection() is None
    assert fake.closed is False
