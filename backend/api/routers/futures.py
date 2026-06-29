from fastapi import APIRouter, HTTPException
from database.connection import get_connection
from api.cache import cached

router = APIRouter()

# 2군 팀코드 → 라벨 (현 10구단 2군 + 상무/고양/울산 + 소프트뱅크 교류전)
_FUT_TEAM = {
    "HH": "한화", "LG": "LG", "WO": "고양", "OB": "두산", "SK": "SSG",
    "SM": "상무", "LT": "롯데", "NC": "NC", "HT": "KIA", "SS": "삼성",
    "KT": "KT", "UL": "울산", "SO": "소프트뱅크",
}


def _label(code):
    return _FUT_TEAM.get(code, code)


@router.get("/games")
@cached(300)
def get_futures_games(season: int, month: int = None):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    where = "WHERE g.season=%s"
    params = [season]
    if month:
        where += " AND EXTRACT(MONTH FROM g.game_date)=%s"
        params.append(month)
    cur.execute(f"""
        SELECT g.game_id, g.game_date, g.away_code, g.home_code, g.away_score,
               g.home_score, g.stadium, g.status, g.series_id,
               (b.game_id IS NOT NULL) AS has_box
        FROM futures_games g
        LEFT JOIN futures_game_box b ON b.game_id = g.game_id
        {where}
        ORDER BY g.game_date, g.game_id
    """, params)
    games = []
    for r in cur.fetchall():
        games.append({
            "game_id": r[0], "game_date": str(r[1]) if r[1] else None,
            "away_code": r[2], "away_label": _label(r[2]),
            "home_code": r[3], "home_label": _label(r[3]),
            "away_score": r[4], "home_score": r[5],
            "stadium": r[6], "status": r[7], "series_id": r[8],
            "is_exhibition": r[8] == 10, "has_box": r[9],
        })
    cur.execute("SELECT DISTINCT EXTRACT(MONTH FROM game_date)::int FROM futures_games WHERE season=%s ORDER BY 1", (season,))
    months = [r[0] for r in cur.fetchall()]
    cur.close(); conn.close()
    return {"games": games, "months": months}


@router.get("/games/{game_id}/box")
@cached(3600)
def get_futures_box(game_id: str):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("""
        SELECT g.game_id, g.game_date, g.away_code, g.home_code, g.away_score,
               g.home_score, g.stadium, g.status, g.series_id,
               b.scoreboard, b.away_batters, b.home_batters, b.pitchers, b.summary
        FROM futures_games g JOIN futures_game_box b ON b.game_id = g.game_id
        WHERE g.game_id=%s
    """, (game_id,))
    r = cur.fetchone()
    cur.close(); conn.close()
    if not r:
        raise HTTPException(status_code=404, detail="박스 없음")
    return {
        "meta": {
            "game_id": r[0], "game_date": str(r[1]) if r[1] else None,
            "away_code": r[2], "away_label": _label(r[2]),
            "home_code": r[3], "home_label": _label(r[3]),
            "away_score": r[4], "home_score": r[5],
            "stadium": r[6], "status": r[7], "series_id": r[8],
        },
        "scoreboard": r[9], "away_batters": r[10], "home_batters": r[11],
        "pitchers": r[12], "summary": r[13],
    }


_FUT_LEADERS = {
    "hitters": [("avg", "avg", True, 50), ("home_runs", "home_runs", True, 1), ("rbis", "rbis", True, 1)],
    "pitchers": [("era", "era", False, 30), ("wins", "wins", True, 1), ("saves", "saves", True, 1)],
}


@router.get("/leaders")
@cached(3600)
def get_futures_leaders(season: int):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    res = {"season": season, "hitters": {}, "pitchers": {}}
    for grp, ptype, cats in [("hitters", "타자", _FUT_LEADERS["hitters"]),
                             ("pitchers", "투수", _FUT_LEADERS["pitchers"])]:
        for key, col, desc, gate in cats:
            # gate = 최소 games (avg/era 비율지표 표본 가드)
            cur.execute(f"""
                SELECT hp.name, f.team_name, f.{col}
                FROM historical_futures_season_stats f
                JOIN historical_players hp ON hp.kbo_player_id = f.kbo_player_id
                WHERE f.season=%s AND f.player_type=%s AND f.{col} IS NOT NULL
                  AND f.games >= %s
                ORDER BY f.{col} {'DESC' if desc else 'ASC'}
                LIMIT 10
            """, (season, ptype, gate))
            res[grp][key] = [
                {"name": x[0], "team_label": _label(x[1]),
                 "value": float(x[2]) if isinstance(x[2], float) or (col in ('avg', 'era')) else int(x[2])}
                for x in cur.fetchall()
            ]
    cur.close(); conn.close()
    return res
