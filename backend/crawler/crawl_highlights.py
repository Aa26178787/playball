import sys
import os
import re
import time
import xml.etree.ElementTree as ET
import urllib.parse as up
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

CURRENT_YEAR = datetime.now().year

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import requests
from database.connection import get_connection

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Referer': 'https://sports.naver.com/',
}

# KBO 관련 YouTube 채널 ID 목록
KBO_YOUTUBE_CHANNELS = [
    'UCJkCKfxJVS_2jGGOqPTqBxw',  # KBO TV (공식)
    'UCPZTalFKDPvkDiYi0CeIyMg',  # 네이버 스포츠 야구
]

# 팀명 → team_id 매핑 (DB 기준)
TEAM_NAME_MAP = {
    'KT': 1, 'KT위즈': 1,
    'KIA': 2, 'KIA타이거즈': 2, '기아타이거즈': 2, '기아': 2,
    '롯데': 4, '롯데자이언츠': 4,
    '한화': 5, '한화이글스': 5,
    'NC': 6, 'NC다이노스': 6,
    '두산': 7, '두산베어스': 7,
    '키움': 8, '키움히어로즈': 8,
    'LG': 9, 'LG트윈스': 9,
    'SSG': 10, 'SSG랜더스': 10,
    '삼성': 11, '삼성라이온즈': 11,
}


def _parse_pub_date(s: str):
    try:
        dt = parsedate_to_datetime(s)
        return dt.astimezone(timezone.utc).replace(tzinfo=None)
    except Exception:
        return None


def _parse_teams_from_title(title: str) -> tuple[int | None, int | None]:
    """제목에서 두 팀 추출: '[두산베어스 Vs LG트윈스]' 형태"""
    m = re.search(r'\[([^\]]+)\]', title)
    if not m:
        return None, None
    bracket = m.group(1)
    parts = re.split(r'\s+[Vv][Ss]?\s+', bracket)
    if len(parts) < 2:
        return None, None
    t1 = TEAM_NAME_MAP.get(parts[0].strip())
    t2 = TEAM_NAME_MAP.get(parts[1].strip())
    return t1, t2


def _parse_date_from_title(title: str, pub_year: int) -> str | None:
    """'5.7(목)' 또는 '5.14' 형태에서 날짜 추출"""
    m = re.search(r'(\d{1,2})\.(\d{1,2})[\(\（]', title)
    if not m:
        m = re.search(r'(\d{1,2})\.(\d{1,2})', title)
    if not m:
        return None
    month, day = int(m.group(1)), int(m.group(2))
    return f'{pub_year}-{month:02d}-{day:02d}'


def find_game_id(team_id1, team_id2, game_date: str) -> int | None:
    if not team_id1 or not team_id2 or not game_date:
        return None
    conn = get_connection()
    if not conn:
        return None
    cur = conn.cursor()
    cur.execute("""
        SELECT id FROM games
        WHERE game_date = %s
        AND (
            (home_team_id = %s AND away_team_id = %s)
            OR (home_team_id = %s AND away_team_id = %s)
        )
        LIMIT 1
    """, (game_date, team_id1, team_id2, team_id2, team_id1))
    row = cur.fetchone()
    cur.close()
    conn.close()
    return row[0] if row else None


def fetch_highlight_rss(query: str = 'KBO 야구 하이라이트') -> list[dict]:
    encoded = up.quote(query)
    url = 'https://news.google.com/rss/search?q=' + encoded + '&hl=ko&gl=KR&ceid=KR:ko'
    articles = []
    try:
        r = requests.get(url, headers=HEADERS, timeout=8)
        if r.status_code != 200:
            return []
        root = ET.fromstring(r.text)
        for item in root.findall('./channel/item')[:30]:
            title = item.findtext('title', '')
            link = item.findtext('link', '')
            pub_raw = item.findtext('pubDate', '')
            source = item.findtext('source', '')
            if ' - ' in title:
                title = title.rsplit(' - ', 1)[0].strip()
            # 하이라이트 관련 제목만
            if not any(kw in title for kw in ['하이라이트', 'HIGHLIGHT', 'highlight', '홈런', '명장면']):
                continue
            pub = _parse_pub_date(pub_raw)
            pub_year = pub.year if pub else CURRENT_YEAR
            # 당해연도 기사만 수집
            if pub_year != CURRENT_YEAR:
                continue
            t1, t2 = _parse_teams_from_title(title)
            game_date = _parse_date_from_title(title, pub_year)
            # 날짜 파싱됐으면 연도 재확인
            if game_date and not game_date.startswith(str(CURRENT_YEAR)):
                continue
            articles.append({
                'title': title,
                'url': link,
                'source': source,
                'published_at': pub,
                'team_id1': t1,
                'team_id2': t2,
                'game_date': game_date,
            })
    except Exception as e:
        print(f'highlight RSS error: {e}')
    return articles


