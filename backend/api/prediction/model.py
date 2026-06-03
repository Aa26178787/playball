"""승리 예측 모델 — Logistic Regression + Random Forest 앙상블.
학습: train_model() → 모델 pickle 저장
예측: predict_win_probability(game_id) → {home_prob, away_prob, top_factors}"""
import os
import pickle
from database.connection import get_connection
from api.prediction.features import get_features

MODEL_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'models')
MODEL_PATH = os.path.join(MODEL_DIR, 'win_predictor.pkl')

# 학습/예측에 사용할 수치 features (이름 + 비숫자 제외)
FEATURE_KEYS = [
    'h_wpct', 'a_wpct',
    'h_pyth_wpct', 'a_pyth_wpct',
    'h_rs_pg', 'a_rs_pg', 'h_ra_pg', 'a_ra_pg',
    'h_team_ops', 'a_team_ops',
    'h_team_woba', 'a_team_woba',
    'h_team_era', 'a_team_era',
    'h_team_whip', 'a_team_whip',
    'h_starter_era', 'a_starter_era',
    'h_starter_whip', 'a_starter_whip',
    'h_starter_recent3_era', 'a_starter_recent3_era',
    'h_lineup_ops', 'a_lineup_ops',
    'h_lineup_woba', 'a_lineup_woba',
    'h_bullpen_era', 'a_bullpen_era',
    'h_bullpen_rest', 'a_bullpen_rest',
    'h2h_wpct',
    'h_recent_wpct', 'a_recent_wpct',
    'h_recent_rs', 'a_recent_rs', 'h_recent_ra', 'a_recent_ra',
    'park_runs_factor', 'park_hr_factor',
]

# Derived diff features (often 더 강한 signal)
DIFF_FEATURE_KEYS = [
    ('wpct_diff', 'h_wpct', 'a_wpct'),
    ('pyth_diff', 'h_pyth_wpct', 'a_pyth_wpct'),
    ('rs_diff', 'h_rs_pg', 'a_rs_pg'),
    ('ra_diff', 'a_ra_pg', 'h_ra_pg'),  # 상대 ra가 클수록 home 유리
    ('ops_diff', 'h_team_ops', 'a_team_ops'),
    ('woba_diff', 'h_team_woba', 'a_team_woba'),
    ('era_diff', 'a_team_era', 'h_team_era'),  # 상대 era가 클수록 home 유리
    ('whip_diff', 'a_team_whip', 'h_team_whip'),
    ('starter_era_diff', 'a_starter_era', 'h_starter_era'),
    ('starter_whip_diff', 'a_starter_whip', 'h_starter_whip'),
    ('starter_recent_diff', 'a_starter_recent3_era', 'h_starter_recent3_era'),
    ('lineup_ops_diff', 'h_lineup_ops', 'a_lineup_ops'),
    ('bullpen_era_diff', 'a_bullpen_era', 'h_bullpen_era'),
    ('bullpen_rest_diff', 'h_bullpen_rest', 'a_bullpen_rest'),
    ('recent_form_diff', 'h_recent_wpct', 'a_recent_wpct'),
]


def feature_vector(feats: dict) -> list[float]:
    """features dict → numeric vector (학습/예측 공통)."""
    base = [float(feats.get(k, 0) or 0) for k in FEATURE_KEYS]
    diffs = [float(feats.get(b, 0) or 0) - float(feats.get(c, 0) or 0) for _, b, c in DIFF_FEATURE_KEYS]
    return base + diffs


def feature_names() -> list[str]:
    return list(FEATURE_KEYS) + [n for n, _, _ in DIFF_FEATURE_KEYS]


