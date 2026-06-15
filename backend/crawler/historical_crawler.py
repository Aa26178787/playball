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

_RESTART_EVERY = 70  # 단일 드라이버 장수명 크래시 방지 (800+ 네비게이션서 chromium 사망 — Connection refused)


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


def _iter_season_rows(driver, url, season, series='0'):
    """KBO 시즌기록 리스트 전 페이지 순회. (headers, [(cells, kbo_player_id), ...]) 반환.
    선수명 앵커 href의 playerId 추출. series='0'정규/4와일드카드/3준PO/5PO/7한국시리즈(ddlSeries)."""
    from selenium.webdriver.common.by import By
    from selenium.webdriver.support.ui import Select
    driver.get(url)
    time.sleep(3)
    sel = driver.find_element(By.CSS_SELECTOR, "select[id*='ddlSeason']")
    if sel.get_attribute('value') != str(season):
        Select(sel).select_by_value(str(season))
        time.sleep(3)
    if series and str(series) != '0':  # 포스트시즌: ddlSeries 선택 (season 선택 후 default 0으로 리셋되므로 뒤에)
        try:
            ssel = driver.find_element(By.CSS_SELECTOR, "select[id*='ddlSeries']")
            if ssel.get_attribute('value') != str(series):
                Select(ssel).select_by_value(str(series))
                time.sleep(3)
        except Exception:
            return [], []

    headers = []
    out = []
    seen = set()
    for page_num in range(1, 31):
        soup = BeautifulSoup(driver.page_source, 'html.parser')
        table = soup.find('table', class_='tData01')
        if not table:
            break
        if not headers:
            headers = [th.get_text(strip=True) for th in table.select('thead th')]
        ncol = len(headers)
        trs = table.select('tbody tr')
        if not trs:
            break
        new = 0
        for tr in trs:
            tds = tr.find_all('td')
            cells = [td.get_text(strip=True) for td in tds]
            # 페이저 스트레이 '다음' 클릭이 이종 테이블(열 수 상이)을 로드하는 케이스 방어
            # (1페이지 시즌엔 진짜 page2가 없어 //a[.="2"]가 엉뚱한 링크를 물던 버그)
            if len(cells) != ncol:
                continue
            pid = None
            a = tr.find('a', href=_PLAYERID_RE)
            if a:
                m = _PLAYERID_RE.search(a.get('href', ''))
                if m:
                    pid = int(m.group(1))
            key = (pid, cells[2] if len(cells) > 2 else None)  # (선수, 팀) — 다팀 split 보존
            if key in seen:
                continue
            seen.add(key)
            out.append((cells, pid))
            new += 1
        # 새 유효행 0 = 마지막 페이지/중복/이종 테이블 → 종료
        if new == 0:
            break
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


