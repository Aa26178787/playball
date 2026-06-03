"""승리 예측 features — game_id로 모든 feature 산출.
26시즌 종료 게임 기반 학습/예측 공통."""
from database.connection import get_connection
from api.prediction.park_factors import get_park_factors


def _f(v, default=0.0):
    """None / Decimal → float."""
    if v is None:
        return default
    try:
        return float(v)
    except Exception:
        return default


def _team_season_stats(cur, team_id: int, season: int) -> dict:
    """팀 시즌 누적 stats from teams + game_batters/game_pitchers 집계."""
    cur.execute("""
        SELECT wins, losses, draws, win_rate
        FROM teams WHERE id = %s
    """, (team_id,))
    row = cur.fetchone()
    wins, losses, draws, wpct = (row or (0, 0, 0, 0))

    # 득점/실점 (게임 단위 합산)
    cur.execute("""
        SELECT
            SUM(CASE WHEN home_team_id=%s THEN home_score ELSE away_score END)::float as rs,
            SUM(CASE WHEN home_team_id=%s THEN away_score ELSE home_score END)::float as ra,
            COUNT(*) as g
        FROM games
        WHERE (home_team_id=%s OR away_team_id=%s)
          AND status='종료' AND EXTRACT(YEAR FROM game_date)=%s
    """, (team_id, team_id, team_id, team_id, season))
    rs, ra, g = cur.fetchone()
    rs, ra, g = _f(rs), _f(ra), max(int(g or 1), 1)

    rs_pg = rs / g
    ra_pg = ra / g

    # Pythagorean 승률 (지수 1.83 → 야구 표준 ~1.8-2.0)
    if rs == 0 and ra == 0:
        pyth_wpct = 0.5
    else:
        pyth_wpct = (rs ** 1.83) / ((rs ** 1.83) + (ra ** 1.83))

    return {
        'wpct': _f(wpct),
        'pyth_wpct': round(pyth_wpct, 3),
        'rs_pg': round(rs_pg, 2),
        'ra_pg': round(ra_pg, 2),
        'games_played': g,
    }


def _team_batting_stats(cur, team_id: int, season: int) -> dict:
    """팀 타격 집계 from batter_stats. wRC+/BABIP 포함."""
    cur.execute("""
        SELECT
            AVG(NULLIF(avg,0))::float as team_avg,
            AVG(NULLIF(ops,0))::float as team_ops,
            AVG(NULLIF(obp,0))::float as team_obp,
            AVG(NULLIF(slg,0))::float as team_slg,
            AVG(NULLIF(woba,0))::float as team_woba,
            AVG(NULLIF(wrc_plus,0))::float as team_wrc_plus,
            AVG(NULLIF(babip,0))::float as team_babip
        FROM batter_stats bs
        JOIN players p ON p.id = bs.player_id
        WHERE p.team_id=%s AND bs.season=%s AND bs.at_bats > 50
    """, (team_id, season))
    row = cur.fetchone() or (0,0,0,0,0,0,0)
    return {
        'team_avg': round(_f(row[0]), 3),
        'team_ops': round(_f(row[1]), 3),
        'team_obp': round(_f(row[2]), 3),
        'team_slg': round(_f(row[3]), 3),
        'team_woba': round(_f(row[4]), 3),
        'team_wrc_plus': round(_f(row[5], 100), 1),
        'team_babip': round(_f(row[6]), 3),
    }


