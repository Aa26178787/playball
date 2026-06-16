# 역대 데이터 UI 노출 — 설계 (2026-06-16)

## 목적
적재 완료된 역대(1982~) 선수·팀 데이터(`historical_*` 테이블)를 앱/웹에 노출.
올드팬 자산 + 비시즌 DAU 방어. 데이터는 이미 준비됨 → 순수 백엔드+프론트(크롤 불요).

## 확정된 의사결정 (브레인스톰 게이트 2026-06-16)
1. **노출 범위 = 풀**: 현역 통산보강 + 은퇴선수 검색/상세 + 스플릿 + 역대탭(명예의전당)
2. **검색 = 통합**: 기존 `/players/search`가 현역+은퇴 둘 다 반환 (검색박스 하나)
3. **은퇴 상세 = 신규 화면**: `historical_player_detail_screen` (기존 2773줄 화면 오염 회피)
4. **검색키 = `kbo_player_id` 정규** (수집 게이트서 확정, 이름조인 폐기)
5. **동명이인** = `kbo_player_id` UNIQUE로 dedup, 표시 = `primary_team + debut~final`

## 데이터 소스 (적재 완료 — 읽기 전용)
- `historical_players` ~1100명: kbo_player_id(정규키), `player_id`(현역 브릿지, nullable),
  bio(birth_date/height/weight/throws/bats/position/career/draft_info),
  debut_year/final_year/primary_team_id/naver_player_id
- `historical_season_stats` ~2880행(1982~2025) + PS 부분: season/team_franchise_id/team_name/
  타자·투수 스탯/`series_type`(DEFAULT '정규' / 와일드카드/준PO/PO/한국시리즈)/세이버(FIP만, war/woba/wrc+=NULL).
  UNIQUE(kbo_player_id, season, team_name, series_type).
  ⚠️ **정규시즌 = `series_type='정규'` 필터 필수** — 머지/통산합산/리더보드 전부 정규만(PS 중복 방지). PS = `series_type<>'정규'` 별도 섹션.
- `historical_awards` 541건: season/award
- `historical_splits` 6750행(2023~25 타자만): split_axis(홈원정/상대팀/월별)/split_value/avg/slg
- `team_franchises` 22행: 구단계보(team_name/start~end_year/current_team_id/is_continuous)

⚠️ 데이터 한계(UI 카피에 반영): 세이버 = FIP만(WAR/wOBA/wRC+ 없음), 스플릿 = 2023~25 타자만 +
분할값당 ~80% 커버, PS = 2006~ 부분결손, KBO 리스트 = 규정충족자만(비규정 시즌 일부 누락).

---

## 아키텍처

### Backend

#### 신규 라우터 `api/routers/historical.py`
- `GET /historical/{kbo_player_id}` `@cached(600)` — 은퇴선수 상세
  - 응답: `bio`(이름/타투/포지션/생일/신장체중/career/draft_info/primary_team/debut~final/is_active+player_id),
    `stats`(전 정규시즌, season DESC, team_name+세이버 포함), `career`(통산 합산 — 카운팅 합·비율 재계산),
    `awards`(연도별), `splits`(있으면, axis별 그룹), `postseason`(series_type≠정규, 있으면),
    `franchise_path`(primary_team의 team_franchises 계보 — 표시용)
  - 404 = kbo_player_id 없음
- `GET /historical/leaders?category=&limit=20` `@cached(3600)` — 역대탭/명예의전당
  - 통산 리더보드: 타자 HR/H/avg(규정환산)/SB, 투수 W/SO/ERA/SV. career 합산 기반.
  - 응답: 카테고리별 TOP N (kbo_player_id/name/primary_team/value/is_active)

#### 기존 확장
- `/players/search` (players.py) — `historical_players` UNION
  - 현역(players) 결과 + 은퇴선수(historical_players WHERE player_id IS NULL — 브릿지 있는 현역은 중복이라 제외)
  - 각 결과에 `key_type`('active'|'historical') + `key_id`(players.id | kbo_player_id) +
    `is_historical` + `years`(debut~final, historical만) 추가. 현역 결과는 기존 필드 무손상.
  - 정렬: 현역 우선 → 은퇴(활동 최근순). LIMIT 분리(현역 20 + 은퇴 20).
- `/players/{id}` (현역 상세, get_player_detail) — 역대시즌 머지
  - `historical_players.player_id = id` 있으면 그 `kbo_player_id`의 `historical_season_stats`
    (`series_type='정규'` AND `season < 2024` — batter/pitcher_stats 24~26과 중복 회피) 를 `result["stats"]`에 합류 → 시즌칩 자동 확장
  - ⚠️ 컬럼 키 매핑: `historical_season_stats`는 컬럼명이 일부 다름(`walks_allowed`/`strikeouts_pitched`/`complete_games`/`shutouts`) → 합류 시 앱 시즌그리드가 쓰는 기존 키(`walks`/`strikeouts`/`cg`/`sho` 등)로 변환 필수
  - `historical_awards` → `result["awards"]` 추가
  - core_compare/qualified(리그비교)는 **최신시즌(현역)만** 유지 — 과거시즌엔 미적용(기존 동작 보존)
  - 과거시즌 행은 세이버 일부 NULL → 앱이 `--`/숨김 처리(기존 트렌드 ERA NULL 가드 패턴 재사용)

