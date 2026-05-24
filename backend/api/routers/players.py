from fastapi import APIRouter, HTTPException
from database.connection import get_connection
from typing import Optional

router = APIRouter()

@router.get("/search")
def search_players(q: str, player_type: str = None):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    if player_type:
        cur.execute("""
            SELECT p.id, p.name, t.name AS team, p.player_type, 
                   p.position, p.number, p.profile_image, p.throws, p.bats
            FROM players p
            JOIN teams t ON p.team_id = t.id
            WHERE p.name LIKE %s AND p.player_type = %s
            ORDER BY p.name LIMIT 20
        """, (f"%{q}%", player_type))
    else:
        cur.execute("""
            SELECT p.id, p.name, t.name AS team, p.player_type,
                   p.position, p.number, p.profile_image, p.throws, p.bats
            FROM players p
            JOIN teams t ON p.team_id = t.id
            WHERE p.name LIKE %s
            ORDER BY p.name LIMIT 20
        """, (f"%{q}%",))
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {
        "players": [
            {
                "id": r[0], "name": r[1], "team": r[2],
                "player_type": r[3], "position": r[4],
                "number": r[5], "profile_image": r[6],
                "throws": r[7], "bats": r[8],
            }
            for r in rows
        ]
    }


@router.get("/hitters")
def get_hitters(
    season: int = 2026,
    limit: int = 100,
    team_id: Optional[int] = None,
    sort_by: str = "avg",
    position: Optional[str] = None,
    qualified: bool = False,
):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    sort_map = {
        "avg":           "avg DESC NULLS LAST",
        "home_runs":     "home_runs DESC NULLS LAST",
        "rbis":          "rbis DESC NULLS LAST",
        "hits":          "hits DESC NULLS LAST",
        "stolen_bases":  "stolen_bases DESC NULLS LAST",
        "ops":           "ops DESC NULLS LAST",
        "war":           "war DESC NULLS LAST",
    }
    order = sort_map.get(sort_by, "avg DESC NULLS LAST")
    team_filter = "AND p.team_id = %s" if team_id else ""
    position_filter = "AND p.position = %s" if position else ""

    if qualified:
        qual_filter = f"""
            AND bs.pa >= (
                SELECT MAX(games) FROM batter_stats WHERE season = {season}
            ) * 3.1
        """
    else:
        qual_filter = ""

    params = [season] + ([team_id] if team_id else []) + ([position] if position else []) + [limit]

    cur = conn.cursor()
    cur.execute(f"""
        SELECT * FROM (
            SELECT DISTINCT ON (p.id)
                p.id, p.name, t.name AS team,
                p.profile_image,
                bs.games, bs.at_bats, bs.hits,
                bs.home_runs, bs.rbis, bs.runs,
                bs.walks, bs.strikeouts, bs.stolen_bases,
                bs.avg, bs.obp, bs.slg, bs.ops,
                bs.woba, bs.wrc_plus, bs.babip, bs.iso, bs.war,
                p.position, t.short_name AS team_code
            FROM batter_stats bs
            JOIN players p ON bs.player_id = p.id
            JOIN teams t ON p.team_id = t.id
            WHERE bs.season = %s {team_filter} {position_filter}
            AND p.player_type = '타자'
            {qual_filter}
            ORDER BY p.id
            LIMIT 1000
        ) sub
        ORDER BY {order}
        LIMIT %s
    """, params)

    rows = cur.fetchall()
    cur.close()
    conn.close()

    return {
        "season": season,
        "count": len(rows),
        "hitters": [
            {
                "id": r[0], "name": r[1], "team": r[2],
                "profile_image": r[3], "games": r[4],
                "at_bats": r[5], "hits": r[6],
                "home_runs": r[7], "rbis": r[8], "runs": r[9],
                "walks": r[10], "strikeouts": r[11], "stolen_bases": r[12],
                "avg":      float(r[13]) if r[13] else 0,
                "obp":      float(r[14]) if r[14] else 0,
                "slg":      float(r[15]) if r[15] else 0,
                "ops":      float(r[16]) if r[16] else 0,
                "woba":     float(r[17]) if r[17] else 0,
                "wrc_plus": r[18],
                "babip":    float(r[19]) if r[19] else 0,
                "iso":      float(r[20]) if r[20] else 0,
                "war":      float(r[21]) if r[21] else 0,
                "position": r[22],
                "team_code": r[23],
            }
            for r in rows
        ]
    }


