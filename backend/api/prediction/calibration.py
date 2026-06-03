"""KBO 26시즌 데이터 기반 sabermetric 공식 상수/가중치 회귀.
구장별 home advantage, Pythagorean exponent, BABIP 보정, composite weights 모두 fit."""
import os
import math
import json
from database.connection import get_connection

CALIB_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    'models', 'calibration.json'
)

_loaded: dict | None = None


def compute_league_constants(season: int = 2026) -> dict:
    """리그 평균: OPS, FIP, ERA, runs/team/game."""
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT AVG(NULLIF(ops,0))::float, AVG(NULLIF(woba,0))::float
        FROM batter_stats WHERE season=%s AND at_bats > 50
    """, (season,))
    ops, woba = cur.fetchone()
    cur.execute("""
        SELECT AVG(NULLIF(era,0))::float, AVG(NULLIF(fip,0))::float,
               AVG(NULLIF(whip,0))::float
        FROM pitcher_stats WHERE season=%s AND innings_pitched > 10
    """, (season,))
    era, fip, whip = cur.fetchone()
    cur.execute("""
        SELECT AVG(home_score + away_score)::float / 2
        FROM games WHERE status='종료' AND EXTRACT(YEAR FROM game_date)=%s
    """, (season,))
    runs_pg = cur.fetchone()[0]
    cur.close(); conn.close()
    return {
        'league_ops': round(float(ops or 0.74), 3),
        'league_woba': round(float(woba or 0.32), 3),
        'league_era': round(float(era or 4.5), 2),
        'league_fip': round(float(fip or 4.5), 2),
        'league_whip': round(float(whip or 1.4), 2),
        'league_runs_pg': round(float(runs_pg or 4.5), 2),
    }


def fit_pythagorean_exponent(season: int = 2026) -> float:
    """팀별 시즌 누적 (RS, RA, actual_wpct) → exp minimizing RMSE.
    expected_wpct = RS^exp / (RS^exp + RA^exp). KBO 경험적으로 1.80-2.10."""
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT
            t.id,
            SUM(CASE WHEN g.home_team_id=t.id THEN g.home_score ELSE g.away_score END)::float as rs,
            SUM(CASE WHEN g.home_team_id=t.id THEN g.away_score ELSE g.home_score END)::float as ra,
            SUM(CASE
                WHEN g.home_team_id=t.id AND g.home_score > g.away_score THEN 1
                WHEN g.away_team_id=t.id AND g.away_score > g.home_score THEN 1
                ELSE 0 END)::float as wins,
            COUNT(*) FILTER (WHERE g.home_score != g.away_score)::float as decided
        FROM teams t
        JOIN games g ON (g.home_team_id=t.id OR g.away_team_id=t.id)
        WHERE g.status='종료' AND EXTRACT(YEAR FROM g.game_date)=%s
        GROUP BY t.id
    """, (season,))
    rows = cur.fetchall()
    cur.close(); conn.close()
    data = [(float(rs), float(ra), float(w) / float(d) if d > 0 else 0.5)
            for _, rs, ra, w, d in rows if d > 0]
    if not data:
        return 1.83
    best_exp, best_rmse = 1.83, 1e9
    for exp10 in range(150, 251):
        exp = exp10 / 100.0
        sq_err = 0.0
        for rs, ra, actual_wpct in data:
            if rs <= 0 or ra <= 0:
                continue
            pred = (rs ** exp) / ((rs ** exp) + (ra ** exp))
            sq_err += (actual_wpct - pred) ** 2
        rmse = math.sqrt(sq_err / len(data))
        if rmse < best_rmse:
            best_rmse, best_exp = rmse, exp
    return round(best_exp, 2)


