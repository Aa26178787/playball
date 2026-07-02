# 알림 지연 개선 (설계)

날짜: 2026-07-02
범위: 백엔드(scheduler) — 앱/DB/fcm 변경 없음(발송 타이밍만 개선)

## 목적
경기 종료 후 **한줄평(game_summary)·게임데이터 마일스톤(사이클·끝내기·다홈런·전구단홈런·완봉/QS·팀기록)** 이 7~30분 늦게 오던 것을, 안전(오발송 없이)을 유지하며 **~2~5분**으로 단축.

## 근본원인 (Phase 1 실측 확정)
- **한줄평**: `_send_game_summary`가 `game_pitchers.result`(승/패/세이브/홀드) 충원을 대기(30s 폴링). result는 `update_finished_game_records`(boxscore 크롤)가 채우는데 **"5분 후" 일회 예약** → 종료 후 ~5-10분. (game 542 로그: 7분 대기)
- **게임데이터 마일스톤**: 전부 `_check_post_game_milestones`의 **+27분 하드코딩 배치**에 묶임(원래는 KBO 시즌/통산 스탯 크롤 +25분 대기용). 하지만 사이클·끝내기는 **PA**(종료 직후 `save_plate_appearances_for_game`서 이미 저장), 다홈런·전구단·완봉/QS·팀기록은 **game_batters/game_pitchers**(boxscore 크롤로 채워짐) 의존 — **KBO 시즌스탯 불요** → 조기 발송 가능.
- 기각: 스케줄러 혼잡(사이클 ~33s, 미미) · rank_change/score_change/clutch(이미 즉시).
- 하한: Naver boxscore 게시시점 · KBO 시즌스탯 갱신(외부, 못 넘음).

## Part 1 — 한줄평 boxscore 크롤 가속
- **문제**: result(및 game_batters)를 채우는 boxscore 크롤이 "5분 후" 일회 예약 → 하한.
- **해결**: 종료경기 boxscore를 **더 빨리·자주** 크롤 → result 채워지는 즉시(≤30s) game_summary 발송.
  - 신규(or 추출) `_crawl_game_boxscore(gid)` = 단일경기 boxscore(result+game_batters) 크롤(경량 requests, `update_finished_game_records`의 per-game 파싱 재사용).
  - **트리거**: ⓐ post_finished서 종료 감지 즉시 1회 호출 ⓑ smart_update 30s 루프서 **result 미충원 종료경기마다 매 사이클 재크롤**(result 채워질 때까지, idempotent).
  - 기존 "5분 후" 일회 예약 → **제거 or 백업으로 강등**(즉시+30s 재시도가 대체).
- **안전**: game_summary는 여전히 result-게이트(빈 result 오발송 없음). 무승부는 기존 스킵 유지. 크롤 idempotent(ON CONFLICT). Naver 미게시면 다음 사이클 재시도(무해).

## Part 2 — 마일스톤 early/late 분리
`_check_post_game_milestones`에서 **게임데이터 감지 블록을 추출** → 조기 발송. 시즌/통산/월간/20-20/연속안타(streak)만 잔류(+27분).

### 이동(early) → 신규 `_check_game_data_records(gid)`
KBO 시즌스탯 불요, 우리 크롤 데이터만 사용:
- **PA 기반**(종료 즉시): 사이클(`game_cycle`) · 끝내기(`walkoff_hr`/`walkoff_hit`).
- **boxscore 기반**(game_batters/game_pitchers, 크롤 후): 완봉/완봉승/노히터/QS(`game_cg`/`game_shutout`/`game_no_hitter`/`game_qs`) · 다홈런(`game_multi_hr`) · 전구단홈런(`season_hr_vs_all`) · 팀기록(`_check_team_records` 호출).
- ⚠️ **재쿼리 독립화**: 현재 이 블록들은 `today_batter`/`batters`(game_batters JOIN batter_stats)를 재사용 → early 패스는 **game_batters/game_pitchers 단독 쿼리**(batter_stats 조인 제거)로 재작성(다홈런=gb.home_runs, 전구단=game_batters, 완봉/QS=game_pitchers, 사이클/끝내기=PA). 순수 판정 헬퍼(is_cycle·walkoff_type·max_consecutive_hr 등) 그대로 재사용 → 로직 동일, 소스 쿼리만 분리.

