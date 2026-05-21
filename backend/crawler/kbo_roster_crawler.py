"""
KBO 공식 사이트 등록말소 / 선수이동 크롤러
- Register.aspx : 당일 1군 등록/말소
- Trade.aspx    : 선수 이동 현황 (치료재활, 임의탈퇴, 군입대 등)
셀레니움 사용 (앵커 기반 팀 탭 전환)
"""
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from datetime import datetime, date
from database.connection import get_connection

# KBO 사이트 팀명 → DB short_name 매핑
_TEAM_NAME_MAP = {
    'KIA': 'HT', 'KIA타이거즈': 'HT',
    '삼성': 'SS', '삼성라이온즈': 'SS',
    '한화': 'HH', '한화이글스': 'HH',
    'NC': 'NC', 'NC다이노스': 'NC',
    '두산': 'OB', '두산베어스': 'OB',
    'LG': 'LG', 'LG트윈스': 'LG',
    'KT': 'KT', 'KT위즈': 'KT',
    'SSG': 'SK', 'SSG랜더스': 'SK',
    '롯데': 'LT', '롯데자이언츠': 'LT',
    '키움': 'WO', '키움히어로즈': 'WO',
}


def _get_driver():
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options
    opts = Options()
    opts.add_argument('--headless')
    opts.add_argument('--no-sandbox')
    opts.add_argument('--disable-dev-shm-usage')
    opts.add_argument('--disable-gpu')
    opts.add_argument('--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')
    return webdriver.Chrome(options=opts)


def _get_team_id_map() -> dict:
    """short_name → team_id"""
    conn = get_connection()
    if not conn:
        return {}
    cur = conn.cursor()
    cur.execute("SELECT id, short_name FROM teams")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {r[1]: r[0] for r in rows}


