import sys
import os
import time
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database.connection import get_connection


def save_kbo_game_record(db_game_id, record):
    """KBO 박스스코어 데이터 DB 저장"""
    if not record:
        return

    conn = get_connection()
    if not conn:
        return

    cur = conn.cursor()

    try:
        # 타자 저장 - 팀 기반 매핑
        for side in ['home', 'away']:
            batters = record[f'{side}_batters']

            cur.execute("""
                SELECT CASE WHEN %s = 'home' THEN g.home_team_id ELSE g.away_team_id END
                FROM games g WHERE g.id = %s
            """, (side, db_game_id))
            team_row = cur.fetchone()
            team_id = team_row[0] if team_row else None

            for b in batters:
                player = None
                if team_id:
                    cur.execute("""
                        SELECT id FROM players
                        WHERE name = %s AND team_id = %s LIMIT 1
                    """, (b['name'], team_id))
                    player = cur.fetchone()

                if not player:
                    cur.execute("SELECT id FROM players WHERE name = %s LIMIT 1", (b['name'],))
                    player = cur.fetchone()

                if not player:
                    continue

                cur.execute("""
                    INSERT INTO game_batters (
                        game_id, player_id, team_side, batting_order,
                        position, at_bats, hits, rbis, home_runs, avg
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 0, %s)
                    ON CONFLICT (game_id, player_id, team_side, batting_order) DO UPDATE SET
                        position = EXCLUDED.position,
                        at_bats = EXCLUDED.at_bats,
                        hits = EXCLUDED.hits,
                        rbis = EXCLUDED.rbis,
                        avg = EXCLUDED.avg
                """, (
                    db_game_id, player[0], side,
                    b['batting_order'], b['position'],
                    b['at_bats'], b['hits'], b['rbis'], b['avg']
                ))

        # 투수 저장 - 팀 기반 매핑 + pitching_order
        for side in ['home', 'away']:
            pitchers = record[f'{side}_pitchers']
            
            # 팀 ID 먼저 가져오기
            cur.execute("""
                SELECT CASE WHEN %s = 'home' THEN g.home_team_id ELSE g.away_team_id END
                FROM games g WHERE g.id = %s
            """, (side, db_game_id))
            team_row = cur.fetchone()
            team_id = team_row[0] if team_row else None
            
            if pitchers:  # 기록이 있을 때만 삭제
                cur.execute("""
                    DELETE FROM game_pitchers
                    WHERE game_id = %s AND team_side = %s
                """, (db_game_id, side))

            for order, p in enumerate(pitchers):
                player = None
                if team_id:
                    # 1순위: 팀 + 이름 + 투수
                    cur.execute("""
                        SELECT id FROM players
                        WHERE name = %s AND team_id = %s AND player_type = '투수'
                        LIMIT 1
                    """, (p['name'], team_id))
                    player = cur.fetchone()

                    if not player:
                        # 2순위: 팀 + 이름
                        cur.execute("""
                            SELECT id FROM players
                            WHERE name = %s AND team_id = %s LIMIT 1
                        """, (p['name'], team_id))
                        player = cur.fetchone()

                if not player:
                    # 3순위: 이름만
                    cur.execute("SELECT id FROM players WHERE name = %s LIMIT 1", (p['name'],))
                    player = cur.fetchone()

                if not player:
                    # 신규 추가
                    if team_id:
                        cur.execute("""
                            INSERT INTO players (name, team_id, player_type)
                            VALUES (%s, %s, '투수') RETURNING id
                        """, (p['name'], team_id))
                        player = cur.fetchone()
                        print(f"신규 투수 추가: {p['name']}")
                    else:
                        continue

                if not player:
                    continue

                result_map = {'세이브': '세이브', '홀드': '홀드', '승': '승', '패': '패'}
                result_str = result_map.get(p.get('result', ''), p.get('result', ''))

                cur.execute("""
                    INSERT INTO game_pitchers (
                        game_id, player_id, team_side,
                        innings_pitched, hits_allowed, runs_allowed, earned_runs,
                        walks, strikeouts, home_runs_allowed, pitch_count,
                        result, pitching_order
                    ) VALUES (
                        %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s
                    )
                    ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                        innings_pitched = EXCLUDED.innings_pitched,
                        hits_allowed = EXCLUDED.hits_allowed,
                        runs_allowed = EXCLUDED.runs_allowed,
                        earned_runs = EXCLUDED.earned_runs,
                        walks = EXCLUDED.walks,
                        strikeouts = EXCLUDED.strikeouts,
                        home_runs_allowed = EXCLUDED.home_runs_allowed,
                        pitch_count = EXCLUDED.pitch_count,
                        result = EXCLUDED.result,
                        pitching_order = EXCLUDED.pitching_order
                """, (
                    db_game_id, player[0], side,
                    p['innings_pitched'], p['hits_allowed'],
                    p['runs_allowed'], p['earned_runs'],
                    p['walks'], p['strikeouts'],
                    p['home_runs_allowed'],
                    p.get('pitch_count', 0),
                    result_str,
                    order,
                ))

        conn.commit()
        print(f'경기 {db_game_id} KBO 기록 저장 완료')

    except Exception as e:
        print(f'경기 {db_game_id} 저장 오류: {e}')
        conn.rollback()
    finally:
        cur.close()
        conn.close()


