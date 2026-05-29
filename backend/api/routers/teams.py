from fastapi import APIRouter, HTTPException, Depends
from database.connection import get_connection
from api.routers.auth import get_current_user, get_optional_user
from api.cache import cached

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
@cached(60)
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
@cached(3600)
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
        WITH deduped AS (
            SELECT rc.id, rc.player_name, rc.player_id, rc.change_type,
                   rc.reason, rc.change_date,
                   ROW_NUMBER() OVER (
                       PARTITION BY rc.player_name, rc.change_type
                       ORDER BY rc.change_date DESC, rc.id DESC
                   ) AS rn
            FROM player_roster_changes rc
            WHERE rc.team_id = %s
              AND rc.change_date >= CURRENT_DATE - %s
        )
        SELECT d.id, d.player_name, d.player_id, d.change_type, d.reason, d.change_date,
               p.position, p.player_type, p.profile_image
        FROM deduped d
        LEFT JOIN players p ON p.id = d.player_id
        WHERE d.rn = 1
        ORDER BY d.change_date DESC, d.id DESC
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


@router.get("/{team_id}/batting-order")
def get_batting_order_stats(team_id: int, season: int = 2026):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    # 타순별 집계
    cur.execute("""
        SELECT
            gb.batting_order,
            COUNT(DISTINCT gb.game_id) AS games,
            SUM(gb.at_bats)    AS at_bats,
            SUM(gb.hits)       AS hits,
            SUM(gb.runs)       AS runs,
            SUM(gb.rbis)       AS rbis,
            SUM(gb.home_runs)  AS home_runs,
            SUM(gb.walks)      AS walks,
            SUM(gb.strikeouts) AS strikeouts
        FROM game_batters gb
        JOIN games g ON g.id = gb.game_id
        WHERE ((g.home_team_id = %s AND gb.team_side = 'home')
            OR (g.away_team_id = %s AND gb.team_side = 'away'))
          AND g.status = '종료'
          AND EXTRACT(YEAR FROM g.game_date) = %s
          AND gb.batting_order BETWEEN 1 AND 9
        GROUP BY gb.batting_order
        ORDER BY gb.batting_order
    """, (team_id, team_id, season))
    rows = cur.fetchall()

    # 타순별 최다 출전 선수
    cur.execute("""
        WITH slot_players AS (
            SELECT gb.batting_order, p.id AS player_id, p.name AS player_name, p.profile_image,
                   COUNT(*) AS apps,
                   ROW_NUMBER() OVER (
                       PARTITION BY gb.batting_order ORDER BY COUNT(*) DESC
                   ) AS rn
            FROM game_batters gb
            JOIN games g ON g.id = gb.game_id
            JOIN players p ON p.id = gb.player_id
            WHERE ((g.home_team_id = %s AND gb.team_side = 'home')
                OR (g.away_team_id = %s AND gb.team_side = 'away'))
              AND g.status = '종료'
              AND EXTRACT(YEAR FROM g.game_date) = %s
              AND gb.batting_order BETWEEN 1 AND 9
              AND gb.at_bats > 0
            GROUP BY gb.batting_order, p.id, p.name, p.profile_image
        )
        SELECT batting_order, player_id, player_name, profile_image FROM slot_players WHERE rn = 1
    """, (team_id, team_id, season))
    top_players = {r[0]: (r[1], r[2], r[3]) for r in cur.fetchall()}  # order → (id, name, image)

    cur.close()
    conn.close()

    stats = []
    for r in rows:
        order, games, ab, h, runs, rbi, hr, bb, so = r
        avg = round(h / ab, 3) if ab > 0 else 0.0
        obp = round((h + bb) / (ab + bb), 3) if (ab + bb) > 0 else 0.0
        slg = round((h + hr) / ab, 3) if ab > 0 else 0.0  # simplified (no 2B/3B)
        tp = top_players.get(order, (None, None, None))
        stats.append({
            "batting_order":    order,
            "games":            games,
            "at_bats":          ab,
            "hits":             h,
            "runs":             runs,
            "rbis":             rbi,
            "home_runs":        hr,
            "walks":            bb,
            "strikeouts":       so,
            "avg":              avg,
            "obp":              obp,
            "top_player":       tp[1],
            "top_player_id":    tp[0],
            "top_player_image": tp[2],
        })
    return {"team_id": team_id, "season": season, "stats": stats}


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