@router.get("/pitchers")
def get_pitchers(
    season: int = 2026,
    limit: int = 100,
    team_id: Optional[int] = None,
    sort_by: str = "era",
    throws: Optional[str] = None,
    qualified: bool = False,
):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    sort_map = {
        "era":        "era ASC NULLS LAST",
        "wins":       "wins DESC NULLS LAST",
        "strikeouts": "strikeouts DESC NULLS LAST",
        "whip":       "whip ASC NULLS LAST",
        "saves":      "saves DESC NULLS LAST",
        "holds":      "holds DESC NULLS LAST",
        "war":        "war DESC NULLS LAST",
    }
    order = sort_map.get(sort_by, "era ASC NULLS LAST")
    team_filter = "AND p.team_id = %s" if team_id else ""
    throws_filter = "AND p.throws = %s" if throws else ""

    if qualified:
        qual_filter = f"""
            AND ps.innings_pitched >= (
                SELECT MAX(games) FROM batter_stats WHERE season = {season}
            ) * 1.0
        """
    else:
        qual_filter = ""

    params = [season] + ([team_id] if team_id else []) + ([throws] if throws else []) + [limit]

    cur = conn.cursor()
    cur.execute(f"""
        SELECT * FROM (
            SELECT DISTINCT ON (p.id)
                p.id, p.name, t.name AS team,
                p.profile_image,
                ps.games, ps.wins, ps.losses,
                ps.saves, ps.holds, ps.innings_pitched,
                ps.strikeouts, ps.walks,
                ps.hits_allowed, ps.home_runs_allowed,
                ps.era, ps.whip, ps.fip,
                ps.k_per_9, ps.bb_per_9, ps.babip, ps.war,
                ps.blown_saves, ps.qs,
                p.throws, t.short_name AS team_code
            FROM pitcher_stats ps
            JOIN players p ON ps.player_id = p.id
            JOIN teams t ON p.team_id = t.id
            WHERE ps.season = %s {team_filter} {throws_filter}
            AND p.player_type = '투수'
            {qual_filter}
            ORDER BY p.id
            LIMIT 1000
        ) sub
        ORDER BY {order}
        LIMIT %s
    """, params)

    rows = cur.fetchall()
    cur.close()
    conn.close()

    return {
        "season": season,
        "count": len(rows),
        "pitchers": [
            {
                "id": r[0], "name": r[1], "team": r[2],
                "profile_image": r[3], "games": r[4],
                "wins": r[5], "losses": r[6],
                "saves": r[7], "holds": r[8],
                "innings_pitched":   float(r[9]) if r[9] else 0,
                "strikeouts": r[10], "walks": r[11],
                "hits_allowed": r[12], "home_runs_allowed": r[13],
                "era":     float(r[14]) if r[14] else 0,
                "whip":    float(r[15]) if r[15] else 0,
                "fip":     float(r[16]) if r[16] else 0,
                "k_per_9": float(r[17]) if r[17] else 0,
                "bb_per_9": float(r[18]) if r[18] else 0,
                "babip":   float(r[19]) if r[19] else 0,
                "war":     float(r[20]) if r[20] else 0,
                "blown_saves": r[21], "qs": r[22],
                "throws":  r[23],
                "team_code": r[24],
            }
            for r in rows
        ]
    }