def update_all_game_records_from_kbo():
    """모든 종료 경기를 KBO 기록실에서 업데이트"""
    conn = get_connection()
    if not conn:
        return

    cur = conn.cursor()
    cur.execute("""
        SELECT g.id, g.naver_game_id,
               REPLACE(g.game_date::text, '-', '') AS game_date_str
        FROM games g
        WHERE g.status = '종료'
        AND g.naver_game_id IS NOT NULL
        ORDER BY g.game_date DESC
    """)
    games = cur.fetchall()
    cur.close()
    conn.close()

    print(f'총 {len(games)}개 경기 KBO 기록 업데이트 시작')

    driver = get_driver()
    from selenium.webdriver.common.by import By
    updated = 0

    for (db_game_id, naver_game_id, game_date_str) in games:
        try:
            kbo_game_id = naver_to_kbo_game_id(naver_game_id)
            if not kbo_game_id:
                continue

            url = f"https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx?gameDate={game_date_str}&gameId={kbo_game_id}&section=REVIEW"
            driver.get(url)
            time.sleep(2)

            try:
                from selenium.webdriver.support.ui import WebDriverWait
                from selenium.webdriver.support import expected_conditions as EC
                WebDriverWait(driver, 3).until(EC.alert_is_present())
                driver.switch_to.alert.accept()
            except:
                pass

            text = driver.find_element(By.TAG_NAME, 'body').text
            lines = [l.strip() for l in text.split('\n') if l.strip()]

            if '타자 기록' not in text:
                continue

            record = parse_kbo_game_record(lines)
            if record:
                save_kbo_game_record(db_game_id, record)
                updated += 1

        except Exception as e:
            print(f'경기 {db_game_id} 오류: {e}')
            try:
                driver.switch_to.alert.accept()
            except:
                pass
            continue

    driver.quit()
    print(f'총 {updated}개 경기 업데이트 완료')


def naver_to_kbo_game_id(naver_game_id):
    """네이버 경기 ID를 KBO 경기 ID로 변환"""
    if naver_game_id and len(naver_game_id) >= 13:
        return naver_game_id[:13]
    return None


def crawl_kbo_game_record(naver_game_id, game_date):
    """KBO 기록실에서 경기 박스스코어 크롤링"""
    kbo_game_id = naver_to_kbo_game_id(naver_game_id)
    if not kbo_game_id:
        return None

    url = f"https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx?gameDate={game_date}&gameId={kbo_game_id}&section=REVIEW"

    driver = get_driver()
    from selenium.webdriver.common.by import By

    try:
        driver.get(url)
        time.sleep(3)

        try:
            from selenium.webdriver.support.ui import WebDriverWait
            from selenium.webdriver.support import expected_conditions as EC
            WebDriverWait(driver, 3).until(EC.alert_is_present())
            driver.switch_to.alert.accept()
        except:
            pass

        text = driver.find_element(By.TAG_NAME, 'body').text
        lines = [l.strip() for l in text.split('\n') if l.strip()]
        return parse_kbo_game_record(lines)
    except Exception as e:
        print(f'경기 기록 크롤링 오류: {e}')
        return None
    finally:
        driver.quit()


