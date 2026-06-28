"""역대 C2 트랙2: 2군(퓨처스) 경기단위 box-only 백필.
- 일정 = Futures/Schedule/GameList.aspx (selenium 월별 ddlYear/ddlMonth nav) → futures_games
- 박스 = Futures/Schedule/BoxScore.aspx (requests + box-score-wrap 슬라이스 파싱) → futures_game_box (JSONB)
⚠️ 2군 pitch-by-pitch 소스 전무 → box-score 천장(라인스코어+선수 box). box 선수행 playerId 앵커 없음 → 이름만.
⚠️ BoxScore HTML 상단 markup이 html.parser를 깨뜨림(table 0개) → box-score-wrap div 슬라이스 후 fragment 파싱 필수.
사용: python3 -m crawler.backfill_futures_games <season> [end_season]   (기본=일정+박스)
      python3 -m crawler.backfill_futures_games box <season>            (박스만 재시도)
ARM snap chromium = driver_util.arm_or_wdm_chrome 경유(직접 webdriver.Chrome 금지).
"""
import sys
import os
import re
import time
import json
import urllib.request

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from bs4 import BeautifulSoup
from database.connection import get_connection

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
_GAMELIST = "https://www.koreabaseball.com/Futures/Schedule/GameList.aspx"
_BOX = "https://www.koreabaseball.com/Futures/Schedule/BoxScore.aspx"
_BOXHREF_RE = re.compile(r'seriesId=(\d+)&seasonId=(\d+)&gameId=([0-9A-Z]+)')
_SCORE_RE = re.compile(r'(\S.*?)\s+(\d+)\s+vs\s+(\d+)\s+(\S.*)')


def _get_driver():
    from selenium.webdriver.chrome.options import Options
    from crawler.driver_util import arm_or_wdm_chrome
    opts = Options()
    for a in ('--headless', '--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu'):
        opts.add_argument(a)
    opts.add_argument(f'--user-agent={UA}')
    return arm_or_wdm_chrome(opts)


def _fetch(url, referer=_GAMELIST):
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Referer': referer})
    return urllib.request.urlopen(req, timeout=20).read().decode('utf-8', 'ignore')


def _i(v):
    try:
        s = str(v).replace(',', '').strip()
        return int(s) if s not in ('', '-') else None
    except (ValueError, TypeError):
        return None


def _f(v):
    try:
        s = str(v).strip()
        return float(s) if s not in ('', '-') else None
    except (ValueError, TypeError):
        return None


def _rows(tbl):
    return [[c.get_text(strip=True) for c in tr.find_all(['th', 'td'])] for tr in tbl.find_all('tr')]


