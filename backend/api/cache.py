import time
import threading
import functools
from typing import Any

_store: dict[str, tuple[Any, float]] = {}
_lock = threading.Lock()


def cache_get(key: str) -> tuple[bool, Any]:
    with _lock:
        if key in _store:
            value, expires = _store[key]
            if time.monotonic() < expires:
                return True, value
            del _store[key]
    return False, None


def cache_set(key: str, value: Any, ttl: int) -> None:
    with _lock:
        _store[key] = (value, time.monotonic() + ttl)


def cached(ttl: int):
    """Decorator: cache FastAPI sync route return value by function name + args."""
    def decorator(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            key = f"{fn.__module__}.{fn.__name__}:{args}:{sorted(kwargs.items())}"
            hit, value = cache_get(key)
            if hit:
                return value
            result = fn(*args, **kwargs)
            cache_set(key, result, ttl)
            return result
        return wrapper
    return decorator
