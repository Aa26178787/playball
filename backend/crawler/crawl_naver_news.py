import sys
import os
import time
import re
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import requests
from database.connection import get_connection

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
}

# 팀 ID → (검색 키워드, 팀명 리스트)
TEAM_INFO = {
    1:  ('LG트윈스', ['LG', 'LG트윈스']),
    2:  ('KT위즈', ['KT', 'KT위즈']),
    3:  ('SSG랜더스', ['SSG', 'SSG랜더스', 'SK와이번스']),
    4:  ('NC다이노스', ['NC', 'NC다이노스']),
    5:  ('두산베어스', ['두산', '두산베어스']),
    6:  ('KIA타이거즈', ['KIA', 'KIA타이거즈', '기아타이거즈', '기아']),
    7:  ('롯데자이언츠', ['롯데', '롯데자이언츠']),
    8:  ('삼성라이온즈', ['삼성', '삼성라이온즈']),
    9:  ('한화이글스', ['한화', '한화이글스']),
    10: ('키움히어로즈', ['키움', '키움히어로즈', '히어로즈']),
}

GOOGLE_RSS_BASE = 'https://news.google.com/rss/search?hl=ko&gl=KR&ceid=KR:ko&q='


def _parse_rfc2822(s: str) -> datetime | None:
    try:
        dt = parsedate_to_datetime(s)
        return dt.astimezone(timezone.utc).replace(tzinfo=None)
    except Exception:
        return None


def _decode_google_url(url: str) -> str:
    """Google News 리다이렉트 URL 유지 (원본 링크 추출 시도)"""
    # Google RSS에서 articles URL은 이미 원본 링크
    return url


def fetch_rss(query: str) -> list[dict]:
    """Google News RSS로 검색"""
    import urllib.parse
    encoded = urllib.parse.quote(query)
    url = GOOGLE_RSS_BASE + encoded
    articles = []
    try:
        r = requests.get(url, headers=HEADERS, timeout=8)
        if r.status_code != 200:
            return []
        root = ET.fromstring(r.text)
        channel = root.find('channel')
        if channel is None:
            return []
        for item in channel.findall('item')[:20]:
            title = item.findtext('title') or ''
            link = item.findtext('link') or ''
            pub_raw = item.findtext('pubDate') or ''
            source = item.findtext('source') or ''
            desc = item.findtext('description') or ''
            # 제목에서 언론사 제거 (Google News 형식: "제목 - 언론사")
            if ' - ' in title:
                parts = title.rsplit(' - ', 1)
                clean_title = parts[0].strip()
                if not source:
                    source = parts[1].strip()
            else:
                clean_title = title.strip()
            pub = _parse_rfc2822(pub_raw)
            if clean_title and link:
                articles.append({
                    'title': clean_title,
                    'url': link,
                    'thumbnail': '',
                    'media': source,
                    'published_at': pub,
                    'description': re.sub(r'<[^>]+>', '', desc).strip(),
                })
    except Exception as e:
        print(f"RSS fetch error ({query}): {e}")
    return articles


def _classify_team(title: str, description: str = '') -> list[int]:
    """제목+설명에서 팀 ID 추출"""
    text = title + ' ' + description
    matched = []
    for team_id, (_, keywords) in TEAM_INFO.items():
        for kw in keywords:
            if kw in text:
                matched.append(team_id)
                break
    return matched or []


def save_news(articles: list[dict], forced_team_id: int | None = None) -> int:
    conn = get_connection()
    if not conn:
        return 0
    cur = conn.cursor()
    saved = 0
    for a in articles:
        if forced_team_id is not None:
            team_ids = [forced_team_id]
        else:
            team_ids = _classify_team(a['title'], a.get('description', ''))
            if not team_ids:
                team_ids = [None]  # 팀 미분류 뉴스도 저장
        for tid in team_ids:
            try:
                cur.execute("""
                    INSERT INTO team_news (team_id, title, url, thumbnail, media, published_at)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    ON CONFLICT (url) DO UPDATE SET
                        team_id = COALESCE(team_news.team_id, EXCLUDED.team_id),
                        published_at = COALESCE(EXCLUDED.published_at, team_news.published_at)
                """, (tid, a['title'], a['url'], a.get('thumbnail') or None,
                      a.get('media') or None, a.get('published_at')))
                if cur.rowcount > 0:
                    saved += 1
            except Exception as e:
                print(f"  news insert error: {e}")
                conn.rollback()
    conn.commit()
    cur.close()
    conn.close()
    return saved


def crawl_all_team_news():
    """전체 팀 뉴스 크롤링 (스케줄러용)"""
    total = 0

    # KBO 전체 뉴스
    articles = fetch_rss('KBO 야구')
    if articles:
        n = save_news(articles)
        total += n
        print(f"  KBO 전체: {n}건")
    time.sleep(0.5)

    # 팀별 뉴스
    for team_id, (query, _) in TEAM_INFO.items():
        articles = fetch_rss(query)
        if articles:
            n = save_news(articles, forced_team_id=team_id)
            total += n
        time.sleep(0.3)

    print(f"[{datetime.now()}] 뉴스 크롤링 완료: {total}건 저장")
    return total


def crawl_news_for_teams(team_ids: list[int]):
    """특정 팀(들) 뉴스만 크롤링 (경기 종료 트리거용)"""
    total = 0

    # KBO 전체 뉴스 1회
    articles = fetch_rss('KBO 야구')
    if articles:
        n = save_news(articles)
        total += n
    time.sleep(0.3)

    # 해당 팀 전용 뉴스
    for tid in team_ids:
        info = TEAM_INFO.get(tid)
        if not info:
            continue
        query, _ = info
        articles = fetch_rss(query)
        if articles:
            n = save_news(articles, forced_team_id=tid)
            total += n
        time.sleep(0.3)

    print(f"[{datetime.now()}] 경기 종료 뉴스 크롤링: {total}건 (팀={team_ids})")
    return total


if __name__ == '__main__':
    crawl_all_team_news()
