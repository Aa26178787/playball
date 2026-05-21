"""
KBO 공식 사이트에서 선수 일자별 기록 크롤링 (서버용 headless)
"""
import time
import re
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database.connection import get_connection


def _get_driver():
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options
    from selenium.webdriver.chrome.service import Service
    from webdriver_manager.chrome import ChromeDriverManager
    options = Options()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--disable-gpu')
    options.add_experimental_option('prefs', {
        'profile.managed_default_content_settings.images': 2,
        'profile.managed_default_content_settings.stylesheets': 2,
    })
    return webdriver.Chrome(
        service=Service(ChromeDriverManager().install()),
        options=options
    )


def _safe_int(val):
    try:
        return int(val)
    except Exception:
        return None


def _safe_float(val):
    try:
        return float(val)
    except Exception:
        return None


def _parse_innings(ip_raw, next_val=None):
    try:
        if ip_raw in ['1/3', '2/3']:
            return 0.1 if ip_raw == '1/3' else 0.2
        if next_val in ['1/3', '2/3']:
            return float(ip_raw) + (0.1 if next_val == '1/3' else 0.2)
        return float(ip_raw)
    except Exception:
        return 0.0


def _parse_daily_hitter(lines):
    records = []
    in_section = False
    for line in lines:
        line = line.strip()
        if not line:
            continue
        if '개인정보' in line or 'Copyright' in line:
            break
        if line.startswith('합계'):
            continue
        if re.match(r'^\d+월\s+상대', line):
            in_section = True
            continue
        if not in_section:
            continue
        vals = line.split()
        if len(vals) < 3:
            continue
        if not re.match(r'^\d{2}\.\d{2}$', vals[0]):
            continue
        try:
            date_str = f"2026-{vals[0].replace('.', '-')}"
            records.append({
                'game_date': date_str,
                'opponent': vals[1],
                'stat_type': 'hitter',
                'avg': _safe_float(vals[2]),
                'pa': _safe_int(vals[3]),
                'ab': _safe_int(vals[4]),
                'runs': _safe_int(vals[5]),
                'hits': _safe_int(vals[6]),
                'doubles': _safe_int(vals[7]),
                'triples': _safe_int(vals[8]),
                'home_runs': _safe_int(vals[9]),
                'rbi': _safe_int(vals[10]),
                'sb': _safe_int(vals[11]),
                'cs': _safe_int(vals[12]),
                'walks': _safe_int(vals[13]),
                'hbp': _safe_int(vals[14]),
                'strikeouts': _safe_int(vals[15]),
                'gdp': _safe_int(vals[16]) if len(vals) > 16 else None,
            })
        except Exception:
            continue
    return records


def _parse_daily_pitcher(lines):
    records = []
    in_section = False
    for line in lines:
        line = line.strip()
        if not line:
            continue
        if '개인정보' in line or 'Copyright' in line:
            break
        if line.startswith('합계'):
            continue
        if re.match(r'^\d+월\s+상대', line):
            in_section = True
            continue
        if not in_section:
            continue
        vals = line.split()
        if len(vals) < 3:
            continue
        if not re.match(r'^\d{2}\.\d{2}$', vals[0]):
            continue
        try:
            date_str = f"2026-{vals[0].replace('.', '-')}"
            result = vals[2] if vals[2] in ['승', '패', '세이브', '홀드', '블론'] else None
            offset = 1 if result else 0
            ip_raw = vals[3 + offset]
            next_v = vals[4 + offset] if 4 + offset < len(vals) else None
            ip = _parse_innings(ip_raw, next_v)
            ip_offset = 1 if next_v in ['1/3', '2/3'] else 0
            base = 4 + offset + ip_offset
            records.append({
                'game_date': date_str,
                'opponent': vals[1],
                'result': result,
                'stat_type': 'pitcher',
                'era': _safe_float(vals[3]) if result else _safe_float(vals[2 + offset]),
                'ip': ip,
                'h': _safe_int(vals[base]),
                'hr': _safe_int(vals[base + 1]),
                'bb': _safe_int(vals[base + 2]),
                'so': _safe_int(vals[base + 4]),
                'r': _safe_int(vals[base + 5]),
                'er': _safe_int(vals[base + 6]),
            })
        except Exception:
            continue
    return records


