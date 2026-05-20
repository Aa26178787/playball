from fastapi import APIRouter, HTTPException
from database.connection import get_connection

router = APIRouter()


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