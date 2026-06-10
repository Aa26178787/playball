"""인게임(in-game) 홈팀 승리확률 모델 — 경기 상태 → P(홈 승)

배경: 5/9 크롤러 개편 후 Naver 승률(metricOption) 미수신 → 자체 모델로 대체.
학습: plate_appearances 컨텍스트(이닝/초말/아웃/주자/점수) + games 최종 승패 라벨.
로지스틱 회귀, 계수만 JSON 저장(ingame_coef.json) → 추론은 순수 파이썬(sklearn 불요).

학습(서버): cd ~/playball/backend && python3 -m api.prediction.ingame_model
추론: from api.prediction.ingame_model import predict_home_win
소비자: /games/{id}/win-prob-series(그래프) · relay current_state.home_win_prob ·
        결정적순간 푸시(델타 감지) · WPA(타석 전후 차).
"""
import json
import math
import os

_COEF_PATH = os.path.join(os.path.dirname(__file__), 'ingame_coef.json')
_coef_cache = None

FEATURE_NAMES = [
    'diff',          # 홈 - 원정 점수차 (±6 클립)
    'progress',      # 경기 진행도 ((이닝-1)*2 + 말?1:0) / 18, 연장 >1
    'diff_x_prog',   # 점수차 × 진행도 — 후반 리드일수록 결정적
    'sign',          # 홈 공격 중 +1 / 원정 공격 -1
    'sign_b1', 'sign_b2', 'sign_b3',   # 주자 (공격팀 부호)
    'sign_outs_left',                  # 남은 아웃 (공격팀 부호, (2-outs)/2)
]


def make_features(inning: int, half: int, outs: int, home_score: int, away_score: int,
                  b1: bool, b2: bool, b3: bool) -> list[float]:
    """half: 0=초(원정공격) 1=말(홈공격). 타석 시작 시점 상태."""
    diff = max(-6, min(6, (home_score or 0) - (away_score or 0)))
    progress = ((max(1, inning) - 1) * 2 + (1 if half else 0)) / 18.0
    sign = 1.0 if half else -1.0
    outs_c = max(0, min(2, outs or 0))
    return [
        float(diff),
        progress,
        diff * progress,
        sign,
        sign * (1.0 if b1 else 0.0),
        sign * (1.0 if b2 else 0.0),
        sign * (1.0 if b3 else 0.0),
        sign * (2 - outs_c) / 2.0,
    ]


def _load_coef():
    global _coef_cache
    if _coef_cache is None:
        with open(_COEF_PATH, encoding='utf-8') as f:
            _coef_cache = json.load(f)
    return _coef_cache


def predict_home_win(inning: int, half, outs: int, home_score: int, away_score: int,
                     b1: bool, b2: bool, b3: bool) -> float:
    """P(홈팀 승) 0~1. half는 0/1 또는 '0'/'1'."""
    h = 1 if str(half) == '1' else 0
    x = make_features(inning, h, outs, home_score, away_score, b1, b2, b3)
    c = _load_coef()
    z = c['intercept'] + sum(w * v for w, v in zip(c['coef'], x))
    return 1.0 / (1.0 + math.exp(-z))


# ─── 학습 CLI ─────────────────────────────────────────────────────────────────

def train():
    import sys
    sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    from database.connection import get_connection
    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import roc_auc_score, brier_score_loss

    conn = get_connection()
    cur = conn.cursor()
    # 컨텍스트 있는 PA만 (시즌 초 NULL 적재분 제외) + 무승부 제외, 시간순
    cur.execute("""
        SELECT pa.inning, pa.inning_half, pa.outs_before,
               pa.home_score, pa.away_score, pa.base1, pa.base2, pa.base3,
               (g.home_score > g.away_score)::int AS home_win, g.game_date
        FROM plate_appearances pa
        JOIN games g ON g.id = pa.game_id
        WHERE g.status = '종료' AND g.home_score <> g.away_score
          AND pa.outs_before IS NOT NULL
        ORDER BY g.game_date, pa.game_id, pa.inning, pa.inning_half, pa.pa_seq
    """)
    rows = cur.fetchall()
    cur.close()
    conn.close()
    print(f'학습 샘플(타석): {len(rows)}')

    X, y = [], []
    for inning, half, outs, hs, a_s, b1, b2, b3, win, _d in rows:
        X.append(make_features(inning, 1 if str(half) == '1' else 0, outs,
                               hs or 0, a_s or 0, bool(b1), bool(b2), bool(b3)))
        y.append(win)

    split = int(len(X) * 0.8)  # 시간순 8:2
    model = LogisticRegression(C=1.0, max_iter=1000)
    model.fit(X[:split], y[:split])
    p_hold = model.predict_proba(X[split:])[:, 1]
    auc = roc_auc_score(y[split:], p_hold)
    brier = brier_score_loss(y[split:], p_hold)
    print(f'홀드아웃 AUC={auc:.4f} Brier={brier:.4f}')

    # 전체 재학습 후 저장
    model.fit(X, y)
    out = {
        'features': FEATURE_NAMES,
        'coef': [round(float(w), 6) for w in model.coef_[0]],
        'intercept': round(float(model.intercept_[0]), 6),
        'n_samples': len(X),
        'auc_holdout': round(float(auc), 4),
        'brier_holdout': round(float(brier), 4),
    }
    with open(_COEF_PATH, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(f'저장 → {_COEF_PATH}')
    print(json.dumps(dict(zip(FEATURE_NAMES, out['coef'])), ensure_ascii=False, indent=1))

    # sanity
    global _coef_cache
    _coef_cache = None
    cases = [
        ('1회초 시작 동점', 1, 0, 0, 0, 0, False, False, False),
        ('9회말 +3 (홈 리드, 2사)', 9, 1, 2, 5, 2, False, False, False),
        ('9회말 -1 (홈 추격, 무사 만루)', 9, 1, 0, 2, 3, True, True, True),
        ('9회초 -3 (홈 열세)', 9, 0, 0, 1, 4, False, False, False),
        ('5회말 +1', 5, 1, 1, 3, 2, False, False, False),
    ]
    for name, inn, hf, o, hs, a_s, b1, b2, b3 in cases:
        p = predict_home_win(inn, hf, o, hs, a_s, b1, b2, b3)
        print(f'  {name}: {p*100:.1f}%')


if __name__ == '__main__':
    train()