def _save_records(cur, player_id, records):
    saved = 0
    for r in records:
        try:
            cur.execute("""
                INSERT INTO player_daily_stats (
                    player_id, game_date, opponent, result, stat_type,
                    avg, pa, ab, runs, hits, doubles, triples, home_runs,
                    rbi, sb, cs, walks, hbp, strikeouts, gdp,
                    era, ip, h, hr, bb, so, r, er
                ) VALUES (
                    %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s, %s, %s
                )
                ON CONFLICT (player_id, game_date, opponent, stat_type) DO UPDATE SET
                    avg = EXCLUDED.avg, pa = EXCLUDED.pa, ab = EXCLUDED.ab,
                    runs = EXCLUDED.runs, hits = EXCLUDED.hits,
                    doubles = EXCLUDED.doubles, triples = EXCLUDED.triples,
                    home_runs = EXCLUDED.home_runs, rbi = EXCLUDED.rbi,
                    sb = EXCLUDED.sb, cs = EXCLUDED.cs,
                    walks = EXCLUDED.walks, hbp = EXCLUDED.hbp,
                    strikeouts = EXCLUDED.strikeouts, gdp = EXCLUDED.gdp,
                    era = EXCLUDED.era, ip = EXCLUDED.ip,
                    h = EXCLUDED.h, hr = EXCLUDED.hr, bb = EXCLUDED.bb,
                    so = EXCLUDED.so, r = EXCLUDED.r, er = EXCLUDED.er
            """, (
                player_id, r.get('game_date'), r.get('opponent'),
                r.get('result'), r.get('stat_type'),
                r.get('avg'), r.get('pa'), r.get('ab'),
                r.get('runs'), r.get('hits'), r.get('doubles'),
                r.get('triples'), r.get('home_runs'), r.get('rbi'),
                r.get('sb'), r.get('cs'), r.get('walks'), r.get('hbp'),
                r.get('strikeouts'), r.get('gdp'),
                r.get('era'), r.get('ip'), r.get('h'), r.get('hr'),
                r.get('bb'), r.get('so'), r.get('r'), r.get('er'),
            ))
            saved += 1
        except Exception:
            continue
    return saved


def crawl_daily_stats_for_today_players():
    """오늘 종료 경기에 출전한 선수들의 KBO 일자별 기록 크롤링"""
    conn = get_connection()
    if not conn:
        return

    cur = conn.cursor()
    cur.execute("""
        SELECT DISTINCT p.id, p.name, p.naver_player_id, p.player_type
        FROM players p
        JOIN (
            SELECT player_id FROM game_batters gb
            JOIN games g ON gb.game_id = g.id
            WHERE g.game_date = CURRENT_DATE AND g.status = '종료'
            UNION
            SELECT player_id FROM game_pitchers gp
            JOIN games g ON gp.game_id = g.id
            WHERE g.game_date = CURRENT_DATE AND g.status = '종료'
        ) played ON p.id = played.player_id
        WHERE p.naver_player_id IS NOT NULL
    """)
    players = cur.fetchall()
    cur.close()
    conn.close()

    if not players:
        print("오늘 출전 선수 없음")
        return

    print(f"[KBO daily] 크롤링 대상: {len(players)}명")
    driver = _get_driver()
    updated = 0
    errors = 0

    for (player_id, name, naver_id, player_type) in players:
        try:
            ptype = 'Hitter' if player_type == '타자' else 'Pitcher'
            url = f"https://www.koreabaseball.com/Record/Player/{ptype}Detail/Daily.aspx?playerId={naver_id}"
            driver.get(url)
            time.sleep(2)
            lines = driver.find_element('tag name', 'body').text.split('\n')

            if player_type == '타자':
                records = _parse_daily_hitter(lines)
            else:
                records = _parse_daily_pitcher(lines)

            if not records:
                continue

            conn = get_connection()
            if not conn:
                continue
            cur = conn.cursor()
            saved = _save_records(cur, player_id, records)
            conn.commit()
            cur.close()
            conn.close()

            updated += 1
            if updated % 10 == 0:
                print(f"[KBO daily] {updated}/{len(players)} 완료")

        except Exception as e:
            errors += 1
            print(f"[KBO daily] 오류 ({name}): {e}")
            try:
                conn.rollback()
                conn.close()
            except Exception:
                pass

    driver.quit()
    print(f"[KBO daily] 완료: {updated}명 업데이트, {errors}명 오류")


# KBO site team name → DB team_id
_KBO_TEAM_ID = {
    'KIA': 2, 'LG': 9, 'SSG': 10, '두산': 7, '한화': 5,
    '롯데': 4, '삼성': 11, 'NC': 6, 'KT': 1, '키움': 8,
}