def parse_kbo_game_record(lines):
    """KBO 리뷰 페이지 파싱"""
    result = {
        'home_batters': [],
        'away_batters': [],
        'home_pitchers': [],
        'away_pitchers': [],
    }

    away_team = None
    home_batter_section = False
    away_batter_section = False
    home_pitcher_section = False
    away_pitcher_section = False
    batter_names = []

    for i, line in enumerate(lines):
        # 타자 기록 섹션
        if '타자 기록' in line:
            team_name = line.replace(' 타자 기록', '').strip()
            if away_team is None:
                away_team = team_name
                away_batter_section = True
                home_batter_section = False
            else:
                home_batter_section = True
                away_batter_section = False
            batter_names = []
            continue

        # 타자 이름 파싱
        if (home_batter_section or away_batter_section) and line and \
                not line.startswith('TOTAL') and not line.startswith('1 2 3'):
            parts = line.split()
            if len(parts) >= 3 and parts[0].isdigit():
                order = int(parts[0])
                pos = parts[1]
                name = parts[2]
                batter_names.append({
                    'batting_order': order,
                    'position': pos,
                    'name': name,
                })

        # TOTAL 다음에 타수/안타/타점/득점/타율
        if line == 'TOTAL' and batter_names:
            stats_start = i + 2
            for j, b in enumerate(batter_names):
                if stats_start + j < len(lines):
                    stat_line = lines[stats_start + j].split()
                    if len(stat_line) >= 5:
                        b['at_bats'] = int(stat_line[0])
                        b['hits'] = int(stat_line[1])
                        b['rbis'] = int(stat_line[2])
                        b['runs'] = int(stat_line[3])
                        b['avg'] = float(stat_line[4])

            if away_batter_section:
                result['away_batters'] = batter_names.copy()
            elif home_batter_section:
                result['home_batters'] = batter_names.copy()
            batter_names = []

        # 투수 기록 섹션
        if '투수 기록' in line:
            if not home_pitcher_section and not away_pitcher_section:
                away_pitcher_section = True
            else:
                away_pitcher_section = False
                home_pitcher_section = True
            continue

        # 투수 데이터 파싱
        if (home_pitcher_section or away_pitcher_section):
            parts = line.split()
            if len(parts) >= 10 and parts[0] not in ['선수명', 'TOTAL']:
                try:
                    name = parts[0]
                    result_map = {'승': '승', '패': '패', '세': '세이브', '홀드': '홀드'}
                    result_str = ''

                    if len(parts) > 2 and parts[2] in result_map:
                        result_str = result_map[parts[2]]
                        inn_idx = 6
                    else:
                        inn_idx = 5

                    inn_raw = parts[inn_idx]
                    if inn_raw in ['1/3', '2/3']:
                        innings = 0.1 if inn_raw == '1/3' else 0.2
                        offset = 0
                    elif inn_idx + 1 < len(parts) and parts[inn_idx + 1] in ['1/3', '2/3']:
                        innings = float(inn_raw) + (0.1 if parts[inn_idx + 1] == '1/3' else 0.2)
                        offset = 1
                    else:
                        innings = float(inn_raw) if inn_raw != '-' else 0
                        offset = 0

                    base = inn_idx + 1 + offset
                    pitcher = {
                        'name':              name,
                        'result':            result_str,
                        'innings_pitched':   innings,
                        'pitch_count':       int(parts[base + 1]),
                        'hits_allowed':      int(parts[base + 3]),
                        'home_runs_allowed': int(parts[base + 4]),
                        'walks':             int(parts[base + 5]),
                        'strikeouts':        int(parts[base + 6]),
                        'runs_allowed':      int(parts[base + 7]),
                        'earned_runs':       int(parts[base + 8]),
                    }

                    if away_pitcher_section:
                        result['away_pitchers'].append(pitcher)
                    elif home_pitcher_section:
                        result['home_pitchers'].append(pitcher)
                except Exception:
                    pass

    return result


