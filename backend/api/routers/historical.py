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


# ── 상세확장: 타이틀 이력 / 팀변천 / 마일스톤 / 스플릿 (2026-06-18) ──
# 카운팅 타이틀(부문 시즌 max 동률): col → 라벨
_TITLE_COUNT = {
    "타자": {"home_runs": "홈런왕", "rbis": "타점왕", "hits": "최다안타", "stolen_bases": "도루왕"},
    "투수": {"wins": "다승왕", "saves": "세이브왕", "strikeouts_pitched": "탈삼진왕"},
}


def _career_titles(cur, kbo_player_id, ptype):
    """시즌별 부문 1위 집계. 카운팅=시즌 max 동률 / 비율(타율·평자책)=규정게이트(시즌 최다출전 games 기준)."""
    titles = []
    for col, label in _TITLE_COUNT.get(ptype, {}).items():
        # (player,season) 합산(트레이드 2행 대응) 후 시즌 max 동률 시즌
        cur.execute(f"""
            WITH ps AS (
              SELECT kbo_player_id, season, SUM(COALESCE({col},0)) v
              FROM historical_season_stats
              WHERE series_type='정규' AND player_type=%s
              GROUP BY kbo_player_id, season
            ), sm AS (SELECT season, MAX(v) m FROM ps GROUP BY season)
            SELECT ps.season FROM ps JOIN sm ON sm.season=ps.season AND ps.v=sm.m
            WHERE ps.kbo_player_id=%s AND ps.v>0 ORDER BY ps.season
        """, (ptype, kbo_player_id))
        seasons = [r[0] for r in cur.fetchall()]
        if seasons:
            titles.append({"category": label, "count": len(seasons), "seasons": seasons})
    # 비율 타이틀 — 규정게이트(타자 pa≥팀경기*3.1 / 투수 이닝≥팀경기*1.0, 팀경기≈시즌 최다출전 games)
    if ptype == "타자":
        cur.execute("""
            WITH ps AS (
              SELECT kbo_player_id, season, SUM(pa) pa, SUM(at_bats) ab,
                     SUM(hits) h, SUM(games) g
              FROM historical_season_stats WHERE series_type='정규' AND player_type='타자'
              GROUP BY kbo_player_id, season
            ), tg AS (SELECT season, MAX(g)*3.1 qp FROM ps GROUP BY season),
            qual AS (
              SELECT ps.kbo_player_id, ps.season,
                     CASE WHEN ps.ab>0 THEN ps.h::numeric/ps.ab ELSE 0 END av
              FROM ps JOIN tg ON tg.season=ps.season WHERE ps.pa >= tg.qp
            ), sm AS (SELECT season, MAX(av) m FROM qual GROUP BY season)
            SELECT qual.season FROM qual JOIN sm ON sm.season=qual.season AND qual.av=sm.m
            WHERE qual.kbo_player_id=%s ORDER BY qual.season
        """, (kbo_player_id,))
        s = [r[0] for r in cur.fetchall()]
        if s:
            titles.append({"category": "타격왕", "count": len(s), "seasons": s})
    else:
        cur.execute("""
            WITH ps AS (
              SELECT kbo_player_id, season, SUM(earned_runs) er, SUM(games) g,
                     SUM(FLOOR(innings_pitched) + (innings_pitched-FLOOR(innings_pitched))*10/3.0) ip
              FROM historical_season_stats WHERE series_type='정규' AND player_type='투수'
              GROUP BY kbo_player_id, season
            ), tg AS (SELECT season, MAX(g) mg FROM ps GROUP BY season),
            qual AS (
              SELECT ps.kbo_player_id, ps.season,
                     CASE WHEN ps.ip>0 THEN ps.er*9/ps.ip ELSE 999 END era
              FROM ps JOIN tg ON tg.season=ps.season WHERE ps.ip >= tg.mg
            ), sm AS (SELECT season, MIN(era) m FROM qual GROUP BY season)
            SELECT qual.season FROM qual JOIN sm ON sm.season=qual.season AND qual.era=sm.m
            WHERE qual.kbo_player_id=%s ORDER BY qual.season
        """, (kbo_player_id,))
        s = [r[0] for r in cur.fetchall()]
        if s:
            titles.append({"category": "평균자책왕", "count": len(s), "seasons": s})
    titles.sort(key=lambda t: t["count"], reverse=True)
    return titles


