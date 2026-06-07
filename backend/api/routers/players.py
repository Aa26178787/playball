from fastapi import APIRouter, HTTPException, Depends
from database.connection import get_connection
from typing import Optional
from api.cache import cached
from api.routers.auth import get_current_user, get_optional_user

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


@router.get("/rankings")
@cached(300)
def get_player_rankings(season: int = 2026):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()

    cur.execute("SELECT MAX(games) FROM batter_stats WHERE season = %s", (season,))
    max_games = cur.fetchone()[0] or 0
    qual_pa = max_games * 3.1
    qual_ip = float(max_games) * 1.0

    cur.execute("""
        SELECT DISTINCT ON (p.id)
            p.id, p.name, t.name, p.profile_image,
            bs.games, bs.at_bats, bs.hits,
            bs.home_runs, bs.rbis, bs.runs,
            bs.walks, bs.strikeouts, bs.stolen_bases,
            bs.avg, bs.obp, bs.slg, bs.ops,
            bs.woba, bs.wrc_plus, bs.babip, bs.iso, bs.war,
            p.position, t.short_name, bs.pa
        FROM batter_stats bs
        JOIN players p ON bs.player_id = p.id
        JOIN teams t ON p.team_id = t.id
        WHERE bs.season = %s AND p.player_type = '타자'
        ORDER BY p.id
    """, (season,))
    hitter_rows = cur.fetchall()

    cur.execute("""
        SELECT DISTINCT ON (p.id)
            p.id, p.name, t.name, p.profile_image,
            ps.games, ps.wins, ps.losses,
            ps.saves, ps.holds, ps.innings_pitched,
            ps.strikeouts, ps.walks,
            ps.hits_allowed, ps.home_runs_allowed,
            ps.era, ps.whip, ps.fip,
            ps.k_per_9, ps.bb_per_9, ps.babip, ps.war,
            ps.blown_saves, ps.qs,
            p.throws, t.short_name
        FROM pitcher_stats ps
        JOIN players p ON ps.player_id = p.id
        JOIN teams t ON p.team_id = t.id
        WHERE ps.season = %s AND p.player_type = '투수'
        ORDER BY p.id
    """, (season,))
    pitcher_rows = cur.fetchall()

    cur.close()
    conn.close()

    def hd(r):
        return {
            "id": r[0], "name": r[1], "team": r[2], "profile_image": r[3],
            "games": r[4], "at_bats": r[5], "hits": r[6],
            "home_runs": r[7], "rbis": r[8], "runs": r[9],
            "walks": r[10], "strikeouts": r[11], "stolen_bases": r[12],
            "avg":      float(r[13]) if r[13] else 0,
            "obp":      float(r[14]) if r[14] else 0,
            "slg":      float(r[15]) if r[15] else 0,
            "ops":      float(r[16]) if r[16] else 0,
            "woba":     float(r[17]) if r[17] else 0,
            "wrc_plus": r[18], "babip": float(r[19]) if r[19] else 0,
            "iso":      float(r[20]) if r[20] else 0,
            "war":      float(r[21]) if r[21] else 0,
            "position": r[22], "team_code": r[23], "pa": r[24] or 0,
        }

    def pd(r):
        return {
            "id": r[0], "name": r[1], "team": r[2], "profile_image": r[3],
            "games": r[4], "wins": r[5], "losses": r[6],
            "saves": r[7], "holds": r[8],
            "innings_pitched": float(r[9]) if r[9] else 0,
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
            "throws": r[23], "team_code": r[24],
        }

    hitters = [hd(r) for r in hitter_rows]
    pitchers = [pd(r) for r in pitcher_rows]
    qual_h = [h for h in hitters if h['pa'] >= qual_pa] if qual_pa > 0 else hitters
    qual_p = [p for p in pitchers if p['innings_pitched'] >= qual_ip] if qual_ip > 0 else pitchers

    def top10(lst, key, asc=False):
        return sorted(lst, key=lambda x: x[key] or 0, reverse=not asc)[:10]

    return {
        "hitters": {
            "avg":          top10(qual_h, 'avg'),
            "home_runs":    top10(hitters, 'home_runs'),
            "rbis":         top10(hitters, 'rbis'),
            "hits":         top10(hitters, 'hits'),
            "stolen_bases": top10(hitters, 'stolen_bases'),
            "ops":          top10(qual_h, 'ops'),
            "war":          top10(hitters, 'war'),
        },
        "pitchers": {
            "era":        top10(qual_p, 'era', asc=True),
            "wins":       top10(pitchers, 'wins'),
            "strikeouts": top10(pitchers, 'strikeouts'),
            "saves":      top10(pitchers, 'saves'),
            "holds":      top10(pitchers, 'holds'),
            "whip":       top10(qual_p, 'whip', asc=True),
            "war":        top10(pitchers, 'war'),
        },
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


# ===== 인기투표 =====

@router.get("/popularity")
def get_player_popularity(limit: int = 20, current_user: dict | None = Depends(get_optional_user)):
    """선수 인기투표 랭킹"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    uid = current_user['user_id'] if current_user else None
    cur.execute("""
        SELECT p.id, p.name, p.player_type, p.position, p.profile_image,
               t.name AS team_name, t.short_name AS team_code,
               COUNT(v.id) AS vote_count,
               %s IS NOT NULL AND EXISTS(
                   SELECT 1 FROM player_popularity_votes
                   WHERE user_id=%s AND player_id=p.id
               ) AS voted
        FROM players p
        JOIN teams t ON t.id = p.team_id
        LEFT JOIN player_popularity_votes v ON v.player_id = p.id
        WHERE p.is_active = TRUE
        GROUP BY p.id, t.name, t.short_name
        HAVING COUNT(v.id) > 0
        ORDER BY vote_count DESC, p.name
        LIMIT %s
    """, (uid, uid, limit))
    rows = cur.fetchall()
    cur.close(); conn.close()
    return {
        "players": [
            {"id": r[0], "name": r[1], "player_type": r[2], "position": r[3],
             "profile_image": r[4], "team_name": r[5], "team_code": r[6],
             "vote_count": r[7], "voted": r[8]}
            for r in rows
        ]
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


@router.get("/{player_id}/pitch-design")
@cached(3600)
def get_pitch_design(player_id: int, season: int = 2026, stance: str = ''):
    """피칭 디자인 — 투수의 구종별 로케이션 5x5 존 분포 (2026-06-07)
    zone index: row*5+col, row0=상단 밖, col0=좌측 밖(포수 시점), 내부 = 1..3
    stance: '' 전체 / 'R' vs우타 / 'L' vs좌타"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("SELECT name FROM players WHERE id = %s", (player_id,))
    row = cur.fetchone()
    if not row:
        cur.close(); conn.close()
        raise HTTPException(status_code=404, detail="선수를 찾을 수 없습니다")
    name = row[0]

    params = [name, season]
    stance_sql = ""
    if stance in ('R', 'L'):
        stance_sql = " AND gpl.stance = %s"
        params.append(stance)
    cur.execute(f"""
        SELECT gpl.pitch_type, gpl.x, gpl.z, gpl.top_sz, gpl.bot_sz, gpl.stance
        FROM game_pitch_locations gpl
        JOIN games g ON g.id = gpl.game_id
        WHERE gpl.pitcher_name = %s
          AND EXTRACT(YEAR FROM g.game_date) = %s
          AND gpl.x IS NOT NULL AND gpl.z IS NOT NULL{stance_sql}
    """, params)
    rows = cur.fetchall()
    cur.close(); conn.close()

    PLATE_HALF = 8.5 / 12.0  # ft — 앱 투구위치 차트와 동일 상수

    def zone_idx(x, z, top, bot):
        third = (PLATE_HALF * 2) / 3
        if x < -PLATE_HALF:
            c = 0
        elif x > PLATE_HALF:
            c = 4
        else:
            c = 1 + min(2, int((x + PLATE_HALF) / third))
        if not top or not bot or top <= bot:
            top, bot = 3.5, 1.5  # ABS 존 미기록 시 표준값
        h3 = (top - bot) / 3
        if z > top:
            r = 0
        elif z < bot:
            r = 4
        else:
            r = 1 + min(2, int((top - z) / h3))
        return r * 5 + c

    by_type: dict = {}
    stance_counts = {'R': 0, 'L': 0}
    for pt, x, z, top, bot, st in rows:
        pt = pt or '기타'
        d = by_type.setdefault(pt, {'count': 0, 'zones': [0] * 25})
        d['count'] += 1
        d['zones'][zone_idx(float(x), float(z), top, bot)] += 1
        if st in stance_counts:
            stance_counts[st] += 1

    total = len(rows)
    pitch_types = [
        {'type': k, 'count': v['count'],
         'pct': round(v['count'] * 100 / total, 1) if total else 0,
         'zones': v['zones']}
        for k, v in sorted(by_type.items(), key=lambda e: -e[1]['count'])
    ]
    return {
        'player_id': player_id, 'name': name, 'season': season,
        'stance': stance or 'all', 'total': total,
        'stance_counts': stance_counts,
        'pitch_types': pitch_types,
    }


@router.get("/{player_id}/batter-zones")
@cached(3600)
def get_batter_zones(player_id: int, season: int = 2026, throws: str = ''):
    """타자 존 히트맵 (2026-06-07) — 피투구 분포 / 헛스윙 / 존별 타율
    - zone: 투수판과 동일 5x5 (타자별 ABS존 기준)
    - throws: '' 전체 / 'R' vs우투 / 'L' vs좌투 (투수 players.throws 조인)
    - 타율: 인플레이(result='hit') 투구 ↔ 같은 (game,inning,half) 내 타석 결과를
      발생 순서로 zip 매칭 (인플레이 = 타석 마지막 1구)"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("SELECT name FROM players WHERE id = %s", (player_id,))
    row = cur.fetchone()
    if not row:
        cur.close(); conn.close()
        raise HTTPException(status_code=404, detail="선수를 찾을 수 없습니다")
    name = row[0]

    throws_sql = ""
    params = [name, season]
    if throws == 'R':
        throws_sql = " AND pp.throws LIKE '우%%'"
    elif throws == 'L':
        throws_sql = " AND pp.throws LIKE '좌%%'"
    cur.execute(f"""
        SELECT gpl.id, gpl.game_id, gpl.inning, gpl.inning_half,
               gpl.x, gpl.z, gpl.top_sz, gpl.bot_sz, gpl.result,
               COALESCE(pp.throws, '')
        FROM game_pitch_locations gpl
        JOIN games g ON g.id = gpl.game_id
        LEFT JOIN players pp ON pp.name = gpl.pitcher_name
        WHERE gpl.batter_name = %s
          AND EXTRACT(YEAR FROM g.game_date) = %s
          AND gpl.x IS NOT NULL AND gpl.z IS NOT NULL{throws_sql}
        ORDER BY gpl.game_id, gpl.inning, gpl.inning_half, gpl.id
    """, params)
    pitches = cur.fetchall()

    # 타석 결과 (안타 판정용) — half 단위로 발생 순서 보존
    cur.execute("""
        SELECT gp.game_id, gp.inning, gp.inning_half, gp.title
        FROM game_pitches gp
        JOIN games g ON g.id = gp.game_id
        WHERE gp.batter_name = %s
          AND EXTRACT(YEAR FROM g.game_date) = %s
          AND gp.type IN (13, 23)
        ORDER BY gp.game_id, gp.inning, gp.inning_half, gp.seqno NULLS LAST, gp.id
    """, (name, season))
    results_rows = cur.fetchall()
    cur.close(); conn.close()

    # (game, inning, half) → 타석 결과 텍스트 큐
    from collections import defaultdict, deque
    res_q: dict = defaultdict(deque)
    for gid, inn, half, title in results_rows:
        res_q[(gid, inn, str(half))].append(title or '')

    PLATE_HALF = 8.5 / 12.0

    def zone_idx(x, z, top, bot):
        third = (PLATE_HALF * 2) / 3
        if x < -PLATE_HALF:
            c = 0
        elif x > PLATE_HALF:
            c = 4
        else:
            c = 1 + min(2, int((x + PLATE_HALF) / third))
        if not top or not bot or top <= bot:
            top, bot = 3.5, 1.5
        h3 = (top - bot) / 3
        if z > top:
            r = 0
        elif z < bot:
            r = 4
        else:
            r = 1 + min(2, int((top - z) / h3))
        return r * 5 + c

    HIT_WORDS = ('안타', '2루타', '3루타', '홈런')

    total_z = [0] * 25       # 피투구 분포
    swings_z = [0] * 25      # 스윙 (swing+foul+hit)
    whiffs_z = [0] * 25      # 헛스윙
    ab_z = [0] * 25          # 타수 카운트 인플레이 (희생 제외)
    hits_z = [0] * 25        # 안타

    for _id, gid, inn, half, x, z, top, bot, result, _thr in pitches:
        zi = zone_idx(float(x), float(z), top, bot)
        total_z[zi] += 1
        if result in ('swing', 'foul', 'hit'):
            swings_z[zi] += 1
        if result == 'swing':
            whiffs_z[zi] += 1
        if result == 'hit':
            # 인플레이 → 발생 순서로 타석 결과 매칭
            q = res_q.get((gid, inn, str(half)))
            title = q.popleft() if q else ''
            res_part = title.split(' : ')[-1] if title else ''
            if '희생' in res_part:
                continue  # 타수 제외
            ab_z[zi] += 1
            if any(w in res_part for w in HIT_WORDS):
                hits_z[zi] += 1

    return {
        'player_id': player_id, 'name': name, 'season': season,
        'throws': throws or 'all',
        'total': len(pitches),
        'zones': {
            'pitches': total_z,
            'swings': swings_z,
            'whiffs': whiffs_z,
            'inplay_ab': ab_z,
            'hits': hits_z,
        },
    }


@router.get("/{player_id}")
@cached(300)
def get_player_detail(player_id: int):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()

    cur.execute("""
        SELECT p.id, p.name, p.player_type, p.position,
            p.number, p.birth_date, t.name AS team,
            p.profile_image, p.height, p.weight,
            p.throws, p.bats, t.short_name AS team_code,
            p.insta_handle
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
        "team_code": player[12],
        "insta_handle": player[13],
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


@router.post("/{player_id}/vote")
def vote_player(player_id: int, current_user: dict = Depends(get_current_user)):
    """선수 인기투표 토글 (하트). 5초 cooldown — 의도치 않은 연속 토글 방지."""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    uid = current_user['user_id']
    # 5초 cooldown 체크 (created_at 기준)
    cur.execute("""
        SELECT EXTRACT(EPOCH FROM (NOW() - created_at)) FROM player_popularity_votes
        WHERE user_id=%s AND player_id=%s
    """, (uid, player_id))
    cooldown_row = cur.fetchone()
    if cooldown_row and cooldown_row[0] is not None and cooldown_row[0] < 5:
        cur.close(); conn.close()
        raise HTTPException(status_code=429, detail="잠시 후 다시 시도해주세요")

    cur.execute("SELECT id FROM player_popularity_votes WHERE user_id=%s AND player_id=%s", (uid, player_id))
    existing = cur.fetchone()
    if existing:
        cur.execute("DELETE FROM player_popularity_votes WHERE user_id=%s AND player_id=%s", (uid, player_id))
        voted = False
    else:
        cur.execute("INSERT INTO player_popularity_votes (user_id, player_id) VALUES (%s, %s)", (uid, player_id))
        voted = True
    conn.commit()
    cur.execute("SELECT COUNT(*) FROM player_popularity_votes WHERE player_id=%s", (player_id,))
    count = cur.fetchone()[0]
    cur.close(); conn.close()
    return {"voted": voted, "vote_count": count}