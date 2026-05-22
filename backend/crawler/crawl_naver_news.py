import sys
import os
import time
import re
from datetime import datetime, timezone

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import requests
from database.connection import get_connection

NAVER_HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Referer': 'https://sports.naver.com/',
}

# 팀 코드 → (team_id, 팀명 리스트)
TEAM_KEYWORDS = {
    1:  ['LG', 'LG트윈스'],
    2:  ['KT', 'KT위즈'],
    3:  ['SSG', 'SSG랜더스', 'SK'],
    4:  ['NC', 'NC다이노스'],
    5:  ['두산', '두산베어스'],
    6:  ['KIA', 'KIA타이거즈', '기아'],
    7:  ['롯데', '롯데자이언츠'],
    8:  ['삼성', '삼성라이온즈'],
    9:  ['한화', '한화이글스'],
    10: ['키움', '키움히어로즈', '히어로즈'],
}

# 네이버 팀 코드 (API 파라미터용)
NAVER_TEAM_CODES = {
    1: 'LG', 2: 'KT', 3: 'SK', 4: 'NC', 5: 'OB',
    6: 'HT', 7: 'LT', 8: 'SS', 9: 'HH', 10: 'WO',
}


def _classify_team(title: str, description: str = '') -> list[int]:
    """뉴스 제목+설명에서 팀 ID 목록 추출 (복수 가능)"""
    text = title + ' ' + description
    matched = []
    for team_id, keywords in TEAM_KEYWORDS.items():
        for kw in keywords:
            if kw in text:
                matched.append(team_id)
                break
    return matched or [None]


def _parse_pub_date(s: str) -> datetime | None:
    """'2026-05-23T14:30:00+09:00' 또는 'YYYY.MM.DD HH:MM' 파싱"""
    if not s:
        return None
    for fmt in ('%Y-%m-%dT%H:%M:%S%z', '%Y.%m.%d %H:%M', '%Y-%m-%d %H:%M:%S'):
        try:
            dt = datetime.strptime(s[:19], fmt[:len(fmt)])
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc).replace(tzinfo=None)
        except Exception:
            continue
    return None


def fetch_kbo_news(page: int = 1, page_size: int = 20) -> list[dict]:
    """네이버 KBO 뉴스 목록 크롤링"""
    articles = []

    # 1차: api-gw 뉴스 엔드포인트
    try:
        url = f"https://api-gw.sports.naver.com/news/kbaseball/list?page={page}&pageSize={page_size}"
        res = requests.get(url, headers=NAVER_HEADERS, timeout=8)
        if res.status_code == 200:
            data = res.json()
            items = (data.get('result') or data.get('data') or {}).get('newsList') or \
                    (data.get('result') or data.get('data') or {}).get('articles') or []
            if not items and isinstance(data.get('result'), list):
                items = data['result']
            for item in items:
                title = item.get('title') or item.get('headline') or ''
                url_item = item.get('url') or item.get('linkUrl') or item.get('link') or ''
                thumbnail = item.get('thumbnail') or item.get('imageUrl') or item.get('thumbnailUrl') or ''
                media = item.get('officeName') or item.get('press') or item.get('media') or ''
                pub = _parse_pub_date(item.get('publishDate') or item.get('pubDate') or item.get('date') or '')
                desc = item.get('summary') or item.get('description') or ''
                if title and url_item:
                    articles.append({
                        'title': title, 'url': url_item,
                        'thumbnail': thumbnail, 'media': media,
                        'published_at': pub, 'description': desc,
                    })
    except Exception:
        pass

    if articles:
        return articles

    # 2차 fallback: 네이버 스포츠 뉴스 일반 API
    try:
        url = f"https://sports.naver.com/kbaseball/news/index.nhn?isphoto=N&page={page}"
        res = requests.get(url, headers=NAVER_HEADERS, timeout=8)
        if res.status_code == 200:
            # 기본 HTML 파싱 (간단한 regex)
            titles = re.findall(r'class="title[^"]*"[^>]*>([^<]+)<', res.text)
            links = re.findall(r'href="(https://sports\.naver\.com/kbaseball/news/view[^"]+)"', res.text)
            for i, (t, l) in enumerate(zip(titles[:page_size], links[:page_size])):
                articles.append({'title': t.strip(), 'url': l.strip(),
                                 'thumbnail': '', 'media': '', 'published_at': None, 'description': ''})
    except Exception:
        pass

    return articles


def fetch_team_news(naver_code: str, page: int = 1) -> list[dict]:
    """팀별 뉴스"""
    articles = []
    try:
        url = f"https://api-gw.sports.naver.com/news/kbaseball/list?teamCode={naver_code}&page={page}&pageSize=15"
        res = requests.get(url, headers=NAVER_HEADERS, timeout=8)
        if res.status_code == 200:
            data = res.json()
            items = (data.get('result') or data.get('data') or {}).get('newsList') or \
                    (data.get('result') or data.get('data') or {}).get('articles') or []
            if not items and isinstance(data.get('result'), list):
                items = data['result']
            for item in items:
                title = item.get('title') or item.get('headline') or ''
                url_item = item.get('url') or item.get('linkUrl') or item.get('link') or ''
                thumbnail = item.get('thumbnail') or item.get('imageUrl') or ''
                media = item.get('officeName') or item.get('press') or ''
                pub = _parse_pub_date(item.get('publishDate') or item.get('pubDate') or '')
                desc = item.get('summary') or item.get('description') or ''
                if title and url_item:
                    articles.append({'title': title, 'url': url_item,
                                     'thumbnail': thumbnail, 'media': media,
                                     'published_at': pub, 'description': desc})
    except Exception:
        pass
    return articles


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
        for tid in team_ids:
            try:
                cur.execute("""
                    INSERT INTO team_news (team_id, title, url, thumbnail, media, published_at)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    ON CONFLICT (url) DO UPDATE SET
                        team_id = COALESCE(EXCLUDED.team_id, team_news.team_id),
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

    # 전체 KBO 뉴스 (팀 자동 분류)
    for page in range(1, 4):
        articles = fetch_kbo_news(page=page, page_size=20)
        if not articles:
            break
        n = save_news(articles)
        total += n
        time.sleep(0.3)

    # 팀별 뉴스
    for team_id, naver_code in NAVER_TEAM_CODES.items():
        articles = fetch_team_news(naver_code, page=1)
        if articles:
            n = save_news(articles, forced_team_id=team_id)
            total += n
        time.sleep(0.2)

    print(f"[{datetime.now()}] 뉴스 크롤링 완료: {total}건 저장")
    return total


def crawl_news_for_teams(team_ids: list[int]):
    """특정 팀(들) 뉴스만 크롤링 (경기 종료 트리거용)"""
    total = 0
    for tid in team_ids:
        code = NAVER_TEAM_CODES.get(tid)
        if not code:
            continue
        articles = fetch_team_news(code, page=1)
        if articles:
            n = save_news(articles, forced_team_id=tid)
            total += n
        time.sleep(0.2)

    # 전체 KBO 뉴스도 1페이지
    articles = fetch_kbo_news(page=1, page_size=20)
    if articles:
        n = save_news(articles)
        total += n

    print(f"[{datetime.now()}] 경기 종료 뉴스 크롤링: {total}건 (팀={team_ids})")
    return total


if __name__ == '__main__':
    crawl_all_team_news()
