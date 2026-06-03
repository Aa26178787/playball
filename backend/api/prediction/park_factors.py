"""파크 팩터 계산 — 26시즌 종료 경기 기반.
구장별 평균 득점 / 리그 평균 득점 → 1.0 기준."""
from database.connection import get_connection

# 메모리 캐시 (서버 재시작 시 재계산)
_park_factors_cache: dict | None = None


def get_park_factors(season: int = 2026, recompute: bool = False) -> dict:
    """{stadium_id: {'runs': float, 'hr': float}}.
    runs > 1.0 = 타자 친화, < 1.0 = 투수 친화."""
    global _park_factors_cache
    if _park_factors_cache is not None and not recompute:
        return _park_factors_cache

    conn = get_connection()
    if not conn:
        return {}
    try:
        cur = conn.cursor()
        # 구장별 평균 득점
        cur.execute("""
            SELECT stadium_id,
                   COUNT(*) as games,
                   AVG(home_score + away_score)::float as avg_runs
            FROM games
            WHERE status = '종료'
              AND EXTRACT(YEAR FROM game_date) = %s
              AND stadium_id IS NOT NULL
              AND home_score IS NOT NULL AND away_score IS NOT NULL
            GROUP BY stadium_id
        """, (season,))
        rows = cur.fetchall()

        # 리그 평균
        cur.execute("""
            SELECT AVG(home_score + away_score)::float
            FROM games
            WHERE status = '종료'
              AND EXTRACT(YEAR FROM game_date) = %s
              AND home_score IS NOT NULL AND away_score IS NOT NULL
        """, (season,))
        league_avg = cur.fetchone()[0] or 10.0

        # 구장별 HR — game_batters.home_runs 합산
        cur.execute("""
            SELECT g.stadium_id,
                   COUNT(DISTINCT g.id) games,
                   SUM(COALESCE(gb.home_runs, 0))::float as total_hr
            FROM games g
            LEFT JOIN game_batters gb ON gb.game_id = g.id
            WHERE g.status = '종료'
              AND EXTRACT(YEAR FROM g.game_date) = %s
              AND g.stadium_id IS NOT NULL
            GROUP BY g.stadium_id
        """, (season,))
        hr_rows = {r[0]: (r[1], r[2]) for r in cur.fetchall()}

        # 리그 평균 HR/game
        cur.execute("""
            SELECT SUM(COALESCE(gb.home_runs, 0))::float / NULLIF(COUNT(DISTINCT g.id), 0)
            FROM games g LEFT JOIN game_batters gb ON gb.game_id = g.id
            WHERE g.status = '종료' AND EXTRACT(YEAR FROM g.game_date) = %s
        """, (season,))
        league_avg_hr = cur.fetchone()[0] or 2.0

        result = {}
        for stadium_id, games, avg_runs in rows:
            run_factor = avg_runs / league_avg if league_avg > 0 else 1.0
            hr_games, hr_total = hr_rows.get(stadium_id, (0, 0))
            hr_avg = (hr_total / hr_games) if hr_games > 0 else league_avg_hr
            hr_factor = hr_avg / league_avg_hr if league_avg_hr > 0 else 1.0
            result[stadium_id] = {
                'runs': round(run_factor, 3),
                'hr': round(hr_factor, 3),
                'games': games,
            }
        cur.close()
        _park_factors_cache = result
        return result
    finally:
        conn.close()


def invalidate_park_factors():
    global _park_factors_cache
    _park_factors_cache = None
