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
    """Monte Carlo: Elo 기반 남은 경기 결과 샘플링 → 최종 순위 → 단계별 진출 확률.
    KBO 포스트시즌 구조:
      1위 → 한국시리즈 직행
      2위 → 플레이오프 직행
      3위 → 준플레이오프 직행
      4위 → 와일드카드전 (1승 어드밴티지)
      5위 → 와일드카드전
    """
    import numpy as np

    team_ids = list(elos.keys())
    n_teams = len(team_ids)
    tid_to_idx = {tid: i for i, tid in enumerate(team_ids)}

    home_probs = np.array([
        expected_score(elos[h], elos[a]) for h, a in remaining
    ])
    home_idx = np.array([tid_to_idx[h] for h, _ in remaining])
    away_idx = np.array([tid_to_idx[a] for _, a in remaining])
    n_games = len(remaining)

    base_wins = np.array([current_wins.get(tid, 0) for tid in team_ids], dtype=np.int32)

    # 각 순위별 카운트 (1위~5위 + 6위 이하)
    rank_count = np.zeros((6, n_teams), dtype=np.int64)  # [rank_idx][team]
    # rank_idx: 0=1위, 1=2위, 2=3위, 3=4위, 4=5위, 5=6위 이하

    BATCH = 1000
    for batch_start in range(0, n_sim, BATCH):
        batch_size = min(BATCH, n_sim - batch_start)
        rng = np.random.random((batch_size, n_games))
        home_wins = rng < home_probs
        sim_wins = np.tile(base_wins, (batch_size, 1)).astype(np.int32)
        for g in range(n_games):
            hi, ai = home_idx[g], away_idx[g]
            sim_wins[home_wins[:, g], hi] += 1
            sim_wins[~home_wins[:, g], ai] += 1
        ranks = np.argsort(-sim_wins, axis=1)
        for r in range(ranks.shape[0]):
            top = ranks[r]
            for i, t in enumerate(top):
                if i < 5:
                    rank_count[i][t] += 1
                else:
                    rank_count[5][t] += 1

    result = {}
    for i, tid in enumerate(team_ids):
        r1 = float(rank_count[0][i]) / n_sim
        r2 = float(rank_count[1][i]) / n_sim
        r3 = float(rank_count[2][i]) / n_sim
        r4 = float(rank_count[3][i]) / n_sim
        r5 = float(rank_count[4][i]) / n_sim
        result[tid] = {
            'ps_prob': r1 + r2 + r3 + r4 + r5,
            'ks_direct_prob': r1,           # 한국시리즈 직행 (1위)
            'po_direct_prob': r2,           # 플레이오프 직행 (2위)
            'spo_direct_prob': r3,          # 준플레이오프 직행 (3위)
            'wc_seed4_prob': r4,            # 와일드카드 4위 (어드밴티지)
            'wc_seed5_prob': r5,            # 와일드카드 5위
            'rank1_prob': r1, 'rank2_prob': r2, 'rank3_prob': r3,
            'rank4_prob': r4, 'rank5_prob': r5,
        }
    return result