def _team_recent_batting(cur, team_id: int, before_date, n: int = 10) -> dict:
    """팀 최근 N경기 OPS/wOBA — 시즌 누적과 분리한 폼 신호."""
    cur.execute("""
        WITH recent_games AS (
            SELECT id FROM games
            WHERE (home_team_id=%s OR away_team_id=%s)
              AND status='종료' AND game_date < %s
            ORDER BY game_date DESC LIMIT %s
        )
        SELECT
            SUM(COALESCE(gb.at_bats,0))::float as ab,
            SUM(COALESCE(gb.hits,0))::float as h,
            SUM(COALESCE(gb.walks,0))::float as bb,
            SUM(COALESCE(gb.rbis,0))::float as rbi,
            SUM(COALESCE(gb.home_runs,0))::float as hr,
            SUM(COALESCE(gb.runs,0))::float as r
        FROM game_batters gb
        WHERE gb.game_id IN (SELECT id FROM recent_games)
          AND ((gb.team_side='home' AND EXISTS (SELECT 1 FROM games g WHERE g.id=gb.game_id AND g.home_team_id=%s))
            OR (gb.team_side='away' AND EXISTS (SELECT 1 FROM games g WHERE g.id=gb.game_id AND g.away_team_id=%s)))
    """, (team_id, team_id, before_date, n, team_id, team_id))
    row = cur.fetchone() or (0, 0, 0, 0, 0, 0)
    ab, h, bb, rbi, hr, r = (_f(x) for x in row)
    obp = (h + bb) / (ab + bb) if (ab + bb) > 0 else 0.0
    # 단순 TB 추정: HR=4, 그 외 단타로 가정 (game_batters에 doubles/triples 없음)
    tb = (h - hr) + 4 * hr
    slg = tb / ab if ab > 0 else 0.0
    return {
        'recent_ops': round(obp + slg, 3),
        'recent_obp': round(obp, 3),
        'recent_slg': round(slg, 3),
    }


def _team_pitching_stats(cur, team_id: int, season: int) -> dict:
    cur.execute("""
        SELECT
            AVG(NULLIF(era,0))::float as team_era,
            AVG(NULLIF(whip,0))::float as team_whip,
            AVG(NULLIF(fip,0))::float as team_fip,
            AVG(NULLIF(k_per_9,0))::float as team_k9,
            AVG(NULLIF(bb_per_9,0))::float as team_bb9
        FROM pitcher_stats ps
        JOIN players p ON p.id = ps.player_id
        WHERE p.team_id=%s AND ps.season=%s AND ps.innings_pitched > 10
    """, (team_id, season))
    row = cur.fetchone() or (0,0,0,0,0)
    return {
        'team_era': round(_f(row[0]), 2),
        'team_whip': round(_f(row[1]), 2),
        'team_fip': round(_f(row[2]), 2),
        'team_k9': round(_f(row[3]), 2),
        'team_bb9': round(_f(row[4]), 2),
    }


def _starter_stats(cur, game_id: int, team_side: str, season: int,
                   opponent_team_id: int = 0) -> dict:
    """선발투수 시즌 stats + 최근 3등판 ERA + 상대팀 시즌 ERA + K/BB ratio.
    pitching_order 0/1 혼재 → MIN."""
    cur.execute("""
        SELECT gp.player_id, p.name
        FROM game_pitchers gp
        JOIN players p ON p.id = gp.player_id
        WHERE gp.game_id=%s AND gp.team_side=%s
        ORDER BY gp.pitching_order ASC NULLS LAST
        LIMIT 1
    """, (game_id, team_side))
    row = cur.fetchone()
    if not row:
        return {'starter_name': '', 'starter_era': 0, 'starter_whip': 0, 'starter_fip': 0,
                'starter_k9': 0, 'starter_bb9': 0, 'starter_kbb': 0,
                'starter_recent3_era': 0, 'starter_vs_opp_era': 0,
                'starter_player_id': 0}
    pid, name = row

    cur.execute("""
        SELECT era, whip, fip, k_per_9, bb_per_9, strikeouts, walks
        FROM pitcher_stats WHERE player_id=%s AND season=%s
    """, (pid, season))
    sr = cur.fetchone() or (0,0,0,0,0,0,0)
    so_total = _f(sr[5])
    bb_total = _f(sr[6])
    kbb = (so_total / bb_total) if bb_total > 0 else 0.0

    # 최근 3등판 ERA from player_daily_stats
    cur.execute("""
        SELECT SUM(er)::float, SUM(ip)::float
        FROM (
            SELECT er, ip FROM player_daily_stats
            WHERE player_id=%s AND stat_type='pitcher'
              AND game_date < (SELECT game_date FROM games WHERE id=%s)
            ORDER BY game_date DESC LIMIT 3
        ) recent
    """, (pid, game_id))
    rsum, ipsum = cur.fetchone() or (0, 0)
    recent_era = (_f(rsum) * 9 / _f(ipsum, 1)) if _f(ipsum) > 0 else _f(sr[0])

    # 상대팀 시즌 ERA (해당 투수가 그 팀 상대로 등판한 경기들 누적)
    vs_opp_era = _f(sr[0])
    if opponent_team_id:
        cur.execute("""
            SELECT SUM(er)::float, SUM(ip)::float
            FROM player_daily_stats pds
            WHERE pds.player_id=%s AND pds.stat_type='pitcher'
              AND pds.opponent = (SELECT name FROM teams WHERE id=%s)
              AND pds.game_date < (SELECT game_date FROM games WHERE id=%s)
              AND EXTRACT(YEAR FROM pds.game_date)=%s
        """, (pid, opponent_team_id, game_id, season))
        vs_row = cur.fetchone() or (0, 0)
        ver, vip = _f(vs_row[0]), _f(vs_row[1])
        if vip > 0:
            vs_opp_era = ver * 9 / vip

    return {
        'starter_player_id': pid,
        'starter_name': name,
        'starter_era': round(_f(sr[0]), 2),
        'starter_whip': round(_f(sr[1]), 2),
        'starter_fip': round(_f(sr[2]), 2),
        'starter_k9': round(_f(sr[3]), 2),
        'starter_bb9': round(_f(sr[4]), 2),
        'starter_kbb': round(kbb, 2),
        'starter_recent3_era': round(recent_era, 2),
        'starter_vs_opp_era': round(vs_opp_era, 2),
    }