def _team_timeline(cur, kbo_player_id):
    """시즌별 소속팀 → 연속 구간 병합 ('삼성 1995~2003 → ...')."""
    cur.execute("""
        SELECT season, team_name FROM historical_season_stats
        WHERE kbo_player_id=%s AND series_type='정규' AND team_name IS NOT NULL
        GROUP BY season, team_name ORDER BY season
    """, (kbo_player_id,))
    out = []
    for season, team in cur.fetchall():
        if out and out[-1]["team"] == team and season <= out[-1]["end"] + 1:
            out[-1]["end"] = max(out[-1]["end"], season)
        else:
            out.append({"team": team, "start": season, "end": season})
    return out


_MILESTONE = {
    "타자": {"home_runs": ([100, 200, 300, 400, 500], "홈런"),
            "hits": ([1000, 1500, 2000, 2500, 3000], "안타"),
            "rbis": ([500, 1000, 1500], "타점"),
            "stolen_bases": ([300, 500], "도루")},
    "투수": {"wins": ([100, 150, 200], "승"),
            "saves": ([100, 200, 300, 400], "세이브"),
            "strikeouts_pitched": ([1000, 1500, 2000, 2500], "탈삼진")},
}


def _career_milestones(career, ptype, is_active, recent):
    """달성 마일스톤 + (현역만)다음 목표 ETA(최근시즌 페이스)."""
    reached, approaching = [], []
    units = {"home_runs": "홈런", "hits": "안타", "rbis": "타점", "stolen_bases": "도루",
             "wins": "승", "saves": "세이브", "strikeouts_pitched": "탈삼진"}
    for col, (thr, unit) in _MILESTONE.get(ptype, {}).items():
        val = career.get(col) or 0
        for t in thr:
            if val >= t:
                reached.append({"label": f"통산 {t}{unit}", "value": t, "current": val})
        nxts = [t for t in thr if val < t]
        if nxts and is_active:
            t = nxts[0]
            remaining = t - val
            pace = (recent.get(col) or 0) if recent else 0
            eta = (2026 + -(-remaining // pace)) if pace > 0 else None
            approaching.append({"label": f"{t}{unit}", "remaining": remaining,
                                "eta_season": int(eta) if eta else None})
    reached.sort(key=lambda x: x["value"], reverse=True)
    return {"reached": reached, "approaching": approaching}


def _player_splits(cur, kbo_player_id):
    """통산 스플릿(historical_splits — 2023~25 타자만). 축별 그룹, 없으면 빈 dict."""
    cur.execute("""
        SELECT split_axis, split_value, season, games, pa, at_bats, hits,
               home_runs, rbis, avg, slg
        FROM historical_splits WHERE kbo_player_id=%s
        ORDER BY season DESC, split_axis, split_value
    """, (kbo_player_id,))
    out: dict = {}
    for r in cur.fetchall():
        out.setdefault(r[0], []).append({
            "value": r[1], "season": r[2], "games": r[3], "pa": r[4],
            "at_bats": r[5], "hits": r[6], "home_runs": r[7], "rbis": r[8],
            "avg": float(r[9]) if r[9] is not None else None,
            "slg": float(r[10]) if r[10] is not None else None,
        })
    return out


def _career_extras(cur, kbo_player_id):
    """타이틀/팀변천/마일스톤/스플릿 번들. 현역·은퇴 공통 (kbo_player_id 키)."""
    cur.execute("""
        SELECT player_type, player_id FROM historical_players WHERE kbo_player_id=%s
    """, (kbo_player_id,))
    row = cur.fetchone()
    if not row:
        return None
    ptype, pid = row
    is_active = pid is not None
    # career 집계 + 최근시즌(페이스)
    cur.execute("""
        SELECT season, team_name, player_type, games, pa, at_bats, runs, hits,
               doubles, triples, home_runs, rbis, walks, hbp, intentional_walks,
               strikeouts, stolen_bases, caught_stealing, gdp, sac_hits, sac_flies,
               wins, losses, saves, holds, innings_pitched, hits_allowed,
               runs_allowed, earned_runs, walks_allowed, hbp_allowed,
               strikeouts_pitched, home_runs_allowed, qs, complete_games, shutouts
        FROM historical_season_stats WHERE kbo_player_id=%s AND series_type='정규'
        ORDER BY season DESC
    """, (kbo_player_id,))
    cols = [c[0] for c in cur.description]
    stats = [dict(zip(cols, r)) for r in cur.fetchall()]
    career = _aggregate_career(stats) if stats else {}
    recent = stats[0] if stats else None
    return {
        "titles": _career_titles(cur, kbo_player_id, ptype),
        "team_timeline": _team_timeline(cur, kbo_player_id),
        "milestones": _career_milestones(career, ptype, is_active, recent),
        "splits": _player_splits(cur, kbo_player_id),
    }


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


# 부문별 순위 탭과 동일 UI용 — 전 카테고리 번들 (앱 카테고리 value ↔ 컬럼)
_RANK_HIT = {"home_runs": "home_runs", "hits": "hits", "rbis": "rbis", "stolen_bases": "stolen_bases"}
_RANK_PIT = {"wins": "wins", "strikeouts": "strikeouts_pitched", "saves": "saves"}


# historical 컬럼 → 현역 batter/pitcher_stats 컬럼명 차이(다른 것만 매핑, 나머지 동일)
_CUR_COL = {"strikeouts_pitched": "strikeouts"}


def _leader_query(cur, ptype, col, limit):
    """통산 리더 = historical(정규, 1982~) + 현역 current시즌(batter/pitcher_stats 중
    historical에 없는 시즌만 — 멱등 NOT EXISTS) 합산. 활성선수 current 누락(최정 2026 등) 보정.
    col은 화이트리스트(_RANK_*/_LEADER_CATS)라 주입 안전."""
    cur_table = "batter_stats" if ptype == "타자" else "pitcher_stats"
    cur_col = _CUR_COL.get(col, col)
    cur.execute(f"""
        WITH allstat AS (
            SELECT hss.kbo_player_id AS kid, COALESCE(hss.{col}, 0) AS v
            FROM historical_season_stats hss
            WHERE hss.series_type = '정규' AND hss.player_type = %s
            UNION ALL
            SELECT hp.kbo_player_id AS kid, COALESCE(cs.{cur_col}, 0) AS v
            FROM {cur_table} cs
            JOIN historical_players hp ON hp.player_id = cs.player_id
            WHERE NOT EXISTS (
                SELECT 1 FROM historical_season_stats h
                WHERE h.kbo_player_id = hp.kbo_player_id
                  AND h.season = cs.season AND h.series_type = '정규'
            )
        )
        SELECT hp.kbo_player_id, hp.name, hp.player_id,
               t.short_name AS team_code, t.name AS team, SUM(a.v) AS total
        FROM allstat a
        JOIN historical_players hp ON hp.kbo_player_id = a.kid
        LEFT JOIN teams t ON t.id = hp.primary_team_id
        GROUP BY hp.kbo_player_id, hp.name, hp.player_id, t.short_name, t.name
        HAVING SUM(a.v) > 0
        ORDER BY total DESC
        LIMIT %s
    """, (ptype, limit))
    return [
        {"kbo_player_id": r[0], "name": r[1], "is_active": r[2] is not None,
         "team_code": r[3], "team": r[4] or "역대", "profile_image": None,
         "value": int(r[5] or 0)}
        for r in cur.fetchall()
    ]


# ⚠️ /rankings·/leaders 는 /{kbo_player_id} 보다 먼저 선언 (정수경로 오매칭 방지)
@router.get("/rankings")
@cached(3600)
def get_historical_rankings(limit: int = 50):
    """부문별 순위 탭과 동일 구조 — 통산 리더 전 카테고리 일괄 (정규시즌 합산)."""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    hitters = {k: _leader_query(cur, "타자", col, limit) for k, col in _RANK_HIT.items()}
    pitchers = {k: _leader_query(cur, "투수", col, limit) for k, col in _RANK_PIT.items()}
    cur.close(); conn.close()
    return {"hitters": hitters, "pitchers": pitchers}


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


@router.get("/{kbo_player_id}/career-extras")
@cached(3600)
def get_historical_career_extras(kbo_player_id: int):
    """은퇴/역대 선수 상세확장 — 타이틀/팀변천/마일스톤/스플릿 (kbo_player_id 키)."""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    try:
        extras = _career_extras(cur, kbo_player_id)
        if extras is None:
            raise HTTPException(status_code=404, detail="역대 선수를 찾을 수 없습니다")
        return extras
    finally:
        cur.close(); conn.close()
