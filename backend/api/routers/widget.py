from fastapi import APIRouter, HTTPException
from database.connection import get_connection

router = APIRouter()


@router.get("/live-scores")
def get_live_scores():
    """위젯용 실시간 스코어 (오늘 경기 전체)"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("""
        SELECT
            g.id,
            g.status,
            g.home_score,
            g.away_score,
            g.current_inning,
            g.inning_half,
            g.start_time,
            ht.name AS home_team,
            ht.short_name AS home_code,
            ht.logo_url AS home_logo,
            at.name AS away_team,
            at.short_name AS away_code,
            at.logo_url AS away_logo,
            s.name AS stadium,
            g.updated_at
        FROM games g
        JOIN teams ht ON g.home_team_id = ht.id
        JOIN teams at ON g.away_team_id = at.id
        LEFT JOIN stadiums s ON g.stadium_id = s.id
        WHERE g.game_date = CURRENT_DATE
        ORDER BY g.status DESC, g.id
    """)

    rows = cur.fetchall()
    cur.close()
    conn.close()

    games = []
    for r in rows:
        games.append({
            "id":             r[0],
            "status":         r[1],
            "home_score":     r[2],
            "away_score":     r[3],
            "current_inning": r[4],
            "inning_half":    r[5],
            "start_time":     str(r[6]) if r[6] else None,
            "home_team":      r[7],
            "home_code":      r[8],
            "home_logo":      r[9],
            "away_team":      r[10],
            "away_code":      r[11],
            "away_logo":      r[12],
            "stadium":        r[13],
            "updated_at":     str(r[14]) if r[14] else None,
        })

    return {
        "date":  str(__import__('datetime').date.today()),
        "count": len(games),
        "games": games
    }


@router.get("/live-scores/{game_id}")
def get_live_score_detail(game_id: int):
    """위젯용 특정 경기 실시간 스코어"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()

    # 경기 기본 정보
    cur.execute("""
        SELECT
            g.id, g.status, g.home_score, g.away_score,
            g.current_inning, g.inning_half,
            g.home_hits, g.away_hits,
            g.home_errors, g.away_errors,
            ht.name AS home_team, ht.short_name AS home_code,
            at.name AS away_team, at.short_name AS away_code,
            g.updated_at
        FROM games g
        JOIN teams ht ON g.home_team_id = ht.id
        JOIN teams at ON g.away_team_id = at.id
        WHERE g.id = %s
    """, (game_id,))

    row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="경기를 찾을 수 없습니다")

    # 이닝별 스코어
    cur.execute("""
        SELECT inning, home_runs, away_runs
        FROM game_innings
        WHERE game_id = %s
        ORDER BY inning
    """, (game_id,))
    innings = cur.fetchall()

    # 현재 투수
    cur.execute("""
        SELECT p.name, gp.role, gp.result, gp.team_side
        FROM game_pitchers gp
        JOIN players p ON gp.player_id = p.id
        WHERE gp.game_id = %s
        ORDER BY gp.id DESC
        LIMIT 2
    """, (game_id,))
    pitchers = cur.fetchall()

    cur.close()
    conn.close()

    return {
        "id":             row[0],
        "status":         row[1],
        "home_score":     row[2],
        "away_score":     row[3],
        "current_inning": row[4],
        "inning_half":    row[5],
        "home_hits":      row[6],
        "away_hits":      row[7],
        "home_errors":    row[8],
        "away_errors":    row[9],
        "home_team":      row[10],
        "home_code":      row[11],
        "away_team":      row[12],
        "away_code":      row[13],
        "updated_at":     str(row[14]) if row[14] else None,
        "innings": [
            {"inning": r[0], "home_runs": r[1], "away_runs": r[2]}
            for r in innings
        ],
        "pitchers": [
            {
                "name":      r[0],
                "role":      r[1],
                "result":    r[2],
                "team_side": r[3],
            }
            for r in pitchers
        ]
    }


@router.get("/my-team-scores/{team_id}")
def get_my_team_score(team_id: int):
    """마이팀 오늘 경기 스코어 (위젯용)"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("""
        SELECT
            g.id, g.status,
            g.home_score, g.away_score,
            g.current_inning, g.inning_half,
            g.start_time,
            ht.name AS home_team,
            ht.short_name AS home_code,
            at.name AS away_team,
            at.short_name AS away_code,
            g.updated_at
        FROM games g
        JOIN teams ht ON g.home_team_id = ht.id
        JOIN teams at ON g.away_team_id = at.id
        WHERE g.game_date = CURRENT_DATE
        AND (g.home_team_id = %s OR g.away_team_id = %s)
        LIMIT 1
    """, (team_id, team_id))

    row = cur.fetchone()
    cur.close()
    conn.close()

    if not row:
        return {"message": "오늘 경기 없음", "game": None}

    return {
        "game": {
            "id":             row[0],
            "status":         row[1],
            "home_score":     row[2],
            "away_score":     row[3],
            "current_inning": row[4],
            "inning_half":    row[5],
            "start_time":     str(row[6]) if row[6] else None,
            "home_team":      row[7],
            "home_code":      row[8],
            "away_team":      row[9],
            "away_code":      row[10],
            "updated_at":     str(row[11]) if row[11] else None,
        }
    }