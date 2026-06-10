"""plate_appearances 백필 — 종료 경기 전체를 PA 파싱해 적재 (1회성/재실행 안전)

사용: cd ~/playball/backend && python3 crawler/backfill_pa.py [--limit N]
upsert라 재실행해도 안전. 진행 로그 100경기 단위.
"""
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database.connection import get_connection
from api.pa_parser import save_plate_appearances_for_game


def main():
    limit = 0
    if '--limit' in sys.argv:
        limit = int(sys.argv[sys.argv.index('--limit') + 1])

    conn = get_connection()
    if not conn:
        print('DB 연결 실패')
        return
    cur = conn.cursor()
    cur.execute("""
        SELECT g.id FROM games g
        WHERE g.status = '종료'
          AND EXISTS (SELECT 1 FROM game_pitches p WHERE p.game_id = g.id)
        ORDER BY g.game_date, g.id
    """)
    game_ids = [r[0] for r in cur.fetchall()]
    cur.close()
    conn.close()
    if limit:
        game_ids = game_ids[:limit]
    print(f'대상 경기: {len(game_ids)}')

    total_pa = 0
    for i, gid in enumerate(game_ids, 1):
        n = save_plate_appearances_for_game(gid)
        total_pa += n
        if i % 100 == 0 or i == len(game_ids):
            print(f'[{i}/{len(game_ids)}] 누적 {total_pa} 타석')
    print(f'DONE — {len(game_ids)}경기 {total_pa}타석')


if __name__ == '__main__':
    main()
