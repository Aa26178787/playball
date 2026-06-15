"""
역대(1982~) 선수 시즌스탯 크롤러 — 트랙A코어.
소스: KBO 공식 Record/Player/{Hitter,Pitcher}Basic/Basic1·Basic2.aspx (selenium, ddlSeason=1982~).
키: kbo_player_id (선수명 앵커 href의 playerId). 별도 역대테이블(historical_players/historical_season_stats)에 적재.
- Basic1 = 핵심, Basic2 = 확장(BB/SO/OBP/SLG/OPS / 투수 CG/SHO/QS). playerId+season+team_name으로 머지.
- team_franchise_id 링크·bio·세이버 recompute·PS/수상 = 후속 enrichment (여기선 raw 시즌스탯만).
ARM snap chromium = driver_util.arm_or_wdm_chrome 경유 필수 (직접 webdriver.Chrome 금지).
"""
import sys
import os
import re
import time

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from bs4 import BeautifulSoup
from database.connection import get_connection

_HIT_B1 = "https://www.koreabaseball.com/Record/Player/HitterBasic/Basic1.aspx"
_HIT_B2 = "https://www.koreabaseball.com/Record/Player/HitterBasic/Basic2.aspx"
_PIT_B1 = "https://www.koreabaseball.com/Record/Player/PitcherBasic/Basic1.aspx"
_PIT_B2 = "https://www.koreabaseball.com/Record/Player/PitcherBasic/Basic2.aspx"


def _get_driver():
    from selenium.webdriver.chrome.options import Options
    from crawler.driver_util import arm_or_wdm_chrome
    opts = Options()
    opts.add_argument('--headless')
    opts.add_argument('--no-sandbox')
    opts.add_argument('--disable-dev-shm-usage')
    opts.add_argument('--disable-gpu')
    opts.add_argument('--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')
    return arm_or_wdm_chrome(opts)


def _safe_int(v):
    if v is None:
        return None
    s = str(v).replace(',', '').strip()
    if s in ('', '-'):
        return None
    try:
        return int(float(s))
    except ValueError:
        return None


def _safe_float(v):
    if v is None:
        return None
    s = str(v).replace(',', '').strip()
    if s in ('', '-'):
        return None
    try:
        return float(s)
    except ValueError:
        return None


def _parse_ip(s):
    """'123 1/3' → 123.1, '7 2/3' → 7.2 (6.1=6⅓ 관례)."""
    if not s:
        return None
    s = str(s).strip()
    try:
        if ' ' in s:
            whole, frac = s.split(' ', 1)
            base = float(whole)
            if frac == '1/3':
                return base + 0.1
            if frac == '2/3':
                return base + 0.2
            return base
        if s in ('-', ''):
            return None
        return float(s)
    except ValueError:
        return None


_PLAYERID_RE = re.compile(r'playerId=(\d+)')


def _iter_season_rows(driver, url, season):
    """KBO 시즌기록 리스트 전 페이지 순회. (headers, [(cells, kbo_player_id), ...]) 반환.
    선수명 앵커 href의 playerId 추출 (text-only 파싱과 달리 id 보존)."""
    from selenium.webdriver.common.by import By
    from selenium.webdriver.support.ui import Select
    driver.get(url)
    time.sleep(3)
    sel = driver.find_element(By.CSS_SELECTOR, "select[id*='ddlSeason']")
    if sel.get_attribute('value') != str(season):
        Select(sel).select_by_value(str(season))
        time.sleep(3)

    headers = []
    out = []
    prev_first = None
    for page_num in range(1, 31):
        soup = BeautifulSoup(driver.page_source, 'html.parser')
        table = soup.find('table', class_='tData01')
        if not table:
            break
        if not headers:
            headers = [th.get_text(strip=True) for th in table.select('thead th')]
        trs = table.select('tbody tr')
        if not trs:
            break
        first_text = trs[0].get_text(strip=True)
        if first_text == prev_first:
            break
        prev_first = first_text
        for tr in trs:
            tds = tr.find_all('td')
            cells = [td.get_text(strip=True) for td in tds]
            if not cells:
                continue
            pid = None
            a = tr.find('a', href=_PLAYERID_RE)
            if a:
                m = _PLAYERID_RE.search(a.get('href', ''))
                if m:
                    pid = int(m.group(1))
            out.append((cells, pid))
        # 다음 페이지 — 숫자 링크 우선 (5단위 블록 점프 회피)
        try:
            driver.find_element('xpath', f'//a[normalize-space(.)="{page_num + 1}"]').click()
            time.sleep(2)
        except Exception:
            try:
                driver.find_element('xpath', '//a[normalize-space(.)="다음"]').click()
                time.sleep(2)
            except Exception:
                break
    return headers, out


def _hidx(headers):
    def h(*names):
        for n in names:
            try:
                return headers.index(n)
            except ValueError:
                continue
        return None
    return h