@router.get("/{player_id}/daily")
def get_player_daily(player_id: int, season: int = 2026):
    """선수 일자별 기록"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("""
        SELECT game_date, opponent, result, stat_type,
            avg, pa, ab, runs, hits, doubles, triples,
            home_runs, rbi, sb, cs, walks, hbp, strikeouts, gdp,
            era, ip, h, hr, bb, so, r, er
        FROM player_daily_stats
        WHERE player_id = %s
        AND EXTRACT(YEAR FROM game_date) = %s
        ORDER BY game_date ASC
    """, (player_id, season))
    rows = cur.fetchall()
    cur.close()
    conn.close()

    return {
        "player_id": player_id,
        "season": season,
        "count": len(rows),
        "daily": [
            {
                "game_date":  str(r[0]),
                "opponent":   r[1],
                "result":     r[2],
                "stat_type":  r[3],
                "avg":        float(r[4]) if r[4] else None,
                "pa":         r[5],
                "ab":         r[6],
                "runs":       r[7],
                "hits":       r[8],
                "doubles":    r[9],
                "triples":    r[10],
                "home_runs":  r[11],
                "rbi":        r[12],
                "sb":         r[13],
                "cs":         r[14],
                "walks":      r[15],
                "hbp":        r[16],
                "strikeouts": r[17],
                "gdp":        r[18],
                "era":        float(r[19]) if r[19] else None,
                "ip":         float(r[20]) if r[20] else None,
                "h":          r[21],
                "hr":         r[22],
                "bb":         r[23],
                "so":         r[24],
                "r":          r[25],
                "er":         r[26],
            }
            for r in rows
        ]
    }


@router.get("/{player_id}/pitch-stats")
def get_player_pitch_stats(player_id: int, season: int = 2026):
    """투수 구종 분포 (game_pitch_locations 집계)"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("SELECT name FROM players WHERE id = %s", (player_id,))
    row = cur.fetchone()
    if not row:
        cur.close(); conn.close()
        raise HTTPException(status_code=404, detail="선수 없음")
    name = row[0]
    cur.execute("""
        SELECT pitch_type, COUNT(*) as cnt
        FROM game_pitch_locations gpl
        JOIN games g ON gpl.game_id = g.id
        WHERE gpl.pitcher_name = %s
          AND EXTRACT(YEAR FROM g.game_date) = %s
          AND gpl.pitch_type IS NOT NULL AND gpl.pitch_type != ''
        GROUP BY pitch_type
        ORDER BY cnt DESC
    """, (name, season))
    rows = cur.fetchall()
    cur.close(); conn.close()
    total = sum(r[1] for r in rows)
    return {
        "player_id": player_id,
        "season": season,
        "total": total,
        "pitch_types": [
            {"type": r[0], "count": r[1], "pct": round(r[1] / total * 100, 1) if total else 0}
            for r in rows
        ],
    }


