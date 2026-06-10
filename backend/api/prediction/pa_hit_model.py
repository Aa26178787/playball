"""per-PA 안타확률 모델 — P(이번 타석 안타 | 타자·투수·맞대결 이력)

학습: plate_appearances 시간순 누적 — 각 타석의 피처는 '그 시점까지' 이력만 사용
(leakage 방지). 라벨 = is_hit (PA 기준, base rate ~0.214).
전 비율 피처는 empirical Bayes shrinkage: (hits + P·N) / (pa + N), P=리그 평균.

계수 JSON(pa_hit_coef.json) 저장 — 추론 순수 파이썬 (ingame_model과 동일 패턴).
야구 per-PA 본질상 AUC ~0.6 기대 — 절대 적중이 아니라 매치업 간 상대 비교 용도.

학습(서버): cd ~/playball/backend && python3 -m api.prediction.pa_hit_model
서빙: /players/matchup 응답 hit_prob (필드뷰 맞대결 캡션)
"""
import json
import math
import os
from collections import defaultdict, deque

_COEF_PATH = os.path.join(os.path.dirname(__file__), 'pa_hit_coef.json')
_coef_cache = None

LEAGUE_HIT = 0.214   # 안타/PA 리그 평균 (백필 실측)
N_BATTER = 50        # shrink prior 표본수
N_RECENT = 25
N_PITCHER = 100
N_MATCHUP = 20
RECENT_WINDOW = 50

FEATURE_NAMES = ['b_rate', 'b_recent', 'p_rate', 'm_rate', 'platoon', 'b_volume']


def shrink(hits: float, pa: float, n_prior: float) -> float:
    return (hits + LEAGUE_HIT * n_prior) / (pa + n_prior)


def platoon_advantage(bats: str, throws: str) -> float:
    """타자가 투수 반대손이면 1 (양타=항상 1). 우언(언더)은 우투 취급."""
    b = (bats or '')[:1]
    t = (throws or '')[:1]
    if b == '양':
        return 1.0
    if b in ('좌', '우') and t in ('좌', '우'):
        return 1.0 if b != t else 0.0
    return 0.5  # 정보 없음


def make_features(b_pa, b_hits, recent_list, p_pa, p_hits, m_pa, m_hits,
                  bats: str, throws: str) -> list[float]:
    return [
        shrink(b_hits, b_pa, N_BATTER),
        shrink(sum(recent_list), len(recent_list), N_RECENT),
        shrink(p_hits, p_pa, N_PITCHER),
        shrink(m_hits, m_pa, N_MATCHUP),
        platoon_advantage(bats, throws),
        min(1.0, math.log1p(b_pa) / math.log1p(600)),  # 표본 크기 신호 (신인 구분)
    ]


def _load_coef():
    global _coef_cache
    if _coef_cache is None:
        with open(_COEF_PATH, encoding='utf-8') as f:
            _coef_cache = json.load(f)
    return _coef_cache


def _sigmoid(z: float) -> float:
    return 1.0 / (1.0 + math.exp(-z))