def parse_box(game_id, series_id, season):
    """BoxScore 1경기 파싱 → dict(scoreboard/away_batters/home_batters/pitchers/summary). 실패=None."""
    url = f"{_BOX}?leagueId=2&seriesId={series_id}&seasonId={season}&gameId={game_id}"
    try:
        h = _fetch(url)
    except Exception:
        return None
    idx = h.find('<div class="box-score-wrap')
    if idx < 0:
        return None
    soup = BeautifulSoup(h[idx:], 'html.parser')
    tabs = soup.find_all('table')
    if not tabs:
        return None
    by_id = {}
    pit_tabs = []
    sum_tab = None
    for t in tabs:
        tid = t.get('id') or ''
        if tid.startswith('tblScordboard') or tid.startswith('tblAwayHitter') or tid.startswith('tblHomeHitter'):
            by_id[tid] = t
        elif tid == 'xtable3':
            pit_tabs.append(t)
        elif tid == '' and sum_tab is None and t.find(string=lambda x: x and '결승타' in x):
            sum_tab = t

    # --- 스코어보드 (1=팀, 2=이닝, 3=RHEB) ---
    scoreboard = None
    if 'tblScordboard1' in by_id and 'tblScordboard3' in by_id:
        teams = _rows(by_id['tblScordboard1'])      # [[TEAM],[away],[home]]
        innr = _rows(by_id.get('tblScordboard2')) if by_id.get('tblScordboard2') else []
        rheb = _rows(by_id['tblScordboard3'])        # [[R,H,E,B],[away..],[home..]]

        def side(i):
            return {
                'team': teams[i][0] if len(teams) > i and teams[i] else None,
                'innings': [_i(x) for x in innr[i]] if len(innr) > i else [],
                'r': _i(rheb[i][0]) if len(rheb) > i and len(rheb[i]) > 0 else None,
                'h': _i(rheb[i][1]) if len(rheb) > i and len(rheb[i]) > 1 else None,
                'e': _i(rheb[i][2]) if len(rheb) > i and len(rheb[i]) > 2 else None,
                'b': _i(rheb[i][3]) if len(rheb) > i and len(rheb[i]) > 3 else None,
            }
        scoreboard = {'away': side(1), 'home': side(2)}

    # --- 타자 box (1=타순/위치/선수명, 3=타수/안타/타점/득점/타율) ---
    def batters(prefix):
        t1 = by_id.get(prefix + '1')
        t3 = by_id.get(prefix + '3')
        if not t1 or not t3:
            return []
        r1 = _rows(t1)[1:]   # 헤더 제외
        r3 = _rows(t3)[1:]
        out = []
        for a, b in zip(r1, r3):
            nm = a[2] if len(a) > 2 else None
            if not nm or nm in ('합계', 'TOTAL', '계'):
                continue
            out.append({
                'order': _i(a[0]) if len(a) > 0 else None,
                'pos': a[1] if len(a) > 1 else None,
                'name': nm,
                'ab': _i(b[0]) if len(b) > 0 else None,
                'h': _i(b[1]) if len(b) > 1 else None,
                'rbi': _i(b[2]) if len(b) > 2 else None,
                'r': _i(b[3]) if len(b) > 3 else None,
                'avg': _f(b[4]) if len(b) > 4 else None,
            })
        return out

    # --- 투수 box (xtable3 ×2: away, home) ---
    # 헤더: 선수명/등판/결과/승/패/세/이닝/타자/투구수/타수/피안타/피홈런/4사구/삼진/실점/자책/평균자책점
    def pitchers(tbl, sidelabel):
        out = []
        rs = _rows(tbl)
        if not rs:
            return out
        hdr = rs[0]
        hi = {name: i for i, name in enumerate(hdr)}

        def col(row, *names):
            for nm in names:
                if nm in hi and hi[nm] < len(row):
                    return row[hi[nm]]
            return None
        for row in rs[1:]:
            nm = row[0] if row else None
            if not nm or nm in ('합계', 'TOTAL', '계'):
                continue
            out.append({
                'side': sidelabel,
                'name': nm,
                'result': col(row, '결과'),
                'w': _i(col(row, '승')), 'l': _i(col(row, '패')), 'sv': _i(col(row, '세')),
                'ip': col(row, '이닝'),
                'batters': _i(col(row, '타자')), 'pitches': _i(col(row, '투구수')),
                'ab': _i(col(row, '타수')), 'h': _i(col(row, '피안타')), 'hr': _i(col(row, '피홈런')),
                'bb_hbp': _i(col(row, '4사구')), 'so': _i(col(row, '삼진')),
                'r': _i(col(row, '실점')), 'er': _i(col(row, '자책')),
                'era': _f(col(row, '평균자책점')),
            })
        return out

    pit = []
    for n, t in enumerate(pit_tabs):
        pit += pitchers(t, 'away' if n == 0 else 'home')

    # --- 게임 요약 (결승타/홈런/2루타/실책/..) ---
    summary = {}
    if sum_tab:
        for row in _rows(sum_tab):
            if len(row) >= 2 and row[0]:
                summary[row[0]] = row[1]

    return {
        'scoreboard': scoreboard,
        'away_batters': batters('tblAwayHitter'),
        'home_batters': batters('tblHomeHitter'),
        'pitchers': pit,
        'summary': summary,
    }