def _lineup_stats(cur, game_id: int, team_side: str, season: int) -> dict:
    """선발 라인업 9명 평균 + 합산 OPS/wOBA + wRC+. 라인업 미공개 시 팀 평균 fallback."""
    cur.execute("""
        SELECT AVG(NULLIF(bs.ops, 0))::float, AVG(NULLIF(bs.woba, 0))::float,
               AVG(NULLIF(bs.avg, 0))::float,
               SUM(NULLIF(bs.woba, 0))::float,
               AVG(NULLIF(bs.wrc_plus, 0))::float,
               COUNT(NULLIF(bs.ops, 0))::int
        FROM game_rosters gr
        JOIN players p ON p.id = gr.player_id
        LEFT JOIN batter_stats bs ON bs.player_id = gr.player_id AND bs.season=%s
        WHERE gr.game_id=%s AND gr.team_side=%s
          AND gr.batting_order BETWEEN 1 AND 9
    """, (season, game_id, team_side))
    row = cur.fetchone() or (0, 0, 0, 0, 0, 0)
    ops, woba, avg = _f(row[0]), _f(row[1]), _f(row[2])
    woba_sum = _f(row[3])
    wrc_plus = _f(row[4], 100)
    lineup_count = int(row[5] or 0)
    # 라인업 미공개 시 팀 평균 fallback (예정 게임)
    if ops == 0 and woba == 0:
        cur.execute("""
            SELECT g.home_team_id, g.away_team_id FROM games g WHERE g.id=%s
        """, (game_id,))
        teams_row = cur.fetchone()
        if teams_row:
            team_id = teams_row[0] if team_side == 'home' else teams_row[1]
            cur.execute("""
                SELECT AVG(NULLIF(ops,0))::float, AVG(NULLIF(woba,0))::float,
                       AVG(NULLIF(avg,0))::float, SUM(NULLIF(woba,0))::float,
                       AVG(NULLIF(wrc_plus,0))::float
                FROM batter_stats bs JOIN players p ON p.id=bs.player_id
                WHERE p.team_id=%s AND bs.season=%s AND bs.at_bats > 50
            """, (team_id, season))
            r2 = cur.fetchone() or (0, 0, 0, 0, 0)
            ops, woba, avg = _f(r2[0]), _f(r2[1]), _f(r2[2])
            woba_sum = _f(r2[3])
            wrc_plus = _f(r2[4], 100)
    return {
        'lineup_ops': round(ops, 3),
        'lineup_woba': round(woba, 3),
        'lineup_avg': round(avg, 3),
        'lineup_woba_sum': round(woba_sum, 3),
        'lineup_wrc_plus': round(wrc_plus, 1),
    }


