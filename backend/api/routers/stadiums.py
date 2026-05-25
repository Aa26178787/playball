from fastapi import APIRouter, HTTPException, Depends, Request, Header
from database.connection import get_connection
from api.routers.auth import get_current_user
from api.security_log import log_admin_access
from pydantic import BaseModel
from typing import Optional
import requests as _req
import os
from datetime import datetime, timedelta

router = APIRouter()

_VOTE_THRESHOLD = 5
_ADMIN_KEY = os.environ.get("ADMIN_KEY", "")


def _check_admin(x_admin_key: Optional[str], ip: str, endpoint: str):
    """X-Admin-Key 헤더 검증 (URL pw 파라미터 대체)"""
    if not _ADMIN_KEY:
        log_admin_access(ip, endpoint, "check", "FAIL_NO_ENV")
        raise HTTPException(status_code=503, detail="관리자 기능 비활성화")
    if x_admin_key != _ADMIN_KEY:
        log_admin_access(ip, endpoint, "check", "FAIL_WRONG_KEY")
        raise HTTPException(status_code=403, detail="권한 없음")


class FoodPlaceSubmit(BaseModel):
    kakao_place_id: str
    name: str
    category: Optional[str] = None
    address: Optional[str] = None
    phone: Optional[str] = None
    url: Optional[str] = None
    memo: Optional[str] = None

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

# ── 팬 맛집 제안 ──────────────────────────────────────────────────────────────

@router.get("/{stadium_id}/food-places/search")
def search_food_place(stadium_id: int, q: str, radius: int = 2000):
    """팬 등록용 카카오 키워드 검색 (존재 확인)"""
    coords = _STADIUM_COORDS.get(stadium_id)
    if not coords:
        raise HTTPException(status_code=404, detail="구장 없음")
    lat, lng = coords
    try:
        res = _req.get(
            "https://dapi.kakao.com/v2/local/search/keyword.json",
            params={"query": q, "x": lng, "y": lat, "radius": radius, "sort": "distance", "size": 10},
            headers={"Authorization": f"KakaoAK {_KAKAO_REST_KEY}"},
            timeout=6,
        )
        docs = res.json().get("documents", [])
        food_cats = ("음식점", "카페", "제과", "편의점")
        return {
            "places": [
                {
                    "id":       d["id"],
                    "name":     d["place_name"],
                    "category": d["category_name"].split(" > ")[-1] if d["category_name"] else "",
                    "address":  d["road_address_name"] or d["address_name"],
                    "phone":    d["phone"],
                    "distance": int(d["distance"]) if d["distance"] else 0,
                    "url":      d["place_url"],
                }
                for d in docs
                if any(c in d["category_name"] for c in food_cats)
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@router.post("/{stadium_id}/food-places")
def submit_food_place(
    stadium_id: int,
    body: FoodPlaceSubmit,
    current_user: dict = Depends(get_current_user),
):
    """팬 맛집 제안 (pending_vote 상태로 등록)"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute(
        "SELECT id FROM stadium_food_places WHERE stadium_id=%s AND kakao_place_id=%s AND status != 'rejected'",
        (stadium_id, body.kakao_place_id),
    )
    if cur.fetchone():
        cur.close(); conn.close()
        raise HTTPException(status_code=409, detail="이미 등록된 장소입니다")
    cur.execute("""
        INSERT INTO stadium_food_places
            (stadium_id, submitted_by, kakao_place_id, name, category, address, phone, url, memo, status)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'pending_vote')
        RETURNING id
    """, (
        stadium_id, current_user["user_id"], body.kakao_place_id,
        body.name, body.category, body.address, body.phone, body.url, body.memo,
    ))
    place_id = cur.fetchone()[0]
    conn.commit(); cur.close(); conn.close()
    return {"id": place_id, "status": "pending_vote"}


@router.get("/{stadium_id}/food-places/community")
def get_community_food(stadium_id: int):
    """팬 추천 맛집 목록 (approved + pending_vote)"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("""
        SELECT f.id, f.name, f.category, f.address, f.phone, f.url, f.memo,
               f.status, f.upvote_count, u.nickname
        FROM stadium_food_places f
        JOIN users u ON f.submitted_by = u.id
        WHERE f.stadium_id = %s AND f.status IN ('approved', 'pending_vote')
        ORDER BY (f.status = 'approved') DESC, f.upvote_count DESC, f.created_at DESC
    """, (stadium_id,))
    rows = cur.fetchall()
    cur.close(); conn.close()
    return {
        "places": [
            {
                "id": r[0], "name": r[1], "category": r[2], "address": r[3],
                "phone": r[4] or "", "url": r[5] or "", "memo": r[6] or "",
                "status": r[7], "upvote_count": r[8], "submitted_by": r[9],
            }
            for r in rows
        ]
    }


@router.post("/food-places/{place_id}/vote")
def vote_food_place(place_id: int, current_user: dict = Depends(get_current_user)):
    """팬 맛집 투표 (토글)"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute(
        "SELECT id FROM stadium_food_votes WHERE place_id=%s AND user_id=%s",
        (place_id, current_user["user_id"]),
    )
    if cur.fetchone():
        cur.execute("DELETE FROM stadium_food_votes WHERE place_id=%s AND user_id=%s",
                    (place_id, current_user["user_id"]))
        cur.execute("UPDATE stadium_food_places SET upvote_count = GREATEST(0, upvote_count - 1) WHERE id=%s",
                    (place_id,))
        conn.commit(); cur.close(); conn.close()
        return {"voted": False}

    cur.execute("INSERT INTO stadium_food_votes (place_id, user_id) VALUES (%s, %s)",
                (place_id, current_user["user_id"]))
    cur.execute("""
        UPDATE stadium_food_places
        SET upvote_count = upvote_count + 1,
            status = CASE
                WHEN upvote_count + 1 >= %s AND status = 'pending_vote' THEN 'pending_admin'
                ELSE status END
        WHERE id = %s
    """, (_VOTE_THRESHOLD, place_id))
    conn.commit(); cur.close(); conn.close()
    return {"voted": True}


