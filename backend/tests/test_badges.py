"""뱃지 엔진 회귀 (DB 필요). evaluate_badges 멱등 + 임계값 경계."""
import os

import pytest

pytestmark = pytest.mark.skipif(
    not os.environ.get("TEST_DATABASE_URL"), reason="no test db")


def _setup(conn):
    cur = conn.cursor()
    for ddl in [
        "DROP TABLE IF EXISTS user_badges",
        "DROP TABLE IF EXISTS point_ledger",
        "DROP TABLE IF EXISTS user_stadium_visits",
        "DROP TABLE IF EXISTS games",
        "CREATE TABLE user_badges (user_id INT, badge_id TEXT, UNIQUE(user_id, badge_id))",
        ("CREATE TABLE point_ledger (id SERIAL PRIMARY KEY, user_id INT, points INT, "
         "reason TEXT, ref_key TEXT, UNIQUE(user_id, reason, ref_key))"),
        "CREATE TABLE games (id INT PRIMARY KEY, stadium_id INT)",
        "CREATE TABLE user_stadium_visits (user_id INT, game_id INT)",
    ]:
        cur.execute(ddl)
    cur.close()


def test_badges_earn_and_idempotent(db):
    _setup(db)
    from api.badges import evaluate_badges
    cur = db.cursor()
    # 적중 1회 + 출석 7일 → pred_win_1, attend_7 충족 / pred_win_10 미충족
    cur.execute("INSERT INTO point_ledger (user_id,points,reason,ref_key) "
                "VALUES (1,50,'prediction_win','pred:1')")
    for i in range(7):
        cur.execute("INSERT INTO point_ledger (user_id,points,reason,ref_key) "
                    "VALUES (1,5,'attendance',%s)", (f"d{i}",))

    out = evaluate_badges(cur, 1)
    earned = {b["id"] for b in out if b["earned"]}
    assert "pred_win_1" in earned
    assert "attend_7" in earned
    assert "pred_win_10" not in earned

    cur.execute("SELECT COUNT(*) FROM user_badges WHERE user_id=1")
    n1 = cur.fetchone()[0]
    evaluate_badges(cur, 1)  # 재평가 — 멱등
    cur.execute("SELECT COUNT(*) FROM user_badges WHERE user_id=1")
    assert cur.fetchone()[0] == n1
