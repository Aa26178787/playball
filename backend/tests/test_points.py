"""포인트 원장 멱등 회귀 테스트 (DB 필요 — TEST_DATABASE_URL).

guard 대상: award()의 UNIQUE(user_id, reason, ref_key) dedup
(정산 재실행/중복 호출 시 이중 적립 방지).
"""
import os

import pytest

pytestmark = pytest.mark.skipif(
    not os.environ.get("TEST_DATABASE_URL"), reason="no test db")


def test_award_idempotent(db):
    from api.points import award, total_points
    cur = db.cursor()
    cur.execute("DROP TABLE IF EXISTS point_ledger")
    cur.execute("""
        CREATE TABLE point_ledger (
            id SERIAL PRIMARY KEY,
            user_id INT,
            points INT,
            reason TEXT,
            ref_key TEXT,
            UNIQUE (user_id, reason, ref_key)
        )
    """)
    assert award(cur, 1, "prediction_win", "pred:42") == 1   # 신규 적립
    assert award(cur, 1, "prediction_win", "pred:42") == 0   # 중복 → dedup
    assert award(cur, 1, "attendance", "2026-06-15") == 1
    assert total_points(cur, 1) == 55  # 50(prediction_win) + 5(attendance)
