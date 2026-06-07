# -*- coding: utf-8 -*-
"""1_train.py — KBO 승리 예측 모델 학습 스크립트 (기말과제)

[전체 흐름]
  ① 데이터 로드   : DB에 저장된 2026시즌 '종료' 경기 전체에서 feature/label 추출
  ② 데이터 분리   : 시간순으로 train(80%) / test(20%) 분리
                    → test는 이 스크립트에서 절대 학습에 사용하지 않고
                      2_evaluate.py 의 성능 평가 전용으로 보존한다
  ③ 가중치 탐색   : train 내부를 다시 80/20(학습/검증)으로 나눠
                    LR·RF 앙상블의 최적 혼합 비율(rf_weight)을 grid search
  ④ 최종 학습/저장: train 전체로 모델을 재학습하고,
                    모델 + 전처리기 + test 데이터를 한 파일(pickle)로 저장

[실행 방법] (backend 디렉토리에서)
  python3 api/prediction/assignment/1_train.py
[산출물]
  models/assignment_model.pkl
"""
import os
import sys
import pickle

# ── import 경로 설정 ─────────────────────────────────────────────────
# 이 파일 위치: backend/api/prediction/assignment/
# feature 추출 모듈(api.prediction.model)을 import 하려면
# 패키지 루트인 backend/ 를 sys.path 에 추가해야 한다.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))

import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import accuracy_score

# load_training_data(season):
#   시즌 내 모든 종료 경기에 대해 경기 '시작 전 시점' 기준 feature 108개를 산출.
#   - 팀 시즌 승률 / 피타고리안 승률 / 경기당 득·실점
#   - 팀 OPS·wOBA·wRC+·ERA·WHIP, 선발투수 시즌·최근3경기 성적, 불펜 ERA·피로도
#   - 상대전적, 최근 폼, 구장 팩터, 연승·연패 등
#   - 홈-원정 차이(diff) 파생 변수 27개 포함
#   반환: (X: feature 행렬, y: 홈팀 승리 여부 0/1, ids: 경기 id 목록 — 시간순)
# feature_names(): X 열 순서와 동일한 feature 이름 목록 (중요도 해석용)
from api.prediction.model import load_training_data, feature_names

SEASON = 2026

# 모델 저장 경로: backend/models/assignment_model.pkl
MODEL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'models')
MODEL_PATH = os.path.join(MODEL_DIR, 'assignment_model.pkl')