def _bullpen_stats(cur, team_id: int, season: int) -> dict:
    """팀 불펜 (비선발) ERA/WHIP/FIP."""
    cur.execute("""
        SELECT AVG(NULLIF(ps.era, 0))::float, AVG(NULLIF(ps.whip, 0))::float,
               AVG(NULLIF(ps.fip, 0))::float
        FROM pitcher_stats ps
        JOIN players p ON p.id = ps.player_id
        WHERE p.team_id=%s AND ps.season=%s
          AND ps.innings_pitched > 5
          AND ps.games > ps.cg
          AND COALESCE(ps.wins,0) + COALESCE(ps.losses,0) < ps.games * 0.6
    """, (team_id, season))
    row = cur.fetchone() or (0, 0, 0)
    return {
        'bullpen_era': round(_f(row[0]), 2),
        'bullpen_whip': round(_f(row[1]), 2),
        'bullpen_fip': round(_f(row[2]), 2),
    }


def _bullpen_load(cur, team_id: int, before_date, days: int = 3) -> dict:
    """불펜 직전 N일 등판 IP 합 — 피로도 정량화."""
    cur.execute("""
        SELECT COALESCE(SUM(pds.ip), 0)::float
        FROM player_daily_stats pds
        JOIN players p ON p.id = pds.player_id
        JOIN game_pitchers gp ON gp.player_id = pds.player_id
        JOIN games g ON g.id = gp.game_id AND g.game_date = pds.game_date
        WHERE p.team_id=%s
          AND pds.stat_type='pitcher'
          AND gp.pitching_order > 1
          AND pds.game_date BETWEEN %s::date - INTERVAL '%s days' AND %s::date - INTERVAL '1 day'
    """, (team_id, before_date, days, before_date))
    ip_sum = _f((cur.fetchone() or [0])[0])
    return {'bullpen_recent_ip': round(ip_sum, 1)}


def _streak(cur, team_id: int, before_date) -> dict:
    """최근 연승/연패 streak (양수=연승, 음수=연패)."""
    cur.execute("""
        SELECT
            CASE
                WHEN home_team_id=%s AND home_score > away_score THEN 1
                WHEN away_team_id=%s AND away_score > home_score THEN 1
                ELSE 0
            END as won
        FROM games
        WHERE (home_team_id=%s OR away_team_id=%s)
          AND status='종료' AND game_date < %s
          AND home_score != away_score
        ORDER BY game_date DESC LIMIT 5
    """, (team_id, team_id, team_id, team_id, before_date))
    results = [r[0] for r in cur.fetchall()]
    if not results:
        return {'streak': 0, 'win_streak_3plus': 0, 'lose_streak_3plus': 0}
    streak = 0
    first = results[0]
    for r in results:
        if r == first:
            streak += 1
        else:
            break
    sign = streak if first == 1 else -streak
    return {
        'streak': sign,
        'win_streak_3plus': 1 if sign >= 3 else 0,
        'lose_streak_3plus': 1 if sign <= -3 else 0,
    }


def _h2h(cur, home_team_id: int, away_team_id: int, season: int) -> dict:
    """시즌 상대전적 (home 기준 wpct)."""
    cur.execute("""
        SELECT
            SUM(CASE WHEN home_score > away_score THEN 1 ELSE 0 END) home_wins,
            SUM(CASE WHEN home_score < away_score THEN 1 ELSE 0 END) home_losses,
            COUNT(*) total
        FROM games
        WHERE home_team_id=%s AND away_team_id=%s
          AND status='종료' AND EXTRACT(YEAR FROM game_date)=%s
    """, (home_team_id, away_team_id, season))
    h_w, h_l, total = cur.fetchone() or (0, 0, 0)
    cur.execute("""
        SELECT
            SUM(CASE WHEN home_score > away_score THEN 1 ELSE 0 END) away_l,
            SUM(CASE WHEN home_score < away_score THEN 1 ELSE 0 END) away_w,
            COUNT(*) total2
        FROM games
        WHERE home_team_id=%s AND away_team_id=%s
          AND status='종료' AND EXTRACT(YEAR FROM game_date)=%s
    """, (away_team_id, home_team_id, season))
    a_l, a_w, t2 = cur.fetchone() or (0, 0, 0)
    home_wins = (h_w or 0) + (a_w or 0)
    home_losses = (h_l or 0) + (a_l or 0)
    total_games = home_wins + home_losses
    return {
        'h2h_home_wins': home_wins,
        'h2h_home_losses': home_losses,
        'h2h_wpct': round(home_wins / total_games, 3) if total_games > 0 else 0.5,
        'h2h_games': total_games,
    }


