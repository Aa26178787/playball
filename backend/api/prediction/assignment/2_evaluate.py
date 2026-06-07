# -*- coding: utf-8 -*-
"""2_evaluate.py — 학습된 승리 예측 모델 성능 평가 스크립트 (기말과제용)

역할:
  1) 1_train.py가 저장한 모델 파일(assignment_model.pkl) 로드
  2) 함께 보존된 평가 전용 test 데이터(학습에 미사용)로 성능 평가
  3) Accuracy / ROC-AUC / Log Loss / 혼동행렬 / 베이스라인 비교 / feature 중요도 출력

실행 (backend 디렉토리에서):
  python3 api/prediction/assignment/2_evaluate.py
"""
import os
import sys
import pickle

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))

import numpy as np
from sklearn.metrics import (
    accuracy_score, roc_auc_score, log_loss, confusion_matrix,
)

MODEL_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          '..', '..', '..', 'models', 'assignment_model.pkl')


def main():
    # ── 1) 모델 파일 로드 ────────────────────────────────────────────
    if not os.path.exists(MODEL_PATH):
        print("[2_evaluate] 모델 파일이 없습니다 — 먼저 1_train.py를 실행하세요")
        sys.exit(1)
    with open(MODEL_PATH, 'rb') as f:
        m = pickle.load(f)
    print(f"[2_evaluate] 모델 로드 완료 (season={m['season']}, "
          f"train={m['train_size']}경기, RF weight={m['rf_weight']})")

    lr, rf, scaler = m['lr'], m['rf'], m['scaler']
    X_test = np.array(m['X_test'], dtype=float)
    y_test = np.array(m['y_test'], dtype=int)
    print(f"[2_evaluate] 평가 데이터: {len(X_test)}경기 (학습에 사용되지 않은 시간순 마지막 20%)")

    # ── 2) 예측 (LR + RF 앙상블) ─────────────────────────────────────
    lr_p = lr.predict_proba(scaler.transform(X_test))[:, 1]
    rf_p = rf.predict_proba(X_test)[:, 1]
    w = m['rf_weight']
    ens_p = (1 - w) * lr_p + w * rf_p
    ens_pred = (ens_p > 0.5).astype(int)

    # ── 3) 성능 지표 ─────────────────────────────────────────────────
    print("\n========== 성능 평가 결과 ==========")
    print(f"LR  단독  : acc={accuracy_score(y_test, (lr_p > 0.5).astype(int)):.3f}  "
          f"auc={roc_auc_score(y_test, lr_p):.3f}")
    print(f"RF  단독  : acc={accuracy_score(y_test, (rf_p > 0.5).astype(int)):.3f}  "
          f"auc={roc_auc_score(y_test, rf_p):.3f}")
    print(f"앙상블    : acc={accuracy_score(y_test, ens_pred):.3f}  "
          f"auc={roc_auc_score(y_test, ens_p):.3f}  "
          f"logloss={log_loss(y_test, ens_p):.3f}")

    # 베이스라인: 항상 홈팀 승 예측
    baseline = max((y_test == 1).mean(), (y_test == 0).mean())
    print(f"베이스라인 (다수 클래스 고정 예측): acc={baseline:.3f}")
    print(f"베이스라인 대비 개선: {accuracy_score(y_test, ens_pred) - baseline:+.3f}")

    # 혼동행렬
    cm = confusion_matrix(y_test, ens_pred)
    print("\n혼동행렬 (행=실제 [원정승, 홈승] / 열=예측):")
    print(f"  원정승  {cm[0][0]:4d}  {cm[0][1]:4d}")
    print(f"  홈승    {cm[1][0]:4d}  {cm[1][1]:4d}")

    # ── 4) Feature 중요도 (RF 기준 Top 10) ──────────────────────────
    print("\nRF Feature Importance Top 10:")
    names = m['feature_names']
    for n_, imp in sorted(zip(names, rf.feature_importances_), key=lambda x: -x[1])[:10]:
        print(f"  {n_:30s} {imp:.4f}")


if __name__ == '__main__':
    main()
