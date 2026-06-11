"""뱃지 엔진 — 메가B 리텐션.

정의는 코드 정적(BADGES), 획득은 user_badges(UNIQUE user_id,badge_id) — 원장 dedup 패턴.
평가 = GET /user/badges lazy: 호출 시 조건 재계산 → 신규 충족분 INSERT → 전체 반환.
신규 뱃지 추가 = BADGES에 정의 + _progress()에 분기.
"""
import logging

logger = logging.getLogger(__name__)

# (badge_id, 이름, 설명, 이모지, 기준값, 측정키)
BADGES = [
    ('visit_1',       '첫 직관',      '직관 기록 1회',          '🏟️', 1,    'visits'),
    ('visit_10',      '직관 단골',    '직관 기록 10회',         '🎫', 10,   'visits'),
    ('visit_30',      '직관 매니아',  '직관 기록 30회',         '🔥', 30,   'visits'),
    ('visit_all',     '전국 구장 정복', '9개 구장 직관 달성',     '🗺️', 9,    'stadiums'),
    ('pred_win_1',    '첫 적중',      '승부예측 적중 1회',      '🎯', 1,    'pred_wins'),
    ('pred_win_10',   '예측 고수',    '승부예측 적중 10회',     '🧙', 10,   'pred_wins'),
    ('pred_win_50',   '점쟁이',       '승부예측 적중 50회',     '🔮', 50,   'pred_wins'),
    ('attend_7',      '일주일 개근',  '출석 누적 7일',          '📅', 7,    'attends'),
    ('attend_30',     '한 달 개근',   '출석 누적 30일',         '🗓️', 30,   'attends'),
    ('points_1000',   '천 점 돌파',   '누적 1,000P 달성',       '💰', 1000, 'points'),
    ('points_5000',   '포인트 부자',  '누적 5,000P 달성',       '👑', 5000, 'points'),
]


def _metrics(cur, user_id: int) -> dict:
    """뱃지 측정값 일괄 계산 (쿼리 4번)"""
    m = {}
    cur.execute("""
        SELECT COUNT(*), COUNT(DISTINCT g.stadium_id)
        FROM user_stadium_visits v
        JOIN games g ON g.id = v.game_id
        WHERE v.user_id = %s
    """, (user_id,))
    row = cur.fetchone()
    m['visits'], m['stadiums'] = int(row[0]), int(row[1])
    cur.execute("""
        SELECT
          COUNT(*) FILTER (WHERE reason = 'prediction_win'),
          COUNT(*) FILTER (WHERE reason = 'attendance'),
          COALESCE(SUM(points), 0)
        FROM point_ledger WHERE user_id = %s
    """, (user_id,))
    row = cur.fetchone()
    m['pred_wins'], m['attends'], m['points'] = int(row[0]), int(row[1]), int(row[2])
    return m


def evaluate_badges(cur, user_id: int) -> list[dict]:
    """평가 + 신규 획득 INSERT. 반환 = 전체 뱃지 (earned/progress 포함). commit은 호출측."""
    m = _metrics(cur, user_id)
    cur.execute("SELECT badge_id FROM user_badges WHERE user_id = %s", (user_id,))
    earned = {r[0] for r in cur.fetchall()}

    out = []
    for bid, name, desc, emoji, threshold, key in BADGES:
        cur_val = m.get(key, 0)
        is_earned = bid in earned
        if not is_earned and cur_val >= threshold:
            cur.execute(
                """
                INSERT INTO user_badges (user_id, badge_id)
                VALUES (%s, %s) ON CONFLICT (user_id, badge_id) DO NOTHING
                """,
                (user_id, bid),
            )
            is_earned = True
        out.append({
            'id': bid, 'name': name, 'desc': desc, 'emoji': emoji,
            'earned': is_earned,
            'progress': min(cur_val, threshold), 'goal': threshold,
        })
    return out
