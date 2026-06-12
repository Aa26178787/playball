import time
import threading
import functools
from typing import Any

# ─── 인메모리 TTL 캐시 ───────────────────────────────────────────────────────
# 목적: DB/Naver API 호출 빈도 감소
# 주의: 단일 프로세스 내 공유 (gunicorn multi-worker 전환 시 Redis로 교체 필요)

# key -> (value, fresh_until, stale_until)
# fresh_until 이전 = 신선, 이후~stale_until = stale(SWR 반환 가능), 이후 = 제거 대상
_store: dict[str, tuple[Any, float, float]] = {}
_global_lock = threading.Lock()

# SWR 백그라운드 갱신 중복 방지 (키별 in-flight 플래그)
_refreshing: set[str] = set()

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
    """신선한 값만 hit. (stale은 cache_get_stale로)"""
    with _global_lock:
        if key in _store:
            value, fresh_until, stale_until = _store[key]
            now = time.monotonic()
            if now < fresh_until:
                return True, value
            if now >= stale_until:
                del _store[key]
    return False, None


def cache_get_stale(key: str) -> tuple[bool, Any]:
    """만료됐지만 stale 보관 기간 내인 값. (신선 값도 True)"""
    with _global_lock:
        if key in _store:
            value, _fresh, stale_until = _store[key]
            if time.monotonic() < stale_until:
                return True, value
            del _store[key]
    return False, None


def cache_set(key: str, value: Any, ttl: int, stale_factor: int = 10) -> None:
    """ttl 동안 신선, 이후 ttl*stale_factor까지 stale 보관 (SWR 재료)."""
    now = time.monotonic()
    with _global_lock:
        _store[key] = (value, now + ttl, now + ttl * stale_factor)


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


def cached(ttl: int, swr: bool = True):
    """Decorator: cache FastAPI sync route return value by function name + args.

    swr=True (기본): 만료 시 stale 값을 즉시 반환하고 백그라운드 스레드가 갱신
    — cold 블로킹(Naver fetch 수 초)이 p99을 끌던 문제 해소 (날씨 워머 패턴 일반화).
    첫 호출(캐시 전무)만 동기 실행. swr=False = 기존 동작(만료 시 동기 재계산).
    """
    def decorator(fn):
        def _refresh_async(key, args, kwargs):
            def run():
                try:
                    result = fn(*args, **kwargs)
                    cache_set(key, result, ttl)
                except Exception:
                    pass  # 갱신 실패 = 기존 stale 유지, 다음 요청이 재시도
                finally:
                    with _global_lock:
                        _refreshing.discard(key)
            threading.Thread(target=run, daemon=True).start()

        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            key = f"{fn.__module__}.{fn.__name__}:{args}:{sorted(kwargs.items())}"

            # 1차 체크: 락 없이 빠른 경로
            hit, value = cache_get(key)
            if hit:
                return value

            # SWR: stale이 있으면 즉시 반환 + 백그라운드 1회 갱신
            if swr:
                stale_hit, stale_value = cache_get_stale(key)
                if stale_hit:
                    with _global_lock:
                        should_refresh = key not in _refreshing
                        if should_refresh:
                            _refreshing.add(key)
                    if should_refresh:
                        _refresh_async(key, args, kwargs)
                    return stale_value

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