def crawl_schedule(season, driver):
    """GameList 월별 nav → futures_games upsert. 반환 게임수."""
    from selenium.webdriver.common.by import By
    from selenium.webdriver.support.ui import Select
    conn = get_connection()
    if not conn:
        return 0
    cur = conn.cursor()
    n = 0
    try:
        driver.get(_GAMELIST)
        time.sleep(2.5)
        Select(driver.find_element(By.CSS_SELECTOR, "select[id*='ddlYear']")).select_by_value(str(season))
        time.sleep(2)
        months = [o.get_attribute('value') for o in
                  Select(driver.find_element(By.CSS_SELECTOR, "select[id*='ddlMonth']")).options]
        for mo in months:
            try:
                Select(driver.find_element(By.CSS_SELECTOR, "select[id*='ddlMonth']")).select_by_value(mo)
                time.sleep(2)
            except Exception:
                continue
            soup = BeautifulSoup(driver.page_source, 'html.parser')
            for tr in soup.select('table tr'):
                a = tr.find('a', href=lambda x: x and 'BoxScore' in x)
                if not a:
                    continue
                m = _BOXHREF_RE.search(a['href'])
                if not m:
                    continue
                series_id, seas, gid = int(m.group(1)), int(m.group(2)), m.group(3)
                if len(gid) < 12:
                    continue
                date = f"{gid[0:4]}-{gid[4:6]}-{gid[6:8]}"
                away_code, home_code = gid[8:10], gid[10:12]
                cells = [c.get_text(' ', strip=True) for c in tr.find_all('td')]
                away_score = home_score = None
                for c in cells:
                    sm = _SCORE_RE.search(c)
                    if sm:
                        away_score, home_score = int(sm.group(2)), int(sm.group(3))
                        break
                stadium = cells[-2] if len(cells) >= 2 and cells[-2] else None
                bigo = cells[-1] if cells and cells[-1] else None
                if bigo and '취소' in bigo:
                    status = '취소'
                elif away_score is not None:
                    status = '종료'
                else:
                    status = '예정'
                cur.execute("""
                    INSERT INTO futures_games (game_id, season, game_date, away_code, home_code,
                        away_score, home_score, stadium, status, series_id)
                    VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                    ON CONFLICT (game_id) DO UPDATE SET away_score=EXCLUDED.away_score,
                        home_score=EXCLUDED.home_score, stadium=EXCLUDED.stadium,
                        status=EXCLUDED.status, series_id=EXCLUDED.series_id, season=EXCLUDED.season,
                        game_date=EXCLUDED.game_date
                """, (gid, seas, date, away_code, home_code, away_score, home_score,
                      stadium, status, series_id))
                n += 1
            conn.commit()
        print(f"[futures schedule {season}] {n} games upserted")
    finally:
        cur.close()
        conn.close()
    return n


def backfill_box(season, only_missing=True):
    """그 시즌 종료경기 박스 fetch+파싱 → futures_game_box. requests 기반(selenium 불요)."""
    conn = get_connection()
    if not conn:
        return 0
    cur = conn.cursor()
    if only_missing:
        cur.execute("""
            SELECT g.game_id, g.series_id, g.season FROM futures_games g
            LEFT JOIN futures_game_box b ON b.game_id = g.game_id
            WHERE g.season=%s AND g.status='종료' AND b.game_id IS NULL
            ORDER BY g.game_date
        """, (season,))
    else:
        cur.execute("SELECT game_id, series_id, season FROM futures_games WHERE season=%s AND status='종료' ORDER BY game_date", (season,))
    games = cur.fetchall()
    saved = 0
    try:
        for gid, sid, seas in games:
            box = parse_box(gid, sid, seas)
            if not box or not box.get('scoreboard'):
                continue
            cur.execute("""
                INSERT INTO futures_game_box (game_id, scoreboard, away_batters, home_batters, pitchers, summary)
                VALUES (%s,%s,%s,%s,%s,%s)
                ON CONFLICT (game_id) DO UPDATE SET scoreboard=EXCLUDED.scoreboard,
                    away_batters=EXCLUDED.away_batters, home_batters=EXCLUDED.home_batters,
                    pitchers=EXCLUDED.pitchers, summary=EXCLUDED.summary, crawled_at=now()
            """, (gid, json.dumps(box['scoreboard']), json.dumps(box['away_batters']),
                  json.dumps(box['home_batters']), json.dumps(box['pitchers']), json.dumps(box['summary'])))
            saved += 1
            if saved % 20 == 0:
                conn.commit()
                print(f"  [box {season}] {saved}/{len(games)}")
            time.sleep(0.4)
        conn.commit()
    finally:
        cur.close()
        conn.close()
    print(f"[futures box {season}] {saved}/{len(games)} boxes")
    return saved


def backfill_season(season):
    drv = _get_driver()
    try:
        crawl_schedule(season, drv)
    finally:
        try:
            drv.quit()
        except Exception:
            pass
    backfill_box(season)


if __name__ == '__main__':
    args = sys.argv[1:]
    if args and args[0] == 'box':
        backfill_box(int(args[1]))
        sys.exit(0)
    if len(args) == 1:
        seasons = [int(args[0])]
    elif len(args) == 2:
        seasons = list(range(int(args[0]), int(args[1]) + 1))
    else:
        print("usage: backfill_futures_games <season> [end_season] | box <season>")
        sys.exit(1)
    for s in seasons:
        print(f"=== futures games season {s} ===")
        backfill_season(s)
        time.sleep(1)
