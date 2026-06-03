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
    """팀 타격 집계 from batter_stats."""
    cur.execute("""
        SELECT
            AVG(NULLIF(avg,0))::float as team_avg,
            AVG(NULLIF(ops,0))::float as team_ops,
            AVG(NULLIF(obp,0))::float as team_obp,
            AVG(NULLIF(slg,0))::float as team_slg,
            AVG(NULLIF(woba,0))::float as team_woba
        FROM batter_stats bs
        JOIN players p ON p.id = bs.player_id
        WHERE p.team_id=%s AND bs.season=%s AND bs.at_bats > 50
    """, (team_id, season))
    row = cur.fetchone() or (0,0,0,0,0)
    return {
        'team_avg': round(_f(row[0]), 3),
        'team_ops': round(_f(row[1]), 3),
        'team_obp': round(_f(row[2]), 3),
        'team_slg': round(_f(row[3]), 3),
        'team_woba': round(_f(row[4]), 3),
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


def _starter_stats(cur, game_id: int, team_side: str, season: int) -> dict:
    """선발투수 시즌 stats + 최근 3등판 ERA."""
    cur.execute("""
        SELECT gp.player_id, p.name
        FROM game_pitchers gp
        JOIN players p ON p.id = gp.player_id
        WHERE gp.game_id=%s AND gp.team_side=%s AND gp.pitching_order=1
        LIMIT 1
    """, (game_id, team_side))
    row = cur.fetchone()
    if not row:
        return {'starter_name': '', 'starter_era': 0, 'starter_whip': 0, 'starter_fip': 0,
                'starter_k9': 0, 'starter_recent3_era': 0}
    pid, name = row

    cur.execute("""
        SELECT era, whip, fip, k_per_9
        FROM pitcher_stats WHERE player_id=%s AND season=%s
    """, (pid, season))
    sr = cur.fetchone() or (0,0,0,0)

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

    return {
        'starter_player_id': pid,
        'starter_name': name,
        'starter_era': round(_f(sr[0]), 2),
        'starter_whip': round(_f(sr[1]), 2),
        'starter_fip': round(_f(sr[2]), 2),
        'starter_k9': round(_f(sr[3]), 2),
        'starter_recent3_era': round(recent_era, 2),
    }


def _lineup_stats(cur, game_id: int, team_side: str, season: int) -> dict:
    """선발 라인업 9명 평균 OPS/wOBA."""
    cur.execute("""
        SELECT AVG(NULLIF(bs.ops, 0))::float, AVG(NULLIF(bs.woba, 0))::float,
               AVG(NULLIF(bs.avg, 0))::float
        FROM game_rosters gr
        JOIN players p ON p.id = gr.player_id
        LEFT JOIN batter_stats bs ON bs.player_id = gr.player_id AND bs.season=%s
        WHERE gr.game_id=%s AND gr.team_side=%s
          AND gr.batting_order BETWEEN 1 AND 9
    """, (season, game_id, team_side))
    row = cur.fetchone() or (0, 0, 0)
    return {
        'lineup_ops': round(_f(row[0]), 3),
        'lineup_woba': round(_f(row[1]), 3),
        'lineup_avg': round(_f(row[2]), 3),
    }


def _bullpen_stats(cur, team_id: int, season: int) -> dict:
    """팀 불펜 (비선발) ERA/WHIP."""
    cur.execute("""
        SELECT AVG(NULLIF(ps.era, 0))::float, AVG(NULLIF(ps.whip, 0))::float
        FROM pitcher_stats ps
        JOIN players p ON p.id = ps.player_id
        WHERE p.team_id=%s AND ps.season=%s
          AND ps.innings_pitched > 5
          AND ps.games > ps.cg
          AND COALESCE(ps.wins,0) + COALESCE(ps.losses,0) < ps.games * 0.6
    """, (team_id, season))
    row = cur.fetchone() or (0, 0)
    return {
        'bullpen_era': round(_f(row[0]), 2),
        'bullpen_whip': round(_f(row[1]), 2),
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

        # 선발
        h_st = _starter_stats(cur, game_id, 'home', season)
        a_st = _starter_stats(cur, game_id, 'away', season)

        # 라인업
        h_line = _lineup_stats(cur, game_id, 'home', season)
        a_line = _lineup_stats(cur, game_id, 'away', season)

        # 불펜
        h_pen = _bullpen_stats(cur, home_id, season)
        a_pen = _bullpen_stats(cur, away_id, season)
        h_rest = _bullpen_rest(cur, home_id, gdate)
        a_rest = _bullpen_rest(cur, away_id, gdate)

        # 상대전적
        h2h = _h2h(cur, home_id, away_id, season)

        # 최근 폼
        h_form = _recent_form(cur, home_id, gdate, 10)
        a_form = _recent_form(cur, away_id, gdate, 10)

        cur.close()

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
            # 라인업
            'h_lineup_ops': h_line['lineup_ops'], 'a_lineup_ops': a_line['lineup_ops'],
            'h_lineup_woba': h_line['lineup_woba'], 'a_lineup_woba': a_line['lineup_woba'],
            # 불펜
            'h_bullpen_era': h_pen['bullpen_era'], 'a_bullpen_era': a_pen['bullpen_era'],
            'h_bullpen_rest': h_rest['bullpen_rest_score'],
            'a_bullpen_rest': a_rest['bullpen_rest_score'],
            # 상대전적
            'h2h_wpct': h2h['h2h_wpct'], 'h2h_games': h2h['h2h_games'],
            # 폼
            'h_recent_wpct': h_form['recent_wpct'], 'a_recent_wpct': a_form['recent_wpct'],
            'h_recent_rs': h_form['recent_rs_pg'], 'a_recent_rs': a_form['recent_rs_pg'],
            'h_recent_ra': h_form['recent_ra_pg'], 'a_recent_ra': a_form['recent_ra_pg'],
            # 파크
            'park_runs_factor': pf['runs'], 'park_hr_factor': pf['hr'],
        }
        return features
    finally:
        conn.close()
