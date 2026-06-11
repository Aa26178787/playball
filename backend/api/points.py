"""포인트 원장 — 메가B 리텐션 토대.

모든 적립/차감은 award() 경유. UNIQUE(user_id, reason, ref_key)가 멱등 보장
(notification_log dedup 패턴) — 정산 재실행/중복 호출 안전.
"""
import logging

logger = logging.getLogger(__name__)

# 적립 규칙 v1
POINTS = {
    'prediction_win': 50,   # 승부예측 적중
    'prediction_lose': 10,  # 참여 (빗나감)
    'prediction_draw': 10,  # 무승부 — 참여 보상
    'attendance': 5,        # 일일 출석 (앱 접속)
    'visit_record': 20,     # 직관 기록 작성
}


def award(cur, user_id: int, reason: str, ref_key: str, points: int | None = None) -> int:
    """적립 시도. 반환 1=신규 적립 / 0=이미 적립(dedup). commit은 호출측."""
    p = points if points is not None else POINTS[reason]
    cur.execute(
        """
        INSERT INTO point_ledger (user_id, points, reason, ref_key)
        VALUES (%s, %s, %s, %s)
        ON CONFLICT (user_id, reason, ref_key) DO NOTHING
        """,
        (user_id, p, reason, ref_key),
    )
    return cur.rowcount


def total_points(cur, user_id: int) -> int:
    cur.execute("SELECT COALESCE(SUM(points), 0) FROM point_ledger WHERE user_id = %s",
                (user_id,))
    return int(cur.fetchone()[0])