def _get_kbo_season_pages(driver, url):
    """KBO 사이트 페이지 전체 순회하며 tbody tr 수집"""
    from bs4 import BeautifulSoup
    driver.get(url)
    time.sleep(3)

    all_rows = []
    headers = []

    while True:
        soup = BeautifulSoup(driver.page_source, 'html.parser')
        table = soup.find('table', class_='tData01')
        if not table:
            break

        if not headers:
            headers = [th.get_text(strip=True) for th in table.select('thead th')]

        for tr in table.select('tbody tr'):
            cols = [td.get_text(strip=True) for td in tr.find_all('td')]
            if cols:
                all_rows.append(cols)

        # 다음 페이지
        try:
            paging = soup.find('div', class_='paging')
            if not paging:
                break
            next_a = None
            for a in paging.find_all('a'):
                if a.get_text(strip=True) in ('다음', '>'):
                    next_a = a
                    break
            if not next_a:
                break
            href = next_a.get('href', '')
            driver.execute_script(f"javascript:{href.split('javascript:')[1]}" if 'javascript:' in href else href)
            time.sleep(2)
        except Exception:
            break

    return headers, all_rows


def crawl_kbo_hitter_season_stats(season=2026):
    """KBO 공식 사이트 HitterBasic/Basic1.aspx → batter_stats 업데이트"""
    url = f"https://www.koreabaseball.com/Record/Player/HitterBasic/Basic1.aspx"
    driver = _get_driver()
    try:
        headers, rows = _get_kbo_season_pages(driver, url)
    finally:
        driver.quit()

    if not rows:
        print("[KBO season] 타자 데이터 없음")
        return

    print(f"[KBO season] 타자 {len(rows)}행 파싱. 헤더: {headers}")

    # 컬럼 인덱스 (헤더 기반)
    def idx(name):
        try:
            return headers.index(name)
        except ValueError:
            return None

    i_name   = idx('선수명') or 1
    i_team   = idx('팀명')   or 2
    i_games  = idx('경기')   or 3
    i_pa     = idx('타석')   or 4
    i_ab     = idx('타수')   or 5
    i_runs   = idx('득점')   or 6
    i_hits   = idx('안타')   or 7
    i_2b     = idx('2루타')  or 8
    i_3b     = idx('3루타')  or 9
    i_hr     = idx('홈런')   or 10
    i_rbi    = idx('타점')   or 11
    i_sb     = idx('도루')   or 12
    i_cs     = idx('도루자') or 13
    i_bb     = idx('볼넷')   or 14
    i_hbp    = idx('사구')   or 15
    i_so     = idx('삼진')   or 16
    i_gdp    = idx('병살')   or 17
    i_avg    = idx('타율')   or 18

    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    saved = errors = 0

    for cols in rows:
        try:
            name     = cols[i_name]
            team_name = cols[i_team]
            team_id  = _KBO_TEAM_ID.get(team_name)
            if not team_id:
                continue

            cur.execute("""
                SELECT id FROM players
                WHERE name = %s AND team_id = %s AND player_type = '타자'
                LIMIT 1
            """, (name, team_id))
            row = cur.fetchone()
            if not row:
                continue
            player_id = row[0]

            cur.execute("""
                INSERT INTO batter_stats (
                    player_id, season, games, pa, at_bats, runs, hits,
                    doubles, triples, home_runs, rbis, stolen_bases, cs,
                    walks, hbp, strikeouts, gdp, avg
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (player_id, season) DO UPDATE SET
                    games        = EXCLUDED.games,
                    pa           = EXCLUDED.pa,
                    at_bats      = EXCLUDED.at_bats,
                    runs         = EXCLUDED.runs,
                    hits         = EXCLUDED.hits,
                    doubles      = EXCLUDED.doubles,
                    triples      = EXCLUDED.triples,
                    home_runs    = EXCLUDED.home_runs,
                    rbis         = EXCLUDED.rbis,
                    stolen_bases = EXCLUDED.stolen_bases,
                    cs           = EXCLUDED.cs,
                    walks        = EXCLUDED.walks,
                    hbp          = EXCLUDED.hbp,
                    strikeouts   = EXCLUDED.strikeouts,
                    gdp          = EXCLUDED.gdp,
                    avg          = EXCLUDED.avg
            """, (
                player_id, season,
                _safe_int(cols[i_games]),
                _safe_int(cols[i_pa]),
                _safe_int(cols[i_ab]),
                _safe_int(cols[i_runs]),
                _safe_int(cols[i_hits]),
                _safe_int(cols[i_2b]),
                _safe_int(cols[i_3b]),
                _safe_int(cols[i_hr]),
                _safe_int(cols[i_rbi]),
                _safe_int(cols[i_sb]),
                _safe_int(cols[i_cs]),
                _safe_int(cols[i_bb]),
                _safe_int(cols[i_hbp]),
                _safe_int(cols[i_so]),
                _safe_int(cols[i_gdp]),
                _safe_float(cols[i_avg]),
            ))
            saved += 1
        except Exception as e:
            errors += 1
            continue

    conn.commit()
    cur.close()
    conn.close()
    print(f"[KBO season] 타자 {saved}명 업데이트, {errors}건 오류")