def crawl_hitter_season(season, series='0', series_label='정규'):
    """타자 시즌스탯 (Basic1 + Basic2) → historical_*. series=ddlSeries(정규/PS). 반환: 적재 행수."""
    driver = _get_driver()
    try:
        h1, rows1 = _iter_season_rows(driver, _HIT_B1, season, series)
        h2, rows2 = _iter_season_rows(driver, _HIT_B2, season, series)
    finally:
        driver.quit()
    if not rows1:
        print(f"[hist hitter {season}/{series_label}] 데이터 없음")
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
                kbo_player_id, season, team_name, series_type, player_type, games,
                pa, at_bats, runs, hits, doubles, triples, home_runs, rbis,
                sac_hits, sac_flies, walks, intentional_walks, hbp, strikeouts,
                gdp, stolen_bases, caught_stealing, avg, obp, slg, ops
            ) VALUES (%s,%s,%s,%s,'타자',%s, %s,%s,%s,%s,%s,%s,%s,%s, %s,%s,%s,%s,%s,%s, %s,%s,%s, %s,%s,%s,%s)
            ON CONFLICT (kbo_player_id, season, team_name, series_type) DO UPDATE SET
                games=EXCLUDED.games, pa=EXCLUDED.pa, at_bats=EXCLUDED.at_bats,
                runs=EXCLUDED.runs, hits=EXCLUDED.hits, doubles=EXCLUDED.doubles,
                triples=EXCLUDED.triples, home_runs=EXCLUDED.home_runs, rbis=EXCLUDED.rbis,
                sac_hits=EXCLUDED.sac_hits, sac_flies=EXCLUDED.sac_flies,
                walks=EXCLUDED.walks, intentional_walks=EXCLUDED.intentional_walks,
                hbp=EXCLUDED.hbp, strikeouts=EXCLUDED.strikeouts, gdp=EXCLUDED.gdp,
                stolen_bases=EXCLUDED.stolen_bases, caught_stealing=EXCLUDED.caught_stealing,
                avg=EXCLUDED.avg, obp=EXCLUDED.obp, slg=EXCLUDED.slg, ops=EXCLUDED.ops
        """, (
            pid, season, team, series_label, g,
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


def crawl_pitcher_season(season, series='0', series_label='정규'):
    """투수 시즌스탯 (Basic1 + Basic2) → historical_*. series=ddlSeries(정규/PS). 반환: 적재 행수."""
    driver = _get_driver()
    try:
        h1, rows1 = _iter_season_rows(driver, _PIT_B1, season, series)
        h2, rows2 = _iter_season_rows(driver, _PIT_B2, season, series)
    finally:
        driver.quit()
    if not rows1:
        print(f"[hist pitcher {season}/{series_label}] 데이터 없음")
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
                kbo_player_id, season, team_name, series_type, player_type, games,
                wins, losses, saves, holds, innings_pitched, hits_allowed,
                home_runs_allowed, walks_allowed, hbp_allowed, strikeouts_pitched,
                runs_allowed, earned_runs, era, whip, complete_games, shutouts, qs
            ) VALUES (%s,%s,%s,%s,'투수',%s, %s,%s,%s,%s,%s,%s, %s,%s,%s,%s, %s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT (kbo_player_id, season, team_name, series_type) DO UPDATE SET
                games=EXCLUDED.games, wins=EXCLUDED.wins, losses=EXCLUDED.losses,
                saves=EXCLUDED.saves, holds=EXCLUDED.holds,
                innings_pitched=EXCLUDED.innings_pitched, hits_allowed=EXCLUDED.hits_allowed,
                home_runs_allowed=EXCLUDED.home_runs_allowed, walks_allowed=EXCLUDED.walks_allowed,
                hbp_allowed=EXCLUDED.hbp_allowed, strikeouts_pitched=EXCLUDED.strikeouts_pitched,
                runs_allowed=EXCLUDED.runs_allowed, earned_runs=EXCLUDED.earned_runs,
                era=EXCLUDED.era, whip=EXCLUDED.whip, complete_games=EXCLUDED.complete_games,
                shutouts=EXCLUDED.shutouts, qs=EXCLUDED.qs
        """, (
            pid, season, team, series_label, g,
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


def crawl_season(season, series='0', series_label='정규'):
    h = crawl_hitter_season(season, series, series_label)
    p = crawl_pitcher_season(season, series, series_label)
    return h, p


# 포스트시즌 시리즈 (ddlSeries 코드)
_PS_SERIES = [('4', '와일드카드'), ('3', '준플레이오프'), ('5', '플레이오프'), ('7', '한국시리즈')]


def crawl_ps_season(season):
    """한 시즌 전 포스트시즌 시리즈 적재 (열리지 않은 시리즈는 데이터 없음으로 자동 스킵)."""
    tot = 0
    for code, label in _PS_SERIES:
        h, p = crawl_season(season, code, label)
        tot += h + p
        time.sleep(1)
    print(f"[hist PS {season}] 총 {tot}행")
    return tot


# ── 수상(awards) enrichment ── detail Award.aspx (서버 IP 도달 OK) ──
def _award_url(kbo_id, player_type):
    seg = 'Pitcher' if player_type == '투수' else 'Hitter'
    return f"https://www.koreabaseball.com/Record/Player/{seg}Detail/Award.aspx?playerId={kbo_id}"


def enrich_awards(limit=None, only_id=None):
    """historical_players 수상경력 detail Award.aspx 크롤 → historical_awards (table 연도|수상)."""
    conn = get_connection()
    if not conn:
        return 0
    cur = conn.cursor()
    if only_id:
        cur.execute("SELECT kbo_player_id, player_type FROM historical_players WHERE kbo_player_id=%s", (only_id,))
    else:
        # 이미 수상 크롤한 선수 스킵(awards_done 마커 대신 historical_awards 존재 여부로 판단하면
        # 무수상 선수가 매번 재크롤됨 → 간단히 전체 또는 limit)
        q = "SELECT kbo_player_id, player_type FROM historical_players ORDER BY kbo_player_id"
        if limit:
            q += f" LIMIT {int(limit)}"
        cur.execute(q)
    targets = cur.fetchall()
    if not targets:
        cur.close()
        conn.close()
        return 0

    driver = _get_driver()
    rows_in = 0
    players_with = 0
    try:
        for i, (kbo_id, ptype) in enumerate(targets):
            if i and i % _RESTART_EVERY == 0:
                try:
                    driver.quit()
                except Exception:
                    pass
                driver = _get_driver()
            src = None
            for attempt in (1, 2):
                try:
                    driver.get(_award_url(kbo_id, ptype))
                    time.sleep(1.5)
                    src = driver.page_source
                    break
                except Exception as e:
                    if attempt == 2:
                        print(f"[awards] {kbo_id} 오류: {e}")
                    else:
                        try:
                            driver.quit()
                        except Exception:
                            pass
                        driver = _get_driver()
            if not src:
                continue
            try:
                soup = BeautifulSoup(src, 'html.parser')
                table = None
                for t in soup.find_all('table'):
                    ths = [x.get_text(strip=True) for x in t.select('thead th')]
                    if '수상' in ths and '연도' in ths:
                        table = t
                        break
                if not table:
                    continue
                got = 0
                for tr in table.select('tbody tr'):
                    tds = [c.get_text(strip=True) for c in tr.find_all('td')]
                    if len(tds) < 2:
                        continue
                    yr = _safe_int(tds[0])
                    award = tds[1].strip()
                    if not award:
                        continue
                    cur.execute("""
                        INSERT INTO historical_awards (kbo_player_id, season, award)
                        VALUES (%s, %s, %s)
                        ON CONFLICT (kbo_player_id, season, award) DO NOTHING
                    """, (kbo_id, yr, award))
                    got += 1
                if got:
                    players_with += 1
                    rows_in += got
                    conn.commit()
            except Exception as e:
                print(f"[awards] {kbo_id} 오류: {e}")
                continue
    finally:
        driver.quit()
    cur.close()
    conn.close()
    print(f"[awards] {players_with}명 수상 {rows_in}건 적재")
    return rows_in


# ── franchise 링크 + debut/final + primary team (순수 SQL, 재실행 안전, 배치 후 실행) ──
def link_franchises():
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    # 1) 시즌행 team_name(MBC/OB/현대..) → team_franchises (시즌 범위로 era 구분)
    cur.execute("""
        UPDATE historical_season_stats s
        SET team_franchise_id = tf.id
        FROM team_franchises tf
        WHERE s.team_franchise_id IS NULL AND s.team_name IS NOT NULL
          AND s.season BETWEEN tf.start_year AND COALESCE(tf.end_year, 9999)
          AND tf.team_name LIKE '%%' || s.team_name || '%%'
    """)
    n1 = cur.rowcount
    # 2) 데뷔/마지막 시즌
    cur.execute("""
        UPDATE historical_players hp
        SET debut_year = a.mn, final_year = a.mx
        FROM (SELECT kbo_player_id, MIN(season) mn, MAX(season) mx
              FROM historical_season_stats GROUP BY kbo_player_id) a
        WHERE hp.kbo_player_id = a.kbo_player_id
    """)
    # 3) 대표팀 = 출전경기 최다 프랜차이즈의 현존 구단 (해체구단뿐이면 NULL 유지)
    cur.execute("""
        UPDATE historical_players hp
        SET primary_team_id = x.current_team_id
        FROM (
            SELECT kbo_player_id, current_team_id FROM (
                SELECT s.kbo_player_id, tf.current_team_id,
                       ROW_NUMBER() OVER (PARTITION BY s.kbo_player_id
                                          ORDER BY SUM(COALESCE(s.games,0)) DESC) rn
                FROM historical_season_stats s
                JOIN team_franchises tf ON tf.id = s.team_franchise_id
                WHERE tf.current_team_id IS NOT NULL
                GROUP BY s.kbo_player_id, tf.current_team_id
            ) z WHERE rn = 1
        ) x WHERE hp.kbo_player_id = x.kbo_player_id
    """)
    conn.commit()
    cur.close()
    conn.close()
    print(f"[link] franchise {n1}행 링크 + debut/final + primary team 갱신")


# ── 신상(bio) enrichment ── detail 페이지 div.player_info (서버 IP 도달 OK) ──
import datetime

_DATE_RE = re.compile(r'(\d{4})\D+(\d{1,2})\D+(\d{1,2})')


def _parse_bio(items):
    """div.player_info li 텍스트들 → bio dict. '포지션: 외야수(좌투좌타)' 형태 파싱."""
    kv = {}
    for it in items:
        if ':' in it:
            k, v = it.split(':', 1)
            kv[k.strip()] = v.strip()
    out = {}
    if kv.get('생년월일'):
        m = _DATE_RE.search(kv['생년월일'])
        if m:
            try:
                out['birth_date'] = datetime.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
            except ValueError:
                pass
    pos = kv.get('포지션', '')
    if pos:
        out['position'] = pos.split('(')[0].strip() or None
        mt = re.search(r'\(([^)]+)\)', pos)
        if mt:
            tt = mt.group(1)
            t = re.search(r'(좌|우|양)투', tt)
            b = re.search(r'(좌|우|양)타', tt)
            if t:
                out['throws'] = t.group(1)
            if b:
                out['bats'] = b.group(1)
    hw = kv.get('신장/체중', '')
    mh = re.search(r'(\d+)\s*cm', hw)
    mw = re.search(r'(\d+)\s*kg', hw)
    if mh:
        out['height'] = int(mh.group(1))
    if mw:
        out['weight'] = int(mw.group(1))
    if kv.get('경력'):
        out['career'] = kv['경력']
    return out


def _detail_url(kbo_id, player_type):
    seg = 'Pitcher' if player_type == '투수' else 'Hitter'
    return f"https://www.koreabaseball.com/Record/Player/{seg}Detail/Basic.aspx?playerId={kbo_id}"


def enrich_bio(limit=None, only_id=None):
    """historical_players 중 bio 미수집(birth_date NULL) 선수 detail 크롤 → bio UPDATE."""
    from selenium.webdriver.common.by import By
    conn = get_connection()
    if not conn:
        return 0
    cur = conn.cursor()
    if only_id:
        cur.execute("SELECT kbo_player_id, player_type FROM historical_players WHERE kbo_player_id=%s", (only_id,))
    else:
        q = "SELECT kbo_player_id, player_type FROM historical_players WHERE birth_date IS NULL ORDER BY kbo_player_id"
        if limit:
            q += f" LIMIT {int(limit)}"
        cur.execute(q)
    targets = cur.fetchall()
    if not targets:
        print("[bio] 대상 없음")
        cur.close()
        conn.close()
        return 0

    driver = _get_driver()
    done = 0
    try:
        for i, (kbo_id, ptype) in enumerate(targets):
            if i and i % _RESTART_EVERY == 0:  # 주기적 드라이버 재생성(크래시 방지)
                try:
                    driver.quit()
                except Exception:
                    pass
                driver = _get_driver()
            src = None
            for attempt in (1, 2):  # 크래시 시 respawn 후 1회 재시도
                try:
                    driver.get(_detail_url(kbo_id, ptype))
                    time.sleep(2)
                    src = driver.page_source
                    break
                except Exception as e:
                    if attempt == 2:
                        print(f"[bio] {kbo_id} 오류: {e}")
                    else:
                        try:
                            driver.quit()
                        except Exception:
                            pass
                        driver = _get_driver()
            if not src:
                continue
            try:
                soup = BeautifulSoup(src, 'html.parser')
                info = soup.find('div', class_='player_info')
                if not info:
                    continue
                items = [li.get_text(' ', strip=True) for li in info.find_all('li')]
                bio = _parse_bio(items)
                if not bio:
                    continue
                cur.execute("""
                    UPDATE historical_players SET
                        birth_date = COALESCE(%s, birth_date),
                        height     = COALESCE(%s, height),
                        weight     = COALESCE(%s, weight),
                        throws     = COALESCE(%s, throws),
                        bats       = COALESCE(%s, bats),
                        position   = COALESCE(%s, position),
                        career     = COALESCE(%s, career)
                    WHERE kbo_player_id=%s
                """, (bio.get('birth_date'), bio.get('height'), bio.get('weight'),
                      bio.get('throws'), bio.get('bats'), bio.get('position'),
                      bio.get('career'), kbo_id))
                conn.commit()
                done += 1
            except Exception as e:
                print(f"[bio] {kbo_id} 오류: {e}")
                continue
    finally:
        driver.quit()
    cur.close()
    conn.close()
    print(f"[bio] {done}명 갱신")
    return done


if __name__ == '__main__':
    args = sys.argv[1:]
    if args and args[0] == 'link':
        link_franchises()
        sys.exit(0)
    if args and args[0] == 'ps':
        # ps <season> [end_season]  — 포스트시즌 전 시리즈
        if len(args) == 2:
            ps_seasons = [int(args[1])]
        elif len(args) == 3:
            ps_seasons = list(range(int(args[1]), int(args[2]) + 1))
        else:
            print("usage: ... ps <season> [end_season]")
            sys.exit(1)
        for s in ps_seasons:
            print(f"=== PS season {s} ===")
            crawl_ps_season(s)
            time.sleep(1.5)
        sys.exit(0)
    if args and args[0] == 'awards':
        if len(args) >= 3 and args[1] == 'id':
            enrich_awards(only_id=int(args[2]))
        else:
            enrich_awards(limit=int(args[1]) if len(args) > 1 else None)
        sys.exit(0)
    if args and args[0] == 'bio':
        # bio [limit]  |  bio id <kbo_id>
        if len(args) >= 3 and args[1] == 'id':
            enrich_bio(only_id=int(args[2]))
        else:
            enrich_bio(limit=int(args[1]) if len(args) > 1 else None)
        sys.exit(0)
    if len(args) == 1:
        seasons = [int(args[0])]
    elif len(args) == 2:
        seasons = list(range(int(args[0]), int(args[1]) + 1))
    else:
        print("usage: python -m crawler.historical_crawler <season> [end] | bio [limit] | bio id <kbo_id>")
        sys.exit(1)
    for s in seasons:
        print(f"=== season {s} ===")
        crawl_season(s)
        time.sleep(1.5)
