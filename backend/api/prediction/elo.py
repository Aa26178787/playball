"""KBO 팀 Elo 레이팅 시스템.
26시즌 완료 경기 기반으로 각 팀의 현재 Elo 계산.
가을야구/한국시리즈 직행 확률 Monte Carlo 시뮬레이션에 사용."""
from database.connection import get_connection

INITIAL_ELO = 1500.0
K_FACTOR = 20.0  # KBO 144경기 적정 K
HFA = 50.0  # 홈 어드밴티지 (Elo 포인트)


def expected_score(rating_home: float, rating_away: float, hfa: float = HFA) -> float:
    """홈팀 기대 승률 (Elo)."""
    return 1.0 / (1.0 + 10 ** ((rating_away - rating_home - hfa) / 400))


def compute_team_elo(season: int = 2026, k: float = K_FACTOR) -> dict:
    """26시즌 완료 경기 전체를 시간순 처리해서 각 팀 현재 Elo 산출.
    무승부는 0.5/0.5 (Elo 표준)."""
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT id FROM teams ORDER BY id
    """)
    team_ids = [r[0] for r in cur.fetchall()]
    elos = {tid: INITIAL_ELO for tid in team_ids}

    cur.execute("""
        SELECT home_team_id, away_team_id, home_score, away_score
        FROM games
        WHERE status='종료' AND EXTRACT(YEAR FROM game_date)=%s
          AND home_score IS NOT NULL AND away_score IS NOT NULL
        ORDER BY game_date, id
    """, (season,))
    games = cur.fetchall()
    cur.close(); conn.close()

    for home_id, away_id, hs, as_ in games:
        if home_id not in elos or away_id not in elos:
            continue
        rh = elos[home_id]
        ra = elos[away_id]
        eh = expected_score(rh, ra)
        if hs > as_:
            sh, sa = 1.0, 0.0
        elif hs < as_:
            sh, sa = 0.0, 1.0
        else:
            sh, sa = 0.5, 0.5
        elos[home_id] = rh + k * (sh - eh)
        elos[away_id] = ra + k * (sa - (1 - eh))
    return elos


def get_remaining_schedule(season: int = 2026) -> list:
    """남은 경기 schedule. [(home_team_id, away_team_id), ...]."""
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT home_team_id, away_team_id
        FROM games
        WHERE status IN ('예정', '라인업') AND EXTRACT(YEAR FROM game_date)=%s
        ORDER BY game_date, id
    """, (season,))
    rows = cur.fetchall()
    cur.close(); conn.close()
    return [(h, a) for h, a in rows]


def simulate_postseason(elos: dict, current_wins: dict, current_losses: dict,
                         remaining: list, n_sim: int = 50000,
                         ps_spots: int = 5, ks_spots: int = 1) -> dict:
    """Monte Carlo: Elo 기반 남은 경기 결과 샘플링 → 최종 순위 → 진출 확률.
    Elo는 시뮬레이션 동안 정적 (단순화). 진짜 정확히는 매 게임 동적 갱신 가능하지만
    100K sim에선 차이 작음."""
    import numpy as np

    team_ids = list(elos.keys())
    n_teams = len(team_ids)
    tid_to_idx = {tid: i for i, tid in enumerate(team_ids)}

    # 사전 계산: 각 남은 경기의 home win prob
    home_probs = np.array([
        expected_score(elos[h], elos[a]) for h, a in remaining
    ])
    home_idx = np.array([tid_to_idx[h] for h, _ in remaining])
    away_idx = np.array([tid_to_idx[a] for _, a in remaining])
    n_games = len(remaining)

    base_wins = np.array([current_wins.get(tid, 0) for tid in team_ids], dtype=np.int32)

    ps_count = np.zeros(n_teams, dtype=np.int64)
    ks_count = np.zeros(n_teams, dtype=np.int64)

    BATCH = 1000
    for batch_start in range(0, n_sim, BATCH):
        batch_size = min(BATCH, n_sim - batch_start)
        # batch_size × n_games random uniform
        rng = np.random.random((batch_size, n_games))
        home_wins = rng < home_probs  # bool array
        # wins 집계
        sim_wins = np.tile(base_wins, (batch_size, 1)).astype(np.int32)
        for g in range(n_games):
            hi, ai = home_idx[g], away_idx[g]
            sim_wins[home_wins[:, g], hi] += 1
            sim_wins[~home_wins[:, g], ai] += 1
        # 순위
        # argsort descending
        ranks = np.argsort(-sim_wins, axis=1)
        for r in range(ranks.shape[0]):
            top = ranks[r]
            for i, t in enumerate(top):
                if i < ps_spots:
                    ps_count[t] += 1
                if i < ks_spots:
                    ks_count[t] += 1

    return {
        team_ids[i]: {
            'ps_prob': float(ps_count[i]) / n_sim,
            'ks_prob': float(ks_count[i]) / n_sim,
        }
        for i in range(n_teams)
    }