def _recent_form(cur, team_id: int, before_date, n: int = 10) -> dict:
    """최근 N경기 승률 + 평균 득/실점."""
    cur.execute("""
        SELECT
            SUM(CASE
                WHEN home_team_id=%s AND home_score > away_score THEN 1
                WHEN away_team_id=%s AND away_score > home_score THEN 1
                ELSE 0 END)::float as wins,
            SUM(CASE
                WHEN home_team_id=%s AND home_score < away_score THEN 1
                WHEN away_team_id=%s AND away_score < home_score THEN 1
                ELSE 0 END)::float as losses,
            AVG(CASE WHEN home_team_id=%s THEN home_score ELSE away_score END)::float as avg_rs,
            AVG(CASE WHEN home_team_id=%s THEN away_score ELSE home_score END)::float as avg_ra,
            COUNT(*) as games
        FROM (
            SELECT * FROM games
            WHERE (home_team_id=%s OR away_team_id=%s)
              AND status='종료'
              AND game_date < %s
            ORDER BY game_date DESC LIMIT %s
        ) recent
    """, (team_id, team_id, team_id, team_id, team_id, team_id, team_id, team_id, before_date, n))
    row = cur.fetchone() or (0, 0, 0, 0, 0)
    w, l, rs, ra, g = row
    g = int(g or 0)
    wpct = (_f(w) / g) if g > 0 else 0.5
    return {
        'recent_wpct': round(wpct, 3),
        'recent_rs_pg': round(_f(rs), 2),
        'recent_ra_pg': round(_f(ra), 2),
        'recent_games': g,
    }


def _bullpen_rest(cur, team_id: int, before_date) -> dict:
    """불펜 휴식 점수 — 어제 등판 투수 수 (낮을수록 휴식 충분)."""
    cur.execute("""
        SELECT COUNT(DISTINCT gp.player_id)
        FROM game_pitchers gp
        JOIN games g ON g.id = gp.game_id
        JOIN players p ON p.id = gp.player_id
        WHERE p.team_id=%s
          AND g.game_date = %s::date - INTERVAL '1 day'
          AND gp.pitching_order > 1
    """, (team_id, before_date))
    used_yesterday = cur.fetchone()[0] or 0
    return {'bullpen_rest_score': round(1.0 - (used_yesterday / 7.0), 3)}


def _context_features(cur, game_id: int, home_id: int, away_id: int, gdate) -> dict:
    """요일/주말/더블헤더 등 컨텍스트 features + interaction."""
    dow = gdate.weekday()  # 0=월, 6=일
    is_weekend = 1 if dow >= 5 else 0
    # 더블헤더: 같은 날 같은 두 팀 게임이 2개
    cur.execute("""
        SELECT COUNT(*) FROM games
        WHERE game_date=%s
          AND ((home_team_id=%s AND away_team_id=%s) OR (home_team_id=%s AND away_team_id=%s))
    """, (gdate, home_id, away_id, away_id, home_id))
    same_day = cur.fetchone()[0] or 1
    is_dh = 1 if same_day > 1 else 0
    # 직전 경기 우천 취소 (양 팀 어느쪽이라도)
    cur.execute("""
        SELECT COUNT(*) FROM games
        WHERE status='취소'
          AND game_date = %s::date - INTERVAL '1 day'
          AND (home_team_id IN (%s,%s) OR away_team_id IN (%s,%s))
    """, (gdate, home_id, away_id, home_id, away_id))
    rain_prev = 1 if (cur.fetchone()[0] or 0) > 0 else 0
    return {
        'day_of_week': dow,
        'is_weekend': is_weekend,
        'is_doubleheader': is_dh,
        'rain_delay_prev': rain_prev,
        # interaction: 평일 더블헤더 (피로 가중)
        'weekday_doubleheader': is_dh * (1 - is_weekend),
    }


def _cap_outliers(features: dict) -> dict:
    """이상치 capping — 회귀 모델 robustness."""
    caps = {
        'h_lineup_ops': (0, 1.2), 'a_lineup_ops': (0, 1.2),
        'h_starter_recent3_era': (1.0, 15.0), 'a_starter_recent3_era': (1.0, 15.0),
        'h_starter_era': (0.5, 15.0), 'a_starter_era': (0.5, 15.0),
        'h_bullpen_era': (1.0, 12.0), 'a_bullpen_era': (1.0, 12.0),
        'h_team_ops': (0.5, 1.0), 'a_team_ops': (0.5, 1.0),
        'h_team_wrc_plus': (50, 180), 'a_team_wrc_plus': (50, 180),
        'h_starter_kbb': (0, 10), 'a_starter_kbb': (0, 10),
    }
    for k, (lo, hi) in caps.items():
        if k in features and features[k]:
            v = features[k]
            features[k] = max(lo, min(hi, v))
    return features