def fit_babip_adjustment(season: int = 2026) -> dict:
    """BABIP 분포 → 분위수 기반 cutoff + 회귀로 보정폭 추정.
    25%/75% 분위수를 cutoff로, 평균 BABIP을 기준으로 OPS 영향 회귀."""
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT babip, ops FROM batter_stats
        WHERE season=%s AND at_bats > 100 AND babip > 0 AND ops > 0
        ORDER BY babip
    """, (season,))
    rows = cur.fetchall()
    cur.close(); conn.close()
    if len(rows) < 20:
        return {'lo_cutoff': 0.28, 'hi_cutoff': 0.32, 'lo_mult': 1.03, 'hi_mult': 0.97}

    babips = [float(r[0]) for r in rows]
    ops_vals = [float(r[1]) for r in rows]
    n = len(babips)
    lo_cutoff = babips[n // 4]
    hi_cutoff = babips[3 * n // 4]
    avg_ops = sum(ops_vals) / n

    # 분위수별 OPS 평균 차이 → 보정폭
    lo_ops = [o for b, o in zip(babips, ops_vals) if b <= lo_cutoff]
    hi_ops = [o for b, o in zip(babips, ops_vals) if b >= hi_cutoff]
    lo_mean = sum(lo_ops) / len(lo_ops) if lo_ops else avg_ops
    hi_mean = sum(hi_ops) / len(hi_ops) if hi_ops else avg_ops
    # 보정폭 = 평균으로 회귀하는 비율 (절반 회귀 가정)
    lo_mult = 1.0 + 0.5 * (avg_ops - lo_mean) / lo_mean if lo_mean > 0 else 1.03
    hi_mult = 1.0 - 0.5 * (hi_mean - avg_ops) / hi_mean if hi_mean > 0 else 0.97
    return {
        'lo_cutoff': round(lo_cutoff, 3),
        'hi_cutoff': round(hi_cutoff, 3),
        'lo_mult': round(min(max(lo_mult, 1.0), 1.10), 3),
        'hi_mult': round(min(max(hi_mult, 0.90), 1.0), 3),
    }


def fit_composite_weights(season: int = 2026) -> dict:
    """공격력/투수력 합성 가중치 grid search.
    O = w_season * O_season + (1-w) * O_recent
    P_starter = w_season * P_season + (1-w) * P_recent
    P_total = w_starter * P_starter + (1-w) * P_bullpen
    실제 종료 경기로 sabermetric prediction acc 최대화하는 (w_o, w_p, w_starter) 선택."""
    from api.prediction.features import get_features
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT id FROM games WHERE status='종료'
          AND EXTRACT(YEAR FROM game_date)=%s
          AND home_score != away_score
        ORDER BY game_date
    """, (season,))
    ids = [r[0] for r in cur.fetchall()]
    cur.close(); conn.close()

    if not ids:
        return {'w_offense_season': 0.7, 'w_pitcher_season': 0.7,
                'w_starter': 0.65, 'w_bullpen_fip': 0.8}

    games_data = []
    for gid in ids[:200]:  # 빠른 fit을 위해 표본 제한
        f = get_features(gid)
        if not f:
            continue
        games_data.append({
            'home_won': f.get('home_won', 0),
            'h_wrc': f.get('h_team_wrc_plus', 100),
            'a_wrc': f.get('a_team_wrc_plus', 100),
            'h_ops': f.get('h_team_ops', 0.74),
            'a_ops': f.get('a_team_ops', 0.74),
            'h_recent_ops': f.get('h_recent_ops', 0.74),
            'a_recent_ops': f.get('a_recent_ops', 0.74),
            'h_babip': f.get('h_team_babip', 0.3),
            'a_babip': f.get('a_team_babip', 0.3),
            'h_fip': f.get('h_starter_fip', 4.5),
            'a_fip': f.get('a_starter_fip', 4.5),
            'h_recent_era': f.get('h_starter_recent3_era', 4.5),
            'a_recent_era': f.get('a_starter_recent3_era', 4.5),
            'h_kbb': f.get('h_starter_kbb', 2.5),
            'a_kbb': f.get('a_starter_kbb', 2.5),
            'h_pen_fip': f.get('h_bullpen_fip', 4.5),
            'a_pen_fip': f.get('a_bullpen_fip', 4.5),
            'h_pen_era': f.get('h_bullpen_era', 4.5),
            'a_pen_era': f.get('a_bullpen_era', 4.5),
            'park_runs': f.get('park_runs_factor', 1.0),
        })

    if not games_data:
        return {'w_offense_season': 0.7, 'w_pitcher_season': 0.7,
                'w_starter': 0.65, 'w_bullpen_fip': 0.8}

    league = compute_league_constants(season)
    L_ops, L_fip, L_era, L_runs = (league['league_ops'], league['league_fip'],
                                    league['league_era'], league['league_runs_pg'])
    pyth_exp = fit_pythagorean_exponent(season)

    def simulate(w_o, w_p, w_s, w_pf):
        correct = 0
        for d in games_data:
            # 공격력 (W_o 가중)
            h_o = w_o * (d['h_wrc'] / 100) + (1 - w_o) * (d['h_recent_ops'] / L_ops)
            a_o = w_o * (d['a_wrc'] / 100) + (1 - w_o) * (d['a_recent_ops'] / L_ops)
            # 선발 (w_p 가중)
            h_p_st = w_p * (L_fip / max(d['h_fip'], 0.1)) + (1 - w_p) * (L_era / max(d['h_recent_era'], 0.1))
            a_p_st = w_p * (L_fip / max(d['a_fip'], 0.1)) + (1 - w_p) * (L_era / max(d['a_recent_era'], 0.1))
            # K/BB 보정
            if d['h_kbb'] > 3: h_p_st *= 1.05
            elif d['h_kbb'] < 2: h_p_st *= 0.95
            if d['a_kbb'] > 3: a_p_st *= 1.05
            elif d['a_kbb'] < 2: a_p_st *= 0.95
            # 불펜 (w_pf 가중)
            h_p_pen = w_pf * (L_fip / max(d['h_pen_fip'], 0.1)) + (1 - w_pf) * (L_era / max(d['h_pen_era'], 0.1))
            a_p_pen = w_pf * (L_fip / max(d['a_pen_fip'], 0.1)) + (1 - w_pf) * (L_era / max(d['a_pen_era'], 0.1))
            # P_total
            h_p_t = w_s * h_p_st + (1 - w_s) * h_p_pen
            a_p_t = w_s * a_p_st + (1 - w_s) * a_p_pen
            # 예상 득점 (park 보정 home advantage)
            home_adv = 1.0 + 0.04 * d['park_runs']
            h_runs = L_runs * h_o * a_p_t * home_adv
            a_runs = L_runs * a_o * h_p_t
            # Pythagorean
            denom = (h_runs ** pyth_exp) + (a_runs ** pyth_exp)
            pred_home_prob = (h_runs ** pyth_exp) / denom if denom > 0 else 0.5
            pred = 1 if pred_home_prob > 0.5 else 0
            if pred == d['home_won']:
                correct += 1
        return correct / len(games_data)

    best = (0.7, 0.7, 0.65, 0.8)
    best_acc = 0.0
    for w_o in [0.5, 0.6, 0.7, 0.8]:
        for w_p in [0.5, 0.6, 0.7, 0.8]:
            for w_s in [0.5, 0.6, 0.65, 0.7, 0.8]:
                for w_pf in [0.6, 0.7, 0.8, 0.9]:
                    acc = simulate(w_o, w_p, w_s, w_pf)
                    if acc > best_acc:
                        best_acc, best = acc, (w_o, w_p, w_s, w_pf)
    return {
        'w_offense_season': best[0],
        'w_pitcher_season': best[1],
        'w_starter': best[2],
        'w_bullpen_fip': best[3],
        'fitted_acc': round(best_acc, 3),
    }


