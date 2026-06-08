# crawl_past_rosters.py
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
import os, time, re, psycopg2

DB_CONFIG = {
    'host': 'localhost', 'port': 5433,
    'database': 'playball', 'user': 'playball_user',
    'password': os.environ.get('DB_PASSWORD', 'playball1234')
}

def get_connection():
    return psycopg2.connect(**DB_CONFIG)

def get_driver():
    options = Options()
    return webdriver.Chrome(options=options)

PITCH_STYLE_MAP = {
    '좌투': '좌완투수', '우투': '우완투수',
    '좌완투수': '좌완투수', '우완투수': '우완투수',
    '우완언더': '우완언더', '좌완언더': '좌완언더',
    '우완사이드': '우완사이드', '좌완사이드': '좌완사이드',
}

NAVER_TEAM_CODE_MAP = {
    'HT': 'KIA', 'OB': '두산', 'LT': '롯데', 'SS': '삼성',
    'HH': '한화', 'SK': 'SSG', 'KT': 'KT', 'NC': 'NC',
    'WO': '키움', 'LG': 'LG',
}

def convert_pitch_style(style):
    if not style:
        return None
    return PITCH_STYLE_MAP.get(style, style)

def is_noise(line):
    return any(x in line for x in [
        'NAVER', '스포츠', '공지', '맨 위로', '로그인', '고객센터',
        '저작권', 'Copyright', '경기 상세', '전력', '응원', '중계',
        '뉴스', '영상', '기록', '라인업',
    ])

def match_side(line, home_code, away_code):
    home_name = NAVER_TEAM_CODE_MAP.get(home_code, home_code)
    away_name = NAVER_TEAM_CODE_MAP.get(away_code, away_code)
    if home_name and home_name in line:
        return 'home'
    if away_name and away_name in line:
        return 'away'
    return None

def crawl_roster(driver, db_game_id, naver_game_id, home_team, away_team, home_short='', away_short=''):
    conn = get_connection()
    cur = conn.cursor()

    # naver_game_id에서 팀 코드 추출
    m = re.match(r'\d{8}([A-Z]{2})([A-Z]{2})\d+', naver_game_id)
    home_code = m.group(1) if m else home_short
    away_code = m.group(2) if m else away_short

    driver.get(f'https://m.sports.naver.com/game/{naver_game_id}/relay')
    time.sleep(8)

    buttons = driver.find_elements(By.TAG_NAME, 'button')
    for btn in buttons:
        if btn.text.strip() == '라인업':
            btn.click()
            time.sleep(3)
            break

    text = driver.find_element(By.TAG_NAME, 'body').text
    lines = [l.strip() for l in text.split('\n') if l.strip()]

    rosters = []
    current_side = None
    current_section = None
    i = 0

    while i < len(lines):
        line = lines[i]

        if is_noise(line):
            i += 1
            continue

        # 팀 선발 섹션
        if re.match(r'.+선발$', line) and len(line) < 20:
            side = match_side(line.replace('선발', '').strip(), home_code, away_code)
            if side:
                current_side = side
            current_section = 'starter'
            i += 1
            continue

        # 후보야수 섹션
        if '후보야수' in line:
            current_section = 'backup'
            side = match_side(line, home_code, away_code)
            if side:
                current_side = side
            i += 1
            continue

        # 불펜투수 섹션
        if '불펜투수' in line:
            current_section = 'bullpen'
            side = match_side(line, home_code, away_code)
            if side:
                current_side = side
            i += 1
            continue

        if current_side is None or current_section is None:
            i += 1
            continue

        # 선발 섹션
        if current_section == 'starter':
            if line == '선발':
                i += 1
                if i < len(lines):
                    pitcher_name = lines[i]
                    i += 1
                    pitching_style = None
                    if i < len(lines) and re.match(r'^[좌우][투완언사]', lines[i]):
                        pitching_style = convert_pitch_style(lines[i])
                        i += 1
                    rosters.append((pitcher_name, current_side, 'pitcher', None, '투수', pitching_style, True))
                continue

            if re.match(r'^\d+$', line):
                batting_order = int(line)
                i += 1
                if i < len(lines):
                    batter_name = lines[i]
                    i += 1
                    position = None
                    if i < len(lines) and ',' in lines[i]:
                        position = lines[i].split(',')[0].strip()
                        i += 1
                    rosters.append((batter_name, current_side, 'batter', batting_order, position, None, True))
                continue

        # 후보야수 섹션
        if current_section == 'backup':
            if (re.match(r'^[가-힣A-Za-z·\s]+$', line) and
                len(line) < 15 and
                not re.match(r'^[좌우][투완언사]', line) and
                '후보' not in line and '불펜' not in line):
                name = line
                i += 1
                position = None
                if i < len(lines) and ',' in lines[i]:
                    position = lines[i].split(',')[0].strip()
                    i += 1
                rosters.append((name, current_side, 'batter', None, position, None, False))
                continue

        # 불펜투수 섹션
        if current_section == 'bullpen':
            if (re.match(r'^[가-힣A-Za-z·\s]+$', line) and
                len(line) < 15 and
                not re.match(r'^[좌우][투완언사]', line) and
                '후보' not in line and '불펜' not in line):
                name = line
                i += 1
                pitching_style = None
                if i < len(lines) and re.match(r'^[좌우][투완언사]', lines[i]):
                    pitching_style = lines[i]
                    i += 1
                rosters.append((name, current_side, 'pitcher', None, '투수', pitching_style, False))
                continue

        i += 1

    # 기존 로스터 삭제
    cur.execute("DELETE FROM game_rosters WHERE game_id = %s", (db_game_id,))

    saved = 0
    for name, side, rtype, order, position, pitching_style, is_starter in rosters:
        cur.execute("SELECT id FROM players WHERE name = %s LIMIT 1", (name,))
        row = cur.fetchone()
        if not row:
            continue
        player_id = row[0]
        cur.execute("""
            INSERT INTO game_rosters (
                game_id, player_id, team_side, roster_type,
                batting_order, position, pitching_style, is_starter
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                batting_order = EXCLUDED.batting_order,
                position = EXCLUDED.position,
                pitching_style = EXCLUDED.pitching_style,
                is_starter = EXCLUDED.is_starter,
                roster_type = EXCLUDED.roster_type
        """, (db_game_id, player_id, side, rtype, order, position, pitching_style, is_starter))
        saved += 1

    conn.commit()
    cur.close()
    conn.close()
    return saved