def main():
    # ═════════════════════════════════════════════════════════════════
    # ① 데이터 로드
    # ═════════════════════════════════════════════════════════════════
    print(f"[1_train] 데이터 로드 (season={SEASON})")
    X, y, ids = load_training_data(SEASON)   # ids는 game_date 오름차순 → 시간순 정렬 보장
    X = np.array(X, dtype=float)
    y = np.array(y, dtype=int)
    print(f"[1_train] 전체 {len(X)}경기, feature {X.shape[1]}개")

    # ═════════════════════════════════════════════════════════════════
    # ② 시간순 train / test 분리
    # ─────────────────────────────────────────────────────────────────
    # 야구 경기 데이터는 시계열이다. 무작위(random) 분할을 쓰면
    # "미래 경기로 학습해서 과거 경기를 맞히는" 정보 누수(data leakage)가
    # 발생해 성능이 부풀려진다. 따라서 시즌 앞 80%로 학습하고
    # 뒤 20%(가장 최근 경기)로 평가하는 시간 기반 분할을 사용한다.
    # ═════════════════════════════════════════════════════════════════
    n = len(X)
    split = int(n * 0.8)
    X_train, X_test = X[:split], X[split:]
    y_train, y_test = y[:split], y[split:]
    test_ids = ids[split:]
    print(f"[1_train] train={len(X_train)} / test={len(X_test)} (test는 2_evaluate.py 전용)")

    # ═════════════════════════════════════════════════════════════════
    # ③ 앙상블 가중치 탐색 (train 내부 검증)
    # ─────────────────────────────────────────────────────────────────
    # 최종 예측 확률 = (1 - w) * LR확률 + w * RF확률
    # 최적 w 를 고르기 위한 평가 데이터가 필요하지만, test를 쓰면
    # test 정보가 모델 선택에 새어 들어간다(test 오염).
    # → train 을 다시 80/20 으로 나눠 뒤 20%를 검증(validation)으로 사용.
    # ═════════════════════════════════════════════════════════════════
    v = int(len(X_train) * 0.8)
    X_tr, X_val = X_train[:v], X_train[v:]
    y_tr, y_val = y_train[:v], y_train[v:]

    # StandardScaler: feature 마다 단위가 다르므로(승률 0~1, ERA 2~6, wRC+ 80~140 …)
    # 평균 0 / 표준편차 1 로 표준화. LR 은 스케일에 민감하므로 필수.
    # (RF 는 트리 분기 기반이라 스케일 영향이 없어 원본 X 를 그대로 사용)
    scaler = StandardScaler()
    X_tr_s = scaler.fit_transform(X_tr)      # 학습 데이터로만 fit (검증 누수 방지)
    X_val_s = scaler.transform(X_val)        # 검증은 같은 변환만 적용

    # 로지스틱 회귀: 선형 결합 기반 — feature 간 선형 관계를 안정적으로 포착.
    # C=1.0: L2 정규화 강도(기본값), max_iter 상향: 수렴 보장.
    lr = LogisticRegression(max_iter=1000, C=1.0, random_state=42)
    lr.fit(X_tr_s, y_tr)
    lr_val = lr.predict_proba(X_val_s)[:, 1]   # [:,1] = 홈팀 승리(=1) 확률

    # 랜덤 포레스트: 비선형 상호작용(예: '선발이 약해도 불펜이 쉬었으면 보완') 포착.
    # n_estimators=200: 트리 수, max_depth=6: 과적합 억제(경기 수가 적으므로 얕게).
    rf = RandomForestClassifier(n_estimators=200, max_depth=6, random_state=42)
    rf.fit(X_tr, y_tr)
    rf_val = rf.predict_proba(X_val)[:, 1]

    # grid search: 후보 가중치들에 대해 검증 정확도를 비교, 최고를 채택.
    best_w, best_acc = 0.5, 0.0
    for w in [0.5, 0.6, 0.7, 0.8, 0.85, 0.9, 0.95, 1.0]:
        p = (1 - w) * lr_val + w * rf_val          # 두 모델 확률의 가중 평균
        acc = accuracy_score(y_val, (p > 0.5).astype(int))
        if acc > best_acc:
            best_w, best_acc = w, acc
    print(f"[1_train] validation 기준 최적 RF weight = {best_w} (val acc={best_acc:.3f})")

    # ═════════════════════════════════════════════════════════════════
    # ④ 최종 모델 학습 + 저장
    # ─────────────────────────────────────────────────────────────────
    # 가중치 결정이 끝났으므로, 검증에 썼던 20%까지 포함한
    # train 전체(원본의 80%)로 모델을 다시 학습한다.
    # (데이터가 적을수록 한 경기라도 더 학습에 쓰는 것이 유리)
    # ═════════════════════════════════════════════════════════════════
    scaler_final = StandardScaler()
    X_train_s = scaler_final.fit_transform(X_train)

    lr_final = LogisticRegression(max_iter=1000, C=1.0, random_state=42)
    lr_final.fit(X_train_s, y_train)

    rf_final = RandomForestClassifier(n_estimators=200, max_depth=6, random_state=42)
    rf_final.fit(X_train, y_train)

    os.makedirs(MODEL_DIR, exist_ok=True)
    with open(MODEL_PATH, 'wb') as f:
        pickle.dump({
            # 학습된 모델 2종 + 전처리기 + 앙상블 가중치
            'lr': lr_final,
            'rf': rf_final,
            'scaler': scaler_final,
            'rf_weight': float(best_w),
            # 해석용 메타 정보
            'feature_names': feature_names(),
            'season': SEASON,
            'train_size': len(X_train),
            # ── 평가 재현성을 위한 test 데이터 동봉 ──────────────────
            # feature 는 'DB의 현재 누적 스탯'으로 계산되므로 시간이 지나
            # 다시 산출하면 값이 달라진다(시즌이 진행되며 스탯 갱신).
            # 따라서 학습 '시점'의 test 스냅샷을 모델 파일에 함께 저장해
            # 2_evaluate.py 가 언제 실행돼도 동일한 평가가 되도록 한다.
            'X_test': X_test,
            'y_test': y_test,
            'test_ids': test_ids,
        }, f)

    print(f"[1_train] 모델 저장 완료 → {os.path.abspath(MODEL_PATH)}")
    print("[1_train] 다음 단계: python3 api/prediction/assignment/2_evaluate.py")


if __name__ == '__main__':
    main()