def _composite_pitching(season_fip: float, recent_era: float, kbb: float,
                        league_fip: float = 4.5, league_era: float = 4.5) -> float:
    """사용자 공식 [2][3] 합성 투수력 P_starter.
    P_season = league_FIP/pitcher_FIP, P_recent = league_ERA/recent_ERA
    K/BB 보정 적용."""
    p_season = league_fip / season_fip if season_fip > 0 else 1.0
    p_recent = league_era / recent_era if recent_era > 0 else 1.0
    if kbb > 3:
        p_recent *= 1.05
    elif kbb < 2:
        p_recent *= 0.95
    return round(0.7 * p_season + 0.3 * p_recent, 3)


def _composite_offense(wrc_plus: float, season_ops: float, recent_ops: float,
                       babip: float, league_ops: float = 0.74) -> float:
    """사용자 공식 [1] 공격력 O.
    O_season = wRC+/100, O_recent = OPS/league_OPS
    BABIP 보정 적용."""
    o_season = wrc_plus / 100 if wrc_plus else 1.0
    if recent_ops <= 0:
        recent_ops = season_ops
    o_recent = recent_ops / league_ops if league_ops > 0 else 1.0
    o = 0.7 * o_season + 0.3 * o_recent
    if babip > 0.320:
        o *= 0.97
    elif 0 < babip < 0.280:
        o *= 1.03
    return round(o, 3)


def _pythag_expected_runs(o_team: float, p_opp_total: float,
                          league_runs: float = 4.5, home_adv: bool = False) -> float:
    """사용자 공식 [5][6] 예상 득점. runs = league_runs * O * P_opp."""
    runs = league_runs * o_team * p_opp_total
    if home_adv:
        runs *= 1.04
    return round(runs, 2)


