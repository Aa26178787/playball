import time
import threading
import functools
from typing import Any

# ─── 인메모리 TTL 캐시 ───────────────────────────────────────────────────────
# 목적: DB/Naver API 호출 빈도 감소
# 주의: 단일 프로세스 내 공유 (gunicorn multi-worker 전환 시 Redis로 교체 필요)

_store: dict[str, tuple[Any, float]] = {}
_global_lock = threading.Lock()

# ─── thundering herd 방지용 per-key lock ────────────────────────────────────
# 문제: 캐시 만료 순간 동시 요청이 몰리면 모든 스레드가 fn()을 동시에 실행
#       → DB/외부 API에 N배 부하 발생 (thundering herd)
# 해결: 키별 Lock으로 첫 번째 스레드만 fn() 실행, 나머지는 결과 대기
# 사용자 1000명 이상 동시접속 시 캐시 만료 시점의 DB 폭발 방지
_key_locks: dict[str, threading.Lock] = {}


def _get_key_lock(key: str) -> threading.Lock:
    """키별 Lock 반환 (없으면 생성). global_lock으로 dict 접근 보호."""
    with _global_lock:
        if key not in _key_locks:
            _key_locks[key] = threading.Lock()
        return _key_locks[key]


def cache_get(key: str) -> tuple[bool, Any]:
    with _global_lock:
        if key in _store:
            value, expires = _store[key]
            if time.monotonic() < expires:
                return True, value
            del _store[key]
    return False, None


def cache_set(key: str, value: Any, ttl: int) -> None:
    with _global_lock:
        _store[key] = (value, time.monotonic() + ttl)


def cache_delete(key: str) -> bool:
    with _global_lock:
        if key in _store:
            del _store[key]
            return True
    return False


def cache_delete_prefix(prefix: str) -> int:
    """prefix로 시작하는 모든 키 삭제."""
    with _global_lock:
        keys = [k for k in _store if k.startswith(prefix)]
        for k in keys:
            del _store[k]
        return len(keys)


def cached(ttl: int):
    """Decorator: cache FastAPI sync route return value by function name + args."""
    def decorator(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            key = f"{fn.__module__}.{fn.__name__}:{args}:{sorted(kwargs.items())}"

            # 1차 체크: 락 없이 빠른 경로
            hit, value = cache_get(key)
            if hit:
                return value

            # per-key lock 획득 후 2차 체크 (double-checked locking)
            # 다른 스레드가 이미 fn()을 실행 중이면 여기서 대기
            key_lock = _get_key_lock(key)
            with key_lock:
                hit, value = cache_get(key)
                if hit:
                    # 앞선 스레드가 이미 채워줬음 — DB 호출 불필요
                    return value
                result = fn(*args, **kwargs)
                cache_set(key, result, ttl)
                return result

        return wrapper
    return decorator
