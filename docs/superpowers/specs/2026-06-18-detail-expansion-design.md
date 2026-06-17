# 선수/팀 상세 콘텐츠 확장 설계 (2026-06-18)

## 목표
적재된 역대 데이터(historical_*, team_franchises, batter/pitcher_stats)로 선수/팀 상세 깊이 강화. 크롤0 = 보유 데이터 계산·노출. 올드팬 자산·비시즌 DAU.

## 범위 (게이트 통과 — 전 항목)
- **선수**(현역+은퇴 공통): ① 타이틀 이력 ② 팀변천 타임라인 ③ 마일스톤 ④ 통산 스플릿
- **팀**: ⑤ 구단 약사/계보 ⑥ 역대 레전드 ⑦ 역대 팀 시즌기록

## 아키텍처 (lazy 분리 엔드포인트 — 핫 상세 로드 안 느리게)
- `GET /players/{id}/career-extras` @cached(3600) — 현역(브릿지 kbo_player_id 해석) → titles/team_timeline/milestones/splits
- `GET /historical/{kbo_id}/career-extras` @cached(3600) — 은퇴(kbo_player_id 직접) → 동일 구조
- 공유 헬퍼 `_career_extras(cur, kbo_player_id, player_type)` (DRY — 두 엔드포인트 공통)
- `GET /teams/{id}/legacy` @cached(3600) — franchise_history/legends/season_records
- 앱 = 상세 진입 시 세컨더리 호출(메인 상세와 별도), 섹션에 주입

## 데이터 로직

### ① 타이틀 이력 (시즌별 부문 1위 집계)
- 소스 = `historical_season_stats` (series_type='정규'). 부문별 시즌 max 보유 선수 = 타이틀.
- **카운팅 부문**(clean max): 타자 home_runs(홈런왕)·rbis(타점왕)·hits(최다안타)·stolen_bases(도루왕)·runs(득점) / 투수 wins(다승왕)·saves(세이브왕)·strikeouts_pitched(탈삼진왕)·holds(홀드왕)
- **비율 부문**(규정게이트 필수): 타자 avg(타격왕, pa≥3.1×팀경기 근사)·obp·slg·ops / 투수 era(평자책왕, innings_pitched≥1.0×팀경기 근사)
  - 규정 근사: KBO 규정타석=팀경기×3.1, 규정이닝=팀경기×1.0. 시즌 팀경기수는 가변 → **그 시즌 최다출전자 games×3.1 / 최다이닝 근사** 대신 단순화: 시즌별 pa 상위 + 해당시즌 리그평균 게임수. **v1 단순화**: 비율 타이틀은 `pa >= 규정(시즌 최대 games 기반)` 필터 후 max. 미달자 ERA 0.00 배제.
- 반환: `[{category:'홈런왕', count:5, seasons:[2002,2003,...]}]` (count desc)
- 구현: 시즌×부문 max를 서브쿼리로, 해당 player가 max와 동률인 시즌 집계.

### ② 팀변천 타임라인
- `historical_season_stats` team_name 시즌순 → **연속 구간 그룹핑**(같은 팀 연속 → start~end 병합).
- 반환: `[{team:'삼성', start:1995, end:2003}, {team:'지바롯데', start:2004, end:2005}, ...]`
- ⚠️ team_name = 당시 구단명(MBC/OB 등). franchise 매핑 표시는 옵션(원명 우선).

### ③ 마일스톤
- career 집계(_aggregate_career 재사용) → 달성 마일스톤 표시.
- 임계: 타자 HR(100/200/300/400/500), 안타(1000/2000/3000), 타점(1000) / 투수 승(100/150/200), 세이브(100/200/300), 탈삼진(1000/2000)
- 반환: `{reached:[{label:'통산 400홈런',value:400}], next:{label:'500홈런', remaining:33, eta_season:null}}`
- ETA: **현역만**(최근시즌 페이스로 remaining/연간 → eta_season). 은퇴=reached만.

### ④ 통산 스플릿
- `historical_splits` (2023~25 타자만 보유) → kbo_player_id career 집계(홈원정/상대팀별 avg/slg).
- ⚠️ 제한적(타자·3시즌) → 데이터 있을 때만 섹션 표시, 없으면 숨김.

### ⑤ 구단 약사/계보
- `team_franchises` current_team_id=team.id 매칭 → era 순 정렬.
- 반환: `[{team_name:'OB 베어스', start:1982, end:1998, note:'...'}, {team_name:'두산 베어스', start:1999, end:null}]`

### ⑥ 역대 레전드
- franchise(team_franchises로 매핑된 historical_season_stats team_franchise_id) 소속 선수 career 집계 → 부문별 TOP3 (HR/승/타율 등).
- 반환: `{batting:[{category:'통산 홈런', players:[{name,kbo_id,value}]}], pitching:[...]}`

### ⑦ 역대 팀 시즌기록
- franchise 소속 시즌행 집계 → 역대 최다승 시즌(games 기준 승 등)·최고 팀타율 등.
- 반환: `[{label:'역대 최다승 시즌', season:1985, value:'...'}]` (v1: 간단히 몇 개)

## 화면 주입
- **현역 player_detail_screen**: 수상경력 섹션(1671) 인근에 타이틀이력 칩 + 팀변천 타임라인 + 마일스톤 + (있으면)스플릿. lazy fetch.
- **은퇴 historical_player_detail_screen**: franchise caption+통산 인근에 타이틀이력+마일스톤(+스플릿). lazy.
- **team_detail_screen**: Overview 또는 신규 섹션에 구단약사 카드 + 역대레전드 + 시즌기록.
- ⚠️ 웹이미지 3규칙·netImage·토큰(Typo/Pal/Radii/Space) 준수. analyze lib=0.

## 검증
- API: 라이브 스팟체크(이승엽 타이틀·팀변천·마일스톤 / 두산 계보 OB→두산 / KIA 역대레전드).
- 헬퍼 순수테스트(타이틀 집계·타임라인 그룹핑·마일스톤 로직).

## 잔여/비목표
- 비율 타이틀 규정게이트 = v1 근사(완벽한 시즌별 규정타석 아님). 우승이력·연봉·부상=크롤 필요=비목표.
- PS 통산(2006~ 결손)·war 통산(시즌 일부만)=표시 제외 or 주의.
