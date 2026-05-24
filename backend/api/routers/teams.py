from fastapi import APIRouter, HTTPException
from database.connection import get_connection

router = APIRouter()


def _calc_streak(team_id, cur):
    cur.execute("""
        SELECT home_team_id, away_team_id, home_score, away_score
        FROM games
        WHERE (home_team_id = %s OR away_team_id = %s)
          AND status = '종료'
          AND home_score != away_score
        ORDER BY game_date DESC, id DESC
        LIMIT 20
    """, (team_id, team_id))
    games = cur.fetchall()
    if not games:
        return 0
    streak = 0
    first_result = None
    for home_id, away_id, hs, as_ in games:
        win = (home_id == team_id and hs > as_) or (away_id == team_id and as_ > hs)
        if first_result is None:
            first_result = win
            streak = 1
        elif win == first_result:
            streak += 1
        else:
            break
    return streak if first_result else -streak


def _calc_recent_5(team_id, cur):
    cur.execute("""
        SELECT home_team_id, away_team_id, home_score, away_score
        FROM games
        WHERE (home_team_id = %s OR away_team_id = %s)
          AND status = '종료'
        ORDER BY game_date DESC, id DESC
        LIMIT 5
    """, (team_id, team_id))
    result = []
    for home_id, away_id, hs, as_ in cur.fetchall():
        if hs == as_:
            result.append('D')
        elif (home_id == team_id and hs > as_) or (away_id == team_id and as_ > hs):
            result.append('W')
        else:
            result.append('L')
    return result


def _calc_last_series(team_id, cur):
    """최근 시리즈 결과: 같은 상대팀과 연속 경기 그룹"""
    cur.execute("""
        SELECT home_team_id, away_team_id, home_score, away_score
        FROM games
        WHERE (home_team_id = %s OR away_team_id = %s)
          AND status = '종료'
        ORDER BY game_date DESC, id DESC
        LIMIT 10
    """, (team_id, team_id))
    games = cur.fetchall()
    if not games:
        return None

    # 첫 경기 상대팀 기준으로 연속 경기 묶기
    first = games[0]
    opponent_id = first[1] if first[0] == team_id else first[0]

    series_games = []
    for home_id, away_id, hs, as_ in games:
        opp = away_id if home_id == team_id else home_id
        if opp != opponent_id:
            break
        if hs == as_:
            series_games.append('D')
        elif (home_id == team_id and hs > as_) or (away_id == team_id and as_ > hs):
            series_games.append('W')
        else:
            series_games.append('L')

    wins = series_games.count('W')
    losses = series_games.count('L')
    total = len(series_games)

    if total == 0:
        return None

    if losses == 0 and wins >= 3:
        label = '스윕 승'
    elif wins >= 2 and losses > 0 and wins > losses:
        label = '위닝 시리즈'
    elif wins == losses:
        label = '스플릿'
    elif wins == 0 and losses >= 3:
        label = '스윕 패'
    elif losses > wins:
        label = '루징 시리즈'
    else:
        label = None

    return {
        "wins": wins,
        "losses": losses,
        "games": total,
        "label": label,
        "opponent_id": opponent_id,
    }


def _calc_pythagorean(team_id, cur) -> float | None:
    cur.execute("""
        SELECT
            SUM(CASE WHEN home_team_id=%s THEN home_score ELSE away_score END),
            SUM(CASE WHEN home_team_id=%s THEN away_score ELSE home_score END)
        FROM games
        WHERE (home_team_id=%s OR away_team_id=%s) AND status='종료'
    """, (team_id, team_id, team_id, team_id))
    row = cur.fetchone()
    rs, ra = (row[0] or 0), (row[1] or 0)
    if rs == 0 and ra == 0:
        return None
    denom = rs ** 2 + ra ** 2
    return round(rs ** 2 / denom, 3) if denom > 0 else None