def _find_player_id(name: str, team_id: int | None) -> int | None:
    conn = get_connection()
    if not conn:
        return None
    cur = conn.cursor()
    # 이름에서 괄호 제거 (예: '오규석(투수)' → '오규석')
    clean = name.split('(')[0].strip()
    if team_id:
        cur.execute("SELECT id FROM players WHERE name = %s AND team_id = %s LIMIT 1",
                    (clean, team_id))
        row = cur.fetchone()
        if row:
            cur.close()
            conn.close()
            return row[0]
    cur.execute("SELECT id FROM players WHERE name = %s LIMIT 1", (clean,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    return row[0] if row else None


def _save_changes(records: list[dict], team_id_map: dict) -> int:
    if not records:
        return 0
    conn = get_connection()
    if not conn:
        return 0
    cur = conn.cursor()
    saved = 0
    for r in records:
        short = _TEAM_NAME_MAP.get(r.get('team_name', ''))
        team_id = team_id_map.get(short) if short else None
        player_raw = r.get('player_name', '')
        player_clean = player_raw.split('(')[0].strip()
        player_id = _find_player_id(player_clean, team_id)
        try:
            cur.execute("""
                INSERT INTO player_roster_changes
                    (player_name, team_id, player_id, change_type, reason, change_date)
                VALUES (%s, %s, %s, %s, %s, %s)
                ON CONFLICT (player_name, team_id, change_type, change_date) DO NOTHING
            """, (
                player_clean, team_id, player_id,
                r['change_type'], r.get('reason', ''), r['change_date']
            ))
            if cur.rowcount > 0:
                saved += 1
        except Exception as e:
            print(f"[RosterCrawl] 저장 실패 {player_clean}: {e}")
    conn.commit()
    cur.close()
    conn.close()
    return saved


def crawl_daily_register() -> list[dict]:
    """
    Register.aspx → '전체 등록 현황' 탭
    table[-2] = 당일 1군 등록
    table[-1] = 당일 1군 말소
    """
    from selenium.webdriver.common.by import By
    import time

    today = date.today()
    records = []
    driver = _get_driver()
    try:
        driver.get('https://www.koreabaseball.com/Player/Register.aspx')
        time.sleep(3)

        # '전체 등록 현황' 탭 클릭
        tabs = driver.find_elements(By.CSS_SELECTOR, 'ul.tab li a, .tab li a')
        for tab in tabs:
            if '전체' in tab.text:
                tab.click()
                time.sleep(2)
                break

        tables = driver.find_elements(By.TAG_NAME, 'table')
        if len(tables) < 2:
            print('[RosterCrawl] Register.aspx: 테이블 부족')
            return records

        # 마지막 두 테이블: 등록(-2), 말소(-1)
        for tbl, change_type in [(tables[-2], '1군등록'), (tables[-1], '등록말소')]:
            rows = tbl.find_elements(By.TAG_NAME, 'tr')
            for row in rows[1:]:  # 헤더 스킵
                cols = [td.text.strip() for td in row.find_elements(By.TAG_NAME, 'td')]
                if not cols or not cols[0]:
                    continue
                if '없습니다' in cols[0]:
                    continue
                # cols: [선수명, 포지션, 팀]
                player_name = cols[0] if len(cols) > 0 else ''
                position = cols[1] if len(cols) > 1 else ''
                team_name = cols[2] if len(cols) > 2 else ''
                if not player_name:
                    continue
                records.append({
                    'player_name': player_name,
                    'team_name': team_name,
                    'change_type': change_type,
                    'reason': position,
                    'change_date': today,
                })

        print(f'[RosterCrawl] Register.aspx: {len(records)}건 파싱')
    except Exception as e:
        print(f'[RosterCrawl] Register.aspx 오류: {e}')
    finally:
        driver.quit()

    return records


def crawl_trade(days: int = 7) -> list[dict]:
    """
    Trade.aspx → 선수 이동 현황
    columns: [날짜, 항목, 팀, 선수, 비고]
    """
    from selenium.webdriver.common.by import By
    from datetime import timedelta
    import time

    records = []
    cutoff = date.today() - timedelta(days=days)
    driver = _get_driver()
    try:
        driver.get('https://www.koreabaseball.com/Player/Trade.aspx')
        time.sleep(3)

        tables = driver.find_elements(By.TAG_NAME, 'table')
        if not tables:
            print('[RosterCrawl] Trade.aspx: 테이블 없음')
            return records

        rows = tables[0].find_elements(By.TAG_NAME, 'tr')
        for row in rows[1:]:
            cols = [td.text.strip() for td in row.find_elements(By.TAG_NAME, 'td')]
            if len(cols) < 4:
                continue
            date_str, item, team_name, player_raw = cols[0], cols[1], cols[2], cols[3]
            reason = cols[4] if len(cols) > 4 else ''
            try:
                row_date = datetime.strptime(date_str, '%Y-%m-%d').date()
            except ValueError:
                continue
            if row_date < cutoff:
                continue

            # '항목' → change_type 정규화
            ct = _normalize_trade_type(item)
            player_name = player_raw.split('(')[0].strip()
            if not player_name:
                continue

            records.append({
                'player_name': player_name,
                'team_name': team_name.strip(),
                'change_type': ct,
                'reason': reason or item,
                'change_date': row_date,
            })

        print(f'[RosterCrawl] Trade.aspx: {len(records)}건 파싱')
    except Exception as e:
        print(f'[RosterCrawl] Trade.aspx 오류: {e}')
    finally:
        driver.quit()

    return records


def _normalize_trade_type(item: str) -> str:
    item = item.strip()
    if '치료' in item or '재활' in item:
        return '부상자명단'
    if '임의탈퇴' in item:
        return '임의탈퇴'
    if '자유계약' in item or 'FA' in item:
        return '자유계약'
    if '군' in item or '입대' in item:
        return '군입대'
    if '트레이드' in item:
        return '트레이드'
    if '웨이버' in item:
        return '웨이버'
    if '방출' in item:
        return '방출'
    if '복귀' in item or '해제' in item:
        return '복귀'
    if '육성' in item:
        return '육성선수'
    if '1군등록' in item or ('등록' in item and '말소' not in item):
        return '1군등록'
    if '말소' in item:
        return '등록말소'
    return item


def run_today():
    """당일 등록말소 크롤링 (Register.aspx)"""
    team_id_map = _get_team_id_map()
    records = crawl_daily_register()
    saved = _save_changes(records, team_id_map)
    print(f'[RosterCrawl] 오늘 등록말소 {saved}건 저장')
    return saved


def run_trade(days: int = 30):
    """선수 이동 현황 크롤링 (Trade.aspx)"""
    team_id_map = _get_team_id_map()
    records = crawl_trade(days=days)
    saved = _save_changes(records, team_id_map)
    print(f'[RosterCrawl] 선수이동 {saved}건 저장')
    return saved


if __name__ == '__main__':
    print('=== 등록말소 크롤링 ===')
    run_today()
    print('=== 선수이동 크롤링 (30일) ===')
    run_trade(days=30)
