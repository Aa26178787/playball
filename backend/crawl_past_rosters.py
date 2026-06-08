# crawl_past_rosters.py
import os
import psycopg2
import requests
import time

DB_CONFIG = {
    'host': 'localhost', 'port': 5433,
    'database': 'playball', 'user': 'playball_user',
    'password': os.environ.get('DB_PASSWORD', 'playball1234')
}

def get_connection():
    return psycopg2.connect(**DB_CONFIG)

PITCH_STYLES = {'좌완투수', '우완투수', '우완사이드', '우완언더', '좌완사이드'}
PITCH_TYPE_MAP = {
    '좌투': '좌완투수', '우투': '우완투수',
    '좌언': '좌완사이드', '우언': '우완언더', '우사': '우완사이드'
}

def _parse_naver_lineup(lines):
    result = {
        'home': {'starter_pitcher': None, 'batters': [], 'backup_batters': [], 'bullpen': []},
        'away': {'starter_pitcher': None, 'batters': [], 'backup_batters': [], 'bullpen': []},
    }

    away_team = None
    start_idx = 0
    for i, line in enumerate(lines):
        if line == '라인업' and i > 0:
            start_idx = i + 1
            break
    lines = lines[start_idx:]

    current_side = None
    current_section = None
    i = 0

    while i < len(lines):
        line = lines[i]

        if line.endswith('선발') and not line.startswith('선발') and len(line) > 2:
            team_name = line[:-2]
            if away_team is None:
                away_team = team_name
                current_side = 'away'
            else:
                current_side = 'home'
            current_section = 'starter'
            i += 1
            if i < len(lines) and lines[i] == '선발':
                i += 1
            continue

        if line == '후보야수':
            i += 1
            continue
        if '후보야수' in line:
            team_name = line.replace(' 후보야수', '').strip()
            current_side = 'away' if team_name == away_team else 'home'
            current_section = 'backup'
            i += 1
            continue

        if line == '불펜투수':
            i += 1
            continue
        if '불펜투수' in line:
            team_name = line.replace(' 불펜투수', '').strip()
            current_side = 'away' if team_name == away_team else 'home'
            current_section = 'bullpen'
            i += 1
            continue

        if '공지' in line or line in ('홈', '야구', '해외야구'):
            break

        if current_side is None or current_section is None:
            i += 1
            continue

        if current_section == 'starter':
            if i + 1 < len(lines) and lines[i + 1] in PITCH_TYPE_MAP:
                result[current_side]['starter_pitcher'] = {
                    'name': line,
                    'pitching_style': PITCH_TYPE_MAP[lines[i + 1]],
                }
                i += 2
                continue
            if line.isdigit() and i + 2 < len(lines):
                pos = lines[i + 2].split(',')[0].strip().split(' ,')[0].strip()
                result[current_side]['batters'].append({
                    'batting_order': int(line),
                    'name': lines[i + 1],
                    'position': pos,
                })
                i += 3
                continue

        elif current_section == 'backup':
            if ',' in line and any(p in line for p in ['우타', '좌타', '양타']):
                i += 1
                continue
            if i + 1 < len(lines):
                next_line = lines[i + 1]
                if ',' in next_line and any(p in next_line for p in ['우타', '좌타', '양타']):
                    pos = next_line.split(',')[0].strip()
                    result[current_side]['backup_batters'].append({
                        'name': line,
                        'position': pos,
                    })
                    i += 2
                    continue

        elif current_section == 'bullpen':
            if line in PITCH_STYLES:
                i += 1
                continue
            if i + 1 < len(lines) and lines[i + 1] in PITCH_STYLES:
                result[current_side]['bullpen'].append({
                    'name': line,
                    'pitching_style': lines[i + 1],
                })
                i += 2
                continue

        i += 1

    return result

def crawl_naver_lineup(naver_game_id):
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options
    from selenium.webdriver.common.by import By

    options = Options()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--disable-gpu')
    driver = webdriver.Chrome(options=options)

    try:
        driver.get(f'https://m.sports.naver.com/game/{naver_game_id}/lineup')
        time.sleep(5)
        text = driver.find_element(By.TAG_NAME, 'body').text
        lines = [l.strip() for l in text.split('\n') if l.strip()]
    finally:
        driver.quit()

    return _parse_naver_lineup(lines)