def main():
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT g.id, g.naver_game_id,
               ht.name, at.name,
               ht.short_name, at.short_name
        FROM games g
        JOIN teams ht ON g.home_team_id = ht.id
        JOIN teams at ON g.away_team_id = at.id
        WHERE g.status = '종료'
        AND g.game_date < '2026-05-09'
        AND g.naver_game_id IS NOT NULL
        ORDER BY g.game_date
    """)
    games = cur.fetchall()
    cur.close()
    conn.close()

    print(f'크롤링 대상: {len(games)}개 경기')
    driver = get_driver()

    for idx, (db_id, naver_id, home_team, away_team, home_short, away_short) in enumerate(games):
        try:
            saved = crawl_roster(driver, db_id, naver_id, home_team, away_team, home_short, away_short)
            print(f'[{idx+1}/{len(games)}] {naver_id} 완료 ({saved}명)', flush=True)
            time.sleep(1)
        except Exception as e:
            print(f'오류 ({naver_id}): {e}', flush=True)
            try:
                driver.quit()
            except:
                pass
            driver = get_driver()
            continue

    driver.quit()
    print('전체 완료!')


if __name__ == '__main__':
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT g.id, g.naver_game_id,
               ht.name, at.name,
               ht.short_name, at.short_name
        FROM games g
        JOIN teams ht ON g.home_team_id = ht.id
        JOIN teams at ON g.away_team_id = at.id
        WHERE g.id = 55
    """)
    row = cur.fetchone()
    cur.close()
    conn.close()

    db_id, naver_id, home_team, away_team, home_short, away_short = row
    print(f'홈: {home_team}({home_short}), 원정: {away_team}({away_short})')

    driver = get_driver()
    saved = crawl_roster(driver, db_id, naver_id, home_team, away_team, home_short, away_short)
    print(f'저장: {saved}명')
    driver.quit()