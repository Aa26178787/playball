from fastapi import APIRouter, HTTPException
from database.connection import get_connection
from api.cache import cached

router = APIRouter()


def _ip_to_outs(ip) -> int:
    """KBO 표기 이닝(6.1=6⅓) → 아웃수. .1=+1, .2=+2."""
    if ip is None:
        return 0
    ip = float(ip)
    whole = int(ip)
    frac = round((ip - whole) * 10)
    return whole * 3 + frac


def _outs_to_ip(outs: int) -> float:
    """아웃수 → KBO 표기 이닝."""
    return round(outs // 3 + (outs % 3) * 0.1, 1)


def _aggregate_career(rows: list[dict]) -> dict:
    """정규시즌 행들 통산 합산. 카운팅=합, 비율=원자료 재계산."""
    if not rows:
        return {}
    ptype = rows[0].get("player_type")
    out: dict = {"player_type": ptype}
    if ptype == "타자":
        keys = ["games", "pa", "at_bats", "runs", "hits", "doubles", "triples",
                "home_runs", "rbis", "walks", "hbp", "intentional_walks",
                "strikeouts", "stolen_bases", "caught_stealing", "gdp",
                "sac_hits", "sac_flies"]
        for k in keys:
            out[k] = sum((r.get(k) or 0) for r in rows)
        ab, h = out["at_bats"], out["hits"]
        tb = h + out["doubles"] + 2 * out["triples"] + 3 * out["home_runs"]
        obp_den = ab + out["walks"] + out["hbp"] + out["sac_flies"]
        out["avg"] = round(h / ab, 3) if ab else 0
        out["obp"] = round((h + out["walks"] + out["hbp"]) / obp_den, 3) if obp_den else 0
        out["slg"] = round(tb / ab, 3) if ab else 0
        out["ops"] = round(out["obp"] + out["slg"], 3)
    else:
        keys = ["games", "wins", "losses", "saves", "holds", "hits_allowed",
                "runs_allowed", "earned_runs", "walks_allowed", "hbp_allowed",
                "strikeouts_pitched", "home_runs_allowed", "qs",
                "complete_games", "shutouts"]
        for k in keys:
            out[k] = sum((r.get(k) or 0) for r in rows)
        outs = sum(_ip_to_outs(r.get("innings_pitched")) for r in rows)
        out["innings_pitched"] = _outs_to_ip(outs)
        ip_full = outs / 3 if outs else 0
        out["era"] = round(out["earned_runs"] * 9 / ip_full, 2) if ip_full else 0
        out["whip"] = round((out["walks_allowed"] + out["hits_allowed"]) / ip_full, 2) if ip_full else 0
    return out


# 통산 리더 카테고리 → (player_type, 컬럼, 내림차순?)
_LEADER_CATS = {
    "home_runs":          ("타자", "home_runs", True),
    "hits":               ("타자", "hits", True),
    "stolen_bases":       ("타자", "stolen_bases", True),
    "rbis":               ("타자", "rbis", True),
    "wins":               ("투수", "wins", True),
    "strikeouts_pitched": ("투수", "strikeouts_pitched", True),
    "saves":              ("투수", "saves", True),
}


# ⚠️ /leaders 는 /{kbo_player_id} 보다 먼저 선언 (정수경로 오매칭 방지 — FastAPI 선언순)
@router.get("/leaders")
@cached(3600)
def get_historical_leaders(category: str = "home_runs", limit: int = 20):
    if category not in _LEADER_CATS:
        raise HTTPException(status_code=400, detail="알 수 없는 카테고리")
    ptype, col, desc = _LEADER_CATS[category]
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    # 통산 합산(정규만) → 카운팅 컬럼 SUM. 컬럼명은 화이트리스트(_LEADER_CATS)라 주입 안전.
    cur.execute(f"""
        SELECT hp.kbo_player_id, hp.name, hp.player_id,
               t.short_name AS team_code, t.name AS team,
               SUM(COALESCE(hss.{col}, 0)) AS total
        FROM historical_season_stats hss
        JOIN historical_players hp ON hp.kbo_player_id = hss.kbo_player_id
        LEFT JOIN teams t ON t.id = hp.primary_team_id
        WHERE hss.series_type = '정규' AND hss.player_type = %s
        GROUP BY hp.kbo_player_id, hp.name, hp.player_id, t.short_name, t.name
        ORDER BY total {'DESC' if desc else 'ASC'}
        LIMIT %s
    """, (ptype, limit))
    rows = cur.fetchall()
    cur.close(); conn.close()
    return {
        "category": category,
        "leaders": [
            {"kbo_player_id": r[0], "name": r[1], "is_active": r[2] is not None,
             "team_code": r[3], "team": r[4], "value": int(r[5] or 0)}
            for r in rows
        ],
    }


@router.get("/{kbo_player_id}")
@cached(600)
def get_historical_player(kbo_player_id: int):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()

    cur.execute("""
        SELECT hp.kbo_player_id, hp.player_id, hp.name, hp.player_type,
               hp.birth_date, hp.height, hp.weight, hp.throws, hp.bats,
               hp.position, hp.career, hp.draft_info, hp.debut_year, hp.final_year,
               hp.profile_image, hp.primary_team_id, t.name AS team, t.short_name AS team_code
        FROM historical_players hp
        LEFT JOIN teams t ON t.id = hp.primary_team_id
        WHERE hp.kbo_player_id = %s
    """, (kbo_player_id,))
    p = cur.fetchone()
    if not p:
        cur.close(); conn.close()
        raise HTTPException(status_code=404, detail="역대 선수를 찾을 수 없습니다")
    (kid, pid, name, ptype, birth, height, weight, throws, bats, position,
     career, draft, debut, final, img, prim_tid, team, team_code) = p

    def fnum(v):
        return float(v) if v is not None else None

    # 시즌 스탯 (정규만)
    cur.execute("""
        SELECT season, team_name, player_type, games, pa, at_bats, runs, hits,
               doubles, triples, home_runs, rbis, walks, hbp, intentional_walks,
               strikeouts, stolen_bases, caught_stealing, gdp, sac_hits, sac_flies,
               avg, obp, slg, ops,
               wins, losses, saves, holds, innings_pitched, hits_allowed,
               runs_allowed, earned_runs, walks_allowed, hbp_allowed,
               strikeouts_pitched, home_runs_allowed, era, whip, qs,
               complete_games, shutouts, war, woba, wrc_plus, fip
        FROM historical_season_stats
        WHERE kbo_player_id = %s AND series_type = '정규'
        ORDER BY season DESC, team_name
    """, (kbo_player_id,))
    cols = [c[0] for c in cur.description]
    NUMERIC = {'avg', 'obp', 'slg', 'ops', 'innings_pitched', 'era', 'whip',
               'war', 'woba', 'fip'}
    stats = []
    for row in cur.fetchall():
        d = dict(zip(cols, row))
        for k in NUMERIC:
            d[k] = fnum(d.get(k))
        stats.append(d)

    # 포스트시즌 (있으면)
    cur.execute("""
        SELECT season, series_type, team_name, player_type, games,
               at_bats, hits, home_runs, rbis, avg,
               innings_pitched, earned_runs, strikeouts_pitched, era
        FROM historical_season_stats
        WHERE kbo_player_id = %s AND series_type <> '정규'
        ORDER BY season DESC
    """, (kbo_player_id,))
    pcols = [c[0] for c in cur.description]
    postseason = [dict(zip(pcols, r)) for r in cur.fetchall()]
    for ps in postseason:
        for k in ('avg', 'innings_pitched', 'era'):
            ps[k] = fnum(ps.get(k))

    # 수상
    cur.execute("""
        SELECT season, award FROM historical_awards
        WHERE kbo_player_id = %s ORDER BY season DESC NULLS LAST, award
    """, (kbo_player_id,))
    awards = [{"season": r[0], "award": r[1]} for r in cur.fetchall()]

    # 스플릿 (있으면, 축별 그룹)
    cur.execute("""
        SELECT split_axis, split_value, season, games, pa, at_bats, hits,
               home_runs, rbis, avg, slg
        FROM historical_splits
        WHERE kbo_player_id = %s
        ORDER BY season DESC, split_axis, split_value
    """, (kbo_player_id,))
    splits: dict = {}
    for r in cur.fetchall():
        splits.setdefault(r[0], []).append({
            "value": r[1], "season": r[2], "games": r[3], "pa": r[4],
            "at_bats": r[5], "hits": r[6], "home_runs": r[7], "rbis": r[8],
            "avg": fnum(r[9]), "slg": fnum(r[10]),
        })

    # franchise 계보 (primary_team 기준 — 표시용)
    franchise_path = []
    if prim_tid:
        cur.execute("""
            SELECT team_name, start_year, end_year FROM team_franchises
            WHERE current_team_id = %s ORDER BY start_year
        """, (prim_tid,))
        franchise_path = [
            {"team_name": r[0], "start_year": r[1], "end_year": r[2]}
            for r in cur.fetchall()
        ]

    cur.close(); conn.close()
    career_totals = _aggregate_career(stats) if stats else {}
    return {
        "bio": {
            "kbo_player_id": kid, "player_id": pid, "name": name,
            "player_type": ptype, "birth_date": str(birth) if birth else None,
            "height": height, "weight": weight, "throws": throws, "bats": bats,
            "position": position, "career_text": career, "draft_info": draft,
            "debut_year": debut, "final_year": final, "profile_image": img,
            "team": team, "team_code": team_code, "is_active": pid is not None,
        },
        "stats": stats,
        "career": career_totals,
        "postseason": postseason,
        "awards": awards,
        "splits": splits,
        "franchise_path": franchise_path,
    }
