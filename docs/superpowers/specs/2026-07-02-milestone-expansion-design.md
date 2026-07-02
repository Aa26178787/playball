# 마일스톤 알림 확장 (설계)

날짜: 2026-07-02
범위: 백엔드(FastAPI/scheduler) — 앱 변경 없음(알림함 type만 추가 표시)

## 목적
KBO 미디어/팬이 기념하는 대기록 중 현 시스템이 놓치는 4종 묶음을 알림으로 추가한다:
① 끝내기(walk-off) 개인 · ② 사이클링 히트 + 한 경기 다홈런 · ③ 전 구단 상대 홈런 + 20-20/30-30/40-40 · ④ 통산 100단위 확장 + 역대순위 캡션.

## 결정 사항 (브레인스톰 확정)
1. 통산 = **핵심임계 100단위 확장(1000 초과분)** + 전 통산 마일스톤에 **"역대 N번째" 캡션**.
2. 끝내기 = **끝내기 친 선수 식별 → 개인 마일스톤**(기존 팀 `notify_walkoff`와 별개, 중복 아님).
3. 대상 라우팅·토글 = 기존 `notify_milestone`(is_career 분기) + 기존 마일스톤 토글 재사용. 신설 토글 없음.

## 아키텍처 (기존 시스템 확장)
- 감지 = 종료 후처리 `crawler/scheduler.py::_check_post_game_milestones(game_id)` 확장(경기 종료 +27분 배치, `post_finished_done`에서 `save_plate_appearances_for_game` 실행 **후** 스케줄 → PA 적재 보장).
- 발송 = `api/fcm_service.py::notify_milestone(...)` 재사용(신규 type만 추가). dedup = `player_milestone_alerts` UNIQUE(player_id,milestone_type,milestone_value,season,month).
- 순수 감지 로직 = 테스트 가능한 헬퍼로 분리(사이클 판정·전구단 셋·순위 계산은 DB 결과를 받아 판정).
- 라벨 = `_MILESTONE_LABELS`에 신규 type 추가.

## 데이터 소스 (실측 확정)
- `plate_appearances`: game_id, inning, inning_half, pa_seq, **batter_name**(⚠️player_id 없음), result_class∈{single,double,triple,hr,bb,hbp,so,out,sac_fly,sac_bunt,fc,error,reach_other,ibb,…}, is_hit, home_score, away_score, win_rate_after.
- `game_batters`: **player_id** + home_runs/hits/… (per game). 시즌 누적·동명이인 회피는 이걸로.
- `batter_stats`: home_runs, stolen_bases, hits, doubles, triples, **tb**(루타), season.
- `games`: home_team_id/away_team_id (상대팀 도출).
- `historical_season_stats`: kbo_player_id별 통산 누계(역대순위용, 기존 `historical._leader_query` 패턴).

## 신규 마일스톤 상세

### ① 끝내기 개인 — `walkoff_hit` / `walkoff_hr`
- 트리거: `_is_walkoff(game_id)` true → `_walkoff_batter(game_id)` 헬퍼.
- `_walkoff_batter`: `plate_appearances`에서 **마지막 이닝 말(inning_half='말') 중 게임을 끝낸 결승 PA** = 그 이닝 말의 is_hit=true PA 중 `win_rate_after`가 100(홈 승 확정) 또는 home_score>away_score로 전환된 마지막 PA. batter_name 반환 + result_class(hr→walkoff_hr, 그 외 안타→walkoff_hit).
- batter_name → player_id: `game_batters` (해당 game_id) 조인으로 매핑(동명이인=같은 경기 내 거의 없음, 다중매칭 시 스킵).
- 대상 = **선수팬 + 팀팬**(career-like 취급 or 명시 targets). 문구 "🎉 {name} 끝내기 홈런!" / "🎉 {name} 끝내기 안타!".
- dedup: player_milestone_alerts(type, value=1, season, month=0) + game_id 동반(notify_milestone game_id 인자).

### ② 사이클링 + 다홈런 — `game_cycle` / `game_multi_hr`
- 사이클: 해당 game_id의 `plate_appearances` batter_name별 result_class 집합에 {single,double,triple,hr} **4종 모두** 포함 → 사이클. batter_name→player_id는 game_batters 매핑.
- 다홈런: `game_batters.home_runs >= 3` (player_id 직접). value=home_runs.
- 대상 = 팀팬(기본 마일스톤). 문구 "🌈 {name} 사이클링 히트!" / "💣 {name} 한 경기 {N}홈런!".

### ③ 전구단홈런 + 20-20 — `season_hr_vs_all` / `season_20_20`·`season_30_30`·`season_40_40`
- 전구단홈런: 오늘 홈런 친 타자(game_batters home_runs>0, player_id)별, 시즌 홈런 상대팀 distinct 계산 = `game_batters gb JOIN games g` 시즌 내 gb.home_runs>0인 경기의 상대팀 집합. **오늘 경기로 상대팀 셋이 처음 9팀 완성**(전날까지 <9, 오늘 포함 =9)일 때만 발송. + `_league_rank_vs_all(season)`(올 시즌 완성 선수수) 캡션 "리그 N번째". value=1.
- 20-20류: `batter_stats` hr≥K AND sb≥K (K∈20,30,40). **오늘 기여로 통과**(오늘 game_batters hr/sb 빼면 미달) 판정. 각 K 별 type. 문구 "⚡ {name} 20-20 클럽!".
- 대상 = 팀팬.