def _calc_home_away(team_id, cur):
    cur.execute("""
        SELECT
            SUM(CASE WHEN home_team_id=%s AND home_score>away_score THEN 1 ELSE 0 END),
            SUM(CASE WHEN home_team_id=%s AND home_score<away_score THEN 1 ELSE 0 END),
            SUM(CASE WHEN home_team_id=%s AND home_score=away_score THEN 1 ELSE 0 END),
            SUM(CASE WHEN away_team_id=%s AND away_score>home_score THEN 1 ELSE 0 END),
            SUM(CASE WHEN away_team_id=%s AND away_score<home_score THEN 1 ELSE 0 END),
            SUM(CASE WHEN away_team_id=%s AND away_score=home_score THEN 1 ELSE 0 END)
        FROM games
        WHERE (home_team_id=%s OR away_team_id=%s) AND status='종료'
    """, (team_id,) * 8)
    row = cur.fetchone()
    return {
        "home": {"wins": int(row[0] or 0), "losses": int(row[1] or 0), "draws": int(row[2] or 0)},
        "away": {"wins": int(row[3] or 0), "losses": int(row[4] or 0), "draws": int(row[5] or 0)},
    }


@router.get("/rankings")
def get_team_rankings():
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
        wins    = r[3] or 0
        losses  = r[4] or 0
        draws   = r[5] or 0
        rank    = r[6]
        gb      = float(r[7]) if r[7] else 0

        streak        = _calc_streak(team_id, cur)
        recent_5      = _calc_recent_5(team_id, cur)
        home_away     = _calc_home_away(team_id, cur)
        last_series   = _calc_last_series(team_id, cur)
        pythag_winpct = _calc_pythagorean(team_id, cur)

        result.append({
            "id":           team_id,
            "name":         r[1],
            "short_name":   r[2],
            "wins":         wins,
            "losses":       losses,
            "draws":        draws,
            "total_games":  wins + losses + draws,
            "rank":         rank,
            "games_behind": None if rank == 1 else gb,
            "win_rate":     float(r[8]) if r[8] else 0,
            "logo_url":     r[9],
            "streak":       streak,
            "recent_5":     recent_5,
            "home_record":  home_away["home"],
            "away_record":  home_away["away"],
            "last_series":  last_series,
            "pythag_winpct": pythag_winpct,
        })

    cur.close()
    conn.close()
    return {"count": len(result), "rankings": result}


@router.get("/")
def get_teams():
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
            {"id": r[0], "name": r[1], "player_type": r[2], "position": r[3], "number": r[4]}
            for r in rows
        ]
    }


@router.get("/{team_id}/games")
def get_team_games(team_id: int, limit: int = 10):
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


