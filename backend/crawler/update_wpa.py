"""투수 WPA 갱신 — plate_appearances 승률델타(홈 기준)를 수비 관점 부호로 합산.

WPA(투수) = Σ side × (win_rate_after − win_rate_before) / 100
  side: 초(half='0') = 홈 수비 → +1 / 말 = 원정 수비 → −1
동명이인 투수(양현종·이태양 중복건)는 이름 매칭 모호 → 스킵(HAVING count=1).

사용: cd ~/playball/backend && python3 crawler/update_wpa.py
cron: 0 15 * * * (UTC 15:00 = KST 자정) — 멱등(시즌 전체 재계산)
"""
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database.connection import get_connection


def main():
    conn = get_connection()
    if not conn:
        print('DB 연결 실패')
        return
    cur = conn.cursor()
    cur.execute("ALTER TABLE pitcher_stats ADD COLUMN IF NOT EXISTS wpa NUMERIC(6,2)")
    cur.execute("""
        UPDATE pitcher_stats ps
        SET wpa = sub.wpa
        FROM (
            SELECT pl.id AS pid,
                   EXTRACT(YEAR FROM g.game_date)::int AS season,
                   ROUND((SUM(
                       CASE WHEN pa.inning_half::text = '0'
                            THEN (pa.win_rate_after - pa.win_rate_before)
                            ELSE -(pa.win_rate_after - pa.win_rate_before) END
                   ) / 100.0)::numeric, 2) AS wpa
            FROM plate_appearances pa
            JOIN games g ON g.id = pa.game_id
            JOIN players pl ON pl.name = pa.pitcher_name AND pl.player_type = '투수'
            JOIN (
                SELECT name FROM players WHERE player_type = '투수'
                GROUP BY name HAVING count(*) = 1
            ) uniq ON uniq.name = pl.name
            WHERE pa.win_rate_before IS NOT NULL
              AND pa.win_rate_after IS NOT NULL
            GROUP BY pl.id, EXTRACT(YEAR FROM g.game_date)
        ) sub
        WHERE ps.player_id = sub.pid AND ps.season = sub.season
    """)
    print(f'[WPA] 투수 갱신: {cur.rowcount}행')
    conn.commit()
    cur.close()
    conn.close()


if __name__ == '__main__':
    main()
