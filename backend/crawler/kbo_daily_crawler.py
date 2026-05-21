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
                    avg        = COALESCE(EXCLUDED.avg,        player_daily_stats.avg),
                    pa         = COALESCE(EXCLUDED.pa,         player_daily_stats.pa),
                    ab         = COALESCE(EXCLUDED.ab,         player_daily_stats.ab),
                    runs       = COALESCE(EXCLUDED.runs,       player_daily_stats.runs),
                    hits       = COALESCE(EXCLUDED.hits,       player_daily_stats.hits),
                    doubles    = COALESCE(EXCLUDED.doubles,    player_daily_stats.doubles),
                    triples    = COALESCE(EXCLUDED.triples,    player_daily_stats.triples),
                    home_runs  = COALESCE(EXCLUDED.home_runs,  player_daily_stats.home_runs),
                    rbi        = COALESCE(EXCLUDED.rbi,        player_daily_stats.rbi),
                    sb         = COALESCE(EXCLUDED.sb,         player_daily_stats.sb),
                    cs         = COALESCE(EXCLUDED.cs,         player_daily_stats.cs),
                    walks      = COALESCE(EXCLUDED.walks,      player_daily_stats.walks),
                    hbp        = COALESCE(EXCLUDED.hbp,        player_daily_stats.hbp),
                    strikeouts = COALESCE(EXCLUDED.strikeouts, player_daily_stats.strikeouts),
                    gdp        = COALESCE(EXCLUDED.gdp,        player_daily_stats.gdp),
                    era        = COALESCE(EXCLUDED.era,        player_daily_stats.era),
                    ip         = COALESCE(EXCLUDED.ip,         player_daily_stats.ip),
                    h          = COALESCE(EXCLUDED.h,          player_daily_stats.h),
                    hr         = COALESCE(EXCLUDED.hr,         player_daily_stats.hr),
                    bb         = COALESCE(EXCLUDED.bb,         player_daily_stats.bb),
                    so         = COALESCE(EXCLUDED.so,         player_daily_stats.so),
                    r          = COALESCE(EXCLUDED.r,          player_daily_stats.r),
                    er         = COALESCE(EXCLUDED.er,         player_daily_stats.er)
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
    prev_first_row = None
    max_pages = 30

    for page_num in range(1, max_pages + 1):
        soup = BeautifulSoup(driver.page_source, 'html.parser')
        table = soup.find('table', class_='tData01')
        if not table:
            print(f"[KBO season] 페이지 {page_num}: 테이블 없음 → 종료")
            break

        if not headers:
            headers = [th.get_text(strip=True) for th in table.select('thead th')]

        trs = table.select('tbody tr')
        if not trs:
            break

        # 같은 페이지 감지 (무한루프 방지)
        first_row_text = ''.join(trs[0].get_text(strip=True))
        if first_row_text == prev_first_row:
            print(f"[KBO season] 페이지 {page_num}: 중복 감지 → 종료")
            break
        prev_first_row = first_row_text

        page_rows = 0
        for tr in trs:
            cols = [td.get_text(strip=True) for td in tr.find_all('td')]
            if cols:
                all_rows.append(cols)
                page_rows += 1

        print(f"[KBO season] 페이지 {page_num}: {page_rows}행 (누적 {len(all_rows)})")

        # 다음 페이지
        try:
            next_btn = driver.find_element('xpath', '//a[normalize-space(.)="다음"]')
            next_btn.click()
            time.sleep(2)
        except Exception:
            print(f"[KBO season] 페이지 {page_num}: 다음 버튼 없음 → 종료")
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

    # 컬럼 인덱스 (영문/한국어 모두 시도)
    def _h(*names):
        for name in names:
            try:
                return headers.index(name)
            except ValueError:
                continue
        return None

    i_name  = _h('선수명') or 1
    i_team  = _h('팀명')   or 2
    i_avg   = _h('AVG', '타율')
    i_games = _h('G', '경기')
    i_pa    = _h('PA', '타석')
    i_ab    = _h('AB', '타수')
    i_runs  = _h('R', '득점')
    i_hits  = _h('H', '안타')
    i_2b    = _h('2B', '2루타')
    i_3b    = _h('3B', '3루타')
    i_hr    = _h('HR', '홈런')
    i_rbi   = _h('RBI', '타점')
    i_sb    = _h('SB', '도루')
    i_cs    = _h('CS', '도루자')
    i_bb    = _h('BB', '볼넷')
    i_hbp   = _h('HBP', '사구')
    i_so    = _h('SO', 'K', '삼진')
    i_gdp   = _h('GDP', '병살')

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

            def _col_int(i):
                return _safe_int(cols[i]) if i is not None and i < len(cols) else None
            def _col_float(i):
                return _safe_float(cols[i]) if i is not None and i < len(cols) else None

            cur.execute("""
                INSERT INTO batter_stats (
                    player_id, season, games, pa, at_bats, runs, hits,
                    doubles, triples, home_runs, rbis, stolen_bases, cs,
                    walks, hbp, strikeouts, gdp, avg
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (player_id, season) DO UPDATE SET
                    games        = EXCLUDED.games,
                    pa           = COALESCE(EXCLUDED.pa,           batter_stats.pa),
                    at_bats      = COALESCE(EXCLUDED.at_bats,      batter_stats.at_bats),
                    runs         = COALESCE(EXCLUDED.runs,         batter_stats.runs),
                    hits         = EXCLUDED.hits,
                    doubles      = COALESCE(EXCLUDED.doubles,      batter_stats.doubles),
                    triples      = COALESCE(EXCLUDED.triples,      batter_stats.triples),
                    home_runs    = EXCLUDED.home_runs,
                    rbis         = EXCLUDED.rbis,
                    stolen_bases = COALESCE(EXCLUDED.stolen_bases, batter_stats.stolen_bases),
                    cs           = COALESCE(EXCLUDED.cs,           batter_stats.cs),
                    walks        = COALESCE(EXCLUDED.walks,        batter_stats.walks),
                    hbp          = COALESCE(EXCLUDED.hbp,          batter_stats.hbp),
                    strikeouts   = COALESCE(EXCLUDED.strikeouts,   batter_stats.strikeouts),
                    gdp          = COALESCE(EXCLUDED.gdp,          batter_stats.gdp),
                    avg          = COALESCE(EXCLUDED.avg,          batter_stats.avg)
            """, (
                player_id, season,
                _col_int(i_games), _col_int(i_pa),  _col_int(i_ab),
                _col_int(i_runs),  _col_int(i_hits), _col_int(i_2b),
                _col_int(i_3b),    _col_int(i_hr),   _col_int(i_rbi),
                _col_int(i_sb),    _col_int(i_cs),   _col_int(i_bb),
                _col_int(i_hbp),   _col_int(i_so),   _col_int(i_gdp),
                _col_float(i_avg),
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

    def _h(*names):
        for name in names:
            try:
                return headers.index(name)
            except ValueError:
                continue
        return None

    i_name  = _h('선수명') or 1
    i_team  = _h('팀명')   or 2
    i_games = _h('G', '경기')
    i_wins  = _h('W', '승')
    i_loss  = _h('L', '패')
    i_sv    = _h('SV', '세이브')
    i_hold  = _h('HLD', '홀드')
    i_ip    = _h('IP', '이닝')
    i_ha    = _h('H', 'HA', '피안타')
    i_hra   = _h('HR', 'HRA', '피홈런')
    i_bb    = _h('BB', '볼넷')
    i_so    = _h('SO', 'K', '삼진')
    i_r     = _h('R', '실점')
    i_er    = _h('ER', '자책점')
    i_era   = _h('ERA', '평균자책점')

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

            def _ci(i):
                return _safe_int(cols[i]) if i is not None and i < len(cols) else None
            def _cf(i):
                return _safe_float(cols[i]) if i is not None and i < len(cols) else None

            ip_str = cols[i_ip] if i_ip is not None and i_ip < len(cols) else '0'
            ip_val = _parse_innings(ip_str)

            cur.execute("""
                INSERT INTO pitcher_stats (
                    player_id, season, games, wins, losses, saves, holds,
                    innings_pitched, hits_allowed, home_runs_allowed,
                    walks, strikeouts, runs_allowed, earned_runs, era
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (player_id, season) DO UPDATE SET
                    games              = EXCLUDED.games,
                    wins               = COALESCE(EXCLUDED.wins,              pitcher_stats.wins),
                    losses             = COALESCE(EXCLUDED.losses,            pitcher_stats.losses),
                    saves              = COALESCE(EXCLUDED.saves,             pitcher_stats.saves),
                    holds              = COALESCE(EXCLUDED.holds,             pitcher_stats.holds),
                    innings_pitched    = EXCLUDED.innings_pitched,
                    hits_allowed       = COALESCE(EXCLUDED.hits_allowed,      pitcher_stats.hits_allowed),
                    home_runs_allowed  = COALESCE(EXCLUDED.home_runs_allowed, pitcher_stats.home_runs_allowed),
                    walks              = COALESCE(EXCLUDED.walks,             pitcher_stats.walks),
                    strikeouts         = COALESCE(EXCLUDED.strikeouts,        pitcher_stats.strikeouts),
                    runs_allowed       = COALESCE(EXCLUDED.runs_allowed,      pitcher_stats.runs_allowed),
                    earned_runs        = COALESCE(EXCLUDED.earned_runs,       pitcher_stats.earned_runs),
                    era                = COALESCE(EXCLUDED.era,               pitcher_stats.era)
            """, (
                player_id, season,
                _ci(i_games), _ci(i_wins), _ci(i_loss),
                _ci(i_sv),    _ci(i_hold), ip_val,
                _ci(i_ha),    _ci(i_hra),  _ci(i_bb),
                _ci(i_so),    _ci(i_r),    _ci(i_er),
                _cf(i_era),
            ))
            saved += 1
        except Exception:
            errors += 1
            continue

    conn.commit()
    cur.close()
    conn.close()
    print(f"[KBO season] 투수 {saved}명 업데이트, {errors}건 오류")