def _upsert_player(cur, kbo_id, name, ptype):
    cur.execute("""
        INSERT INTO historical_players (kbo_player_id, name, player_type)
        VALUES (%s, %s, %s)
        ON CONFLICT (kbo_player_id) DO UPDATE SET
            name = EXCLUDED.name,
            player_type = COALESCE(historical_players.player_type, EXCLUDED.player_type)
    """, (kbo_id, name, ptype))


def crawl_hitter_season(season):
    """타자 시즌스탯 (Basic1 + Basic2) → historical_*. 반환: 적재 행수."""
    driver = _get_driver()
    try:
        h1, rows1 = _iter_season_rows(driver, _HIT_B1, season)
        h2, rows2 = _iter_season_rows(driver, _HIT_B2, season)
    finally:
        driver.quit()
    if not rows1:
        print(f"[hist hitter {season}] Basic1 데이터 없음")
        return 0

    a = _hidx(h1)
    i_name, i_team = (a('선수명') or 1), (a('팀명') or 2)
    idx1 = dict(avg=a('AVG'), g=a('G'), pa=a('PA'), ab=a('AB'), r=a('R'), h=a('H'),
                b2=a('2B'), b3=a('3B'), hr=a('HR'), rbi=a('RBI'),
                sac=a('SAC'), sf=a('SF'))
    # Basic2 인덱스 + playerId→cells 매핑
    b = _hidx(h2)
    idx2 = dict(bb=b('BB'), ibb=b('IBB'), hbp=b('HBP'), so=b('SO', 'K'),
                gdp=b('GDP'), slg=b('SLG'), obp=b('OBP'), ops=b('OPS'),
                sb=b('SB'), cs=b('CS'))
    b2_by_pid = {pid: cells for cells, pid in rows2 if pid}

    conn = get_connection()
    if not conn:
        return 0
    cur = conn.cursor()
    saved = 0
    for cells, pid in rows1:
        if not pid:
            continue
        def c1(k):
            i = idx1[k]
            return cells[i] if i is not None and i < len(cells) else None
        g = _safe_int(c1('g'))
        if not g or g < 1:
            continue
        name = cells[i_name] if i_name < len(cells) else None
        team = cells[i_team] if i_team < len(cells) else None
        c2 = b2_by_pid.get(pid, [])
        def cb(k):
            i = idx2[k]
            return c2[i] if i is not None and i < len(c2) else None
        _upsert_player(cur, pid, name, '타자')
        cur.execute("""
            INSERT INTO historical_season_stats (
                kbo_player_id, season, team_name, player_type, games,
                pa, at_bats, runs, hits, doubles, triples, home_runs, rbis,
                sac_hits, sac_flies, walks, intentional_walks, hbp, strikeouts,
                gdp, stolen_bases, caught_stealing, avg, obp, slg, ops
            ) VALUES (%s,%s,%s,'타자',%s, %s,%s,%s,%s,%s,%s,%s,%s, %s,%s,%s,%s,%s,%s, %s,%s,%s, %s,%s,%s,%s)
            ON CONFLICT (kbo_player_id, season, team_name) DO UPDATE SET
                games=EXCLUDED.games, pa=EXCLUDED.pa, at_bats=EXCLUDED.at_bats,
                runs=EXCLUDED.runs, hits=EXCLUDED.hits, doubles=EXCLUDED.doubles,
                triples=EXCLUDED.triples, home_runs=EXCLUDED.home_runs, rbis=EXCLUDED.rbis,
                sac_hits=EXCLUDED.sac_hits, sac_flies=EXCLUDED.sac_flies,
                walks=EXCLUDED.walks, intentional_walks=EXCLUDED.intentional_walks,
                hbp=EXCLUDED.hbp, strikeouts=EXCLUDED.strikeouts, gdp=EXCLUDED.gdp,
                stolen_bases=EXCLUDED.stolen_bases, caught_stealing=EXCLUDED.caught_stealing,
                avg=EXCLUDED.avg, obp=EXCLUDED.obp, slg=EXCLUDED.slg, ops=EXCLUDED.ops
        """, (
            pid, season, team, g,
            _safe_int(c1('pa')), _safe_int(c1('ab')), _safe_int(c1('r')), _safe_int(c1('h')),
            _safe_int(c1('b2')), _safe_int(c1('b3')), _safe_int(c1('hr')), _safe_int(c1('rbi')),
            _safe_int(c1('sac')), _safe_int(c1('sf')),
            _safe_int(cb('bb')), _safe_int(cb('ibb')), _safe_int(cb('hbp')), _safe_int(cb('so')),
            _safe_int(cb('gdp')), _safe_int(cb('sb')), _safe_int(cb('cs')),
            _safe_float(c1('avg')), _safe_float(cb('obp')), _safe_float(cb('slg')), _safe_float(cb('ops')),
        ))
        saved += 1
    conn.commit()
    cur.close()
    conn.close()
    print(f"[hist hitter {season}] {saved}행 적재")
    return saved