def save_game_roster(db_game_id, naver_game_id):
    try:
        lineup = crawl_naver_lineup(naver_game_id)
        if not lineup:
            return 0

        conn = get_connection()
        cur = conn.cursor()

        cur.execute("""
            SELECT g.home_team_id, g.away_team_id
            FROM games g WHERE g.id = %s
        """, (db_game_id,))
        game = cur.fetchone()
        if not game:
            cur.close()
            conn.close()
            return 0
        home_team_id, away_team_id = game

        def find_player(name, team_id, player_type=None):
            cur.execute("""
                SELECT id FROM players
                WHERE name = %s AND team_id = %s LIMIT 1
            """, (name, team_id))
            row = cur.fetchone()
            if row:
                return row[0]
            cur.execute("SELECT id FROM players WHERE name = %s LIMIT 1", (name,))
            row = cur.fetchone()
            if row:
                return row[0]
            return None

        # 기존 로스터 삭제
        cur.execute("DELETE FROM game_rosters WHERE game_id = %s", (db_game_id,))
        saved = 0

        for side, team_id in [('home', home_team_id), ('away', away_team_id)]:
            data = lineup[side]

            sp = data.get('starter_pitcher')
            if sp:
                player_id = find_player(sp['name'], team_id, '투수')
                if player_id:
                    cur.execute("""
                        INSERT INTO game_rosters (
                            game_id, player_id, team_side, roster_type,
                            batting_order, position, pitching_style, is_starter
                        ) VALUES (%s, %s, %s, 'pitcher', NULL, '투수', %s, TRUE)
                        ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                            pitching_style = EXCLUDED.pitching_style,
                            is_starter = TRUE,
                            roster_type = 'pitcher'
                    """, (db_game_id, player_id, side, sp['pitching_style']))
                    saved += 1

            for b in data.get('batters', []):
                player_id = find_player(b['name'], team_id, '타자')
                if player_id:
                    cur.execute("""
                        INSERT INTO game_rosters (
                            game_id, player_id, team_side, roster_type,
                            batting_order, position, pitching_style, is_starter
                        ) VALUES (%s, %s, %s, 'batter', %s, %s, NULL, TRUE)
                        ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                            batting_order = EXCLUDED.batting_order,
                            position = EXCLUDED.position,
                            is_starter = TRUE,
                            roster_type = 'batter'
                    """, (db_game_id, player_id, side, b['batting_order'], b['position']))
                    saved += 1

            for b in data.get('backup_batters', []):
                player_id = find_player(b['name'], team_id, '타자')
                if player_id:
                    cur.execute("""
                        INSERT INTO game_rosters (
                            game_id, player_id, team_side, roster_type,
                            batting_order, position, pitching_style, is_starter
                        ) VALUES (%s, %s, %s, 'batter', NULL, %s, NULL, FALSE)
                        ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                            position = EXCLUDED.position,
                            batting_order = NULL,
                            is_starter = FALSE,
                            roster_type = 'batter'
                    """, (db_game_id, player_id, side, b['position']))
                    saved += 1

            for p in data.get('bullpen', []):
                player_id = find_player(p['name'], team_id, '투수')
                if player_id:
                    cur.execute("""
                        INSERT INTO game_rosters (
                            game_id, player_id, team_side, roster_type,
                            batting_order, position, pitching_style, is_starter
                        ) VALUES (%s, %s, %s, 'pitcher', NULL, '투수', %s, FALSE)
                        ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                            pitching_style = EXCLUDED.pitching_style,
                            is_starter = FALSE,
                            roster_type = 'pitcher'
                    """, (db_game_id, player_id, side, p['pitching_style']))
                    saved += 1

        conn.commit()
        cur.close()
        conn.close()
        return saved

    except Exception as e:
        print(f'오류 ({naver_game_id}): {e}')
        import traceback
        traceback.print_exc()
        return 0


def main():
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT g.id, g.naver_game_id
        FROM games g
        WHERE g.status = '종료'
        AND g.game_date < '2026-05-09'
        AND g.naver_game_id IS NOT NULL
        ORDER BY g.game_date
    """)
    games = cur.fetchall()
    cur.close()
    conn.close()

    print(f'크롤링 대상: {len(games)}개 경기')

    for idx, (db_id, naver_id) in enumerate(games):
        saved = save_game_roster(db_id, naver_id)
        print(f'[{idx+1}/{len(games)}] {naver_id} 완료 ({saved}명)', flush=True)
        time.sleep(1)

    print('전체 완료!')


if __name__ == '__main__':
    main()