@router.get("/{team_id}/season-stats")
@cached(300)
def get_team_season_stats(team_id: int, season: int = 2026):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()

    # 팀 승패 + 득실점
    cur.execute("""
        SELECT
            SUM(CASE WHEN (home_team_id=%s AND home_score>away_score)
                       OR (away_team_id=%s AND away_score>home_score) THEN 1 ELSE 0 END) AS wins,
            SUM(CASE WHEN (home_team_id=%s AND home_score<away_score)
                       OR (away_team_id=%s AND away_score<home_score) THEN 1 ELSE 0 END) AS losses,
            SUM(CASE WHEN home_score=away_score THEN 1 ELSE 0 END) AS draws,
            SUM(CASE WHEN home_team_id=%s THEN home_score ELSE away_score END) AS runs_scored,
            SUM(CASE WHEN home_team_id=%s THEN away_score ELSE home_score END) AS runs_allowed,
            COUNT(*) AS total_games
        FROM games
        WHERE (home_team_id=%s OR away_team_id=%s)
          AND status='종료'
          AND EXTRACT(YEAR FROM game_date)=%s
    """, (team_id,)*8 + (season,))
    gr = cur.fetchone()
    wins = int(gr[0] or 0)
    losses = int(gr[1] or 0)
    draws = int(gr[2] or 0)
    runs_scored = int(gr[3] or 0)
    runs_allowed = int(gr[4] or 0)
    total_games = int(gr[5] or 0)

    # 팀 타격 집계 (batter_stats — doubles/triples 있음)
    cur.execute("""
        SELECT
            SUM(bs.at_bats)      AS ab,
            SUM(bs.hits)         AS h,
            SUM(bs.doubles)      AS d2,
            SUM(bs.triples)      AS d3,
            SUM(bs.home_runs)    AS hr,
            SUM(bs.rbis)         AS rbi,
            SUM(bs.walks)        AS bb,
            SUM(bs.strikeouts)   AS so,
            SUM(bs.runs)         AS runs,
            SUM(bs.stolen_bases) AS sb
        FROM batter_stats bs
        JOIN players p ON p.id = bs.player_id
        WHERE p.team_id = %s
          AND bs.season = %s
    """, (team_id, season))
    br = cur.fetchone()
    ab = int(br[0] or 0); h = int(br[1] or 0); d2 = int(br[2] or 0)
    d3 = int(br[3] or 0); hr = int(br[4] or 0); rbi = int(br[5] or 0)
    bb = int(br[6] or 0); so = int(br[7] or 0)
    b_runs = int(br[8] or 0); sb = int(br[9] or 0)
    avg = round(h / ab, 3) if ab > 0 else 0.0
    obp = round((h + bb) / (ab + bb), 3) if (ab + bb) > 0 else 0.0
    tb = h + d2 + 2*d3 + 3*hr
    slg = round(tb / ab, 3) if ab > 0 else 0.0
    ops = round(obp + slg, 3)

    # 팀 투구 집계 (game_pitchers)
    cur.execute("""
        SELECT
            SUM(gp.innings_pitched) AS ip,
            SUM(gp.earned_runs)     AS er,
            SUM(gp.hits_allowed)    AS ha,
            SUM(gp.walks)           AS bb,
            SUM(gp.strikeouts)      AS so,
            SUM(gp.home_runs_allowed) AS hra
        FROM game_pitchers gp
        JOIN games g ON g.id = gp.game_id
        WHERE ((g.home_team_id = %s AND gp.team_side = 'home')
            OR (g.away_team_id = %s AND gp.team_side = 'away'))
          AND g.status = '종료'
          AND EXTRACT(YEAR FROM g.game_date) = %s
    """, (team_id, team_id, season))
    pr = cur.fetchone()
    ip = float(pr[0] or 0); er = int(pr[1] or 0)
    ha = int(pr[2] or 0); p_bb = int(pr[3] or 0)
    p_so = int(pr[4] or 0); hra = int(pr[5] or 0)
    era = round(er / ip * 9, 2) if ip > 0 else 0.0
    whip = round((ha + p_bb) / ip, 2) if ip > 0 else 0.0

    cur.close()
    conn.close()

    run_diff = runs_scored - runs_allowed
    rpg = round(runs_scored / total_games, 2) if total_games > 0 else 0.0
    rapg = round(runs_allowed / total_games, 2) if total_games > 0 else 0.0
    denom = runs_scored**2 + runs_allowed**2
    pythag = round(runs_scored**2 / denom, 3) if denom > 0 else None

    return {
        "team_id": team_id,
        "season": season,
        "record": {
            "wins": wins, "losses": losses, "draws": draws,
            "total_games": total_games,
            "runs_scored": runs_scored, "runs_allowed": runs_allowed,
            "run_diff": run_diff, "rpg": rpg, "rapg": rapg,
            "pythag_winpct": pythag,
        },
        "batting": {
            "avg": avg, "obp": obp, "slg": slg, "ops": ops,
            "hits": h, "home_runs": hr, "rbis": rbi,
            "walks": bb, "strikeouts": so, "runs": b_runs, "stolen_bases": sb,
        },
        "pitching": {
            "era": era, "whip": whip,
            "innings_pitched": round(ip, 1),
            "strikeouts": p_so, "walks": p_bb,
            "hits_allowed": ha, "home_runs_allowed": hra,
        },
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


# ===== 팀 인기투표 =====

@router.get("/popularity")
def get_team_popularity(current_user: dict | None = Depends(get_optional_user)):
    """팀 인기투표 랭킹"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    uid = current_user['user_id'] if current_user else None
    cur.execute("""
        SELECT t.id, t.name, t.short_name, t.logo_url,
               COUNT(v.id) AS vote_count,
               %s IS NOT NULL AND EXISTS(
                   SELECT 1 FROM team_popularity_votes
                   WHERE user_id=%s AND team_id=t.id
               ) AS voted
        FROM teams t
        LEFT JOIN team_popularity_votes v ON v.team_id = t.id
        GROUP BY t.id
        ORDER BY vote_count DESC, t.name
    """, (uid, uid))
    rows = cur.fetchall()
    cur.close(); conn.close()
    return {
        "teams": [
            {"id": r[0], "name": r[1], "short_name": r[2], "logo_url": r[3],
             "vote_count": r[4], "voted": r[5]}
            for r in rows
        ]
    }


@router.post("/{team_id}/vote")
def vote_team(team_id: int, current_user: dict = Depends(get_current_user)):
    """팀 인기투표 토글 (하트)"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    uid = current_user['user_id']
    cur.execute("SELECT id FROM team_popularity_votes WHERE user_id=%s AND team_id=%s", (uid, team_id))
    existing = cur.fetchone()
    if existing:
        cur.execute("DELETE FROM team_popularity_votes WHERE user_id=%s AND team_id=%s", (uid, team_id))
        voted = False
    else:
        cur.execute("INSERT INTO team_popularity_votes (user_id, team_id) VALUES (%s, %s)", (uid, team_id))
        voted = True
    conn.commit()
    cur.execute("SELECT COUNT(*) FROM team_popularity_votes WHERE team_id=%s", (team_id,))
    count = cur.fetchone()[0]
    cur.close(); conn.close()
    return {"voted": voted, "vote_count": count}
