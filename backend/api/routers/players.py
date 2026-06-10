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
@cached(300)
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
                p.position, t.short_name AS team_code, p.number,
                (SELECT mode() WITHIN GROUP (ORDER BY gr.position)
                 FROM game_rosters gr
                 WHERE gr.player_id = p.id
                   AND gr.position IS NOT NULL AND gr.position <> ''
                   AND gr.position NOT IN ('대타', '대주자', '투수')) AS detail_pos
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
                "position": r[25] or r[22],  # game_rosters 주포지션(세부) 우선, 없으면 players.position
                "team_code": r[23],
                "number": r[24],
            }
            for r in rows
        ]
    }


@router.get("/pitchers")
@cached(300)
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
                p.throws, t.short_name AS team_code, p.number
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
                "number": r[25],
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
@cached(300)
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
@cached(600)
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
@cached(600)
def get_matchup_stats(batter_id: int, pitcher_id: int):
    """타자 vs 투수 직접 맞대결 — plate_appearances 타석 단위 정밀 집계
    (구버전은 같은 경기 출전이면 타 투수 상대 타석까지 합산하던 근사치였음)"""
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
            COUNT(*) AS pa,
            COUNT(DISTINCT game_id) AS games,
            COUNT(*) FILTER (WHERE result_class IN
              ('single','double','triple','hr','out','so','error','fc','reach_other')) AS at_bats,
            COUNT(*) FILTER (WHERE is_hit) AS hits,
            COUNT(*) FILTER (WHERE result_class = 'hr') AS home_runs,
            COUNT(*) FILTER (WHERE result_class = 'double') AS doubles,
            COUNT(*) FILTER (WHERE result_class = 'triple') AS triples,
            COUNT(*) FILTER (WHERE result_class IN ('bb','ibb')) AS walks,
            COUNT(*) FILTER (WHERE result_class = 'hbp') AS hbp,
            COUNT(*) FILTER (WHERE result_class = 'so') AS strikeouts
        FROM plate_appearances
        WHERE batter_name = %s AND pitcher_name = %s
    """, (b[1], p[1]))
    row = cur.fetchone()
    cur.close(); conn.close()
    pa, games, ab, h, hr, d2, d3, bb, hbp, k = row
    avg = round(h / ab, 3) if ab > 0 else 0.0
    obp_den = ab + bb + hbp
    return {
        "batter": {"id": b[0], "name": b[1]},
        "pitcher": {"id": p[0], "name": p[1]},
        "pa": pa,
        "games": games,
        "at_bats": ab,
        "hits": h,
        "home_runs": hr,
        "doubles": d2,
        "triples": d3,
        "walks": bb,
        "hbp": hbp,
        "strikeouts": k,
        "avg": avg,
        "obp": round((h + bb + hbp) / obp_den, 3) if obp_den > 0 else 0.0,
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

    # Naver 표기: '중견수 왼쪽 1루타' / '내야안타' / '2루타' … ('안타' 단독 표기는 안 씀)
    HIT_WORDS = ('1루타', '2루타', '3루타', '홈런', '안타')

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


@router.get("/{player_id}/pitcher-zones")
@cached(3600)
def get_pitcher_zones(player_id: int, season: int = 2026, stance: str = ''):
    """피칭 존 히트맵 — 투수의 존별 피투구 분포 / 피안타율 (구종 무관 합산)
    - zone: 5x5 (타자 ABS존 기준)
    - stance: '' 전체 / 'R' vs우타 / 'L' vs좌타 (gpl.stance)
    - 피안타율: 인플레이(result='hit') ↔ 같은 (game,inning,half,batter) 타석 결과 zip 매칭
      (투수가 한 half에 여러 타자 상대 → batter_name 포함 키로 정밀 매칭)"""
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

    stance_sql = ""
    params = [name, season]
    if stance in ('R', 'L'):
        stance_sql = " AND gpl.stance = %s"
        params.append(stance)
    cur.execute(f"""
        SELECT gpl.game_id, gpl.inning, gpl.inning_half, gpl.batter_name,
               gpl.x, gpl.z, gpl.top_sz, gpl.bot_sz, gpl.result
        FROM game_pitch_locations gpl
        JOIN games g ON g.id = gpl.game_id
        WHERE gpl.pitcher_name = %s
          AND EXTRACT(YEAR FROM g.game_date) = %s
          AND gpl.x IS NOT NULL AND gpl.z IS NOT NULL{stance_sql}
        ORDER BY gpl.game_id, gpl.inning, gpl.inning_half, gpl.id
    """, params)
    pitches = cur.fetchall()

    cur.execute("""
        SELECT gp.game_id, gp.inning, gp.inning_half, gp.batter_name, gp.title
        FROM game_pitches gp
        JOIN games g ON g.id = gp.game_id
        WHERE gp.pitcher_name = %s
          AND EXTRACT(YEAR FROM g.game_date) = %s
          AND gp.type IN (13, 23)
        ORDER BY gp.game_id, gp.inning, gp.inning_half, gp.seqno NULLS LAST, gp.id
    """, (name, season))
    results_rows = cur.fetchall()
    cur.close(); conn.close()

    from collections import defaultdict, deque
    res_q: dict = defaultdict(deque)
    for gid, inn, half, bname, title in results_rows:
        res_q[(gid, inn, str(half), bname)].append(title or '')

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

    HIT_WORDS = ('1루타', '2루타', '3루타', '홈런', '안타')
    total_z = [0] * 25
    ab_z = [0] * 25
    hits_z = [0] * 25
    for gid, inn, half, bname, x, z, top, bot, result in pitches:
        zi = zone_idx(float(x), float(z), top, bot)
        total_z[zi] += 1
        if result == 'hit':
            q = res_q.get((gid, inn, str(half), bname))
            title = q.popleft() if q else ''
            res_part = title.split(' : ')[-1] if title else ''
            if '희생' in res_part:
                continue
            ab_z[zi] += 1
            if any(w in res_part for w in HIT_WORDS):
                hits_z[zi] += 1

    return {
        'player_id': player_id, 'name': name, 'season': season,
        'stance': stance or 'all',
        'total': len(pitches),
        'zones': {
            'pitches': total_z,
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
            p.insta_handle, p.is_foreign, p.full_name
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
        "is_foreign": player[14],
        "full_name": player[15],
        "stats": []
    }

    if player[2] == "타자":
        cur.execute("""
            SELECT season, games, at_bats, runs, hits, doubles, triples,
                home_runs, rbis, walks, strikeouts, stolen_bases,
                avg, obp, slg, ops, woba, wrc_plus, babip, iso, war,
                pa, tb, cs, sac, sf, ibb, hbp, gdp, errors,
                sb_pct, mh, risp, ph_ba,
                sba, fpct, po, assists, dp, pb, p_pa,
                xbh, bb_k, gpa, bb_pct, k_pct
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
                "xbh": r[41], "bb_k": float(r[42]) if r[42] else 0,
                "gpa": float(r[43]) if r[43] else 0,
                "bb_pct": float(r[44]) if r[44] else 0,
                "k_pct": float(r[45]) if r[45] else 0,
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
                gs, gf, svo, k_bb, k_pct, bb_pct, k_bb_pct
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
                "k_bb":     float(r[39]) if r[39] else 0,
                "k_pct":    float(r[40]) if r[40] else 0,
                "bb_pct":   float(r[41]) if r[41] else 0,
                "k_bb_pct": float(r[42]) if r[42] else 0,
            }
            for r in stats
        ]

    # 핵심 스탯 비교 — rate(타율/ERA 등)=규정 풀·게이트, counting(홈런/세이브 등)=전체 풀·항상.
    # 앱이 메뉴서 4개 골라 표시 → 서버는 메뉴 전체 비교 제공. 실패해도 본문 정상
    try:
        latest = result["stats"][0] if result.get("stats") else None
        if latest:
            cur.execute("SELECT COALESCE(MAX(games),0) FROM batter_stats WHERE season=%s", (latest["season"],))
            maxg = cur.fetchone()[0] or 0
            is_dom = not player[14]   # 국내 선수만 국내랭크 표시

            def _cmp(table, where_extra, where_params, stats, guard_zero=True):
                # stats: [(key, col, higher_better)] — 컬럼명은 하드코딩(주입 안전)
                # guard_zero: rate 하위-better(ERA 등)는 0=무데이터 제외, counting 하위-better(실책 등)는 0=최고라 미제외
                cols = [f"round(AVG(t.{c})::numeric,3)" for (k, c, h) in stats]
                cols += ["COUNT(*)", "COUNT(*) FILTER (WHERE NOT pl.is_foreign)"]
                vps = []
                for (k, c, h) in stats:
                    op = ">" if h else "<"; g = "" if (h or not guard_zero) else f" AND t.{c}>0"
                    cols.append(f"COUNT(*) FILTER (WHERE t.{c} {op} %s{g})"); vps.append(latest.get(k) or 0)
                for (k, c, h) in stats:
                    op = ">" if h else "<"; g = "" if (h or not guard_zero) else f" AND t.{c}>0"
                    cols.append(f"COUNT(*) FILTER (WHERE t.{c} {op} %s{g} AND NOT pl.is_foreign)"); vps.append(latest.get(k) or 0)
                cur.execute(
                    f"SELECT {', '.join(cols)} FROM {table} t JOIN players pl ON pl.id=t.player_id "
                    f"WHERE t.season=%s {where_extra}",
                    vps + [latest["season"]] + where_params)
                r = cur.fetchone(); n = len(stats)
                avgs, tot, dtot = r[0:n], r[n], r[n + 1]
                lbet, dbet = r[n + 2:2 * n + 2], r[2 * n + 2:3 * n + 2]
                out = {}
                for i, (k, c, h) in enumerate(stats):
                    d = {"lg": float(avgs[i] or 0), "rank": (lbet[i] or 0) + 1, "total": tot or 0}
                    if is_dom:
                        d["dom_rank"] = (dbet[i] or 0) + 1; d["dom_total"] = dtot or 0
                    out[k] = d
                return out

            if player[2] == "타자":
                qual = (latest.get("pa") or 0) >= maxg * 3.1
                result["qualified"] = qual
                # counting (전체 풀, 항상). 하위-better: strikeouts(삼진)·errors·pb
                cc = _cmp("batter_stats", "AND t.pa>0", [], [
                    ("home_runs", "home_runs", True), ("rbis", "rbis", True), ("hits", "hits", True),
                    ("stolen_bases", "stolen_bases", True), ("walks", "walks", True), ("strikeouts", "strikeouts", False),
                    ("tb", "tb", True), ("xbh", "xbh", True), ("war", "war", True), ("runs", "runs", True),
                    ("errors", "errors", False), ("po", "po", True), ("assists", "assists", True),
                    ("dp", "dp", True), ("pb", "pb", False),
                ], guard_zero=False)
                if qual:  # rate (규정 풀)
                    cc.update(_cmp("batter_stats", "AND t.pa>=%s", [maxg * 3.1], [
                        ("avg", "avg", True), ("obp", "obp", True), ("slg", "slg", True), ("ops", "ops", True),
                        ("woba", "woba", True), ("wrc_plus", "wrc_plus", True), ("babip", "babip", True),
                        ("iso", "iso", True), ("risp", "risp", True), ("bb_pct", "bb_pct", True),
                        ("k_pct", "k_pct", False), ("gpa", "gpa", True), ("bb_k", "bb_k", True), ("fpct", "fpct", True),
                    ]))
                result["core_compare"] = cc
            elif player[2] == "투수":
                qual = (latest.get("innings_pitched") or 0) >= maxg * 1.0
                result["qualified"] = qual
                # counting (전체 풀, 항상). 하위-better: losses·blown_saves
                cc = _cmp("pitcher_stats", "AND t.innings_pitched>0", [], [
                    ("strikeouts", "strikeouts", True), ("wins", "wins", True), ("saves", "saves", True),
                    ("holds", "holds", True), ("qs", "qs", True), ("innings_pitched", "innings_pitched", True),
                    ("war", "war", True), ("losses", "losses", False), ("blown_saves", "blown_saves", False),
                ], guard_zero=False)
                if qual:  # rate (규정 풀)
                    cc.update(_cmp("pitcher_stats", "AND t.innings_pitched>=%s", [maxg * 1.0], [
                        ("era", "era", False), ("whip", "whip", False), ("k_per_9", "k_per_9", True),
                        ("bb_per_9", "bb_per_9", False), ("fip", "fip", False), ("babip", "babip", False),
                        ("avg_against", "avg_against", False), ("k_pct", "k_pct", True),
                        ("bb_pct", "bb_pct", False), ("k_bb_pct", "k_bb_pct", True),
                    ]))
                result["core_compare"] = cc
    except Exception:
        pass

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