def calibrate_all(season: int = 2026) -> dict:
    """전체 calibration 수행 + JSON 저장."""
    league = compute_league_constants(season)
    pyth_exp = fit_pythagorean_exponent(season)
    babip = fit_babip_adjustment(season)
    weights = fit_composite_weights(season)
    result = {
        'season': season,
        'league': league,
        'pythagorean_exponent': pyth_exp,
        'babip': babip,
        'composite_weights': weights,
    }
    os.makedirs(os.path.dirname(CALIB_PATH), exist_ok=True)
    with open(CALIB_PATH, 'w') as f:
        json.dump(result, f, indent=2)
    print(f"[calibration] 저장: {CALIB_PATH}")
    print(json.dumps(result, indent=2))
    return result


def get_calibration() -> dict:
    """캐시 우선, 없으면 기본값."""
    global _loaded
    if _loaded is not None:
        return _loaded
    if os.path.exists(CALIB_PATH):
        try:
            with open(CALIB_PATH) as f:
                _loaded = json.load(f)
                return _loaded
        except Exception:
            pass
    # 기본값
    _loaded = {
        'season': 2026,
        'league': {'league_ops': 0.74, 'league_woba': 0.32,
                   'league_era': 4.5, 'league_fip': 4.5,
                   'league_whip': 1.4, 'league_runs_pg': 4.5},
        'pythagorean_exponent': 1.83,
        'babip': {'lo_cutoff': 0.28, 'hi_cutoff': 0.32, 'lo_mult': 1.03, 'hi_mult': 0.97},
        'composite_weights': {'w_offense_season': 0.7, 'w_pitcher_season': 0.7,
                              'w_starter': 0.65, 'w_bullpen_fip': 0.8},
    }
    return _loaded


def invalidate():
    global _loaded
    _loaded = None


if __name__ == '__main__':
    import sys
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    calibrate_all()
