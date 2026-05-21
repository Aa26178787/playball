"""
KBO 공식 사이트 등록말소 크롤러
https://www.koreabaseball.com/Player/PlayerRegister.aspx
"""
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import requests
from bs4 import BeautifulSoup
from datetime import datetime, timedelta
from database.connection import get_connection

# KBO short_name → teams.short_name 매핑
_KBO_TEAM_MAP = {
    'LG': 'LG', 'KT': 'KT', 'SSG': 'SK', 'NC': 'NC',
    'DL': 'OB',  # 두산
    'KIA': 'HT', 'LT': 'LT', 'SS': 'SS', 'HH': 'HH', 'KW': 'WO',
    # 사이트에 표시되는 팀명 변형 대응
    '두산': 'OB', 'KIA': 'HT', '롯데': 'LT', '삼성': 'SS',
    '한화': 'HH', '키움': 'WO', 'SSG': 'SK', 'NC': 'NC',
    'LG': 'LG', 'KT': 'KT',
}

_HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Referer': 'https://www.koreabaseball.com/',
}

_SESSION = requests.Session()
_SESSION.headers.update(_HEADERS)


def _get_team_ids() -> dict:
    """short_name → id 맵 반환"""
    conn = get_connection()
    if not conn:
        return {}
    cur = conn.cursor()
    cur.execute("SELECT id, short_name, name FROM teams")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    result = {}
    for tid, short, name in rows:
        result[short] = tid
        result[name] = tid
    return result


def _find_player_id(name: str, team_id: int | None) -> int | None:
    """이름 + 팀 기반 player_id 조회"""
    conn = get_connection()
    if not conn:
        return None
    cur = conn.cursor()
    if team_id:
        cur.execute("SELECT id FROM players WHERE name = %s AND team_id = %s LIMIT 1",
                    (name, team_id))
        row = cur.fetchone()
        if row:
            cur.close()
            conn.close()
            return row[0]
    cur.execute("SELECT id FROM players WHERE name = %s LIMIT 1", (name,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    return row[0] if row else None


def _get_viewstate(html: str) -> dict:
    """ASP.NET ViewState 파라미터 추출"""
    soup = BeautifulSoup(html, 'html.parser')
    fields = {}
    for name in ['__VIEWSTATE', '__VIEWSTATEGENERATOR', '__EVENTVALIDATION']:
        tag = soup.find('input', {'name': name})
        if tag:
            fields[name] = tag.get('value', '')
    return fields


def crawl_roster_changes(date: datetime | None = None) -> list[dict]:
    """
    KBO 등록말소 페이지 크롤링.
    date: 조회할 날짜 (None이면 오늘)
    반환: [{'player_name', 'team_name', 'change_type', 'reason', 'change_date'}, ...]
    """
    if date is None:
        date = datetime.now()

    date_str = date.strftime('%Y-%m-%d')
    url = 'https://www.koreabaseball.com/Player/PlayerRegister.aspx'

    try:
        # 첫 GET으로 ViewState 확보
        resp = _SESSION.get(url, timeout=10)
        resp.raise_for_status()
        vs = _get_viewstate(resp.text)

        data = {
            **vs,
            '__EVENTTARGET': '',
            '__EVENTARGUMENT': '',
            'ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$ucCalendar$txtDate': date_str,
            'ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$ucCalendar$btnSearch': '조회',
        }

        resp2 = _SESSION.post(url, data=data, timeout=10)
        resp2.raise_for_status()
        return _parse_roster_html(resp2.text, date.date())

    except Exception as e:
        print(f"[RosterCrawl] 크롤링 실패: {e}")
        return []


def _parse_roster_html(html: str, date) -> list[dict]:
    soup = BeautifulSoup(html, 'html.parser')
    results = []

    # 테이블 찾기
    table = soup.find('table', class_='tbl-type02')
    if not table:
        # fallback: tbody 직접 탐색
        table = soup.find('table', {'id': lambda x: x and 'gvList' in str(x)})
    if not table:
        return results

    rows = table.find('tbody').find_all('tr') if table.find('tbody') else table.find_all('tr')[1:]

    for row in rows:
        cols = [td.get_text(strip=True) for td in row.find_all('td')]
        if len(cols) < 4:
            continue
        # 컬럼: 날짜, 팀, 선수, 구분(등록/말소), 사유
        try:
            if len(cols) >= 5:
                row_date_str, team_name, player_name, change_type, reason = cols[0], cols[1], cols[2], cols[3], cols[4]
            else:
                team_name, player_name, change_type, reason = cols[0], cols[1], cols[2], cols[3] if len(cols) > 3 else ''
                row_date_str = str(date)

            if not player_name or not team_name:
                continue

            results.append({
                'player_name': player_name,
                'team_name': team_name.strip(),
                'change_type': change_type.strip(),
                'reason': reason.strip(),
                'change_date': date,
            })
        except Exception:
            continue

    return results


def save_roster_changes(records: list[dict], team_ids: dict):
    """크롤링 결과 DB 저장"""
    if not records:
        return 0

    conn = get_connection()
    if not conn:
        return 0

    cur = conn.cursor()
    saved = 0

    for r in records:
        team_name = r['team_name']
        # 팀 매핑
        team_id = None
        for key, tid in team_ids.items():
            if key in team_name or team_name in key:
                team_id = tid
                break

        player_id = _find_player_id(r['player_name'], team_id)

        try:
            cur.execute("""
                INSERT INTO player_roster_changes
                    (player_name, team_id, player_id, change_type, reason, change_date)
                VALUES (%s, %s, %s, %s, %s, %s)
                ON CONFLICT (player_name, team_id, change_type, change_date) DO NOTHING
            """, (
                r['player_name'], team_id, player_id,
                r['change_type'], r['reason'], r['change_date']
            ))
            if cur.rowcount > 0:
                saved += 1
        except Exception as e:
            print(f"[RosterCrawl] 저장 실패 {r['player_name']}: {e}")

    conn.commit()
    cur.close()
    conn.close()
    print(f"[RosterCrawl] {saved}건 저장 완료")
    return saved


def run_today():
    """오늘 등록말소 크롤링 + 저장"""
    team_ids = _get_team_ids()
    records = crawl_roster_changes()
    save_roster_changes(records, team_ids)


def run_range(days: int = 7):
    """최근 N일치 크롤링"""
    team_ids = _get_team_ids()
    today = datetime.now()
    for i in range(days):
        d = today - timedelta(days=i)
        records = crawl_roster_changes(d)
        save_roster_changes(records, team_ids)


if __name__ == '__main__':
    run_range(30)
