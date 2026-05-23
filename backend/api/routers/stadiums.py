from fastapi import APIRouter, HTTPException
from database.connection import get_connection
import requests as _req
from datetime import datetime, timedelta

router = APIRouter()

_KAKAO_REST_KEY = "7985e6da2ec83998731bfa4a58ff99a5"

# 구장 좌표 하드코딩 (DB에 없을 때 fallback)
_STADIUM_COORDS = {
    1: (37.5121, 127.0719),
    2: (37.4982, 126.8672),
    3: (37.2997, 127.0095),
    4: (37.4370, 126.6934),
    5: (36.3169, 127.4289),
    6: (35.1685, 126.8890),
    7: (35.8411, 128.6813),
    8: (35.2225, 128.5816),
    9: (35.1940, 129.0613),
}

_food_cache: dict = {}
_food_cache_ts: dict = {}
_FOOD_CACHE_TTL = timedelta(hours=1)


@router.get("/")
def get_stadiums():
    """전체 경기장 목록"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("""
        SELECT s.id, s.name, s.address, s.latitude, s.longitude,
               s.capacity, t.name AS team_name, t.logo_url
        FROM stadiums s
        LEFT JOIN teams t ON s.team_id = t.id
        ORDER BY s.id
    """)

    rows = cur.fetchall()
    cur.close()
    conn.close()

    return {
        "count": len(rows),
        "stadiums": [
            {
                "id":        r[0],
                "name":      r[1],
                "address":   r[2],
                "latitude":  float(r[3]) if r[3] else None,
                "longitude": float(r[4]) if r[4] else None,
                "capacity":  r[5],
                "team_name": r[6],
                "logo_url":  r[7],
            }
            for r in rows
        ]
    }


@router.get("/{stadium_id}")
def get_stadium_detail(stadium_id: int):
    """경기장 상세 + 예정 경기"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()

    # 경기장 기본 정보
    cur.execute("""
        SELECT s.id, s.name, s.address, s.latitude, s.longitude,
               s.capacity, t.name AS team_name, t.logo_url
        FROM stadiums s
        LEFT JOIN teams t ON s.team_id = t.id
        WHERE s.id = %s
    """, (stadium_id,))

    row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="경기장을 찾을 수 없습니다")

    stadium = {
        "id":        row[0],
        "name":      row[1],
        "address":   row[2],
        "latitude":  float(row[3]) if row[3] else None,
        "longitude": float(row[4]) if row[4] else None,
        "capacity":  row[5],
        "team_name": row[6],
        "logo_url":  row[7],
    }

    # 이 경기장에서 열릴 예정 경기 (최근 5경기)
    cur.execute("""
        SELECT g.id, g.game_date, g.status,
               g.home_score, g.away_score,
               ht.name AS home_team,
               at.name AS away_team
        FROM games g
        JOIN teams ht ON g.home_team_id = ht.id
        JOIN teams at ON g.away_team_id = at.id
        JOIN stadiums s ON g.stadium_id = s.id
        WHERE s.id = %s
        ORDER BY g.game_date DESC
        LIMIT 5
    """, (stadium_id,))

    games = cur.fetchall()
    cur.close()
    conn.close()

    return {
        "stadium": stadium,
        "recent_games": [
            {
                "id":         r[0],
                "game_date":  str(r[1]),
                "status":     r[2],
                "home_score": r[3],
                "away_score": r[4],
                "home_team":  r[5],
                "away_team":  r[6],
            }
            for r in games
        ]
    }


@router.get("/{stadium_id}/nearby-food")
def get_nearby_food(stadium_id: int, radius: int = 1000):
    """구장 주변 음식점 (카카오 로컬 API, 1시간 캐시)"""
    now = datetime.now()
    cache_key = (stadium_id, radius)
    if cache_key in _food_cache and (now - _food_cache_ts[cache_key]) < _FOOD_CACHE_TTL:
        return _food_cache[cache_key]

    coords = _STADIUM_COORDS.get(stadium_id)
    if not coords:
        conn = get_connection()
        if not conn:
            raise HTTPException(status_code=500, detail="DB 연결 실패")
        cur = conn.cursor()
        cur.execute("SELECT latitude, longitude FROM stadiums WHERE id = %s", (stadium_id,))
        row = cur.fetchone()
        cur.close(); conn.close()
        if not row or not row[0]:
            raise HTTPException(status_code=404, detail="구장을 찾을 수 없습니다")
        coords = (float(row[0]), float(row[1]))

    lat, lng = coords
    try:
        res = _req.get(
            "https://dapi.kakao.com/v2/local/search/category.json",
            params={
                "category_group_code": "FD6",
                "x": lng,
                "y": lat,
                "radius": radius,
                "sort": "distance",
                "size": 15,
            },
            headers={"Authorization": f"KakaoAK {_KAKAO_REST_KEY}"},
            timeout=6,
        )
        if res.status_code != 200:
            raise HTTPException(status_code=502, detail=f"카카오 API {res.status_code}")
        docs = res.json().get("documents", [])
        result = {
            "stadium_id": stadium_id,
            "places": [
                {
                    "id":       d["id"],
                    "name":     d["place_name"],
                    "category": d["category_name"].split(" > ")[-1],
                    "address":  d["road_address_name"] or d["address_name"],
                    "phone":    d["phone"],
                    "distance": int(d["distance"]) if d["distance"] else 0,
                    "url":      d["place_url"],
                }
                for d in docs
            ],
        }
        _food_cache[cache_key] = result
        _food_cache_ts[cache_key] = now
        return result
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"맛집 조회 실패: {e}")


@router.get("/by-name/{stadium_name}")
def get_stadium_by_name(stadium_name: str):
    """경기장 이름으로 검색 (크롤링 데이터의 구장명으로 조회)"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("""
        SELECT s.id, s.name, s.address, s.latitude, s.longitude, s.capacity
        FROM stadiums s
        WHERE s.name LIKE %s
    """, (f"%{stadium_name}%",))

    row = cur.fetchone()
    cur.close()
    conn.close()

    if not row:
        raise HTTPException(status_code=404, detail="경기장을 찾을 수 없습니다")

    return {
        "id":        row[0],
        "name":      row[1],
        "address":   row[2],
        "latitude":  float(row[3]) if row[3] else None,
        "longitude": float(row[4]) if row[4] else None,
        "capacity":  row[5],
    }