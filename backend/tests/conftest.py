import os

import pytest


@pytest.fixture
def db():
    """일회용 테스트 DB 연결 (autocommit). TEST_DATABASE_URL 미설정이면 skip.
    DB 의존 테스트(토큰/포인트)만 사용 — 순수 파서 테스트는 이 fixture 불요."""
    url = os.environ.get("TEST_DATABASE_URL")
    if not url:
        pytest.skip("TEST_DATABASE_URL 미설정 — DB 테스트 건너뜀")
    import psycopg2
    conn = psycopg2.connect(url)
    conn.autocommit = True
    yield conn
    conn.close()