def crawl_kbo_pitcher_season_stats(season=2026):
    """KBO 공식 사이트 PitcherBasic/Basic1.aspx → pitcher_stats 업데이트"""
    url = "https://www.koreabaseball.com/Record/Player/PitcherBasic/Basic1.aspx"
    driver = _get_driver()
    try:
        headers, rows = _get_kbo_season_pages(driver, url)
    finally:
        driver.quit()

    if not rows:
        print("[KBO season] 투수 데이터 없음")
        return

    print(f"[KBO season] 투수 {len(rows)}행 파싱. 헤더: {headers}")

    def idx(name):
        try:
            return headers.index(name)
        except ValueError:
            return None

    i_name  = idx('선수명') or 1
    i_team  = idx('팀명')   or 2
    i_games = idx('경기')   or 3
    i_wins  = idx('승')     or 4
    i_loss  = idx('패')     or 5
    i_sv    = idx('세이브') or 6
    i_hold  = idx('홀드')   or 7
    i_ip    = idx('이닝')   or 8
    i_ha    = idx('피안타') or 9
    i_hra   = idx('피홈런') or 10
    i_bb    = idx('볼넷')   or 11
    i_so    = idx('삼진')   or 12
    i_r     = idx('실점')   or 13
    i_er    = idx('자책점') or 14
    i_era   = idx('평균자책점') or 15

    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    saved = errors = 0

    for cols in rows:
        try:
            name      = cols[i_name]
            team_name = cols[i_team]
            team_id   = _KBO_TEAM_ID.get(team_name)
            if not team_id:
                continue

            cur.execute("""
                SELECT id FROM players
                WHERE name = %s AND team_id = %s AND player_type = '투수'
                LIMIT 1
            """, (name, team_id))
            row = cur.fetchone()
            if not row:
                continue
            player_id = row[0]

            ip_str = cols[i_ip] if i_ip < len(cols) else '0'
            ip_val = _parse_innings(ip_str)

            cur.execute("""
                INSERT INTO pitcher_stats (
                    player_id, season, games, wins, losses, saves, holds,
                    innings_pitched, hits_allowed, home_runs_allowed,
                    walks, strikeouts, runs_allowed, earned_runs, era
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (player_id, season) DO UPDATE SET
                    games              = EXCLUDED.games,
                    wins               = EXCLUDED.wins,
                    losses             = EXCLUDED.losses,
                    saves              = EXCLUDED.saves,
                    holds              = EXCLUDED.holds,
                    innings_pitched    = EXCLUDED.innings_pitched,
                    hits_allowed       = EXCLUDED.hits_allowed,
                    home_runs_allowed  = EXCLUDED.home_runs_allowed,
                    walks              = EXCLUDED.walks,
                    strikeouts         = EXCLUDED.strikeouts,
                    runs_allowed       = EXCLUDED.runs_allowed,
                    earned_runs        = EXCLUDED.earned_runs,
                    era                = EXCLUDED.era
            """, (
                player_id, season,
                _safe_int(cols[i_games]),
                _safe_int(cols[i_wins]),
                _safe_int(cols[i_loss]),
                _safe_int(cols[i_sv]),
                _safe_int(cols[i_hold]),
                ip_val,
                _safe_int(cols[i_ha]),
                _safe_int(cols[i_hra]),
                _safe_int(cols[i_bb]),
                _safe_int(cols[i_so]),
                _safe_int(cols[i_r]),
                _safe_int(cols[i_er]),
                _safe_float(cols[i_era]),
            ))
            saved += 1
        except Exception:
            errors += 1
            continue

    conn.commit()
    cur.close()
    conn.close()
    print(f"[KBO season] 투수 {saved}명 업데이트, {errors}건 오류")