def save_highlights(articles: list[dict]) -> int:
    conn = get_connection()
    if not conn:
        return 0
    cur = conn.cursor()
    saved = 0
    for a in articles:
        game_id = find_game_id(a['team_id1'], a['team_id2'], a['game_date'])
        try:
            cur.execute("""
                INSERT INTO game_highlights (game_id, title, url, source, published_at)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (url) DO UPDATE SET
                    game_id = COALESCE(EXCLUDED.game_id, game_highlights.game_id)
            """, (game_id, a['title'], a['url'], a.get('source') or None, a.get('published_at')))
            if cur.rowcount > 0:
                saved += 1
        except Exception as e:
            print(f'  highlight insert error: {e}')
            conn.rollback()
    conn.commit()
    cur.close()
    conn.close()
    return saved


# ── YouTube RSS 하이라이트 ──────────────────────────────────────────────────────

_YT_NS = {
    'atom':  'http://www.w3.org/2005/Atom',
    'yt':    'http://www.youtube.com/xml/schemas/2015',
    'media': 'http://search.yahoo.com/mrss/',
}
_KBO_KW = ['하이라이트', 'KBO', '야구', '홈런', '명장면', 'Shorts', '#Shorts', 'vs', 'VS', '경기']


def fetch_youtube_highlights(today: str | None = None) -> list[dict]:
    """KBO YouTube 채널 RSS → 당일 영상 수집 (Shorts 포함)"""
    if today is None:
        today = datetime.now().strftime('%Y-%m-%d')
    articles = []
    for channel_id in KBO_YOUTUBE_CHANNELS:
        try:
            url = f'https://www.youtube.com/feeds/videos.xml?channel_id={channel_id}'
            r = requests.get(url, headers=HEADERS, timeout=10)
            if r.status_code != 200:
                continue
            root = ET.fromstring(r.content)
            for entry in root.findall('atom:entry', _YT_NS):
                title_el   = entry.find('atom:title',     _YT_NS)
                link_el    = entry.find('atom:link',      _YT_NS)
                pub_el     = entry.find('atom:published', _YT_NS)
                vid_el     = entry.find('yt:videoId',     _YT_NS)
                if title_el is None or link_el is None:
                    continue
                title    = title_el.text or ''
                link     = link_el.get('href', '')
                pub_str  = pub_el.text if pub_el is not None else ''
                video_id = vid_el.text if vid_el is not None else ''
                # 당일 영상만
                if pub_str[:10] != today:
                    continue
                # KBO 관련 키워드 없으면 스킵
                if not any(kw in title for kw in _KBO_KW):
                    continue
                # Shorts는 /shorts/ URL 사용
                is_shorts = '#Shorts' in title or 'Shorts' in title
                video_url = (f'https://www.youtube.com/shorts/{video_id}'
                             if is_shorts and video_id else link)
                t1, t2 = _parse_teams_from_title(title)
                try:
                    pub_dt = datetime.fromisoformat(pub_str.replace('Z', '+00:00')).replace(tzinfo=None)
                except Exception:
                    pub_dt = datetime.now()
                articles.append({
                    'title': title,
                    'url':   video_url,
                    'source': 'youtube',
                    'published_at': pub_dt,
                    'team_id1': t1,
                    'team_id2': t2,
                    'game_date': today,
                })
        except Exception as e:
            print(f'[YouTube RSS] 채널 {channel_id} 오류: {e}')
    return articles


# ── Naver 스포츠 하이라이트 ────────────────────────────────────────────────────

_NAVER_HL_APIS = [
    'https://api-gw.sports.naver.com/contents/video?category=KBO&count=30&page=1',
    'https://sports.naver.com/kbo/highlights/index',
]