def get_features(game_id: int, season: int = 2026) -> dict:
    """게임 1건의 전체 feature dict.
    예측/학습 공통 — game_date 시점 기준 prior data만 사용."""
    conn = get_connection()
    if not conn:
        return {}
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT home_team_id, away_team_id, stadium_id, game_date,
                   home_score, away_score, status
            FROM games WHERE id=%s
        """, (game_id,))
        row = cur.fetchone()
        if not row:
            return {}
        home_id, away_id, stadium_id, gdate, hs, as_, status = row

        park_factors = get_park_factors(season)
        pf = park_factors.get(stadium_id, {'runs': 1.0, 'hr': 1.0})

        # 팀
        h_season = _team_season_stats(cur, home_id, season)
        a_season = _team_season_stats(cur, away_id, season)
        h_bat = _team_batting_stats(cur, home_id, season)
        a_bat = _team_batting_stats(cur, away_id, season)
        h_pit = _team_pitching_stats(cur, home_id, season)
        a_pit = _team_pitching_stats(cur, away_id, season)

        # 선발 (상대팀 ID 전달 → vs_opp_era 계산)
        h_st = _starter_stats(cur, game_id, 'home', season, opponent_team_id=away_id)
        a_st = _starter_stats(cur, game_id, 'away', season, opponent_team_id=home_id)

        # 라인업
        h_line = _lineup_stats(cur, game_id, 'home', season)
        a_line = _lineup_stats(cur, game_id, 'away', season)

        # 불펜
        h_pen = _bullpen_stats(cur, home_id, season)
        a_pen = _bullpen_stats(cur, away_id, season)
        h_rest = _bullpen_rest(cur, home_id, gdate)
        a_rest = _bullpen_rest(cur, away_id, gdate)
        h_load = _bullpen_load(cur, home_id, gdate, days=3)
        a_load = _bullpen_load(cur, away_id, gdate, days=3)

        # 팀 최근 10경기 OPS
        h_recent_bat = _team_recent_batting(cur, home_id, gdate, n=10)
        a_recent_bat = _team_recent_batting(cur, away_id, gdate, n=10)

        # 상대전적
        h2h = _h2h(cur, home_id, away_id, season)

        # 최근 폼
        h_form = _recent_form(cur, home_id, gdate, 10)
        a_form = _recent_form(cur, away_id, gdate, 10)

        # streak
        h_streak = _streak(cur, home_id, gdate)
        a_streak = _streak(cur, away_id, gdate)

        # 컨텍스트
        ctx = _context_features(cur, game_id, home_id, away_id, gdate)

        cur.close()

        # 사용자 공식 [2][3][4] 합성 투수력
        h_p_starter = _composite_pitching(h_st['starter_fip'], h_st['starter_recent3_era'], h_st['starter_kbb'])
        a_p_starter = _composite_pitching(a_st['starter_fip'], a_st['starter_recent3_era'], a_st['starter_kbb'])
        # 불펜 P = 0.8 * (league_FIP/bullpen_FIP) + 0.2 * (league_ERA/bullpen_recent_ERA)
        h_p_bullpen = round(
            0.8 * (4.5 / h_pen['bullpen_fip'] if h_pen['bullpen_fip'] > 0 else 1.0) +
            0.2 * (4.5 / h_pen['bullpen_era'] if h_pen['bullpen_era'] > 0 else 1.0), 3)
        a_p_bullpen = round(
            0.8 * (4.5 / a_pen['bullpen_fip'] if a_pen['bullpen_fip'] > 0 else 1.0) +
            0.2 * (4.5 / a_pen['bullpen_era'] if a_pen['bullpen_era'] > 0 else 1.0), 3)
        h_p_total = round(0.65 * h_p_starter + 0.35 * h_p_bullpen, 3)
        a_p_total = round(0.65 * a_p_starter + 0.35 * a_p_bullpen, 3)
        # 사용자 공식 [1] 공격력
        h_o = _composite_offense(h_bat['team_wrc_plus'], h_bat['team_ops'],
                                  h_recent_bat['recent_ops'], h_bat['team_babip'])
        a_o = _composite_offense(a_bat['team_wrc_plus'], a_bat['team_ops'],
                                  a_recent_bat['recent_ops'], a_bat['team_babip'])
        # 사용자 공식 [5][6] 예상 득점
        h_exp_runs = _pythag_expected_runs(h_o, a_p_total, home_adv=True)
        a_exp_runs = _pythag_expected_runs(a_o, h_p_total, home_adv=False)
        # Pythagorean 게임 단위 win prob (참고용 — feature)
        if (h_exp_runs ** 2 + a_exp_runs ** 2) > 0:
            sabermetric_home_win_prob = round(
                (h_exp_runs ** 2) / (h_exp_runs ** 2 + a_exp_runs ** 2), 3)
        else:
            sabermetric_home_win_prob = 0.54

        features = {
            'game_id': game_id,
            'home_team_id': home_id,
            'away_team_id': away_id,
            'stadium_id': stadium_id,
            'game_date': gdate.isoformat(),
            # outcome (학습용)
            'home_won': 1 if (hs or 0) > (as_ or 0) else 0,
            'status': status,
            # 팀 시즌
            'h_wpct': h_season['wpct'], 'a_wpct': a_season['wpct'],
            'h_pyth_wpct': h_season['pyth_wpct'], 'a_pyth_wpct': a_season['pyth_wpct'],
            'h_rs_pg': h_season['rs_pg'], 'a_rs_pg': a_season['rs_pg'],
            'h_ra_pg': h_season['ra_pg'], 'a_ra_pg': a_season['ra_pg'],
            # 타격
            'h_team_ops': h_bat['team_ops'], 'a_team_ops': a_bat['team_ops'],
            'h_team_woba': h_bat['team_woba'], 'a_team_woba': a_bat['team_woba'],
            # 투수팀
            'h_team_era': h_pit['team_era'], 'a_team_era': a_pit['team_era'],
            'h_team_whip': h_pit['team_whip'], 'a_team_whip': a_pit['team_whip'],
            # 선발
            'h_starter_era': h_st['starter_era'], 'a_starter_era': a_st['starter_era'],
            'h_starter_whip': h_st['starter_whip'], 'a_starter_whip': a_st['starter_whip'],
            'h_starter_fip': h_st['starter_fip'], 'a_starter_fip': a_st['starter_fip'],
            'h_starter_recent3_era': h_st['starter_recent3_era'],
            'a_starter_recent3_era': a_st['starter_recent3_era'],
            'h_starter_name': h_st['starter_name'], 'a_starter_name': a_st['starter_name'],
            # 신규 sabermetric
            'h_team_wrc_plus': h_bat['team_wrc_plus'], 'a_team_wrc_plus': a_bat['team_wrc_plus'],
            'h_team_babip': h_bat['team_babip'], 'a_team_babip': a_bat['team_babip'],
            'h_recent_ops': h_recent_bat['recent_ops'], 'a_recent_ops': a_recent_bat['recent_ops'],
            'h_starter_bb9': h_st['starter_bb9'], 'a_starter_bb9': a_st['starter_bb9'],
            'h_starter_kbb': h_st['starter_kbb'], 'a_starter_kbb': a_st['starter_kbb'],
            'h_starter_vs_opp_era': h_st['starter_vs_opp_era'],
            'a_starter_vs_opp_era': a_st['starter_vs_opp_era'],
            # 라인업 (avg + sum + wRC+)
            'h_lineup_ops': h_line['lineup_ops'], 'a_lineup_ops': a_line['lineup_ops'],
            'h_lineup_woba': h_line['lineup_woba'], 'a_lineup_woba': a_line['lineup_woba'],
            'h_lineup_woba_sum': h_line['lineup_woba_sum'], 'a_lineup_woba_sum': a_line['lineup_woba_sum'],
            'h_lineup_wrc_plus': h_line['lineup_wrc_plus'], 'a_lineup_wrc_plus': a_line['lineup_wrc_plus'],
            # 불펜 (FIP 추가 + 부하)
            'h_bullpen_era': h_pen['bullpen_era'], 'a_bullpen_era': a_pen['bullpen_era'],
            'h_bullpen_fip': h_pen['bullpen_fip'], 'a_bullpen_fip': a_pen['bullpen_fip'],
            'h_bullpen_rest': h_rest['bullpen_rest_score'],
            'a_bullpen_rest': a_rest['bullpen_rest_score'],
            'h_bullpen_recent_ip': h_load['bullpen_recent_ip'],
            'a_bullpen_recent_ip': a_load['bullpen_recent_ip'],
            # 사용자 공식 합성 (P_total, O, Pythagorean expected runs)
            'h_p_starter': h_p_starter, 'a_p_starter': a_p_starter,
            'h_p_bullpen': h_p_bullpen, 'a_p_bullpen': a_p_bullpen,
            'h_p_total': h_p_total, 'a_p_total': a_p_total,
            'h_offense_o': h_o, 'a_offense_o': a_o,
            'h_exp_runs': h_exp_runs, 'a_exp_runs': a_exp_runs,
            'sabermetric_home_win_prob': sabermetric_home_win_prob,
            # 상대전적
            'h2h_wpct': h2h['h2h_wpct'], 'h2h_games': h2h['h2h_games'],
            # 폼
            'h_recent_wpct': h_form['recent_wpct'], 'a_recent_wpct': a_form['recent_wpct'],
            'h_recent_rs': h_form['recent_rs_pg'], 'a_recent_rs': a_form['recent_rs_pg'],
            'h_recent_ra': h_form['recent_ra_pg'], 'a_recent_ra': a_form['recent_ra_pg'],
            # streak (momentum)
            'h_streak': h_streak['streak'], 'a_streak': a_streak['streak'],
            'h_win_streak_3plus': h_streak['win_streak_3plus'],
            'a_win_streak_3plus': a_streak['win_streak_3plus'],
            'h_lose_streak_3plus': h_streak['lose_streak_3plus'],
            'a_lose_streak_3plus': a_streak['lose_streak_3plus'],
            # 파크
            'park_runs_factor': pf['runs'], 'park_hr_factor': pf['hr'],
            # 컨텍스트
            'day_of_week': ctx['day_of_week'],
            'is_weekend': ctx['is_weekend'],
            'is_doubleheader': ctx['is_doubleheader'],
            'rain_delay_prev': ctx['rain_delay_prev'],
            'weekday_doubleheader': ctx['weekday_doubleheader'],
        }
        return _cap_outliers(features)
    finally:
        conn.close()
