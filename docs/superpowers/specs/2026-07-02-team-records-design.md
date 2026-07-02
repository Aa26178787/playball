# 팀 기록 알림 (설계)

날짜: 2026-07-02
범위: 백엔드(scheduler/fcm_service) — 앱 변경 없음(알림함 type만 추가)

## 목적
개인 마일스톤에 이어 **팀-경기 기록**(선발 전원 안타/타점/득점·팀 다홈런·대량안타·연속타자 홈런)을 종료 후처리서 감지해 팀팬에게 알림.

## 결정 사항 (브레인스톰 확정)
- 대상 = **팀팬** (`notify_team_milestone` 토글 재사용, 신설 없음).
- 기록 6종(아래). 두 자릿수 득점·한이닝 기록·팀통산 = 비목표(빈도/후속).

## 데이터 (실측 확정)
- `game_batters`: game_id, player_id, **team_side('home'/'away')**, batting_order, runs, hits, rbis, home_runs. (선발 식별용 is_starter 없음 → game_rosters 사용)
- `game_rosters`: game_id, player_id, team_side, **is_starter**, batting_order.
- `games`: home_team_id, away_team_id (team_side→team_id 매핑).
- `plate_appearances`: inning, inning_half('초'=away공격/'말'=home공격), pa_seq, result_class('hr' 등). (연속타자 홈런용)
- `teams`: id, short_name (문구용 팀명).

## 감지 (신규 `_check_team_records(game_id)`, 팀별 home/away)
| 기록 | type | value | 판정 |
|---|---|---|---|
| 선발 전원 안타 | `team_all_hit` | 1 | game_rosters 선발(is_starter=true, batting_order 1-9, 팀별 정확히 9명) × game_batters(player_id) hits, **전원 hits≥1** |
| 선발 전원 타점 | `team_all_rbi` | 1 | 선발 9명 전원 rbis≥1 |
| 선발 전원 득점 | `team_all_run` | 1 | 선발 9명 전원 runs≥1 |
| 팀 한경기 다홈런 | `team_multi_hr` | HR수 | `SUM(home_runs)` per team_side ≥ 5 |
| 팀 대량 안타 | `team_many_hits` | 안타수 | `SUM(hits)` per team_side ≥ 20 |
| 연속타자 홈런 | `team_consec_hr` | 연속수 | plate_appearances (inning, inning_half)별 pa_seq 순 result_class 시퀀스의 **최대 연속 'hr' 런 ≥ 3**; inning_half→공격팀 매핑, 게임 내 팀별 최댓값 |

- 선발 판정: 팀별 선발이 **정확히 9명**이고 전원 game_batters 매칭될 때만(로스터 결손/미매칭 → 스킵, 안전 무발송).
- 연속타자: '초'=away 공격, '말'=home 공격. 이닝-하프 내 연속 타자만(이닝 넘어가면 상대팀 공격이라 끊김).

## 알림
신규 `fcm_service.notify_team_record(team_id: int, record_type: str, team_name: str, value: int = 0)`:
- targets = `_get_team_fan_targets(team_id, 'notify_team_milestone')`. 없으면 return.
- 라벨맵 `_TEAM_RECORD_LABELS`(emoji,cat,unit): `team_all_hit`('🔥','선발 전원 안타','')·`team_all_rbi`('🔥','선발 전원 타점','')·`team_all_run`('🏃','선발 전원 득점','')·`team_multi_hr`('💣','한 경기','홈런')·`team_many_hits`('💥','한 경기','안타')·`team_consec_hr`('⚡','','').
- **title 조립**:
  - `team_consec_hr` = 특례 직접 조립 → `f"⚡ {team_name} {value}연속 타자 홈런!"`.
  - 그 외 = `format_milestone_title(emoji, team_name, '', cat, value, unit, '')` 재사용 → 예 "🔥 {team} 선발 전원 안타!"(value=1,unit=''→숫자 생략) · "💣 {team} 한 경기 5홈런!"(value=5,unit='홈런') · "💥 {team} 한 경기 20안타!".
- body = title과 동일(팀 기록은 본문 부가정보 없음).
- **collapse(06-30 트레이 교훈)**: `_send(targets, title, body, data, "team_record", game_id=None)`. game_id=None이라 `_collapse_key`가 `data['team_id']`로 트레이 분리 → **같은 경기 다수 팀기록이 합쳐지지 않도록 `data['team_id'] = f"{team_id}_{record_type}"`**(record별 분리). 실제 수치 team_id는 `data['tid']=str(team_id)` 별도. quiet hours·인앱저장·채널 = `_send` 자동.

## 순수 헬퍼 (milestone_detect.py 추가, TDD)
- `max_consecutive_hr(seq: list[str]) -> int` — 시퀀스 최대 연속 'hr' 런.
- (선발 전원 판정은 DB 결과 리스트 받아 `all(x>=1 for x in vals) and len==9` 인라인 — 별도 헬퍼 불요, but `all_meet(vals: list[int], n: int=9) -> bool` = `len(vals)==n and all(v>=1 for v in vals)` 추가해 테스트).

## dedup
- `notification_log` UNIQUE(game_id, type='team_record', sub_id=`f"{team_id}:{record_type}"`) — 기존 `_already_notified`/`_mark_notified` 재사용. 경기·팀·기록당 1회.

## 순서/배치
- `_check_post_game_milestones` 직후(같은 post_finished 경로, PA 적재 후) 또는 27분 배치에 `_check_team_records(gid)` 동반 스케줄. 선발 전원/다홈런=game_batters(종료 시 확정), 연속홈런=PA(적재 후). → **개인 마일스톤과 동일 +27분 배치**(schedule.every(27) 블록에 추가) 권장.

## 에러/엣지
- 선발 <9 or game_batters 미매칭 → 스킵. PA 미적재 → 연속홈런만 스킵. 취소/무승부 무관(기록은 성립경기 기준, status='종료'만 후처리 진입). 신규 커넥션 try/finally. 블록별 예외 격리.

## 테스트/검증
- pytest: `max_consecutive_hr`·`all_meet` (순수) — `tests/test_team_records.py`.
- py_compile scheduler/fcm_service. 서버 pytest. smoke.
- 라이브 스팟체크: 최근 종료경기서 `_check_team_records(gid)` 수동 호출(대량득점 경기 택해 감지 확인, dedup 1회).
- ⚠️ 실발송 = 다음 경기부터.

## 비목표
- 두 자릿수 득점(빈도)·한 이닝 기록·팀 연속경기·팀 통산·투수진 노히트노런(팀) = 후속.
- 앱 UI 신규(알림함 기존 표시)·APK.

## 영향 파일
- `backend/crawler/scheduler.py` — `_check_team_records` 신규 + post-game 스케줄.
- `backend/api/fcm_service.py` — `notify_team_record` + `_TEAM_RECORD_LABELS`.
- `backend/api/milestone_detect.py` — `max_consecutive_hr`·`all_meet` 추가.
- `backend/tests/test_team_records.py` — 신규.
