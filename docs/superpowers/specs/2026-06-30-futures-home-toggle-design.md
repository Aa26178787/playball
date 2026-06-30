# 홈 화면 1군 ↔ 퓨처스 토글 (설계)

날짜: 2026-06-30
범위: Flutter 앱(웹 동반) — 백엔드 변경 없음

## 목적
홈(경기) 탭에서 `[1군 | 퓨처스]` 세그먼트 토글로 1군 일정과 2군(퓨처스) 일정을 오갈 수 있게 한다. 퓨처스 모드는 기존 1군 레이아웃(월/날짜 스트립 + 게임카드 리스트)을 **그대로 재사용**하고 데이터만 퓨처스로 채운다. 기존에 순위 탭 5번째에 있던 퓨처스 탭은 중복이므로 제거한다.

## 결정 사항 (브레인스톰 확정)
1. 퓨처스 뷰 = 1군 레이아웃 전체(월/날짜 스트립 + 카드)를 퓨처스 데이터로 변경.
2. 토글 위치 = 헤더 상단, 월/날짜 스트립 바로 위(날짜 점프 근처)에 세그먼트 단독 줄.
3. 순위 탭의 기존 퓨처스 탭(5번째) = 제거 → 순위 탭 4개로 복귀.
4. 퓨처스 모드일 때 1군 전용 컨트롤(전체/마이팀 필터 칩 · 간략 토글) = 숨김.

## 데이터 소스 (기존 재사용, 백엔드 무변경)
- `GET /futures/games?season={year}&month={m}` → `{ games:[{game_id, game_date, away_code, away_label, home_code, home_label, away_score, home_score, stadium, status, series_id, is_exhibition, has_box}], months:[int] }` (이미 존재).
- `GET /futures/games/{game_id}/box` → 박스스코어 (탭 시 `showFuturesBoxSheet`로 이미 소비).
- 퓨처스는 라이브/중계 없음 → status ∈ {예정, 종료, 취소}만. 30초 폴링·LIVE pill 미적용.
- 시즌 범위: 퓨처스 데이터 = 2025, 2026만 (`months` 응답으로 확인).

## 상태 (home_screen `_HomeScreenState`)
- `bool _futuresMode = false` — 현재 뷰. 토글로 전환. **영속 안 함**(앱 재시작 시 항상 1군). 세션 내 유지.
- `Map<String, List> _futuresByDate` — 현재 보는 월의 퓨처스 게임을 `yyyy-MM-dd` → 게임리스트로 그룹. 날짜 스트립 활성/리스트 둘 다 여기서 파생.
- `Set<String> _futuresActiveDates` — `_futuresByDate.keys` (스트립에서 경기 있는 날만 탭 가능; 1군의 `_gameDates`와 동일 역할).
- `bool _futuresLoading`.

## 로딩 로직
1군: 기존 `_loadGames` 그대로 (오늘=bootstrap, 그 외 `getGamesByDate`).

퓨처스: **월 단위 1콜**로 해당 월 전체를 받아 날짜별 그룹핑(1군 캘린더 lazy 패턴과 동일).
- `_loadFuturesMonth(year, month)`: `getFuturesGames(year, month)` → `games`를 `game_date`로 그룹 → `_futuresByDate` / `_futuresActiveDates` 갱신.
- 월이 바뀌면(스트립 chevron/피커) 해당 월 재로딩. 이미 로딩한 월은 캐시(`_futuresByDate`가 월 단위라 월 전환 시 교체; 단순화 위해 매 월 전환 1콜 허용 — `@cached(300)` 서버 + LocalCache로 충분히 가벼움).
- 날짜 선택 시 추가 호출 없음 — `_futuresByDate[selectedKey]`에서 리스트만 필터.

## 토글 전환 동작
- 1군 → 퓨처스: `_futuresMode=true`. 라이브 타이머 정지. 현재 `_selectedDate`의 연/월로 `_loadFuturesMonth`. 선택일에 퓨처스 게임이 없으면 그 월의 **가장 최근 경기일**(없으면 최신 퓨처스월의 최근일)로 `_selectedDate` 점프.
- 퓨처스 → 1군: `_futuresMode=false`. 1군 라이브 타이머 재개. `_selectedDate`가 1군 시즌 범위 밖이면 오늘로 복귀 후 `_loadGames`.
- `setState` + 햅틱(기존 토글 패턴 준용).