def crawl_pitcher_season(season):
    """투수 시즌스탯 (Basic1 + Basic2) → historical_*. 반환: 적재 행수."""
    driver = _get_driver()
    try:
        h1, rows1 = _iter_season_rows(driver, _PIT_B1, season)
        h2, rows2 = _iter_season_rows(driver, _PIT_B2, season)
    finally:
        driver.quit()
    if not rows1:
        print(f"[hist pitcher {season}] Basic1 데이터 없음")
        return 0

    a = _hidx(h1)
    i_name, i_team = (a('선수명') or 1), (a('팀명') or 2)
    idx1 = dict(g=a('G'), w=a('W'), l=a('L'), sv=a('SV'), hld=a('HLD'),
                ip=a('IP'), h=a('H', 'HA'), hr=a('HR', 'HRA'), bb=a('BB'),
                hbp=a('HBP'), so=a('SO', 'K'), r=a('R'), er=a('ER'),
                era=a('ERA'), whip=a('WHIP'))
    b = _hidx(h2)
    idx2 = dict(cg=b('CG'), sho=b('SHO'), qs=b('QS'))
    b2_by_pid = {pid: cells for cells, pid in rows2 if pid}

    conn = get_connection()
    if not conn:
        return 0
    cur = conn.cursor()
    saved = 0
    for cells, pid in rows1:
        if not pid:
            continue
        def c1(k):
            i = idx1[k]
            return cells[i] if i is not None and i < len(cells) else None
        g = _safe_int(c1('g'))
        if not g or g < 1:
            continue
        name = cells[i_name] if i_name < len(cells) else None
        team = cells[i_team] if i_team < len(cells) else None
        c2 = b2_by_pid.get(pid, [])
        def cb(k):
            i = idx2[k]
            return c2[i] if i is not None and i < len(c2) else None
        sv = _safe_int(c1('sv'))
        hld = _safe_int(c1('hld'))
        if sv is not None and sv > g:
            sv = None
        if hld is not None and hld > g:
            hld = None
        _upsert_player(cur, pid, name, '투수')
        cur.execute("""
            INSERT INTO historical_season_stats (
                kbo_player_id, season, team_name, player_type, games,
                wins, losses, saves, holds, innings_pitched, hits_allowed,
                home_runs_allowed, walks_allowed, hbp_allowed, strikeouts_pitched,
                runs_allowed, earned_runs, era, whip, complete_games, shutouts, qs
            ) VALUES (%s,%s,%s,'투수',%s, %s,%s,%s,%s,%s,%s, %s,%s,%s,%s, %s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT (kbo_player_id, season, team_name) DO UPDATE SET
                games=EXCLUDED.games, wins=EXCLUDED.wins, losses=EXCLUDED.losses,
                saves=EXCLUDED.saves, holds=EXCLUDED.holds,
                innings_pitched=EXCLUDED.innings_pitched, hits_allowed=EXCLUDED.hits_allowed,
                home_runs_allowed=EXCLUDED.home_runs_allowed, walks_allowed=EXCLUDED.walks_allowed,
                hbp_allowed=EXCLUDED.hbp_allowed, strikeouts_pitched=EXCLUDED.strikeouts_pitched,
                runs_allowed=EXCLUDED.runs_allowed, earned_runs=EXCLUDED.earned_runs,
                era=EXCLUDED.era, whip=EXCLUDED.whip, complete_games=EXCLUDED.complete_games,
                shutouts=EXCLUDED.shutouts, qs=EXCLUDED.qs
        """, (
            pid, season, team, g,
            _safe_int(c1('w')), _safe_int(c1('l')), sv, hld,
            _parse_ip(c1('ip')), _safe_int(c1('h')),
            _safe_int(c1('hr')), _safe_int(c1('bb')), _safe_int(c1('hbp')), _safe_int(c1('so')),
            _safe_int(c1('r')), _safe_int(c1('er')), _safe_float(c1('era')), _safe_float(c1('whip')),
            _safe_int(cb('cg')), _safe_int(cb('sho')), _safe_int(cb('qs')),
        ))
        saved += 1
    conn.commit()
    cur.close()
    conn.close()
    print(f"[hist pitcher {season}] {saved}행 적재")
    return saved


def crawl_season(season):
    h = crawl_hitter_season(season)
    p = crawl_pitcher_season(season)
    return h, p


if __name__ == '__main__':
    args = sys.argv[1:]
    if len(args) == 1:
        seasons = [int(args[0])]
    elif len(args) == 2:
        seasons = list(range(int(args[0]), int(args[1]) + 1))
    else:
        print("usage: python -m crawler.historical_crawler <season> [end_season]")
        sys.exit(1)
    for s in seasons:
        print(f"=== season {s} ===")
        crawl_season(s)
        time.sleep(1.5)
