# -*- coding: utf-8 -*-
"""2_evaluate.py — 학습된 승리 예측 모델 성능 평가 스크립트 (기말과제)

[전체 흐름]
  ① 모델 로드 : 1_train.py 가 저장한 assignment_model.pkl 에서
                LR / RF / Scaler / 앙상블 가중치 / test 데이터를 복원
  ② 예측      : 학습에 사용되지 않은 test 데이터(시간순 마지막 20%)에 대해
                두 모델의 확률을 산출하고 가중 평균으로 앙상블
  ③ 평가      : Accuracy / ROC-AUC / Log Loss / 혼동행렬을 출력하고
                베이스라인(다수 클래스 고정 예측)과 비교
  ④ 해석      : RF feature importance 상위 10개로 어떤 변수가
                승부 예측에 기여했는지 확인

[실행 방법] (backend 디렉토리에서)
  python3 api/prediction/assignment/2_evaluate.py
[사전 조건]
  1_train.py 를 먼저 실행해 models/assignment_model.pkl 이 존재해야 함
"""
import os
import sys
import pickle

# backend 루트를 import 경로에 추가 (1_train.py 와 동일한 이유)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))

import numpy as np
from sklearn.metrics import (
    accuracy_score,   # 정분류율: 맞힌 경기 비율 — 가장 직관적인 지표
    roc_auc_score,    # 확률 순위 품질: 0.5=무작위, 1.0=완벽. 임계값과 무관
    log_loss,         # 확률 보정 품질: 자신있게 틀릴수록 큰 패널티 (낮을수록 좋음)
    confusion_matrix, # 클래스별 오류 패턴 (홈승/원정승 어느 쪽을 틀리는지)
)

MODEL_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          '..', '..', '..', 'models', 'assignment_model.pkl')


def main():
    # ═════════════════════════════════════════════════════════════════
    # ① 모델 파일 로드
    # ═════════════════════════════════════════════════════════════════
    if not os.path.exists(MODEL_PATH):
        print("[2_evaluate] 모델 파일이 없습니다 — 먼저 1_train.py를 실행하세요")
        sys.exit(1)
    with open(MODEL_PATH, 'rb') as f:
        m = pickle.load(f)
    print(f"[2_evaluate] 모델 로드 완료 (season={m['season']}, "
          f"train={m['train_size']}경기, RF weight={m['rf_weight']})")

    lr, rf, scaler = m['lr'], m['rf'], m['scaler']

    # test 데이터는 1_train.py 가 '학습 시점'에 동봉해 둔 스냅샷.
    # (feature 가 DB 누적 스탯 기반이라, 지금 다시 산출하면 값이 변해
    #  공정한 비교가 불가능 — 그래서 파일에서 그대로 꺼내 쓴다)
    X_test = np.array(m['X_test'], dtype=float)
    y_test = np.array(m['y_test'], dtype=int)
    print(f"[2_evaluate] 평가 데이터: {len(X_test)}경기 (학습에 사용되지 않은 시간순 마지막 20%)")

    # ═════════════════════════════════════════════════════════════════
    # ② 예측 — LR + RF 앙상블
    # ─────────────────────────────────────────────────────────────────
    # LR 은 학습 때와 동일한 표준화(scaler.transform)를 거친 입력 사용.
    # RF 는 스케일 불변이므로 원본 X_test 그대로 입력.
    # 최종 확률 = (1-w)·LR + w·RF  (w 는 1_train 의 검증에서 결정된 값)
    # ═════════════════════════════════════════════════════════════════
    lr_p = lr.predict_proba(scaler.transform(X_test))[:, 1]   # 홈팀 승리 확률
    rf_p = rf.predict_proba(X_test)[:, 1]
    w = m['rf_weight']
    ens_p = (1 - w) * lr_p + w * rf_p
    ens_pred = (ens_p > 0.5).astype(int)   # 확률 0.5 초과 → 홈승(1) 예측

    # ═════════════════════════════════════════════════════════════════
    # ③ 성능 지표
    # ═════════════════════════════════════════════════════════════════
    print("\n========== 성능 평가 결과 ==========")
    print(f"LR  단독  : acc={accuracy_score(y_test, (lr_p > 0.5).astype(int)):.3f}  "
          f"auc={roc_auc_score(y_test, lr_p):.3f}")
    print(f"RF  단독  : acc={accuracy_score(y_test, (rf_p > 0.5).astype(int)):.3f}  "
          f"auc={roc_auc_score(y_test, rf_p):.3f}")
    print(f"앙상블    : acc={accuracy_score(y_test, ens_pred):.3f}  "
          f"auc={roc_auc_score(y_test, ens_p):.3f}  "
          f"logloss={log_loss(y_test, ens_p):.3f}")

    # 베이스라인: 아무 정보 없이 '다수 클래스'(보통 홈승 — 홈 어드밴티지)만
    # 고정 예측했을 때의 정확도. 모델이 이보다 높아야 의미가 있다.
    baseline = max((y_test == 1).mean(), (y_test == 0).mean())
    print(f"베이스라인 (다수 클래스 고정 예측): acc={baseline:.3f}")
    print(f"베이스라인 대비 개선: {accuracy_score(y_test, ens_pred) - baseline:+.3f}")

    # 혼동행렬: 행=실제, 열=예측.
    #   [0][0] 원정승을 원정승으로 (정답) | [0][1] 원정승을 홈승으로 (오답)
    #   [1][0] 홈승을 원정승으로 (오답)   | [1][1] 홈승을 홈승으로 (정답)
    cm = confusion_matrix(y_test, ens_pred)
    print("\n혼동행렬 (행=실제 [원정승, 홈승] / 열=예측):")
    print(f"  원정승  {cm[0][0]:4d}  {cm[0][1]:4d}")
    print(f"  홈승    {cm[1][0]:4d}  {cm[1][1]:4d}")

    # ═════════════════════════════════════════════════════════════════
    # ④ Feature 중요도 (RF 기준 Top 10)
    # ─────────────────────────────────────────────────────────────────
    # RF 의 feature_importances_: 각 변수가 트리 분기에서 불순도를
    # 얼마나 감소시켰는지의 평균 — '어떤 정보가 승부를 갈랐나'의 근사.
    # ═════════════════════════════════════════════════════════════════
    print("\nRF Feature Importance Top 10:")
    names = m['feature_names']
    for n_, imp in sorted(zip(names, rf.feature_importances_), key=lambda x: -x[1])[:10]:
        print(f"  {n_:30s} {imp:.4f}")


if __name__ == '__main__':
    main()