## UI 변경 (home_screen)
1. **세그먼트 토글**: 월/날짜 스트립 컨테이너(현 1484~1492) 최상단에 `[1군 | 퓨처스]` pill 세그먼트 1줄 추가. 선택=`Pal.ink`/배경, 비선택=`Pal.sub`. 디자인 토큰(`Typo`,`Pal`,`Radii.pill`,`Space`) 사용.
2. **월/날짜 스트립**: 그대로 재사용. 퓨처스 모드에서는 활성일 판정 소스를 `_gameDates` 대신 `_futuresActiveDates`로, 월 네비 범위를 퓨처스 시즌(2025~2026)으로 분기. '오늘' 점프는 퓨처스 모드에서 "최신 경기일"로 동작(오늘에 2군 경기 없을 수 있음).
3. **1군 컨트롤 숨김**: `if (!_futuresMode)`로 전체/마이팀 필터 칩 줄 + 간략 토글 줄 감싸 퓨처스 모드 시 미표시.
4. **게임 리스트**: `_buildGameList()`가 `_futuresMode`면 퓨처스 카드 리스트로 분기. 카드 = 공용 위젯 `FuturesGameCard`(아래). 탭 → `has_box==true`면 `showFuturesBoxSheet`, 아니면 비활성.
5. **오프시즌/서버배너/등록말소 배너**: 퓨처스 모드에서는 1군 전용(등록말소 배너)만 숨김. 서버 배너는 공통 유지.

## 컴포넌트 분리
- **신규 `app/lib/widgets/futures_game_card.dart`**: 현 `futures_screen.dart`의 `_gameCard`를 그대로 추출한 공용 위젯(`FuturesGameCard(game, isDark, onTap)`). 홈 퓨처스 모드 + (필요 시) 어디서든 재사용.
- **`futures_screen.dart` 제거**: 월 브라우징 UI는 홈 날짜 스트립으로 대체됨. 카드 로직은 위 위젯으로 이전. `futures_box_sheet.dart`는 유지(재사용).
- **`team_screen.dart`**: 순위 탭 TabBar/TabBarView에서 퓨처스 탭(5번째) + `FuturesScreen` 참조 제거 → 탭 4개(팀순위/팀기록/부문별순위/역대기록실)로 복귀. import 정리.

## 경계/인터페이스
- `FuturesGameCard`: 입력 = 게임 Map + isDark + onTap 콜백. 내부 = 로고/스코어/상태/구장/교류전 배지 렌더. 의존 = `TeamLogo`, 디자인 토큰. 홈/기타 소비자가 내부를 몰라도 사용 가능.
- 홈 상태는 1군/퓨처스 두 데이터 경로를 `_futuresMode` 단일 플래그로 분기. 로딩 함수(`_loadGames` vs `_loadFuturesMonth`)는 독립.

## 엣지/에러
- 퓨처스 월 1콜 실패 → `_futuresLoading=false` + 빈 상태("경기 없음"). 기존 try/catch 패턴.
- 월에 경기 0개 → 날짜 전부 비활성 + "경기 없음".
- 연도 경계 월 이동(예: 2026-01 → 2025-12) 시 `season` = 선택일 연도로 재계산.
- 토글 빠른 연타 → setState 멱등, 마지막 상태 기준 1콜(기존 `_loadGen` race 가드 준용).

## 테스트/검증
- `flutter analyze lib` = 0.
- 골든 회귀 통과(영향 위젯 = 홈/team_screen 구조 변경; 기존 골든 영향 없으면 통과 확인).
- 수동/웹 스팟체크: 토글 전환 → 퓨처스 날짜 스트립·카드 표시·박스 시트 진입, 1군 복귀 정상. (Flutter canvas 헤드리스 관찰 불가 → 사용자 디바이스/웹 스팟체크 권장.)
- 웹 동반 빌드+배포(`--wasm`, `/app/` 200) — 앱 수정 시 웹 동반 원칙.

## 비목표 (YAGNI)
- 퓨처스 라이브 중계/투구/필드뷰 (소스 없음 — C2에서 infeasible 확정).
- 퓨처스 풀 히어로 카드(날씨/선발/최근5/예측) — 데이터 없음, 컴팩트 카드로 충분.
- 토글 선택 영속(앱 재시작 시 기억) — v1 제외.
- 퓨처스 마이팀 필터 — v1 숨김(추후 2군 팀코드 매칭으로 추가 가능).

## 영향 파일 요약
- `app/lib/screens/home/home_screen.dart` — 토글·분기·퓨처스 로딩(주 변경).
- `app/lib/widgets/futures_game_card.dart` — 신규(카드 추출).
- `app/lib/screens/futures/futures_screen.dart` — 제거.
- `app/lib/screens/team/team_screen.dart` — 퓨처스 탭 제거.
- `app/lib/api/api_service.dart` — `getFuturesGames` 기존 그대로 사용(변경 없음 예상).
- 백엔드 — 변경 없음.