### 잔류(late +27분) → `_check_post_game_milestones`
`BATTER_SEASON`·`PITCHER_SEASON`·20-20(batter_stats hr/sb)·`CAREER_*`·young_*·hitting_streak·personal_monthly — batter_stats/pitcher_stats/daily 의존(KBO 스탯 +25분). 현 +27분 스케줄 유지.

### 트리거 배선 (단일 함수, 1회 호출)
- `_check_game_data_records(gid)` = **한 함수**(사이클·끝내기·완봉/QS·다홈런·전구단·팀기록 전부). 내부 각 블록은 데이터 존재 게이트(PA 없으면 사이클/끝내기 스킵, game_batters 없으면 boxscore 블록 스킵) + dedup.
- **호출 시점**: smart_update 30s 루프서 **종료경기의 game_batters가 채워진 순간 1회**(`notification_log`(gid,'game_data_records') dedup으로 1회 보장). game_batters는 Part 1의 boxscore 크롤이 채우므로 종료 후 **~1-2분**. PA는 이미 종료 직후 저장돼 있어 같은 시점에 사이클/끝내기도 발송. → 종료 후 ~1-2분에 게임데이터 마일스톤+팀기록 일괄 발송.
- **season/career**: `_check_post_game_milestones` +27분(불변). ⚠️ **이동한 게임데이터 타입은 여기서 제거**(이중발송 없음, dedup 백스톱도 有).
- 기존 `_check_team_records` +27분 스케줄(07-02c)도 **제거**(이제 `_check_game_data_records`가 조기 호출).

## 안전장치 (전부 유지)
- game_summary result-게이트 · 데이터존재 게이트(PA/game_batters 없으면 스킵) · dedup(player_milestone_alerts UNIQUE·notification_log UNIQUE) · 블록별 예외격리 · 크롤 idempotent.
- 외부(Naver/KBO) 하한 존중 — 그보다 빠르겐 못 감(정직).

## 순서/구조
- 감지 로직 = 기존 블록 **이동**(재작성 최소, 순수헬퍼 재사용). 신규 순수판정 없음(기존 milestone_detect 재사용).
- `_check_game_data_records`는 PA/boxscore 각 게이트 + 자체 dedup → 여러 번 호출돼도 안전(조기 1회 + 필요시 재시도).

## 테스트/검증
- py_compile scheduler. 서버 기존 pytest(회귀). smoke.
- 라이브: 최근 종료경기서 `_check_game_data_records(gid)`·`_crawl_game_boxscore(gid)` 수동 호출 무크래시. **다음 종료경기서 실제 지연 로그 재측정**(종료→한줄평/마일스톤 델타 <5분 확인).
- ⚠️ 실효과 = 다음 라이브 경기 관측(헤드리스 불가). 스팟체크 권장.

## 비목표
- 마일스톤 +27분自체 단축(KBO 스탯 하한, 오발송 리스크) · 스케줄러 멀티스레드화(혼잡 미미라 불요) · game_end 2단계 발송(스코어 즉시+한줄평 후속, 중복알림).

## 영향 파일
- `backend/crawler/scheduler.py` — `_crawl_game_boxscore`(Part1) + `_check_game_data_records`(Part2 추출) + post_finished/smart_update 배선 + `_check_post_game_milestones`서 게임데이터 블록 제거 + "5분 후" 예약 조정.
- 앱/DB/fcm_service = 변경 없음.

## 구현 순서 권장 (플랜 분리)
1. **Part 1 먼저**(독립 배포 가능, 저위험, 한줄평 주범) → 검증.
2. **Part 2**(마일스톤 추출, 고위험 — 최근 배포 코드 리팩터라 리뷰 강화).