def load_training_data(season: int = 2026):
    """26시즌 종료 게임 전체 → (X, y) 반환."""
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT id FROM games
        WHERE status='종료' AND EXTRACT(YEAR FROM game_date)=%s
        ORDER BY game_date, id
    """, (season,))
    game_ids = [r[0] for r in cur.fetchall()]
    cur.close(); conn.close()

    X, y, ids = [], [], []
    for gid in game_ids:
        try:
            f = get_features(gid, season=season)
            if not f or f.get('status') != '종료':
                continue
            X.append(feature_vector(f))
            y.append(int(f.get('home_won', 0)))
            ids.append(gid)
        except Exception as e:
            print(f"feature 산출 오류 gid={gid}: {e}")
    return X, y, ids


def train_model(season: int = 2026):
    """전 26시즌 데이터로 LR + RF 앙상블 학습 + pickle 저장."""
    import numpy as np
    from sklearn.linear_model import LogisticRegression
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.preprocessing import StandardScaler
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import accuracy_score, roc_auc_score, log_loss

    print(f"[train] 데이터 로드 season={season}")
    X, y, ids = load_training_data(season)
    print(f"[train] {len(X)}개 게임 features 산출")

    X = np.array(X, dtype=float)
    y = np.array(y, dtype=int)

    # Time-based split (마지막 20% test)
    n = len(X)
    split = int(n * 0.8)
    X_tr, X_te = X[:split], X[split:]
    y_tr, y_te = y[:split], y[split:]

    scaler = StandardScaler()
    X_tr_s = scaler.fit_transform(X_tr)
    X_te_s = scaler.transform(X_te)

    lr = LogisticRegression(max_iter=1000, C=1.0, random_state=42)
    lr.fit(X_tr_s, y_tr)
    lr_p = lr.predict_proba(X_te_s)[:, 1]

    rf = RandomForestClassifier(n_estimators=200, max_depth=6, random_state=42)
    rf.fit(X_tr, y_tr)
    rf_p = rf.predict_proba(X_te)[:, 1]

    ens_p = (lr_p + rf_p) / 2
    ens_pred = (ens_p > 0.5).astype(int)

    print(f"\n[train] LR  test acc={accuracy_score(y_te, (lr_p>0.5).astype(int)):.3f} auc={roc_auc_score(y_te, lr_p):.3f}")
    print(f"[train] RF  test acc={accuracy_score(y_te, (rf_p>0.5).astype(int)):.3f} auc={roc_auc_score(y_te, rf_p):.3f}")
    print(f"[train] ENS test acc={accuracy_score(y_te, ens_pred):.3f} auc={roc_auc_score(y_te, ens_p):.3f} logloss={log_loss(y_te, ens_p):.3f}")

    # Baseline: 홈팀 54% 고정
    baseline = (y_te == 1).mean()
    print(f"[train] home 승률 baseline={baseline:.3f}")

    # Feature importance
    print("\n[train] Top 10 feature importance (RF):")
    names = feature_names()
    imps = sorted(zip(names, rf.feature_importances_), key=lambda x: -x[1])
    for n_, im in imps[:10]:
        print(f"  {n_:30s} {im:.4f}")

    os.makedirs(MODEL_DIR, exist_ok=True)
    with open(MODEL_PATH, 'wb') as f:
        pickle.dump({
            'lr': lr, 'rf': rf, 'scaler': scaler,
            'feature_names': names,
            'season': season,
            'test_acc': float(accuracy_score(y_te, ens_pred)),
            'test_auc': float(roc_auc_score(y_te, ens_p)),
        }, f)
    print(f"\n[train] 모델 저장: {MODEL_PATH}")


_loaded_model = None


def _load_model():
    global _loaded_model
    if _loaded_model is None and os.path.exists(MODEL_PATH):
        with open(MODEL_PATH, 'rb') as f:
            _loaded_model = pickle.load(f)
    return _loaded_model


def reload_model():
    global _loaded_model
    _loaded_model = None
    return _load_model()


def predict_win_probability(game_id: int) -> dict:
    """예정 또는 진행중 게임의 home 승리 확률."""
    feats = get_features(game_id)
    if not feats:
        return {'error': 'no features'}

    model = _load_model()
    if model is None:
        # 모델 미학습 — fallback log5 + 보정
        return _fallback_log5(feats)

    import numpy as np
    vec = np.array([feature_vector(feats)], dtype=float)
    vec_s = model['scaler'].transform(vec)
    lr_p = model['lr'].predict_proba(vec_s)[0, 1]
    rf_p = model['rf'].predict_proba(vec)[0, 1]
    ens_p = (lr_p + rf_p) / 2

    # Top factor explanation (LR 계수 × scaled feature)
    lr_coefs = model['lr'].coef_[0]
    contributions = vec_s[0] * lr_coefs
    names = model['feature_names']
    sorted_idx = sorted(range(len(contributions)), key=lambda i: -abs(contributions[i]))[:5]
    top_factors = [
        {'feature': names[i], 'contribution': round(float(contributions[i]), 3),
         'direction': 'home' if contributions[i] > 0 else 'away'}
        for i in sorted_idx
    ]

    return {
        'home_prob': round(float(ens_p), 3),
        'away_prob': round(float(1 - ens_p), 3),
        'lr_prob': round(float(lr_p), 3),
        'rf_prob': round(float(rf_p), 3),
        'top_factors': top_factors,
        'home_starter': feats.get('h_starter_name', ''),
        'away_starter': feats.get('a_starter_name', ''),
        'model_version': model.get('season'),
        'test_acc': model.get('test_acc'),
    }


def _fallback_log5(feats: dict) -> dict:
    """모델 미학습 시 Log5 + 보정 단순 계산."""
    h_wpct = feats.get('h_wpct', 0.5) or 0.5
    a_wpct = feats.get('a_wpct', 0.5) or 0.5
    h_era = feats.get('h_starter_era', 4.5) or 4.5
    a_era = feats.get('a_starter_era', 4.5) or 4.5
    home_adv = 0.04

    denom = (h_wpct + a_wpct - 2 * h_wpct * a_wpct)
    log5 = (h_wpct - h_wpct * a_wpct) / denom if denom > 0 else 0.5
    pitcher_adj = (a_era - h_era) / 25.0
    p = log5 + home_adv + pitcher_adj
    p = max(0.05, min(0.95, p))
    return {
        'home_prob': round(p, 3),
        'away_prob': round(1 - p, 3),
        'method': 'fallback_log5',
        'home_starter': feats.get('h_starter_name', ''),
        'away_starter': feats.get('a_starter_name', ''),
    }


if __name__ == '__main__':
    import sys
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    train_model()