@router.get("/{player_id}/vote-status")
def get_player_vote_status(player_id: int, current_user: dict | None = Depends(get_optional_user)):
    """선수 인기투표 상태 (하트 표시용 — 비캐시, 유저별 voted)."""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM player_popularity_votes WHERE player_id=%s", (player_id,))
    count = cur.fetchone()[0]
    voted = False
    if current_user:
        cur.execute("SELECT 1 FROM player_popularity_votes WHERE user_id=%s AND player_id=%s",
                    (current_user['user_id'], player_id))
        voted = cur.fetchone() is not None
    cur.close(); conn.close()
    return {"vote_count": count, "voted": voted}


@router.post("/{player_id}/report-insta")
def report_insta(player_id: int, current_user: dict | None = Depends(get_optional_user)):
    """인스타 핸들 오류 신고 (이 계정이 선수 본인이 아닐 때). 비로그인도 가능. 검토는 insta_handle_reports psql."""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("SELECT insta_handle FROM players WHERE id=%s", (player_id,))
    row = cur.fetchone()
    if not row:
        cur.close(); conn.close()
        raise HTTPException(status_code=404, detail="선수를 찾을 수 없습니다")
    uid = current_user['user_id'] if current_user else None
    cur.execute(
        "INSERT INTO insta_handle_reports (player_id, handle, user_id) VALUES (%s, %s, %s)",
        (player_id, row[0], uid))
    conn.commit()
    cur.close(); conn.close()
    return {"ok": True}