def crawl_kbo_pitcher_stats(season=2026):
    """KBO 기록실에서 투수 통계만 크롤링"""
    conn = get_connection()
    if not conn:
        return

    cur = conn.cursor()
    cur.execute("""
        SELECT id, name, naver_player_id
        FROM players
        WHERE naver_player_id IS NOT NULL
        AND player_type = '투수'
        ORDER BY id
    """)
    players = cur.fetchall()
    cur.close()
    conn.close()

    print(f'투수 크롤링 대상: {len(players)}명')
    driver = get_driver()
    from selenium.webdriver.common.by import By

    updated = 0
    for (db_id, name, naver_id) in players:
        try:
            url = f"https://www.koreabaseball.com/Record/Player/PitcherDetail/Basic.aspx?playerId={naver_id}"
            driver.get(url)
            time.sleep(1.5)
            text = driver.find_element(By.TAG_NAME, 'body').text
            stats = parse_pitcher_stats(text, season)

            if not stats or 'games' not in stats or stats['games'] == 0:
                continue

            conn = get_connection()
            cur = conn.cursor()
            cur.execute("""
                INSERT INTO pitcher_stats (
                    player_id, season, games, wins, losses, saves, holds,
                    innings_pitched, hits_allowed, runs_allowed, earned_runs,
                    walks, strikeouts, home_runs_allowed, era, whip
                ) VALUES (
                    %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s
                )
                ON CONFLICT (player_id, season) DO UPDATE SET
                    games = EXCLUDED.games,
                    wins = EXCLUDED.wins,
                    losses = EXCLUDED.losses,
                    saves = EXCLUDED.saves,
                    holds = EXCLUDED.holds,
                    innings_pitched = EXCLUDED.innings_pitched,
                    hits_allowed = EXCLUDED.hits_allowed,
                    runs_allowed = EXCLUDED.runs_allowed,
                    earned_runs = EXCLUDED.earned_runs,
                    walks = EXCLUDED.walks,
                    strikeouts = EXCLUDED.strikeouts,
                    home_runs_allowed = EXCLUDED.home_runs_allowed,
                    era = EXCLUDED.era,
                    whip = EXCLUDED.whip
            """, (
                db_id, season,
                stats.get('games', 0), stats.get('wins', 0),
                stats.get('losses', 0), stats.get('saves', 0),
                stats.get('holds', 0), stats.get('innings_pitched', 0),
                stats.get('hits_allowed', 0), stats.get('runs_allowed', 0),
                stats.get('earned_runs', 0), stats.get('walks', 0),
                stats.get('strikeouts', 0), stats.get('home_runs_allowed', 0),
                stats.get('era', 0), stats.get('whip', 0),
            ))
            conn.commit()
            cur.close()
            conn.close()
            updated += 1
            print(f'{name}: {stats.get("games")}경기 업데이트')

        except Exception as e:
            print(f'오류 ({name}): {e}')
            try:
                conn.rollback()
                conn.close()
            except:
                pass
            continue

    driver.quit()
    print(f'총 {updated}명 투수 통계 업데이트 완료')


def get_driver():
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options
    from selenium.webdriver.chrome.service import Service
    from webdriver_manager.chrome import ChromeDriverManager

    options = Options()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--blink-settings=imagesEnabled=false')
    options.add_experimental_option('prefs', {
        'profile.managed_default_content_settings.images': 2,
        'profile.managed_default_content_settings.stylesheets': 2,
    })
    return webdriver.Chrome(
        service=Service(ChromeDriverManager().install()),
        options=options
    )


