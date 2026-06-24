# 우천중단(Rain Delay) 감지·표시·알림 — 설계

**날짜**: 2026-06-23
**트리거**: "이닝별 중계에서 우천중단 감지 시, 게임카드 및 status 부분에 우천중단 표시 + 알림 추가"

## 목적
경기 진행 중 우천으로 **일시 중단**된 상황을 감지해 ① 게임카드/경기상세 status에 "우천중단" 표시 ② 양 팀 팬에게 푸시 알림. 기존 **우천취소**(경기 전 `BEFORE`+`경기취소` → status `취소`)와 **별개** — 중단은 **재개 가능**한 일시 상태.

## 조사 결과 (근거)
- Naver schedule API `statusInfo` 표본(2025~2026 수개월): 취소 = `BEFORE`+`경기취소`뿐. 경기 중 **중단을 나타내는 명시 필드 없음**(`suspendedFlag` 부재). 중단은 드물어 라이브 표본도 없음.
- → 감지는 **relay textRelays 텍스트 키워드**로 (사용자 승인). status enum은 안 건드리고 **별도 flag** 사용 (사용자 승인). 알림은 **양 팀 팬 전체** (우천취소와 동일, 사용자 승인).

## 설계

### 1) 저장 — `games.suspended BOOLEAN DEFAULT FALSE`
- 마이그레이션: `ALTER TABLE games ADD COLUMN IF NOT EXISTS suspended BOOLEAN DEFAULT FALSE;` (기존 테이블, GRANT 불요).
- status는 `진행` 그대로 유지, suspended가 오버레이. 재개/종료/취소 시 자동 false.

### 2) 감지 — `naver_crawler.is_game_suspended(naver_game_id, inning) -> bool`
- relay(현재 이닝) fetch → **가장 최근** textRelays 항목들의 text/title/textOptions[].text 스캔.
- 키워드(보수적, 오탐 최소): `서스펜디드`, `우천`+`중단`, `강우`+`중단`, `경기 중단`, `경기가 중단`, `중단되었`.
- 최근 항목 기준이라 **경기 재개 시(최근 항목=정상 투구) 자동 false**.
- ⚠️ Naver가 중단 텍스트를 실제로 발행하는지 라이브 미검증 — 키워드는 리스트 상수로 두어 실제 중단 발생 시 튜닝.

### 3) scheduler 통합 — `_check_rain_delays()` (smart_update 1분 루프 내, 진행 경기 대상)
- 진행 경기마다 `is_game_suspended` 호출 → DB `suspended`와 비교.
- **false→true** 전환: `UPDATE games SET suspended=TRUE`; `notify_rain_delay(...)` (미발송 시); `emit_event(gid,'rain_delay',...)`; `_mark_notified(gid,'rain_delay')`.
- **true→false** (재개/종료): `UPDATE games SET suspended=FALSE`. (알림 없음)
- 종료/취소 감지 경로에서도 suspended=FALSE 보장(종료 후처리에 가드).
- dedup: `_already_notified(gid,'rain_delay')` (sub_id 없음, 우천취소 패턴 동일). **경기당 1회** 알림(재중단 재알림은 v1 비목표).

### 4) 알림 — `fcm_service.notify_rain_delay(game_id, home, away, home_id, away_id)`
- `notify_game_cancelled` 미러: targets=`_get_targets('notify_game_start',[home_id,away_id])`.
- title `🌧️ 우천 중단` / body `{home} vs {away} 경기가 우천으로 중단됐습니다.` / data type `rain_delay`.
- user_notifications type=`rain_delay`. (game_start 버그 패턴 무관 — rain_delay는 이 경로만 기록)

### 5) API — `suspended` 필드 노출
- `/games/today`, `/games/date/{d}`, `/games/{id}`: SELECT에 `g.suspended` 추가 → 응답 `"suspended": bool`.
- 게임카드 소스(today/date)가 핵심. 상세도 포함.

### 6) 앱 UI
- 게임 모델 파싱에 `suspended` 추가.
- **게임카드**(full+compact) status pill: suspended면 LIVE 대신 **"우천중단"**(amber/회색 톤) 표시.
- **경기상세** status 영역: suspended면 "우천중단" 배지.
- **알림탭** `_typeIcon`: `rain_delay` → `Icons.umbrella` + 회색(취소와 구분 위해 amber 계열).

## 비목표 (v1)
- 재중단 재알림(경기당 1회만). 중단 사유/예상 재개시각. 중단 누적 시간 표시.

## 검증
- 백엔드: `py_compile` + (가능하면) 단위 — `is_game_suspended` 키워드 매칭 순수 테스트(샘플 relay dict).
- 앱: `flutter analyze lib` = 0.
- 라이브: 실제 우천중단 발생 시 flag/알림/표시 확인 (발생 전까진 키워드 매칭 단위테스트로 대체).
- 웹 동반 빌드+배포.

## 영향 파일
- `backend/database/` 마이그레이션 sql (신규)
- `backend/crawler/naver_crawler.py` (`is_game_suspended`)
- `backend/crawler/scheduler.py` (`_check_rain_delays`, 종료 가드)
- `backend/api/fcm_service.py` (`notify_rain_delay`)
- `backend/api/routers/games.py` (today/date/detail에 suspended)
- `app/lib/.../home_screen.dart`(또는 게임카드 위젯), `game_detail_screen.dart`, `notifications_screen.dart`, 게임 모델 파싱