### App (`app/lib`)

#### 검색결과 (player_screen)
- `_searchResults` 행에 `is_historical` 분기: 은퇴선수 = '역대' 배지 + 활동연도(`years`) 캡션.
  탭(active→player_detail, historical→historical_detail) 라우팅 = `key_type`.
- 동명이인 = `primary_team + years`로 행 구분.

#### 현역 상세 (player_detail_screen — 기존 재사용)
- 시즌칩이 머지된 `stats`(과거시즌 포함) 자동 렌더 → 코드 변경 최소(시즌칩 로직이 이미 stats 기반).
- 수상 섹션(`awards`) 신규 추가(있으면).

#### 은퇴 상세 (신규 `historical_player_detail_screen`)
- 진입 = 검색결과/역대탭 → `kbo_player_id`. `ApiService.getHistoricalPlayer(kboId)`.
- 섹션: 히어로(bio + franchise 계보 + draft/career) → 통산 핵심 → 시즌별 표 →
  포스트시즌(있으면) → 수상 → 스플릿(있으면, 축별 테이블) → franchise 계보 캡션.
- 라이브 데이터(존히트맵/구종/투구위치/트렌드/비교/인스타/투표) **없음** — 섹션 자체를 안 그림.
- ⚠️ 웹 이미지 3규칙 준수(netImage/netCircleAvatar, profile_image 없으면 이니셜 폴백).

#### 역대 탭 (player_screen 또는 진입점)
- `/historical/leaders` 소비 = 명예의전당 리더보드(카테고리 칩 + TOP 리스트, 행 탭→은퇴상세).
- 배치: player_screen 탭 추가(타자/투수/인기투표/**역대**) 또는 인기투표 탭 근처 진입.

### ApiService (api_service.dart)
- `getHistoricalPlayer(int kboId)` → `/historical/{kboId}`
- `getHistoricalLeaders({String category, int limit})` → `/historical/leaders`
- `searchPlayers` = 기존 시그니처 유지(응답에 historical 필드만 추가, 하위호환)

---

## 데이터 흐름
1. 검색 → `/players/search` → 현역+은퇴 혼합 결과 → 행 배지/라우팅
2. 현역 탭 → `/players/{id}` → 머지된 통산 시즌칩 (기존 화면)
3. 은퇴 탭 → `/historical/{kbo_player_id}` → 신규 상세
4. 역대탭 → `/historical/leaders` → 명예의전당 → 행 탭 → 3

## 에러 처리
- 모든 신규 엔드포인트 try/except + DB 연결 실패 500, 미존재 404 (기존 라우터 패턴).
- 앱 = `AppErrorView`(테마인식, 기존) 재사용. 빈 섹션 = 미렌더(공백 회피).
- 머지 실패(현역 브릿지 없음/역대행 없음)는 graceful — 기존 stats만 표시.

## 테스트
- Backend: `backend/tests/` pytest — historical 상세 집계(통산 합산 정확성)·search union dedup·leaders 정렬.
  순수 파서 가능분 + scratch DB(`playball_test`) 통합. 라이브 스팟체크(이승엽 467HR·선동열·franchise 계보).
- App: `flutter analyze lib` = 0. 골든(신규 화면 — 선택, share_cards 패턴).
- 웹: wasm 재빌드 → `/app/` 200, 검색서 은퇴선수 노출 육안(헤드리스 스팟).

## 구현 단계 (Phase — 점진 배포 가능)
- **P1 (API 토대)**: historical.py 라우터(상세+leaders) + /players/search union + /players/{id} 머지.
  main.py 라우터 등록. → 서버 배포 + 스모크.
- **P2 (현역 통산)**: 앱 현역상세 시즌칩 머지 확인 + 수상 섹션. 검색결과 배지/라우팅.
- **P3 (은퇴 상세)**: `historical_player_detail_screen` 신규 + ApiService.
- **P4 (역대탭)**: 명예의전당 리더보드 탭.
- 각 Phase = 웹 동반 빌드+배포(앱수정=웹필수 원칙).

## 비목표 (YAGNI)
- 투수 스플릿·OPS/OBP 스플릿·역대전체 스플릿 (데이터 미수집 — C2)
- WAR/wOBA/wRC+ 표시 (데이터 없음)
- 역대선수 인기투표/비교/공유카드 (라이브 기능, 추후)
- franchise 전용 계보 뷰 화면 (상세 내 캡션으로 충분)
- PS 완전성 복구 (역대수집 C2/low-pri)