def predict_hit_prob(conn, batter_name: str, pitcher_name: str) -> float | None:
    """현재까지 전체 이력으로 이번 타석 안타확률. conn은 호출측 소유(닫지 않음)."""
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT COUNT(*), COALESCE(SUM(is_hit::int), 0)
            FROM plate_appearances WHERE batter_name = %s
        """, (batter_name,))
        b_pa, b_hits = cur.fetchone()
        cur.execute("""
            SELECT is_hit FROM plate_appearances
            WHERE batter_name = %s ORDER BY id DESC LIMIT %s
        """, (batter_name, RECENT_WINDOW))
        recent = [1 if r[0] else 0 for r in cur.fetchall()]
        cur.execute("""
            SELECT COUNT(*), COALESCE(SUM(is_hit::int), 0)
            FROM plate_appearances WHERE pitcher_name = %s
        """, (pitcher_name,))
        p_pa, p_hits = cur.fetchone()
        cur.execute("""
            SELECT COUNT(*), COALESCE(SUM(is_hit::int), 0)
            FROM plate_appearances WHERE batter_name = %s AND pitcher_name = %s
        """, (batter_name, pitcher_name))
        m_pa, m_hits = cur.fetchone()
        cur.execute("SELECT bats FROM players WHERE name = %s LIMIT 1", (batter_name,))
        rb = cur.fetchone()
        cur.execute("SELECT throws FROM players WHERE name = %s LIMIT 1", (pitcher_name,))
        rp = cur.fetchone()
        cur.close()
        x = make_features(b_pa, b_hits, recent, p_pa, p_hits, m_pa, m_hits,
                          (rb[0] if rb else '') or '', (rp[0] if rp else '') or '')
        c = _load_coef()
        z = c['intercept'] + sum(w * v for w, v in zip(c['coef'], x))
        return _sigmoid(z)
    except Exception:
        return None


# ─── 학습 CLI ─────────────────────────────────────────────────────────────────

def train():
    import sys
    sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    from database.connection import get_connection
    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import roc_auc_score, brier_score_loss

    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT pa.batter_name, pa.pitcher_name, pa.is_hit::int
        FROM plate_appearances pa
        JOIN games g ON g.id = pa.game_id
        ORDER BY g.game_date, pa.game_id, pa.inning, pa.inning_half, pa.pa_seq
    """)
    rows = cur.fetchall()
    cur.execute("SELECT name, COALESCE(bats,''), COALESCE(throws,'') FROM players")
    hand = {name: (b, t) for name, b, t in cur.fetchall()}
    cur.close()
    conn.close()
    print(f'학습 샘플(타석, 시간순): {len(rows)}')

    b_st = defaultdict(lambda: [0, 0])               # batter: [pa, hits]
    p_st = defaultdict(lambda: [0, 0])               # pitcher: [pa, hits_allowed]
    m_st = defaultdict(lambda: [0, 0])               # (b,p): [pa, hits]
    rec = defaultdict(lambda: deque(maxlen=RECENT_WINDOW))

    X, y = [], []
    for b, p, hit in rows:
        bs = b_st[b]; ps = p_st[p]; ms = m_st[(b, p)]
        bats = hand.get(b, ('', ''))[0]
        throws = hand.get(p, ('', ''))[1]
        X.append(make_features(bs[0], bs[1], list(rec[b]), ps[0], ps[1],
                               ms[0], ms[1], bats, throws))
        y.append(hit)
        # 상태 갱신 (이 타석 반영 — 다음 타석부터 보임)
        bs[0] += 1; bs[1] += hit
        ps[0] += 1; ps[1] += hit
        ms[0] += 1; ms[1] += hit
        rec[b].append(hit)

    split = int(len(X) * 0.8)
    model = LogisticRegression(C=1.0, max_iter=1000)
    model.fit(X[:split], y[:split])
    ph = model.predict_proba(X[split:])[:, 1]
    auc = roc_auc_score(y[split:], ph)
    brier = brier_score_loss(y[split:], ph)
    print(f'홀드아웃 AUC={auc:.4f} Brier={brier:.4f} (base rate {sum(y)/len(y):.3f})')

    model.fit(X, y)
    out = {
        'features': FEATURE_NAMES,
        'coef': [round(float(w), 6) for w in model.coef_[0]],
        'intercept': round(float(model.intercept_[0]), 6),
        'n_samples': len(X),
        'auc_holdout': round(float(auc), 4),
        'brier_holdout': round(float(brier), 4),
        'league_hit': LEAGUE_HIT,
    }
    with open(_COEF_PATH, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(f'저장 → {_COEF_PATH}')
    print(json.dumps(dict(zip(FEATURE_NAMES, out['coef'])), ensure_ascii=False, indent=1))

    # sanity — 강타자 vs 평균투수 / 약타자 vs 강투수 비교
    global _coef_cache
    _coef_cache = None
    conn = get_connection()
    for bn, pn in [('김도영', '올러'), ('강백호', '올러'), ('박찬호', '폰세')]:
        pr = predict_hit_prob(conn, bn, pn)
        print(f'  {bn} vs {pn}: {pr*100:.1f}%' if pr else f'  {bn} vs {pn}: N/A')
    conn.close()


if __name__ == '__main__':
    train()
