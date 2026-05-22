"""
선수 프로필 이미지 크롤러
Naver 스포츠 API에서 선수 이미지 URL 수집 → players.profile_image 업데이트
"""
import sys
import os
import time

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import requests
from database.connection import get_connection

NAVER_HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Referer': 'https://sports.naver.com/',
}


def fetch_player_image(naver_player_id):
    """Naver 스포츠 API에서 선수 이미지 URL 반환"""
    try:
        url = f"https://api-gw.sports.naver.com/sports/kbo/v2/player/{naver_player_id}/career"
        res = requests.get(url, headers=NAVER_HEADERS, timeout=6)
        if res.status_code != 200:
            return None
        data = res.json()
        # 경로 탐색: result.player.playerImageUrl 또는 result.playerImageUrl
        result = data.get('result') or data.get('data') or {}
        player = result.get('player') or result
        img = player.get('playerImageUrl') or player.get('imageUrl') or player.get('profileImageUrl')
        return img if img and img.startswith('http') else None
    except Exception:
        return None


def fetch_player_image_v2(naver_player_id):
    """대체 엔드포인트 시도"""
    try:
        url = f"https://api-gw.sports.naver.com/schedule/stat/player?category=kbo&playerId={naver_player_id}"
        res = requests.get(url, headers=NAVER_HEADERS, timeout=6)
        if res.status_code != 200:
            return None
        data = res.json()
        result = data.get('result') or {}
        img = result.get('playerImageUrl') or result.get('imageUrl')
        return img if img and img.startswith('http') else None
    except Exception:
        return None


def crawl_player_images(overwrite=False, limit=None):
    conn = get_connection()
    if not conn:
        return

    cur = conn.cursor()
    if overwrite:
        cur.execute("""
            SELECT id, naver_player_id, name
            FROM players
            WHERE naver_player_id IS NOT NULL
            ORDER BY id
            LIMIT %s
        """, (limit or 10000,))
    else:
        cur.execute("""
            SELECT id, naver_player_id, name
            FROM players
            WHERE naver_player_id IS NOT NULL
            AND (profile_image IS NULL OR profile_image = '')
            ORDER BY id
            LIMIT %s
        """, (limit or 10000,))

    players = cur.fetchall()
    cur.close()
    conn.close()

    print(f"이미지 크롤링 대상: {len(players)}명")
    updated = 0

    for player_id, naver_id, name in players:
        img = fetch_player_image(naver_id)
        if not img:
            img = fetch_player_image_v2(naver_id)

        if img:
            conn2 = get_connection()
            if conn2:
                cur2 = conn2.cursor()
                cur2.execute(
                    "UPDATE players SET profile_image = %s WHERE id = %s",
                    (img, player_id)
                )
                conn2.commit()
                cur2.close()
                conn2.close()
                updated += 1
                print(f"  [{updated}] {name} → {img[:60]}...")
        else:
            print(f"  {name} (id={naver_id}): 이미지 없음")

        time.sleep(0.3)

    print(f"이미지 업데이트 완료: {updated}/{len(players)}명")


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--overwrite', action='store_true', help='기존 이미지도 덮어쓰기')
    parser.add_argument('--limit', type=int, default=None, help='처리할 최대 인원')
    args = parser.parse_args()
    crawl_player_images(overwrite=args.overwrite, limit=args.limit)