@router.put("/food-places/{place_id}/admin")
def admin_update_food_place(
    place_id: int, action: str, request: Request,
    x_admin_key: Optional[str] = Header(None)
):
    """관리자 승인/거절 (X-Admin-Key 헤더 필수)"""
    ip = request.headers.get("X-Real-IP") or request.client.host
    _check_admin(x_admin_key, ip, f"PUT /food-places/{place_id}/admin")
    if action not in ("approve", "reject"):
        raise HTTPException(status_code=400, detail="action은 approve 또는 reject")
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    new_status = "approved" if action == "approve" else "rejected"
    cur.execute("UPDATE stadium_food_places SET status=%s WHERE id=%s RETURNING id", (new_status, place_id))
    if not cur.fetchone():
        cur.close(); conn.close()
        raise HTTPException(status_code=404, detail="장소 없음")
    conn.commit(); cur.close(); conn.close()
    log_admin_access(ip, f"PUT /food-places/{place_id}/admin", action, "OK")
    return {"status": new_status}


@router.get("/food-places/pending")
def admin_pending_food(
    request: Request,
    x_admin_key: Optional[str] = Header(None)
):
    """관리자용 pending 목록 (X-Admin-Key 헤더 필수)"""
    ip = request.headers.get("X-Real-IP") or request.client.host
    _check_admin(x_admin_key, ip, "GET /food-places/pending")
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("""
        SELECT f.id, f.stadium_id, s.name AS stadium_name,
               f.name, f.category, f.address, f.memo, f.status, f.upvote_count, u.nickname
        FROM stadium_food_places f
        JOIN users u ON f.submitted_by = u.id
        JOIN stadiums s ON f.stadium_id = s.id
        WHERE f.status IN ('pending_vote', 'pending_admin')
        ORDER BY f.status='pending_admin' DESC, f.upvote_count DESC
    """)
    rows = cur.fetchall()
    cur.close(); conn.close()
    return {
        "places": [
            {"id": r[0], "stadium_id": r[1], "stadium": r[2], "name": r[3], "category": r[4],
             "address": r[5], "memo": r[6], "status": r[7], "upvotes": r[8], "submitted_by": r[9]}
            for r in rows
        ]
    }
