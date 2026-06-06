# -*- coding: utf-8 -*-
"""
선수 인스타그램 핸들 수집 (검수 전제 반자동)

전략:
  1) DuckDuckGo HTML 검색 ("{이름} {팀} 야구 인스타그램") → instagram.com/<handle> 링크 추출
  2) 실패 시 나무위키 문서에서 instagram 외부링크 추출

사용:
  python3 crawl_insta_handles.py            # 검수용 CSV(insta_candidates.csv) 출력만
  python3 crawl_insta_handles.py --apply insta_reviewed.csv   # 검수 완료 CSV 일괄 UPDATE

주의: 자동 결과는 동명이인/팬계정 오매칭 가능 — 반드시 검수 후 apply.
"""
import csv
import re
import sys
import time
import requests
from urllib.parse import unquote

sys.path.insert(0, '/home/ubuntu/playball/backend')
from database.connection import get_connection  # noqa: E402

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
    'Accept-Language': 'ko-KR,ko;q=0.9',
}

# instagram.com/<handle> — 예약 경로 제외
_IG_RE = re.compile(r'instagram\.com/([A-Za-z0-9._]{2,30})')
_IG_RESERVED = {'p', 'reel', 'reels', 'explore', 'accounts', 'stories', 'tv', 'about', 'directory'}


def _extract_handle(text: str) -> str | None:
    for m in _IG_RE.finditer(text):
        h = m.group(1).rstrip('.')
        if h.lower() not in _IG_RESERVED:
            return h
    return None


def search_ddg(name: str, team: str) -> tuple[str | None, str]:
    """DuckDuckGo HTML 검색 → 첫 instagram 핸들"""
    q = f'{name} {team} 야구 인스타그램'
    try:
        r = requests.get('https://html.duckduckgo.com/html/',
                         params={'q': q}, headers=HEADERS, timeout=10)
        if r.status_code != 200:
            return None, f'ddg_http_{r.status_code}'
        # 결과 링크는 uddg= 인코딩 — 디코드 후 탐색
        decoded = unquote(r.text)
        h = _extract_handle(decoded)
        return h, 'ddg' if h else 'ddg_none'
    except Exception as e:
        return None, f'ddg_err_{type(e).__name__}'


def search_namu(name: str) -> tuple[str | None, str]:
    """나무위키 문서 본문에서 instagram 외부링크 추출"""
    for title in (name, f'{name}(야구선수)', f'{name}(야구 선수)'):
        try:
            r = requests.get(f'https://namu.wiki/w/{title}', headers=HEADERS, timeout=10)
            if r.status_code != 200:
                continue
            h = _extract_handle(r.text)
            if h:
                return h, f'namu:{title}'
        except Exception:
            continue
        time.sleep(1.5)
    return None, 'namu_none'


def collect():
    conn = get_connection()
    cur = conn.cursor()
    # 현역 (team_id 有) + 미등록만
    cur.execute("""
        SELECT p.id, p.name, t.name
        FROM players p JOIN teams t ON t.id = p.team_id
        WHERE p.insta_handle IS NULL
        ORDER BY t.id, p.name
    """)
    rows = cur.fetchall()
    cur.close(); conn.close()
    print(f'대상 {len(rows)}명')

    out = []
    for i, (pid, name, team) in enumerate(rows):
        handle, src = search_ddg(name, team)
        if not handle:
            handle, src = search_namu(name)
        out.append((pid, name, team, handle or '', src))
        print(f'[{i+1}/{len(rows)}] {team} {name} → {handle or "-"} ({src})')
        time.sleep(2.0)  # throttle

    with open('insta_candidates.csv', 'w', newline='', encoding='utf-8-sig') as f:
        w = csv.writer(f)
        w.writerow(['player_id', 'name', 'team', 'handle', 'source'])
        w.writerows(out)
    found = sum(1 for r in out if r[3])
    print(f'완료 — {found}/{len(out)} 후보. insta_candidates.csv 검수 후 --apply')


def apply(path: str):
    conn = get_connection()
    cur = conn.cursor()
    n = 0
    with open(path, encoding='utf-8-sig') as f:
        for row in csv.DictReader(f):
            h = (row.get('handle') or '').strip()
            if not h:
                continue
            cur.execute('UPDATE players SET insta_handle = %s WHERE id = %s',
                        (h, int(row['player_id'])))
            n += 1
    conn.commit(); cur.close(); conn.close()
    print(f'{n}명 적용 완료')


if __name__ == '__main__':
    if len(sys.argv) >= 3 and sys.argv[1] == '--apply':
        apply(sys.argv[2])
    else:
        collect()