def fetch_naver_highlights(today: str | None = None) -> list[dict]:
    """Naver 스포츠 KBO 하이라이트 수집"""
    if today is None:
        today = datetime.now().strftime('%Y-%m-%d')
    articles = []
    try:
        # API 방식 시도
        r = requests.get(_NAVER_HL_APIS[0], headers=HEADERS, timeout=10)
        if r.status_code == 200:
            data = r.json()
            items = data.get('result', {}).get('list', []) or data.get('list', []) or []
            for item in items:
                title = item.get('title', '') or item.get('videoTitle', '')
                url   = item.get('videoUrl', '') or item.get('linkUrl', '')
                pub   = item.get('playDate', '') or item.get('regDate', '')
                if not title or not url:
                    continue
                # 당일 기사만
                if pub and pub[:10] != today:
                    continue
                t1, t2 = _parse_teams_from_title(title)
                articles.append({
                    'title': title,
                    'url': url,
                    'source': 'naver_sports',
                    'published_at': datetime.now(),
                    'team_id1': t1,
                    'team_id2': t2,
                    'game_date': today,
                })
    except Exception:
        pass

    if not articles:
        # HTML 파싱 fallback
        try:
            r = requests.get(_NAVER_HL_APIS[1], headers=HEADERS, timeout=10)
            if r.status_code == 200:
                html = r.text
                # 하이라이트 링크 패턴 추출
                patterns = [
                    re.compile(r'href="(https?://(?:tv|v)\.naver\.com/v/[^"]+)"[^>]*>([^<]+)</a>'),
                    re.compile(r'href="(/kbo/highlights/video\?[^"]+)"[^>]*title="([^"]+)"'),
                ]
                for pat in patterns:
                    for m in pat.finditer(html):
                        href, title = m.group(1), m.group(2)
                        url = href if href.startswith('http') else f'https://sports.naver.com{href}'
                        t1, t2 = _parse_teams_from_title(title)
                        articles.append({
                            'title': title,
                            'url': url,
                            'source': 'naver_sports',
                            'published_at': datetime.now(),
                            'team_id1': t1,
                            'team_id2': t2,
                            'game_date': today,
                        })
        except Exception as e:
            print(f'[Naver 하이라이트] HTML 파싱 오류: {e}')
    return articles


def crawl_highlights():
    today = datetime.now().strftime('%Y-%m-%d')
    total = 0

    # 1) Google News RSS (기존)
    for q in ['KBO 야구 하이라이트', 'KBO 하이라이트 TVING', 'KBO 경기 명장면']:
        articles = fetch_highlight_rss(q)
        total += save_highlights(articles)
        time.sleep(0.5)

    # 2) YouTube 채널 RSS (당일 쇼츠 + 하이라이트)
    yt_articles = fetch_youtube_highlights(today)
    if yt_articles:
        total += save_highlights(yt_articles)
        print(f'[YouTube] {len(yt_articles)}건 수집')

    # 3) Naver 스포츠 하이라이트
    nv_articles = fetch_naver_highlights(today)
    if nv_articles:
        total += save_highlights(nv_articles)
        print(f'[Naver] {len(nv_articles)}건 수집')

    print(f'[{datetime.now()}] 하이라이트 크롤링 완료: {total}건')
    return total


def crawl_highlights_for_game(game_id: int) -> int:
    """특정 경기 하이라이트 크롤링 (경기 종료 트리거)"""
    conn = get_connection()
    if not conn:
        return 0
    cur = conn.cursor()
    cur.execute("""
        SELECT ht.name, at2.name, g.game_date
        FROM games g
        JOIN teams ht ON g.home_team_id = ht.id
        JOIN teams at2 ON g.away_team_id = at2.id
        WHERE g.id = %s
    """, (game_id,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    if not row:
        return 0

    home_name, away_name, game_date = row
    query = f'{home_name} {away_name} 하이라이트'
    articles = fetch_highlight_rss(query)
    # 매칭 실패 기사도 이 game_id로 강제 연결
    for a in articles:
        if not find_game_id(a['team_id1'], a['team_id2'], a['game_date']):
            a['_force_game_id'] = game_id
    conn2 = get_connection()
    if not conn2:
        return 0
    cur2 = conn2.cursor()
    saved = 0
    for a in articles:
        gid = a.get('_force_game_id') or find_game_id(a['team_id1'], a['team_id2'], a['game_date']) or game_id
        try:
            cur2.execute("""
                INSERT INTO game_highlights (game_id, title, url, source, published_at)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (url) DO UPDATE SET
                    game_id = COALESCE(EXCLUDED.game_id, game_highlights.game_id)
            """, (gid, a['title'], a['url'], a.get('source') or None, a.get('published_at')))
            if cur2.rowcount > 0:
                saved += 1
        except Exception as e:
            print(f'  highlight insert error: {e}')
            conn2.rollback()
    conn2.commit()
    cur2.close()
    conn2.close()
    return saved


if __name__ == '__main__':
    crawl_highlights()
