from fastapi import APIRouter, HTTPException
from database.connection import get_connection

router = APIRouter()


def _calc_streak(team_id, cur):
    """팀의 현재 연승/연패 계산"""
    cur.execute("""
        SELECT g.home_team_id, g.away_team_id, g.home_score, g.away_score
        FROM games g
        WHERE (g.home_team_id = %s OR g.away_team_id = %s)
        AND g.status = '종료'
        AND g.home_score != g.away_score
        ORDER BY g.game_date DESC, g.id DESC
        LIMIT 20
    """, (team_id, team_id))
    games = cur.fetchall()

    if not games:
        return 0

    streak = 0
    first_result = None

    for home_id, away_id, home_score, away_score in games:
        is_home = home_id == team_id
        win = (is_home and home_score > away_score) or \
              (not is_home and away_score > home_score)

        if first_result is None:
            first_result = win
            streak = 1
        elif win == first_result:
            streak += 1
        else:
            break

    # 양수=연승, 음수=연패
    return streak if first_result else -streak


@router.get("/rankings")
def get_team_rankings():
    """팀 순위표 - 연승/연패, 전체 게임수 포함"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("""
        SELECT id, name, short_name, wins, losses, draws,
               rank, games_behind, win_rate, logo_url
        FROM teams
        ORDER BY rank ASC NULLS LAST, wins DESC
    """)
    rows = cur.fetchall()

    result = []
    for r in rows:
        team_id = r[0]
        wins = r[3] or 0
        losses = r[4] or 0
        draws = r[5] or 0
        total_games = wins + losses + draws
        streak = _calc_streak(team_id, cur)

        result.append({
            "id":           team_id,
            "name":         r[1],
            "short_name":   r[2],
            "wins":         wins,
            "losses":       losses,
            "draws":        draws,
            "total_games":  total_games,
            "rank":         r[6],
            "games_behind": float(r[7]) if r[7] else 0,
            "win_rate":     float(r[8]) if r[8] else 0,
            "logo_url":     r[9],
            "streak":       streak,  # 양수=연승, 음수=연패, 0=해당없음
        })

    cur.close()
    conn.close()

    return {"count": len(result), "rankings": result}


@router.get("/")
def get_teams():
    """팀 목록"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("""
        SELECT id, name, short_name, wins, losses, draws,
               rank, games_behind, win_rate, logo_url
        FROM teams
        ORDER BY rank ASC NULLS LAST, wins DESC
    """)

    rows = cur.fetchall()
    cur.close()
    conn.close()

    return {
        "count": len(rows),
        "teams": [
            {
                "id":           r[0],
                "name":         r[1],
                "short_name":   r[2],
                "wins":         r[3],
                "losses":       r[4],
                "draws":        r[5],
                "rank":         r[6],
                "games_behind": float(r[7]) if r[7] else 0,
                "win_rate":     float(r[8]) if r[8] else 0,
                "logo_url":     r[9],
            }
            for r in rows
        ]
    }


@router.get("/{team_id}/players")
def get_team_players(team_id: int):
    """팀 선수 목록"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("SELECT id, name FROM teams WHERE id = %s", (team_id,))
    team = cur.fetchone()
    if not team:
        raise HTTPException(status_code=404, detail="팀을 찾을 수 없습니다")

    cur.execute("""
        SELECT id, name, player_type, position, number
        FROM players
        WHERE team_id = %s AND is_active = TRUE
        ORDER BY player_type, number
    """, (team_id,))

    rows = cur.fetchall()
    cur.close()
    conn.close()

    return {
        "team_id":   team[0],
        "team_name": team[1],
        "count":     len(rows),
        "players": [
            {
                "id":          r[0],
                "name":        r[1],
                "player_type": r[2],
                "position":    r[3],
                "number":      r[4],
            }
            for r in rows
        ]
    }


@router.get("/{team_id}/games")
def get_team_games(team_id: int, limit: int = 10):
    """팀 최근 경기 결과"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("SELECT id, name FROM teams WHERE id = %s", (team_id,))
    team = cur.fetchone()
    if not team:
        raise HTTPException(status_code=404, detail="팀을 찾을 수 없습니다")

    cur.execute("""
        SELECT
            g.id, g.game_date, g.status,
            g.home_score, g.away_score,
            ht.name AS home_team,
            at.name AS away_team
        FROM games g
        JOIN teams ht ON g.home_team_id = ht.id
        JOIN teams at ON g.away_team_id = at.id
        WHERE (g.home_team_id = %s OR g.away_team_id = %s)
          AND g.status = '종료'
        ORDER BY g.game_date DESC
        LIMIT %s
    """, (team_id, team_id, limit))

    rows = cur.fetchall()
    cur.close()
    conn.close()

    return {
        "team_id":   team[0],
        "team_name": team[1],
        "count":     len(rows),
        "games": [
            {
                "id":         r[0],
                "game_date":  str(r[1]),
                "status":     r[2],
                "home_score": r[3],
                "away_score": r[4],
                "home_team":  r[5],
                "away_team":  r[6],
            }
            for r in rows
        ]
    }