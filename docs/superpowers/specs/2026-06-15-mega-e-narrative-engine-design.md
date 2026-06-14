# 메가E v1 — 내러티브 엔진 (설계)

작성일: 2026-06-15
상태: 승인됨 (구현 대기)

## 목표

경기 데이터를 사람 말로 바꾸는 **단일 내러티브 엔진**을 만들고, 3개 surface에 연결한다.
라이트팬 funnel(앱 최대 약점)을 메우는 게 핵심. v1은 템플릿 기반(비용0·즉시·네트워크 의존X),
엔진 인터페이스를 추상화해 추후 LLM으로 내부만 교체 가능하게 한다.

## v1 범위

1. **AI 경기 한줄평** — 종료 시 생성, 기존 `game_summary` 푸시 본문을 한줄평으로 교체(신규 푸시·토글 없음)
2. **오늘의 MVP** — WPA(plate_appearances `win_rate_after - before`) 기반 승팀 최대기여자
3. **라이브 "지금 무슨 상황?" 캡션** — relay `current_state`에서 생성, 인앱 표시(푸시 없음)

### 범위 외 (v2+)
경기 3줄 요약·아침브리핑 자연어 강화·캐주얼모드 홈·쉬운 스탯 등급. LLM 생성 전환. 다이제스트.

## 컴포넌트

### 1. `backend/api/narrative.py` — 순수 템플릿 모듈
- DB 접근 없음. 구조화된 dict 입력 → 한국어 str 출력. LLM 교체가능(같은 시그니처).
- `game_review(facts: dict) -> str`
  - 입력: home/away 팀명·스코어, 승/패/세이브/홀드 투수, mvp(name·line), 결정 순간(WPA 최대 타석 설명),
    플래그(walkoff·extra_innings·sweep 등), 선발 QS 여부
  - 출력: 1~2문장 한국어 한줄평. 분기 우선순위 = 끝내기 > 연장 > 역전(WPA 큰 변동) > 완/대승 > 투수전 > 평이
- `live_caption(state: dict) -> str`
  - 입력: inning·half, out, base1~3, score 차, (있으면) home_win_prob
  - 출력: 짧은 한국어 상황 한 줄 ("2사 만루, 한 방이면 역전" / "8회말 1점차 접전"). 데이터 부족·경기 외 시 빈 문자열
- `mvp_line(mvp: dict) -> str` — "3안타 2타점 결승타" 류 한 줄
- 톤: 간결·중립·과장 없음. 빈 입력/누락 필드 안전(가드).

### 2. WPA 기반 MVP 계산 (`_send_game_summary` 내)
- 쿼리: `plate_appearances`에서 타석별 `win_rate_after - win_rate_before`를 타격팀 기준 부호화,
  타자별 합산 → 승팀에서 |합| 최대 = MVP. WPA는 홈 기준(0~100)이므로 원정 타자는 부호 반전.
- 폴백: WPA 데이터 없음(시즌초 컨텍스트 NULL) → 기존 rbis/hr 휴리스틱 MVP 사용.
- 산출: mvp_player_id, mvp_name, mvp_line(narrative.mvp_line)

### 3. `game_reviews` 테이블 (신규)
```
game_id        INT PRIMARY KEY REFERENCES games(id) ON DELETE CASCADE
review_text    TEXT
mvp_player_id  INT NULL REFERENCES players(id) ON DELETE SET NULL
mvp_name       TEXT
mvp_line       TEXT
created_at     TIMESTAMPTZ DEFAULT now()
```
- 종료 후처리서 1회 upsert(ON CONFLICT(game_id) DO UPDATE). 재계산 안전.
- `GRANT ALL ON game_reviews TO playball_user;` + 시퀀스 없음(game_id가 PK).
- 재사용: 경기상세 배지, 추후 공유 카드/다이제스트.

### 4. 통합 지점
- **`crawler/scheduler.py` `_send_game_summary`**: facts 수집(스코어·투수·WPA MVP·game_event_stream의
  walkoff/extra_innings 플래그) → `narrative.game_review(facts)` → `game_reviews` upsert →
  `notify_game_summary(..., review_text=리뷰)` 호출
- **`api/fcm_service.py` `notify_game_summary`**: `review_text` 파라미터 추가. 있으면 푸시 본문으로 사용
  (없으면 기존 조립 본문 — 하위호환)
- **relay 엔드포인트**(`api/routers/games.py`): `current_state`로 `live_caption` 생성 →
  `field_view.situation_caption`에 주입 (relay 캐시 안쪽, 추가 비용 미미)
- **game detail 엔드포인트**: `game_reviews` LEFT JOIN → 응답에 `review`(text·mvp) 포함

### 5. 클라이언트 (app/lib)
- **경기상세 상단**: 한줄평 배지(review_text) + MVP 칩(mvp_name·mvp_line) — `review` 있을 때만
- **필드뷰**: "지금 무슨 상황?" 캡션(situation_caption) — 비어있지 않을 때만
- **킬스위치**: `AppConfig.enabled('narrative')` 가드 (배지·캡션 둘 다). OFF = graceful 숨김

### 6. 킬스위치 (backend FEATURES + 클라 AppConfig 1:1)
- backend admin FEATURES에 `narrative` 추가, 클라 `AppConfig.enabled('narrative')` 가드.
- 기본 ON(kill_switches 미기재=enabled).

## 데이터 흐름
```
[종료 감지] post_finished → _send_game_summary
   → facts 쿼리(games/game_pitchers/plate_appearances WPA/game_event_stream)
   → narrative.game_review(facts) + mvp_line
   → game_reviews upsert
   → notify_game_summary(review_text=...) → fcm 푸시(본문=한줄평)
[라이브] relay 응답 조립 → narrative.live_caption(current_state) → field_view.situation_caption
[조회] game detail → game_reviews join → review 필드 → 앱 배지/MVP칩
```

## 에러 처리
- narrative 함수: 입력 누락/빈값에 빈 문자열 또는 평이 문구 반환(예외 던지지 않음). 푸시·relay 흐름 차단 금지.
- game_reviews 저장 실패: try/except로 격리 — 실패해도 푸시는 발송(리뷰 없는 기존 동작으로 폴백).
- WPA MVP 쿼리 실패/빈 결과: rbis 휴리스틱 폴백.
- relay live_caption: 예외 시 빈 문자열(필드뷰 캡션만 누락, relay 정상).

## 테스트
- `backend/tests/test_narrative.py` (순수, DB 불요 — 오늘 pytest 패턴):
  - game_review 분기(끝내기/연장/역전/투수전/평이) 각 1케이스
  - live_caption(만루/접전/경기외 빈문자열/데이터부족)
  - mvp_line 포맷
- WPA MVP 쿼리 = DB 테스트(skipif TEST_DATABASE_URL) — 부호반전·폴백 검증 (선택, 시간 되면)
- CI backend-test job가 자동 실행.

## 검증 (구현 후)
- 서버 pytest 통과 (오늘처럼 scratch DB)
- py_compile + 배포 + smoke ALL PASS
- 실경기 1건으로 한줄평 본문·MVP·캡션 육안 확인(라이브 시간대) — 선택
- 웹 재빌드+배포 (클라 변경 동반)

## 구현 순서 (writing-plans에서 상세 스토리화)
1. narrative.py + test_narrative.py (순수, 독립 검증)
2. game_reviews 테이블 + GRANT
3. WPA MVP 쿼리 + _send_game_summary 통합 + notify_game_summary review_text
4. relay live_caption 주입
5. game detail review join
6. 클라: 배지·MVP칩·캡션 + AppConfig narrative 가드
7. 배포(서버) + 웹 재빌드
