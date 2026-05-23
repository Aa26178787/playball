import sys
import os
import math
import time

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import requests
from database.connection import get_connection

NAVER_HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Referer': 'https://sports.naver.com/',
}


def compute_z(pts):
    try:
        y0, vy0, ay = pts['y0'], pts['vy0'], pts['ay']
        z0, vz0, az = pts['z0'], pts['vz0'], pts['az']
        cross_y = pts.get('crossPlateY', 0.7083)
        A = 0.5 * ay
        B = vy0
        C = y0 - cross_y
        disc = B * B - 4 * A * C
        if disc < 0:
            return None
        t1 = (-B - math.sqrt(disc)) / (2 * A)
        t2 = (-B + math.sqrt(disc)) / (2 * A)
        valid = [t for t in [t1, t2] if t > 0]
        if not valid:
            return None
        t = min(valid)
        return round(z0 + vz0 * t + 0.5 * az * t ** 2, 4)
    except Exception:
        return None


def classify(text):
    if not text:
        return 'other'
    if '볼' in text:
        return 'ball'
    if '헛스윙' in text or '스윙' in text:
        return 'swing'
    if '파울' in text:
        return 'foul'
    if '타격' in text or '안타' in text or '홈런' in text or '2루타' in text or '3루타' in text:
        return 'hit'
    if '스트라이크' in text:
        return 'strike'
    return 'other'


def save_pitch_locations_for_game(game_id, naver_game_id, max_inning):
    conn = get_connection()
    if not conn:
        return 0
    cur = conn.cursor()

    cur.execute("SELECT naver_player_id, name FROM players WHERE naver_player_id IS NOT NULL")
    pitcher_cache = {str(r[0]): r[1] for r in cur.fetchall()}

    cur.execute("DELETE FROM game_pitch_locations WHERE game_id = %s", (game_id,))

    rows = []
    for inning in range(1, max_inning + 1):
        try:
            url = f"https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/relay?inning={inning}"
            res = requests.get(url, headers=NAVER_HEADERS, timeout=8)
            if res.status_code != 200:
                continue
            text_relays = res.json().get('result', {}).get('textRelayData', {}).get('textRelays', [])
        except Exception:
            continue

        for item in reversed(text_relays):
            pts_opts = item.get('ptsOptions', [])
            txt_opts = item.get('textOptions', [])
            batter = item.get('title', '')
            inning_half = str(item.get('homeOrAway', ''))
            if not pts_opts:
                continue

            pitch_txts = [o for o in txt_opts if o.get('type') == 1]
            # fallback: type=8 타석시작 opt의 pitcher (교체 후 첫 타석에서 부정확할 수 있음)
            fallback_pitcher = ''
            for opt in txt_opts:
                gs = opt.get('currentGameState') or {}
                pid = str(gs.get('pitcher') or '')
                if pid and pid in pitcher_cache:
                    fallback_pitcher = pitcher_cache[pid]
                    break

            for i, pts in enumerate(pts_opts):
                x = pts.get('crossPlateX')
                z = compute_z(pts)
                if x is None or z is None:
                    continue
                result_text = ''
                stuff = ''
                pitcher_name = fallback_pitcher
                if i < len(pitch_txts):
                    opt = pitch_txts[i]
                    result_text = opt.get('text') or ''
                    stuff = opt.get('stuff') or ''
                    # 구마다 currentGameState.pitcher 우선 사용 (투수교체 정확도)
                    gs = opt.get('currentGameState') or {}
                    pid = str(gs.get('pitcher') or '')
                    if pid and pid in pitcher_cache:
                        pitcher_name = pitcher_cache[pid]
                if '고의' in result_text:
                    continue
                rows.append((
                    game_id, inning, inning_half, pitcher_name, batter,
                    round(float(x), 4), z, classify(result_text),
                    pts.get('topSz'), pts.get('bottomSz'),
                    stuff, pts.get('stance', 'R'),
                ))

        time.sleep(0.15)

    if rows:
        cur.executemany("""
            INSERT INTO game_pitch_locations
                (game_id, inning, inning_half, pitcher_name, batter_name,
                 x, z, result, top_sz, bot_sz, pitch_type, stance)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, rows)

    conn.commit()
    cur.close()
    conn.close()
    return len(rows)


def crawl_all_past_pitch_locations(batch_size=30):
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()

    cur.execute("""
        SELECT g.id, g.naver_game_id,
               COALESCE(MAX(gi.inning), 9) AS max_inning
        FROM games g
        LEFT JOIN game_innings gi ON g.id = gi.game_id
        WHERE g.status = '종료'
        AND g.naver_game_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1 FROM game_pitch_locations gpl WHERE gpl.game_id = g.id
        )
        GROUP BY g.id, g.naver_game_id
        ORDER BY g.game_date DESC
        LIMIT %s
    """, (batch_size,))
    games = cur.fetchall()
    cur.close()
    conn.close()

    print(f"투구 위치 크롤링 대상: {len(games)}경기")
    for game_id, naver_game_id, max_inning in games:
        print(f"  game_id={game_id} {naver_game_id} innings={max_inning} ...", end='', flush=True)
        try:
            n = save_pitch_locations_for_game(game_id, naver_game_id, int(max_inning))
            print(f" {n}구")
        except Exception as e:
            print(f" ERROR: {e}")
        time.sleep(0.5)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--batch', type=int, default=30, help='한 번에 크롤링할 경기 수')
    args = parser.parse_args()
    crawl_all_past_pitch_locations(batch_size=args.batch)
