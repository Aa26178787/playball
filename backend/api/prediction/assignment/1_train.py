# -*- coding: utf-8 -*-
"""1_train.py — 승리 예측 모델 학습 스크립트 (기말과제용, 기존 운영 코드와 분리)

역할:
  1) DB에서 2026시즌 종료 경기 전체의 feature/label 로드
  2) 시간순으로 train(80%) / test(20%) 분리 — test는 절대 학습에 사용하지 않고
     2_evaluate.py 전용으로 보존
  3) train 내부를 다시 80/20(train/validation)으로 나눠 앙상블 가중치 탐색
  4) 최적 모델(LR + RF + Scaler + 가중치)을 test 데이터와 함께 파일로 저장

실행 (backend 디렉토리에서):
  python3 api/prediction/assignment/1_train.py
출력:
  models/assignment_model.pkl
"""
import os
import sys
import pickle

# backend 루트를 import 경로에 추가
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))

import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import accuracy_score

from api.prediction.model import load_training_data, feature_names

SEASON = 2026
MODEL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'models')
MODEL_PATH = os.path.join(MODEL_DIR, 'assignment_model.pkl')


def main():
    # ── 1) 데이터 로드 ───────────────────────────────────────────────
    print(f"[1_train] 데이터 로드 (season={SEASON})")
    X, y, ids = load_training_data(SEASON)
    X = np.array(X, dtype=float)
    y = np.array(y, dtype=int)
    print(f"[1_train] 전체 {len(X)}경기, feature {X.shape[1]}개")

    # ── 2) 시간순 train / test 분리 (test = 마지막 20%, 평가 전용 보존) ──
    n = len(X)
    split = int(n * 0.8)
    X_train, X_test = X[:split], X[split:]
    y_train, y_test = y[:split], y[split:]
    test_ids = ids[split:]
    print(f"[1_train] train={len(X_train)} / test={len(X_test)} (test는 2_evaluate.py 전용)")

    # ── 3) train 내부 80/20 검증 split — 앙상블 가중치 탐색용 ─────────
    v = int(len(X_train) * 0.8)
    X_tr, X_val = X_train[:v], X_train[v:]
    y_tr, y_val = y_train[:v], y_train[v:]

    scaler = StandardScaler()
    X_tr_s = scaler.fit_transform(X_tr)
    X_val_s = scaler.transform(X_val)

    lr = LogisticRegression(max_iter=1000, C=1.0, random_state=42)
    lr.fit(X_tr_s, y_tr)
    lr_val = lr.predict_proba(X_val_s)[:, 1]

    rf = RandomForestClassifier(n_estimators=200, max_depth=6, random_state=42)
    rf.fit(X_tr, y_tr)
    rf_val = rf.predict_proba(X_val)[:, 1]

    best_w, best_acc = 0.5, 0.0
    for w in [0.5, 0.6, 0.7, 0.8, 0.85, 0.9, 0.95, 1.0]:
        p = (1 - w) * lr_val + w * rf_val
        acc = accuracy_score(y_val, (p > 0.5).astype(int))
        if acc > best_acc:
            best_w, best_acc = w, acc
    print(f"[1_train] validation 기준 최적 RF weight = {best_w} (val acc={best_acc:.3f})")

    # ── 4) 최종 모델: train 전체(80%)로 재학습 후 저장 ─────────────────
    scaler_final = StandardScaler()
    X_train_s = scaler_final.fit_transform(X_train)

    lr_final = LogisticRegression(max_iter=1000, C=1.0, random_state=42)
    lr_final.fit(X_train_s, y_train)

    rf_final = RandomForestClassifier(n_estimators=200, max_depth=6, random_state=42)
    rf_final.fit(X_train, y_train)

    os.makedirs(MODEL_DIR, exist_ok=True)
    with open(MODEL_PATH, 'wb') as f:
        pickle.dump({
            'lr': lr_final,
            'rf': rf_final,
            'scaler': scaler_final,
            'rf_weight': float(best_w),
            'feature_names': feature_names(),
            'season': SEASON,
            'train_size': len(X_train),
            # 평가 재현성: feature는 현재 DB 상태에 의존하므로
            # 학습 시점의 test 데이터를 모델 파일에 함께 보존
            'X_test': X_test,
            'y_test': y_test,
            'test_ids': test_ids,
        }, f)

    print(f"[1_train] 모델 저장 완료 → {os.path.abspath(MODEL_PATH)}")
    print("[1_train] 다음 단계: python3 api/prediction/assignment/2_evaluate.py")


if __name__ == '__main__':
    main()