def parse_hitter_stats(text, season=2026):
    """KBO 기록실 타자 스탯 파싱"""
    lines = text.split('\n')
    stats = {}

    for i, line in enumerate(lines):
        if f'{season} 성적' in line:
            try:
                row1 = lines[i+3].strip().split()
                row2 = lines[i+5].strip().split()

                if len(row1) >= 15 and row1[0] not in ['기록이', 'KBO', '팀명']:
                    stats['avg'] =          float(row1[1]) if row1[1] != '-' else 0
                    stats['games'] =        int(row1[2])
                    stats['pa'] =           int(row1[3])
                    stats['at_bats'] =      int(row1[4])
                    stats['runs'] =         int(row1[5])
                    stats['hits'] =         int(row1[6])
                    stats['doubles'] =      int(row1[7])
                    stats['triples'] =      int(row1[8])
                    stats['home_runs'] =    int(row1[9])
                    stats['rbis'] =         int(row1[11])
                    stats['stolen_bases'] = int(row1[12])

                if len(row2) >= 13 and row2[0] not in ['기록이', 'KBO', 'BB']:
                    stats['walks'] =      int(row2[0])
                    stats['strikeouts'] = int(row2[3])
                    stats['slg'] =        float(row2[5]) if row2[5] != '-' else 0
                    stats['obp'] =        float(row2[6]) if row2[6] != '-' else 0
                    stats['ops'] =        float(row2[10]) if row2[10] != '-' else 0

            except Exception as e:
                print(f'타자 스탯 파싱 오류: {e}')
            break

    return stats


def parse_pitcher_stats(text, season=2026):
    """KBO 기록실 투수 스탯 파싱"""
    lines = text.split('\n')
    stats = {}

    for i, line in enumerate(lines):
        if f'{season} 성적' in line:
            try:
                row1 = lines[i+3].strip().split()
                row2 = lines[i+5].strip().split()

                if len(row1) < 13 or row1[0] in ['기록이', 'KBO', '팀명']:
                    break

                stats['era'] =    float(row1[1]) if row1[1] != '-' else 0
                stats['games'] =  int(row1[2])
                stats['wins'] =   int(row1[5])
                stats['losses'] = int(row1[6])
                stats['saves'] =  int(row1[7])
                stats['holds'] =  int(row1[8])

                ip_raw = row1[12]
                if ip_raw in ['1/3', '2/3']:
                    stats['innings_pitched'] = 0.1 if ip_raw == '1/3' else 0.2
                    offset = 0
                elif len(row1) > 13 and row1[13] in ['1/3', '2/3']:
                    full = float(ip_raw)
                    stats['innings_pitched'] = full + (0.1 if row1[13] == '1/3' else 0.2)
                    offset = 1
                else:
                    stats['innings_pitched'] = float(ip_raw) if ip_raw != '-' else 0
                    offset = 0

                stats['hits_allowed'] =      int(row1[13+offset])
                stats['home_runs_allowed'] = int(row1[16+offset])

                if len(row2) >= 11 and row2[0] not in ['기록이', 'KBO']:
                    stats['walks'] =        int(row2[2])
                    stats['strikeouts'] =   int(row2[4])
                    stats['runs_allowed'] = int(row2[7])
                    stats['earned_runs'] =  int(row2[8])
                    stats['whip'] =         float(row2[10]) if row2[10] != '-' else 0

            except Exception as e:
                print(f'투수 스탯 파싱 오류: {e}')
            break

    return stats


def parse_innings(inn_str):
    """이닝 문자열 파싱 (7 2/3 → 7.2)"""
    inn_str = str(inn_str).strip()
    try:
        if '/' in inn_str:
            parts = inn_str.split()
            if len(parts) == 2:
                full = float(parts[0]) if parts[0].replace('.', '').isdigit() else 0
                frac = parts[1]
            else:
                full = 0
                frac = parts[0]
            if frac == '1/3':
                return full + 0.1
            elif frac == '2/3':
                return full + 0.2
            return full
        return float(inn_str)
    except:
        return 0.0


