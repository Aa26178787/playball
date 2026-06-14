# 메가F v1 — 리텐션 점화 (설계)

작성일: 2026-06-15
상태: 승인됨 (구현 대기)

## 목표

이미 빌드됐지만 `kill_switches.points = false`로 꺼져 있는 리텐션 루프(포인트·승부예측·
출석·뱃지·주간미션·리더보드)를 켜고, 켜기 전 회귀 테스트로 안전망을 깐다. 추가로 예측
마감 카운트다운(클라)과 예측 결과 푸시(서버)를 신설해 참여 동기를 강화한다.

핵심 = "신규 빌드 최소, 만든 것 활성화 + 검증". 신규 코드는 결과 푸시·카운트다운·테스트뿐.

## 현재 상태 (확인됨)
- `app_config.kill_switches = {"points": false}` — points만 OFF, 나머지 ON.
- 빌드 완료(`AppConfig.enabled('points')` 가드): 게임카드 `_PredictionBar` 팬투표, 출석(+5),
  마이페이지 points_screen, 뱃지(`api/badges.py` 11종), 주간미션(`/user/missions`), 리더보드(TOP50).
- 정산: scheduler 종료 후처리 루프(~1663-1685)에서 `award()` 적중50/참여10/무10. 푸시 없음.

## v1 범위
1. 활성화 (points ON)
2. 회귀 테스트 (badges/missions — award는 기보유)
3. 예측 결과 푸시 (신규)
4. 예측 마감 카운트다운 (클라, 신규)

### 범위 외 (F2)
오늘의 MVP 팬투표(E MVP와 결합), 리더보드 홈 노출, 1:1 예측 대결, 팬 레벨 통합.

## 컴포넌트

### 1. 활성화
- `POST /admin/feature-flags`로 `points` ON (kill_switches에서 points 제거 또는 true). admin
  엔드포인트가 `/app-config` 캐시 무효화 동반(06-12d). SQL 직접보다 엔드포인트 사용(캐시 일관).
- **순서**: 테스트·결과푸시·카운트다운 배포 완료 후 마지막에 ON (켜진 상태로 신규 코드 노출).

### 2. 회귀 테스트 (DB, skipif TEST_DATABASE_URL — 오늘 패턴)
- `backend/tests/test_badges.py`:
  - evaluate_badges 멱등: 동일 조건 2회 평가 → user_badges 중복 INSERT 없음(신규 획득 1회만)
  - 임계값 경계: metric이 threshold 도달 시 획득, 미달 시 미획득
- `backend/tests/test_missions.py`:
  - 주간 미션 진척 계산 정확
  - 완료 시 자동 보상 award 멱등(reason=mission_weekly, 재호출 시 중복 적립 X)
- 최소 테이블만 conftest에서 생성(user_badges, point_ledger, 필요시 game_predictions 등).
  `_metrics`가 참조하는 테이블이 많으면 해당 함수를 직접 호출하지 말고 평가 단위(임계 비교) 테스트로
  좁힌다 — 광범위 스키마 생성 회피. (실행 시 badges.py `_metrics`/`evaluate_badges` 의존 테이블 확인 후 결정)

### 3. 예측 결과 푸시 (신규)
- `api/fcm_service.py`: `notify_prediction_result(user_id, game_id, home_team, away_team, outcome, points)`
  - outcome ∈ {win, lose, draw}. 본문 예: 적중="🎯 예측 적중! +50P ({home} vs {away})",
    참여="아쉽게 빗나감 +10P", 무승부="무승부 +10P".
  - 단일 유저 타겟(`push_tokens` 조회) → `_send` 경유(quiet hours·채널·무효토큰 정리 자동).
  - data.type='prediction_result', game_id. 인앱 알림함 저장 포함(_send가 처리).
  - notification_log dedup: `(game_id, 'prediction_result', user_id)` — 정산 재실행 안전.
- `crawler/scheduler.py` 정산 루프: award 후 (user_id, outcome) 수집 → 팀명 1회 조회 →
  commit 후 유저별 `notify_prediction_result` 호출(try/except 격리 — 푸시 실패해도 정산 유지).
- 게이트: 예측 참여 = 암묵 opt-in. points 플래그 가드(꺼져 있으면 예측 자체가 없어 무발송).
  별도 알림 토글 신설 안 함(F2서 필요 시).

### 4. 예측 마감 카운트다운 (클라, 순수)
- `_PredictionBar`(home_screen 게임카드): game.startTime 기준 "마감 N분 전" 표시.
  - 예정/라인업이고 시작 전: 카운트다운. 시작 시각 지나면 투표 잠금 + "마감" 표시.
  - 1분 주기 갱신(이미 홈 폴링/타이머 있으면 재사용, 없으면 경량 Timer 또는 build 시 계산).
  - 이미 `AppConfig.enabled('points')` 가드 안.

## 데이터 흐름
```
[정산] post_finished 정산 루프 → 각 예측자 award → 팀명 조회 →
   notify_prediction_result(uid, gid, home, away, outcome, pts) → 푸시GW → 푸시+인앱
[활성화] admin POST /admin/feature-flags points=ON → /app-config 캐시 무효화 → 앱 가드 통과
[카운트다운] 게임카드 _PredictionBar: startTime - now → "마감 N분 전" / 잠금
```

## 에러 처리
- 결과 푸시: 유저별 try/except — 한 명 실패가 정산/타 유저 푸시 막지 않음. 토큰 없으면 무발송(정상).
- notification_log dedup으로 정산 재실행 시 중복 푸시 방지.
- 활성화: admin 엔드포인트 실패 시 SQL 폴백 가능하나 캐시 무효화 누락 주의(엔드포인트 우선).
- 카운트다운: startTime 파싱 실패 시 카운트다운 숨김(투표 버튼은 유지).

## 테스트 / 검증
- `test_badges.py`·`test_missions.py` 서버 pytest(scratch DB) 통과 + CI green.
- 예측 결과 푸시: 가짜 예측 1건 시뮬 또는 라이브 종료 1경기로 푸시 발송 로그 확인(선택).
- 활성화 후: `/app-config` kill_switches에 points 없음/true 확인, 앱 팬투표 노출 확인.
- smoke ALL PASS, 웹 재빌드.

## 구현 순서 (writing-plans에서 상세화)
1. test_badges.py + test_missions.py (켜기 전 안전망)
2. notify_prediction_result (fcm_service)
3. 정산 루프에 결과 푸시 통합 (scheduler)
4. 클라 _PredictionBar 마감 카운트다운
5. 배포(서버) + 웹 재빌드 + pytest/smoke 검증
6. **마지막**: points 활성화 (admin) + 노출 확인