@router.get("/{team_id}/roster-changes")
def get_roster_changes(team_id: int, days: int = 30):
    """팀 등록말소 이력 (최근 N일)"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("""
        SELECT rc.id, rc.player_name, rc.player_id, rc.change_type,
               rc.reason, rc.change_date,
               p.position, p.player_type, p.profile_image
        FROM player_roster_changes rc
        LEFT JOIN players p ON p.id = rc.player_id
        WHERE rc.team_id = %s
          AND rc.change_date >= CURRENT_DATE - %s
        ORDER BY rc.change_date DESC, rc.id DESC
    """, (team_id, days))
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {
        "team_id": team_id,
        "changes": [
            {
                "id":           r[0],
                "player_name":  r[1],
                "player_id":    r[2],
                "change_type":  r[3],
                "reason":       r[4],
                "change_date":  str(r[5]),
                "position":     r[6],
                "player_type":  r[7],
                "profile_image": r[8],
            }
            for r in rows
        ]
    }


@router.get("/{team_id}/monthly-stats")
def get_team_monthly_stats(team_id: int, season: int = 2026):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("""
        SELECT
            EXTRACT(MONTH FROM game_date)::int AS month,
            COUNT(*) FILTER (
                WHERE (home_team_id = %s AND home_score > away_score)
                   OR (away_team_id = %s AND away_score > home_score)
            ) AS wins,
            COUNT(*) FILTER (
                WHERE (home_team_id = %s AND home_score < away_score)
                   OR (away_team_id = %s AND away_score < home_score)
            ) AS losses,
            COUNT(*) FILTER (WHERE status = '종료') AS games
        FROM games
        WHERE (home_team_id = %s OR away_team_id = %s)
          AND status = '종료'
          AND EXTRACT(YEAR FROM game_date) = %s
        GROUP BY 1
        ORDER BY 1
    """, (team_id, team_id, team_id, team_id, team_id, team_id, season))
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {
        "team_id": team_id,
        "season": season,
        "monthly": [
            {
                "month": r[0],
                "wins": r[1],
                "losses": r[2],
                "games": r[3],
                "win_rate": round(r[1] / r[3], 3) if r[3] > 0 else 0.0,
            }
            for r in rows
        ],
    }


@router.get("/{team_id}/head-to-head")
def get_head_to_head(team_id: int, season: int = 2026):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("""
        SELECT
            opp.id AS opp_id,
            opp.name AS opp_name,
            opp.short_name AS opp_code,
            COUNT(*) AS total,
            COUNT(*) FILTER (
                WHERE (g.home_team_id = %s AND g.home_score > g.away_score)
                   OR (g.away_team_id = %s AND g.away_score > g.home_score)
            ) AS wins,
            COUNT(*) FILTER (
                WHERE (g.home_team_id = %s AND g.home_score < g.away_score)
                   OR (g.away_team_id = %s AND g.away_score < g.home_score)
            ) AS losses,
            COUNT(*) FILTER (WHERE g.home_score = g.away_score) AS draws,
            COALESCE(SUM(
                CASE WHEN g.home_team_id = %s THEN g.home_score ELSE g.away_score END
            ), 0) AS runs_scored,
            COALESCE(SUM(
                CASE WHEN g.home_team_id = %s THEN g.away_score ELSE g.home_score END
            ), 0) AS runs_allowed
        FROM games g
        JOIN teams opp ON opp.id = CASE
            WHEN g.home_team_id = %s THEN g.away_team_id
            ELSE g.home_team_id
        END
        WHERE (g.home_team_id = %s OR g.away_team_id = %s)
          AND g.status = '종료'
          AND g.home_score IS NOT NULL
          AND EXTRACT(YEAR FROM g.game_date) = %s
        GROUP BY opp.id, opp.name, opp.short_name
        ORDER BY wins DESC, losses ASC
    """, (team_id, team_id, team_id, team_id, team_id, team_id, team_id, team_id, team_id, season))
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {
        "team_id": team_id,
        "season": season,
        "records": [
            {
                "opp_id":      r[0],
                "opp_name":    r[1],
                "opp_code":    r[2],
                "total":       r[3],
                "wins":        r[4],
                "losses":      r[5],
                "draws":       r[6],
                "runs_scored": r[7],
                "runs_allowed":r[8],
                "win_rate":    round(r[4] / r[3], 3) if r[3] > 0 else 0.0,
            }
            for r in rows
        ],
    }


@router.get("/roster-changes/today")
def get_today_roster_changes():
    """오늘 전체 팀 등록말소"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("""
        SELECT rc.player_name, rc.player_id, rc.change_type, rc.reason,
               t.name AS team_name, t.short_name AS team_code, rc.team_id,
               p.position, p.player_type
        FROM player_roster_changes rc
        LEFT JOIN teams t ON t.id = rc.team_id
        LEFT JOIN players p ON p.id = rc.player_id
        WHERE rc.change_date = CURRENT_DATE
        ORDER BY rc.change_type, t.name, rc.player_name
    """)
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {
        "date": str(__import__('datetime').date.today()),
        "changes": [
            {
                "player_name":  r[0],
                "player_id":    r[1],
                "change_type":  r[2],
                "reason":       r[3],
                "team_name":    r[4],
                "team_code":    r[5],
                "team_id":      r[6],
                "position":     r[7],
                "player_type":  r[8],
            }
            for r in rows
        ]
    }