### ④ 통산 확장 + 역대순위 캡션
- 임계 확장: `career_hits`·`career_so` = 기존 라운드 + **1000 초과분 100단위**(1100,1200,…,2900). `career_tb`(루타) **신규**(라운드 2000,2500,3000,3500,4000,4500,5000). (홈런은 기존 100단위 유지)
- **역대순위 캡션**: 전 통산 마일스톤 발송 시 `_career_rank(stat_key, value)` = (historical 통산 + 현역 batter/pitcher_stats 통산) ≥ value 선수수 → `extra_label="역대 N번째"`로 notify_milestone에 전달. 캐시(값별) 권장.
- 문구 예 "✨ {name} 통산 1100안타! (역대 N번째)".

## 라벨/문구 처리
- `_MILESTONE_LABELS` 추가: `walkoff_hr`('🎉','끝내기 홈런','')·`walkoff_hit`('🎉','끝내기 안타','')·`game_cycle`('🌈','사이클링 히트','')·`game_multi_hr`('💣','한 경기','홈런')·`season_hr_vs_all`('🎯','전 구단 상대 홈런','')·`season_20_20`('⚡','20-20 클럽','')·`season_30_30`('⚡','30-30 클럽','')·`season_40_40`('🔥','40-40 클럽','')·`career_tb`('✨','통산','루타').
- ⚠️ **바이너리 마일스톤 문구 개선**: 현 title = `f"{emoji} {name} {month}{cat} {value}{unit}!"` → value=1·unit='' 이면 "끝내기 홈런 **1**!"처럼 어색. `notify_milestone` title 조립에서 **`unit==''` 이고 `value<=1`이면 value 생략** → "🎉 {name} 끝내기 홈런!". (기존 game_cg/완봉 등도 함께 개선됨)

## 순수 헬퍼 (테스트 대상)
- `is_cycle(result_classes: set) -> bool` — {single,double,triple,hr} ⊆ set.
- `walkoff_type(result_class: str) -> str|None` — 'hr'→'walkoff_hr' / is_hit인 안타류→'walkoff_hit' / else None.
- `crossed(prev: int, curr: int, thresholds: list[int]) -> list[int]` — prev<t≤curr 통과 임계(기존 패턴 함수화, 100단위 확장에 재사용).
- `dual_crossed(prev_hr, curr_hr, prev_sb, curr_sb, k) -> bool` — 20-20류 오늘 완성: `(prev_hr<k OR prev_sb<k) AND curr_hr>=k AND curr_sb>=k` (오늘 이전엔 미완성, 오늘 포함 시 둘 다 달성).
※ DB 쿼리는 헬퍼 밖(scheduler), 판정만 순수 함수.

## 에러/엣지
- PA 미적재(구경기/파싱실패) → 끝내기/사이클 감지 스킵(안전 무발송), 예외 격리(기존 try/except 패턴).
- batter_name→player_id 다중매칭(동명이인) → 스킵(오발송 방지).
- 전구단홈런 = 오늘 완성만(전날까지 상태 재계산) → dedup으로 시즌 1회.
- 무승부/취소 = 끝내기 아님(_is_walkoff false).
- 커넥션 = try/finally(신규 헬퍼 get_connection).

## 대상/토글
- career-like(선수 개인기록성) = 선수팬+팀팬, 나머지 = 팀팬. **`notify_milestone`의 `is_career` 판정 확장**: 현재 `startswith('career_'/'young_career_')` → **명시 세트 추가** `{'walkoff_hr','walkoff_hit','season_hr_vs_all'}`도 career-like로 취급(선수팬+팀팬). `game_cycle`/`game_multi_hr`/`season_20_20`·`30_30`·`40_40` = 팀팬만(is_career=False 유지).
- 신규 토글 없음. 기존 notify_milestone/notify_team_milestone 토글 준용. quiet hours·푸시GW·notification 저장 = 기존 `_send` 경유(자동).

## 테스트/검증
- pytest(순수): `is_cycle`·`walkoff_type`·`crossed`·`dual_crossed` — `backend/tests/test_milestone_expansion.py`.
- 라이브 스팟체크(scratch DB 또는 실경기): 오늘 노시환 전구단홈런·강백호 통산안타 케이스 재현(수동 트리거 `_check_post_game_milestones(gid)`).
- `py_compile` scheduler/fcm_service. smoke ALL PASS.
- ⚠️ **실발송은 다음 해당 경기부터**(소급 없음, 기존 마일스톤 관행).

## 비목표 (YAGNI / 후속)
- 트리플크라운·시즌 타이틀(시즌말 확정 필요) · 연속경기 홈런/출루 · 데뷔전 첫기록 · 퍼펙트게임(노히터로 부분 커버) — 별도 후속.
- 앱 UI 신규 화면(알림함은 기존 milestone 아이콘 재사용) · APK(웹+서버 라인).
- 역대순위 정확한 "달성일 순" (count 근사 = 통산≥value 선수수, 실무상 동일).

## 영향 파일
- `backend/crawler/scheduler.py` — `_check_post_game_milestones` 확장 + 헬퍼(`_walkoff_batter`, 전구단 셋 쿼리, 역대순위 쿼리).
- `backend/api/fcm_service.py` — `_MILESTONE_LABELS` 신규 + title 조립 개선 + is_career 세트 확장.
- `backend/api/milestone_detect.py` (신규, 선택) — 순수 판정 헬퍼(`is_cycle`/`walkoff_type`/`crossed`/`dual_crossed`).
- `backend/tests/test_milestone_expansion.py` — 신규.
- 앱/DB 스키마 = 변경 없음(player_milestone_alerts 재사용).
