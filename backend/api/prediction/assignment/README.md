# KBO 승리 예측 모델 — 로직 정리 (기말과제 참고용)

> 운영 코드: `backend/api/prediction/` (model.py / features.py / calibration.py / eval.py)
> 과제 스크립트: 이 폴더의 `1_train.py` / `2_evaluate.py`

## 사용 스택 (딥러닝 아님)

- **scikit-learn**: LogisticRegression, RandomForestClassifier, StandardScaler, metrics
- **numpy**, **pickle** (모델 저장)
- TensorFlow / Keras / PyTorch **사용 안 함** — 전통 ML

## 모델 구조 — 3단 앙상블

```
ml_p  = (1 - w_rf) · LogisticRegression확률 + w_rf · RandomForest확률
final = (1 - w_s)  · ml_p                  + w_s  · sabermetric 베이스라인 확률
```

| 구성요소 | 설정 | 역할 |
|---|---|---|
| Logistic Regression | C=1.0, max_iter=1000, StandardScaler 입력 | 선형 관계 안정 포착 |
| Random Forest | 200 trees, max_depth=6 (과적합 억제) | 비선형 상호작용 (예: 선발 약해도 불펜 휴식으로 보완) |
| Sabermetric 베이스라인 | 피타고리안 등 공식 기반 홈승 확률 | 데이터 적은 초반 안정화 (운영 모델만, 과제판은 LR+RF 2단) |
| w_rf, w_s | **grid search** (검증 정확도 기준) | 자동 선택 |

- RF는 스케일 불변 → 원본 입력 / LR만 표준화 입력
- 성능: 앙상블 acc ~70.1% (운영 학습 시점), 홈승 베이스라인 ~54%

## Features (~108개)

| 그룹 | 항목 |
|---|---|
| 팀 시즌 | 승률, **피타고리안 승률**(지수 1.83), 경기당 득/실점 |
| 팀 타격 | OPS, wOBA, wRC+, BABIP (batter_stats 집계, AB>50) |
| 팀 투수 | ERA, WHIP |
| **선발투수** | 시즌 ERA/WHIP, 최근 3경기 ERA, BB/9, K/BB, **vs 상대팀 ERA** |
| **라인업** (발표 시) | 타순 9명 OPS/wOBA합/wRC+ |
| **불펜** | ERA, FIP, 최근 소화 이닝(피로도), 휴식일 |
| 상황 | 상대전적(h2h), 최근 폼(승률/득실/OPS), **구장 팩터**(득점/HR), 요일/주말/더블헤더 |
| 모멘텀 | 연승/연패 수치, 3연승+/3연패+ 플래그 |
| 합성 | P_starter/P_bullpen/P_total, 기대득점, saber 홈승확률 |
| **Diff 파생 27개** | 홈-원정 차이 (wpct_diff, starter_era_diff …) — 단독값보다 강한 신호 |

feature 산출은 경기 '시작 전 시점' 기준 (features.py `get_features(game_id)`).

## 학습 파이프라인

1. 2026시즌 **종료 경기 전체** 로드 (시간순)
2. **시간순 split** train 80% / test 20% — 랜덤 split은 미래 정보 누수라 금지
3. 가중치 grid search:
   - 운영(model.py): test셋으로 직접 탐색 후 100% refit
   - **과제(1_train.py)**: train 내부 80/20 검증으로만 탐색 (test 오염 방지) → train 전체 refit
4. pickle 저장 — 과제판은 **test 스냅샷(X_test/y_test) 동봉**
   (feature가 DB 누적 스탯 의존 → 재산출 시 값 변동 → 평가 재현성 확보 목적)

## 평가 (2_evaluate.py)

- 지표: Accuracy(정분류율) / ROC-AUC(확률 순위 품질) / Log Loss(확률 보정) / 혼동행렬
- 베이스라인: 다수 클래스(홈승) 고정 예측 대비 개선폭
- 해석: RF feature_importances_ Top 10 (최근 학습에서 1위 = `h2h_wpct` 상대전적)

### 최근 실행 결과 (2026-06-07, 350경기)
```
train 280 / test 70, val 기준 w_rf=0.5
LR 단독  acc 0.557  auc 0.578
RF 단독  acc 0.686  auc 0.724
앙상블   acc 0.557  auc 0.629  logloss 0.673
베이스라인 0.543
```
관찰: 이 분할에선 RF 단독 > 앙상블 — validation/test 분포 차이로 가중치 일반화가
흔들린 사례 (표본 70경기 소규모). 토론 포인트로 활용 가능.

## 운영 연동 (scheduler)

- 매일 오늘 경기 예측 로깅 (`log_today_predictions`)
- **라인업 발표 / 등록말소 발생 시 재예측** + API 캐시 무효화
- 학습 전 `calibrate_all(season)`: 리그 상수/피타고리안 지수/composite 가중치 시즌 보정
- API: `GET /games/{id}/predict` → 앱 GameCard 승리확률 pill

## 실행 명령 (backend 디렉토리)

```bash
python3 api/prediction/assignment/1_train.py     # → models/assignment_model.pkl
python3 api/prediction/assignment/2_evaluate.py  # → 성능 리포트 출력
```
