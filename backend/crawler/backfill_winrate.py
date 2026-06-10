"""win_rate 백필 — 5/9 크롤러 개편 후 NULL이던 승률을 relay 재크롤로 채움

save_game_pitches 재실행 (ON CONFLICT COALESCE가 win_rate만 보충, 기존 행 안전).
이후 backfill_pa.py 재실행하면 PA의 win_rate_before/after까지 채워짐.

사용: cd ~/playball/backend && python3 crawler/backfill_winrate.py [--limit N]
요청량: 게임당 이닝수(~9.5) × 1.2s 간격 — 135경기 ≈ 26분
"""
import sys
import os
import time
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database.connection import get_connection
from crawler.naver_crawler import save_game_pitches


def main():
    limit = 0
    if '--limit' in sys.argv:
        limit = int(sys.argv[sys.argv.index('--limit') + 1])

    conn = get_connection()
    cur = conn.cursor()
    # win_rate 전무한 종료 경기 (5/9 이후분)
    cur.execute("""
        SELECT g.id, g.naver_game_id, COALESCE(g.current_inning, 9)
        FROM games g
        WHERE g.status = '종료' AND g.naver_game_id IS NOT NULL
          AND EXISTS (SELECT 1 FROM game_pitches p WHERE p.game_id = g.id)
          AND NOT EXISTS (SELECT 1 FROM game_pitches p
                          WHERE p.game_id = g.id AND p.home_win_rate IS NOT NULL)
        ORDER BY g.game_date
    """)
    targets = cur.fetchall()
    cur.close()
    conn.close()
    if limit:
        targets = targets[:limit]
    print(f'대상 경기: {len(targets)}')

    for i, (gid, ngid, max_inn) in enumerate(targets, 1):
        for inn in range(1, int(max_inn) + 1):
            try:
                save_game_pitches(gid, ngid, inn)
            except Exception as e:
                print(f'  오류 game={gid} inn={inn}: {e}')
            time.sleep(1.2)
        print(f'[{i}/{len(targets)}] game={gid} {max_inn}이닝 완료')
    print('DONE')


if __name__ == '__main__':
    main()
