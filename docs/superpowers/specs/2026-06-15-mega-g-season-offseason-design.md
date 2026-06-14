# 메가G v1 — 시즌 상태머신 + 오프시즌 모드 (설계)

작성일: 2026-06-15
상태: 승인됨 (구현 대기)

## 목표

야구앱 최대 갭 = 비시즌 DAU 폭락. G는 ① 시즌 단계를 자동 인지하는 상태머신(토대) ②
오프시즌 홈 UX ③ 연말결산 Wrapped 카드를 만든다. 정규시즌(현재)엔 대부분 비가시이나,
Wrapped는 보유 데이터로 지금 빌드·미리보기 가능하고 상태머신은 Oct/Nov 전환을 대비한다.

## 현재 상태 (확인됨)
- `app_config.season_phase` = 'regular' (수동 admin 설정). 클라 `AppConfig.seasonPhase` getter 有.
- 소비자 0, 자동화 0 — 사실상 빈 껍데기.

## v1 범위
1. 시즌 상태머신 자동화 (scheduler)
2. 오프시즌/무경기 홈 UX (D-day + 결산 진입)
3. 연말결산 Wrapped (backend 집계 + 클라 화면 + 공유)

### 범위 외 (G2+)
스토브리그 FA 트래커, 브라켓 예측(postseason), 오프시즌 퀴즈 시즌제, 명장면 리플레이.

## 컴포넌트

### 1. 시즌 상태머신 자동화
- 순수 함수 `api/season.py::compute_phase(today, first_game, last_game, has_recent) -> str`
  - `first_game`/`last_game` = 올해 정규경기 최초/최종 game_date (date), `has_recent` = 오늘 기준
    ±10일 내 경기 존재 여부.
  - 규칙: first_game 없음 → 'offseason'(일정 미정). today < first_game → 'preseason'.
    today > last_game(±10일 내 경기 없음) → 'offseason'. 그 외 → 'regular'.
  - postseason은 자동 판별 안 함(KBO 일정에 PS 구분 메타 부재).
- `crawler/scheduler.py` 일일 잡 `_update_season_phase()`:
  - games에서 올해 first/last/recent 조회 → compute_phase → app_config.season_phase 갱신.
  - ⚠️ 현재 season_phase=='postseason'이면 덮어쓰지 않음(admin 핀 보존).
  - 변경 시에만 UPDATE + /app-config 캐시 무효화(admin.py set_feature_flag의 캐시 무효화 패턴 참조).
  - 등록: `schedule.every().day.at("18:30").do(_update_season_phase)` (UTC, KST 03:30 저트래픽).

### 2. 오프시즌/무경기 홈 UX
- 홈에서 `AppConfig.seasonPhase == 'offseason'`일 때(또는 선택일 무경기 + offseason):
  - 마이팀 **다음 경기 D-day 카드**(미래 일정 있으면) — 기존 게임 fetch 활용, 없으면 "다음 시즌을
    기다려요" 안내.
  - **연말결산 진입 버튼**(Wrapped 화면으로).
- 정규시즌엔 미노출(기존 날짜스트립/게임리스트 그대로). offseason 분기만 추가.
- 무가드(홈 기본 UX) — 단 결산 진입은 share/points 데이터 의존.

### 3. 연말결산 Wrapped
- backend `GET /user/season-wrapped?year=YYYY` [Bearer]:
  - 집계(해당 연도): 직관 횟수·승/패/무·방문 구장 수(user_stadium_visits+games),
    예측 적중/참여(point_ledger reason), 투표 수(player/team votes), 누적 포인트,
    출석 일수, 최애 팀/선수(favorite_*). year 기본 = 현재 연도.
  - 반환 dict(없는 항목 0/null). 비로그인 401.
- 클라 `screens/wrapped/season_wrapped_screen.dart`:
  - 카드형 요약(직관/예측/포인트/최애 등) — share_cards.dart 톤. `showShareCardDialog`로 공유(웹은 버튼 숨김 — 기존 규칙).
  - 진입: 마이페이지(상시) + 오프시즌 홈 버튼.
  - `AppConfig.enabled('share')` 가드는 공유 버튼만(화면 자체는 노출).

## 데이터 흐름
```
[상태머신] scheduler 일일 → games first/last/recent → compute_phase → season_phase 갱신
   → /app-config 캐시 무효화 → 앱 AppConfig.seasonPhase
[홈] seasonPhase==offseason → D-day 카드 + 결산 진입
[Wrapped] mypage/offseason 진입 → GET /user/season-wrapped → 카드 렌더 → 공유
```

## 에러 처리
- compute_phase: first_game None 등 엣지에 안전(예외 X, 'offseason' 폴백).
- _update_season_phase: 쿼리/갱신 실패 try/except 격리 — 실패해도 기존 phase 유지.
- season-wrapped: 데이터 없으면 0/null(빈 결산도 렌더). 쿼리 실패 시 500 대신 부분 try.
- 홈 offseason 분기: seasonPhase 파싱/None은 'regular' 폴백(기존 getter 기본값).

## 테스트 / 검증
- `backend/tests/test_season.py` (순수): compute_phase 케이스(preseason/regular/offseason/일정없음).
- season-wrapped 집계 = DB 테스트(skipif) 선택 — 시간 되면.
- 서버 pytest(scratch DB) + smoke + 웹 재빌드.
- 상태머신 라이브 검증: 잡 1회 수동 실행 → season_phase=='regular' 유지 확인(현재 정규).
- 오프시즌 홈/Wrapped 육안은 phase 강제(admin으로 offseason 임시 설정)로 미리보기 가능(선택).

## 구현 순서 (writing-plans에서 상세화)
1. season.py compute_phase + test_season.py
2. scheduler _update_season_phase + 등록
3. backend /user/season-wrapped 집계
4. 클라 season_wrapped_screen + 마이페이지 진입
5. 홈 오프시즌 분기(D-day + 결산 진입)
6. 배포 + pytest/smoke + 웹 재빌드
