"""과거 시즌(2024·2025) 수집 — games + 이닝중계(game_pitches) + 투구위치(pitch_locations)

사용: cd ~/playball/backend && python3 crawler/backfill_seasons.py 2025 [--skip-games] [--no-locations]
체인 예: python3 crawler/backfill_seasons.py 2025 && python3 crawler/backfill_seasons.py 2024 \
         && python3 crawler/backfill_pa.py

- resume 안전: 이미 pitches 있는 경기 skip, games는 upsert
- 라이브 보호: KST 17~23시엔 자동 일시정지 (scheduler의 Naver 호출과 경합 방지)
- 요청 1.2s 간격 (win_rate 백필 1,300요청 무사고로 검증된 페이스)
"""
import sys
import os
import time
from datetime import date, datetime, timedelta, timezone

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database.connection import get_connection
from crawler.naver_crawler import get_games_by_date, save_games, save_game_pitches

KST = timezone(timedelta(hours=9))
SEASON_RANGE = {  # 시범경기 제외, 정규+PS 여유 범위
    2024: ('2024-03-09', '2024-11-30'),
    2025: ('2025-03-08', '2025-11-30'),
}
SLEEP = 1.2


def _range(season):
    # 미등록 시즌(2010~2023) = 3/24~11/30. ⚠️구포맷(13자)은 시범도 정규와 동일 id →
    # 날짜로만 시범 제외(시범=early-mid 3월). 3/24 시작 = 시범 후·개막전 포함, PS(10~11월) 포함.
    return SEASON_RANGE.get(season, (f'{season}-03-24', f'{season}-11-30'))


def _is_kbo(gid, season):
    # 신포맷=끝 '0{season}'(2020+) / 구포맷=YYYYMMDD+팀4+'0' 13자(연도 prefix)
    return gid.endswith(f'0{season}') or (gid.startswith(str(season)) and len(gid) == 13)


def _live_guard():
    """KST 17~23시 = 라이브 크롤 시간대 — 대기"""
    while True:
        h = datetime.now(KST).hour
        if 17 <= h < 23:
            print(f'[{datetime.now(KST):%H:%M}] 라이브 시간대 — 10분 대기', flush=True)
            time.sleep(600)
        else:
            return


def backfill_games(season: int):
    d0 = date.fromisoformat(_range(season)[0])
    d1 = date.fromisoformat(_range(season)[1])
    n_days = (d1 - d0).days + 1
    print(f'== {season} games: {d0} ~ {d1} ({n_days}일) ==', flush=True)
    total = 0
    d = d0
    while d <= d1:
        _live_guard()
        games = get_games_by_date(d.isoformat())
        kbo = [g for g in games if _is_kbo(g.get('game_id', ''), season)]
        if kbo:
            save_games(kbo)
            total += len(kbo)
        d += timedelta(days=1)
        time.sleep(0.8)
    print(f'== {season} games 완료: {total}경기 ==', flush=True)


def backfill_pitches(season: int, with_locations: bool = True):
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT g.id, g.naver_game_id FROM games g
        WHERE g.status = '종료' AND EXTRACT(YEAR FROM g.game_date) = %s
          AND NOT EXISTS (SELECT 1 FROM game_pitches p WHERE p.game_id = g.id)
        ORDER BY g.game_date
    """, (season,))
    targets = cur.fetchall()
    cur.close()
    conn.close()
    print(f'== {season} pitches: 대상 {len(targets)}경기 ==', flush=True)

    for i, (gid, ngid) in enumerate(targets, 1):
        _live_guard()
        max_inn = 0
        for inn in range(1, 13):
            # 10회 이상은 직전 이닝 데이터가 있을 때만 (연장 여부 확인)
            if inn >= 10 and max_inn < inn - 1:
                break
            try:
                save_game_pitches(gid, ngid, inn)
            except Exception as e:
                print(f'  오류 game={gid} inn={inn}: {e}', flush=True)
            time.sleep(SLEEP)
            conn = get_connection()
            cur = conn.cursor()
            cur.execute("SELECT 1 FROM game_pitches WHERE game_id=%s AND inning=%s LIMIT 1", (gid, inn))
            if cur.fetchone():
                max_inn = inn
            cur.close()
            conn.close()
        if with_locations and max_inn:
            try:
                from crawler.crawl_pitch_locations import save_pitch_locations_for_game
                n = save_pitch_locations_for_game(gid, ngid, max_inn)
                print(f'[{i}/{len(targets)}] game={gid} {max_inn}이닝 + 위치 {n}구', flush=True)
            except Exception as e:
                print(f'[{i}/{len(targets)}] game={gid} {max_inn}이닝 (위치 오류: {e})', flush=True)
        else:
            print(f'[{i}/{len(targets)}] game={gid} {max_inn}이닝', flush=True)
    print(f'== {season} pitches 완료 ==', flush=True)


def main():
    season = int(sys.argv[1])
    if '--skip-games' not in sys.argv:
        backfill_games(season)
    backfill_pitches(season, with_locations='--no-locations' not in sys.argv)
    print(f'DONE {season}', flush=True)


if __name__ == '__main__':
    main()