def crawl_kbo_stats(season=2026):
    """KBO 기록실에서 전체 선수 통계 크롤링"""
    conn = get_connection()
    if not conn:
        return

    cur = conn.cursor()
    cur.execute("""
        SELECT id, name, naver_player_id, player_type
        FROM players
        WHERE naver_player_id IS NOT NULL
        ORDER BY id
    """)
    players = cur.fetchall()
    cur.close()
    conn.close()

    print(f'크롤링 대상: {len(players)}명')
    driver = get_driver()
    from selenium.webdriver.common.by import By

    updated = 0
    for (db_id, name, naver_id, player_type) in players:
        try:
            if player_type == '타자':
                url = f"https://www.koreabaseball.com/Record/Player/HitterDetail/Basic.aspx?playerId={naver_id}"
            else:
                url = f"https://www.koreabaseball.com/Record/Player/PitcherDetail/Basic.aspx?playerId={naver_id}"

            driver.get(url)
            time.sleep(1.5)
            text = driver.find_element(By.TAG_NAME, 'body').text

            if player_type == '타자':
                stats = parse_hitter_stats(text, season)
            else:
                stats = parse_pitcher_stats(text, season)

            if not stats or 'games' not in stats or stats['games'] == 0:
                continue

            conn = get_connection()
            cur = conn.cursor()

            if player_type == '타자':
                cur.execute("""
                    INSERT INTO batter_stats (
                        player_id, season, games, at_bats, runs, hits,
                        doubles, triples, home_runs, rbis, walks, strikeouts,
                        stolen_bases, avg, obp, slg, ops
                    ) VALUES (
                        %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s
                    )
                    ON CONFLICT (player_id, season) DO UPDATE SET
                        games = EXCLUDED.games,
                        at_bats = EXCLUDED.at_bats,
                        runs = EXCLUDED.runs,
                        hits = EXCLUDED.hits,
                        doubles = EXCLUDED.doubles,
                        triples = EXCLUDED.triples,
                        home_runs = EXCLUDED.home_runs,
                        rbis = EXCLUDED.rbis,
                        walks = EXCLUDED.walks,
                        strikeouts = EXCLUDED.strikeouts,
                        stolen_bases = EXCLUDED.stolen_bases,
                        avg = EXCLUDED.avg,
                        obp = EXCLUDED.obp,
                        slg = EXCLUDED.slg,
                        ops = EXCLUDED.ops
                """, (
                    db_id, season,
                    stats.get('games', 0), stats.get('at_bats', 0),
                    stats.get('runs', 0), stats.get('hits', 0),
                    stats.get('doubles', 0), stats.get('triples', 0),
                    stats.get('home_runs', 0), stats.get('rbis', 0),
                    stats.get('walks', 0), stats.get('strikeouts', 0),
                    stats.get('stolen_bases', 0),
                    stats.get('avg', 0), stats.get('obp', 0),
                    stats.get('slg', 0), stats.get('ops', 0),
                ))
            else:
                cur.execute("""
                    INSERT INTO pitcher_stats (
                        player_id, season, games, wins, losses, saves, holds,
                        innings_pitched, hits_allowed, runs_allowed, earned_runs,
                        walks, strikeouts, home_runs_allowed, era, whip
                    ) VALUES (
                        %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s
                    )
                    ON CONFLICT (player_id, season) DO UPDATE SET
                        games = EXCLUDED.games,
                        wins = EXCLUDED.wins,
                        losses = EXCLUDED.losses,
                        saves = EXCLUDED.saves,
                        holds = EXCLUDED.holds,
                        innings_pitched = EXCLUDED.innings_pitched,
                        hits_allowed = EXCLUDED.hits_allowed,
                        runs_allowed = EXCLUDED.runs_allowed,
                        earned_runs = EXCLUDED.earned_runs,
                        walks = EXCLUDED.walks,
                        strikeouts = EXCLUDED.strikeouts,
                        home_runs_allowed = EXCLUDED.home_runs_allowed,
                        era = EXCLUDED.era,
                        whip = EXCLUDED.whip
                """, (
                    db_id, season,
                    stats.get('games', 0), stats.get('wins', 0),
                    stats.get('losses', 0), stats.get('saves', 0),
                    stats.get('holds', 0), stats.get('innings_pitched', 0),
                    stats.get('hits_allowed', 0), stats.get('runs_allowed', 0),
                    stats.get('earned_runs', 0), stats.get('walks', 0),
                    stats.get('strikeouts', 0), stats.get('home_runs_allowed', 0),
                    stats.get('era', 0), stats.get('whip', 0),
                ))

            conn.commit()
            cur.close()
            conn.close()
            updated += 1
            print(f'{name} ({player_type}): {stats.get("games")}경기 업데이트')

        except Exception as e:
            print(f'오류 ({name}): {e}')
            try:
                conn.rollback()
                conn.close()
            except:
                pass
            continue

    driver.quit()
    print(f'총 {updated}명 통계 업데이트 완료')


if __name__ == "__main__":
    crawl_kbo_stats(2026)