@router.get("/matchup")
def get_matchup_stats(batter_id: int, pitcher_id: int):
    """타자 vs 투수 상대전적 (반대팀으로 같은 경기 출전 시 타자 성적 합산)"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("SELECT id, name, player_type FROM players WHERE id = %s", (batter_id,))
    b = cur.fetchone()
    cur.execute("SELECT id, name, player_type FROM players WHERE id = %s", (pitcher_id,))
    p = cur.fetchone()
    if not b or not p:
        cur.close(); conn.close()
        raise HTTPException(status_code=404, detail="선수 없음")
    cur.execute("""
        SELECT
            COUNT(DISTINCT gb.game_id) as games,
            COALESCE(SUM(gb.at_bats), 0) as at_bats,
            COALESCE(SUM(gb.hits), 0) as hits,
            COALESCE(SUM(gb.home_runs), 0) as home_runs,
            COALESCE(SUM(gb.rbis), 0) as rbis,
            COALESCE(SUM(gb.walks), 0) as walks,
            COALESCE(SUM(gb.strikeouts), 0) as strikeouts
        FROM game_batters gb
        JOIN game_pitchers gp ON gb.game_id = gp.game_id AND gb.team_side != gp.team_side
        WHERE gb.player_id = %s AND gp.player_id = %s
    """, (batter_id, pitcher_id))
    row = cur.fetchone()
    cur.close(); conn.close()
    games, ab, h, hr, rbi, bb, k = row
    avg = round(h / ab, 3) if ab > 0 else 0.0
    return {
        "batter": {"id": b[0], "name": b[1]},
        "pitcher": {"id": p[0], "name": p[1]},
        "games": games,
        "at_bats": ab,
        "hits": h,
        "home_runs": hr,
        "rbis": rbi,
        "walks": bb,
        "strikeouts": k,
        "avg": avg,
    }


@router.get("/{player_id}")
def get_player_detail(player_id: int):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()

    cur.execute("""
        SELECT p.id, p.name, p.player_type, p.position,
            p.number, p.birth_date, t.name AS team,
            p.profile_image, p.height, p.weight,
            p.throws, p.bats
        FROM players p
        JOIN teams t ON p.team_id = t.id
        WHERE p.id = %s
    """, (player_id,))
    player = cur.fetchone()

    if not player:
        raise HTTPException(status_code=404, detail="선수를 찾을 수 없습니다")

    result = {
        "id": player[0], "name": player[1],
        "player_type": player[2], "position": player[3],
        "number": player[4],
        "birth_date": str(player[5]) if player[5] else None,
        "team": player[6], "profile_image": player[7],
        "height": player[8], "weight": player[9],
        "throws": player[10], "bats": player[11],
        "stats": []
    }

    if player[2] == "타자":
        cur.execute("""
            SELECT season, games, at_bats, runs, hits, doubles, triples,
                home_runs, rbis, walks, strikeouts, stolen_bases,
                avg, obp, slg, ops, woba, wrc_plus, babip, iso, war,
                pa, tb, cs, sac, sf, ibb, hbp, gdp, errors,
                sb_pct, mh, risp, ph_ba,
                sba, fpct, po, assists, dp, pb, p_pa
            FROM batter_stats
            WHERE player_id = %s
            ORDER BY season DESC
        """, (player_id,))
        stats = cur.fetchall()
        result["stats"] = [
            {
                "season": r[0], "games": r[1], "at_bats": r[2],
                "runs": r[3], "hits": r[4], "doubles": r[5],
                "triples": r[6], "home_runs": r[7], "rbis": r[8],
                "walks": r[9], "strikeouts": r[10], "stolen_bases": r[11],
                "avg":      float(r[12]) if r[12] else 0,
                "obp":      float(r[13]) if r[13] else 0,
                "slg":      float(r[14]) if r[14] else 0,
                "ops":      float(r[15]) if r[15] else 0,
                "woba":     float(r[16]) if r[16] else 0,
                "wrc_plus": r[17],
                "babip":    float(r[18]) if r[18] else 0,
                "iso":      float(r[19]) if r[19] else 0,
                "war":      float(r[20]) if r[20] else 0,
                "pa": r[21], "tb": r[22], "cs": r[23],
                "sac": r[24], "sf": r[25], "ibb": r[26],
                "hbp": r[27], "gdp": r[28], "errors": r[29],
                "sb_pct": float(r[30]) if r[30] else 0,
                "mh": r[31],
                "risp":  float(r[32]) if r[32] else 0,
                "ph_ba": float(r[33]) if r[33] else 0,
                "sba": r[34], "fpct": float(r[35]) if r[35] else None,
                "po": r[36], "assists": r[37], "dp": r[38], "pb": r[39],
                "p_pa": float(r[40]) if r[40] else None,
            }
            for r in stats
        ]

    elif player[2] == "투수":
        cur.execute("""
            SELECT season, games, wins, losses, saves, holds,
                innings_pitched, hits_allowed, runs_allowed, earned_runs,
                walks, strikeouts, home_runs_allowed, era, whip, war,
                blown_saves, fip, k_per_9, bb_per_9, babip,
                cg, sho, wpct, tbf, np, doubles_allowed, triples_allowed,
                sac, sf, ibb, hbp, wp, bk, qs, avg_against,
                gs, gf, svo
            FROM pitcher_stats
            WHERE player_id = %s
            ORDER BY season DESC
        """, (player_id,))
        stats = cur.fetchall()
        result["stats"] = [
            {
                "season": r[0], "games": r[1], "wins": r[2],
                "losses": r[3], "saves": r[4], "holds": r[5],
                "innings_pitched":   float(r[6]) if r[6] else 0,
                "hits_allowed": r[7], "runs_allowed": r[8],
                "earned_runs": r[9], "walks": r[10], "strikeouts": r[11],
                "home_runs_allowed": r[12],
                "era":     float(r[13]) if r[13] else 0,
                "whip":    float(r[14]) if r[14] else 0,
                "war":     float(r[15]) if r[15] else 0,
                "blown_saves": r[16],
                "fip":     float(r[17]) if r[17] else 0,
                "k_per_9": float(r[18]) if r[18] else 0,
                "bb_per_9": float(r[19]) if r[19] else 0,
                "babip":   float(r[20]) if r[20] else 0,
                "cg": r[21], "sho": r[22],
                "wpct":    float(r[23]) if r[23] else 0,
                "tbf": r[24], "np": r[25],
                "doubles_allowed": r[26], "triples_allowed": r[27],
                "sac": r[28], "sf": r[29], "ibb": r[30],
                "hbp": r[31], "wp": r[32], "bk": r[33],
                "qs": r[34],
                "avg_against": float(r[35]) if r[35] else 0,
                "gs": r[36], "gf": r[37], "svo": r[38],
            }
            for r in stats
        ]

    # 로스터 상태 (최근 변경 이력)
    cur.execute("""
        SELECT change_type, reason, change_date
        FROM player_roster_changes
        WHERE player_id = %s
        ORDER BY change_date DESC
        LIMIT 1
    """, (player_id,))
    rc = cur.fetchone()
    result["roster_status"] = {
        "change_type": rc[0],
        "reason": rc[1],
        "change_date": str(rc[2]),
    } if rc else None

    cur.close()
    conn.close()
    return result