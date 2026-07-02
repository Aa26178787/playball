# 팀 기록 알림 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 팀-경기 기록(선발 전원 안타/타점/득점·팀 다홈런·대량안타·연속타자 홈런) 6종을 종료 후처리서 감지해 팀팬에게 알림.

**Architecture:** 순수 판정(`max_consecutive_hr`/`all_meet`)은 기존 `api/milestone_detect.py`에 추가(TDD). 감지 = 신규 `scheduler._check_team_records(game_id)`(개인 마일스톤과 같은 +27분 배치, PA 적재 후). 발송 = 신규 `fcm_service.notify_team_record` → 팀팬(`notify_team_milestone` 토글). dedup = `notification_log`. 앱/DB 스키마 무변경.

**Tech Stack:** Python/FastAPI, psycopg2, pytest. 데이터 = game_rosters(is_starter)·game_batters(team_side,hits/rbis/runs/home_runs)·games·plate_appearances(inning_half,result_class)·teams.

## Global Constraints
- 한글 파일 = Edit/Write 도구만. 커밋 메시지 `"` 금지.
- `py_compile` 통과 필수. 순수 헬퍼 pytest 통과(로컬 pytest 없으면 python-assert fallback; 실 pytest = 서버, Task 4).
- team_side ∈ {'home','away'}. 'home'→games.home_team_id, 'away'→games.away_team_id. inning_half '말'=home 공격 / '초'=away 공격.
- dedup: `_already_notified(game_id, 'team_record', f"{team_id}:{record_type}")` / `_mark_notified(...)` (기존 헬퍼).
- collapse(06-30 트레이 교훈): notify_team_record는 `_send(..., game_id=None)` + `data['team_id']=f"{team_id}_{record_type}"`(record별 트레이 분리).
- 발송 = 다음 경기부터(소급 없음). 신규 커넥션 try/finally. 블록별 예외 격리.
- 선발 = 정확히 9명 매칭 시만(결손 스킵). 성립경기(status='종료')만 후처리 진입(기존 경로).

---

### Task 1: 순수 헬퍼 추가 + 테스트

**Files:**
- Modify: `backend/api/milestone_detect.py`
- Create: `backend/tests/test_team_records.py`

**Interfaces:**
- Produces: `max_consecutive_hr(seq: list) -> int`, `all_meet(vals: list, n: int = 9) -> bool`.

- [ ] **Step 1: 실패 테스트 작성**

`backend/tests/test_team_records.py`:
```python
from api.milestone_detect import max_consecutive_hr, all_meet


def test_max_consecutive_hr():
    assert max_consecutive_hr(['hr', 'hr', 'hr']) == 3
    assert max_consecutive_hr(['single', 'hr', 'hr', 'out', 'hr']) == 2
    assert max_consecutive_hr(['hr', 'so', 'hr', 'hr', 'hr', 'hr']) == 4
    assert max_consecutive_hr(['single', 'double']) == 0
    assert max_consecutive_hr([]) == 0


def test_all_meet():
    assert all_meet([1, 2, 1, 1, 3, 1, 2, 1, 1], 9)          # 9명 전원 >=1
    assert not all_meet([1, 2, 0, 1, 1, 1, 1, 1, 1], 9)      # 한 명 0
    assert not all_meet([1, 1, 1], 9)                        # 9명 미만
    assert not all_meet([], 9)
    assert all_meet([2, 3], 2)
```

- [ ] **Step 2: 실패 확인**

Run (pytest 없으면 fallback):
```
cd C:/Users/qq772/playball-fut/backend && python3 -c "import sys; sys.path.insert(0,'.'); import tests.test_team_records as t; [getattr(t,n)() for n in dir(t) if n.startswith('test_')]; print('OK')"
```
Expected: FAIL — `ImportError: cannot import name 'max_consecutive_hr'`.

- [ ] **Step 3: 헬퍼 구현**

`backend/api/milestone_detect.py` 파일 끝에 추가:
```python
def max_consecutive_hr(seq) -> int:
    """result_class 시퀀스에서 연속 'hr' 최대 런 길이."""
    best = run = 0
    for rc in seq:
        if rc == 'hr':
            run += 1
            if run > best:
                best = run
        else:
            run = 0
    return best


def all_meet(vals, n: int = 9) -> bool:
    """정확히 n개이고 전원 >= 1 (선발 전원 안타/타점/득점 판정)."""
    return len(vals) == n and all((v or 0) >= 1 for v in vals)
```

- [ ] **Step 4: 통과 확인**

Run:
```
cd C:/Users/qq772/playball-fut/backend && python3 -c "import sys; sys.path.insert(0,'.'); import tests.test_team_records as t; fns=[n for n in dir(t) if n.startswith('test_')]; [getattr(t,n)() for n in fns]; print('ALL', len(fns), 'PASS')"
```
Expected: `ALL 2 PASS`.

- [ ] **Step 5: 커밋**

```bash
git -C C:/Users/qq772/playball-fut add backend/api/milestone_detect.py backend/tests/test_team_records.py
git -C C:/Users/qq772/playball-fut commit -m "feat(team-record): pure helpers max_consecutive_hr + all_meet"
```

---

### Task 2: fcm_service `notify_team_record`

**Files:**
- Modify: `backend/api/fcm_service.py`

**Interfaces:**
- Consumes: `format_milestone_title` (milestone_detect), `_get_team_fan_targets`, `_send` (existing).
- Produces: `notify_team_record(team_id: int, record_type: str, team_name: str, value: int = 0)`.

- [ ] **Step 1: `notify_team_record` + 라벨맵 추가**

`backend/api/fcm_service.py`의 `notify_team_roster_change` 함수(현 ~538) 뒤에 추가:
```python
_TEAM_RECORD_LABELS: dict[str, tuple] = {
    'team_all_hit':  ('🔥', '선발 전원 안타', ''),
    'team_all_rbi':  ('🔥', '선발 전원 타점', ''),
    'team_all_run':  ('🏃', '선발 전원 득점', ''),
    'team_multi_hr': ('💣', '한 경기', '홈런'),
    'team_many_hits':('💥', '한 경기', '안타'),
    'team_consec_hr':('⚡', '', ''),
}


def notify_team_record(team_id: int, record_type: str, team_name: str, value: int = 0):
    """팀-경기 기록 알림 → 팀팬(notify_team_milestone 토글).
    06-30 트레이 collapse 회피: game_id=None + data.team_id=f"{tid}_{type}"(record별 분리)."""
    targets = _get_team_fan_targets(team_id, 'notify_team_milestone')
    if not targets:
        return
    emoji, cat, unit = _TEAM_RECORD_LABELS.get(record_type, ('⭐', record_type, ''))
    if record_type == 'team_consec_hr':
        title = f"{emoji} {team_name} {value}연속 타자 홈런!"
    else:
        from api.milestone_detect import format_milestone_title
        title = format_milestone_title(emoji, team_name, '', cat, value, unit, '')
    data = {"type": "team_record", "team_id": f"{team_id}_{record_type}", "tid": str(team_id)}
    _send(targets, title, title, data, "team_record", None)
```

- [ ] **Step 2: 채널 매핑 확인(team_record → 기본 채널)**

`_channel_for(ntype)` 함수를 열어(grep `def _channel_for`), 알 수 없는 ntype이 기본 채널로 폴백하는지 확인. 'team_record'가 명시 매핑 없으면 기본(myteam/default) 폴백이면 OK — 폴백이 없고 KeyError를 던지면 `_channel_for`에 `'team_record'`를 마이팀 채널로 추가. (대개 `.get(..., default)` 폴백이므로 무변경.)

- [ ] **Step 3: py_compile + 라벨 확인**

Run:
```bash
cd C:/Users/qq772/playball-fut/backend && python3 -m py_compile api/fcm_service.py && \
python3 -c "src=open('api/fcm_service.py').read(); assert 'def notify_team_record' in src and 'team_all_hit' in src and 'team_consec_hr' in src; print('OK')"
```
Expected: `OK`.

- [ ] **Step 4: 커밋**

```bash
git -C C:/Users/qq772/playball-fut add backend/api/fcm_service.py
git -C C:/Users/qq772/playball-fut commit -m "feat(team-record): notify_team_record + labels (team_record collapse per record)"
```

---

### Task 3: scheduler `_check_team_records` + 스케줄 배선

**Files:**
- Modify: `backend/crawler/scheduler.py`

**Interfaces:**
- Consumes: `max_consecutive_hr`, `all_meet` (Task 1), `notify_team_record` (Task 2), `_already_notified`/`_mark_notified`/`get_connection` (existing).

- [ ] **Step 1: `_check_team_records` 함수 추가**

`_check_post_game_milestones` 함수(현 730) 바로 위에 추가:
```python
def _check_team_records(game_id: int):
    """팀-경기 기록 감지 → 팀팬 알림. 종료 후처리(+27분, PA 적재 후)."""
    from api.milestone_detect import max_consecutive_hr, all_meet
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT g.home_team_id, g.away_team_id, ht.short_name, at.short_name
            FROM games g
            JOIN teams ht ON ht.id = g.home_team_id
            JOIN teams at ON at.id = g.away_team_id
            WHERE g.id = %s
        """, (game_id,))
        r = cur.fetchone()
        if not r:
            cur.close()
            return
        team_of = {'home': (r[0], r[2]), 'away': (r[1], r[3])}
        # 선발 전원 (팀별 정확히 9명)
        allrec = {}
        for side in ('home', 'away'):
            cur.execute("""
                SELECT COALESCE(gb.hits, 0), COALESCE(gb.rbis, 0), COALESCE(gb.runs, 0)
                FROM game_rosters gr
                LEFT JOIN game_batters gb
                  ON gb.game_id = gr.game_id AND gb.player_id = gr.player_id
                WHERE gr.game_id = %s AND gr.team_side = %s
                  AND gr.is_starter = TRUE AND gr.batting_order BETWEEN 1 AND 9
            """, (game_id, side))
            rows = cur.fetchall()
            hits = [x[0] for x in rows]; rbis = [x[1] for x in rows]; runs = [x[2] for x in rows]
            allrec[side] = {'hit': all_meet(hits, 9), 'rbi': all_meet(rbis, 9), 'run': all_meet(runs, 9)}
        # 팀 다홈런 / 대량안타
        cur.execute("""
            SELECT team_side, COALESCE(SUM(home_runs), 0), COALESCE(SUM(hits), 0)
            FROM game_batters WHERE game_id = %s GROUP BY team_side
        """, (game_id,))
        teamagg = {row[0]: (row[1], row[2]) for row in cur.fetchall()}
        # 연속타자 홈런 (이닝-하프 내 연속)
        cur.execute("""
            SELECT inning, inning_half, result_class
            FROM plate_appearances WHERE game_id = %s
            ORDER BY inning, pa_seq
        """, (game_id,))
        groups = {}
        for inn, half, rc in cur.fetchall():
            groups.setdefault((inn, half), []).append(rc)
        consec = {'home': 0, 'away': 0}
        for (inn, half), seq in groups.items():
            side = 'home' if half == '말' else 'away'
            m = max_consecutive_hr(seq)
            if m > consec[side]:
                consec[side] = m
        cur.close()
    except Exception as e:
        print(f"[팀기록] 쿼리 오류: {e}")
        return
    finally:
        conn.close()
    # 발송
    try:
        from api.fcm_service import notify_team_record
        for side in ('home', 'away'):
            tid, tname = team_of[side]

            def fire(rtype, value=0):
                sub = f"{tid}:{rtype}"
                if _already_notified(game_id, 'team_record', sub):
                    return
                notify_team_record(tid, rtype, tname, value)
                _mark_notified(game_id, 'team_record', sub)

            if allrec[side]['hit']:
                fire('team_all_hit')
            if allrec[side]['rbi']:
                fire('team_all_rbi')
            if allrec[side]['run']:
                fire('team_all_run')
            hr, hits = teamagg.get(side, (0, 0))
            if hr >= 5:
                fire('team_multi_hr', hr)
            if hits >= 20:
                fire('team_many_hits', hits)
            if consec[side] >= 3:
                fire('team_consec_hr', consec[side])
    except Exception as e:
        print(f"[팀기록] 발송 오류: {e}")
```
> ⚠️ `fire`가 루프 변수 `tid`/`tname`을 클로저로 캡처 — 각 `side` 반복서 즉시 호출하므로 late-binding 문제 없음(호출이 정의 직후, 다음 반복 전).

- [ ] **Step 2: 종료 후처리 +27분 배치에 배선**

`_check_post_game_milestones`를 스케줄하는 라인(현 1797 `schedule.every(27).minutes.do(_run_once, _check_post_game_milestones, gid)`) 바로 다음에 추가:
```python
                    schedule.every(27).minutes.do(_run_once, _check_team_records, gid)
```

- [ ] **Step 3: py_compile**

Run: `cd C:/Users/qq772/playball-fut/backend && python3 -m py_compile crawler/scheduler.py`
Expected: 성공(무출력).

- [ ] **Step 4: 커밋**

```bash
git -C C:/Users/qq772/playball-fut add backend/crawler/scheduler.py
git -C C:/Users/qq772/playball-fut commit -m "feat(team-record): _check_team_records detection + post-game schedule"
```

---

### Task 4: 검증 + 배포

**Files:** 없음.

- [ ] **Step 1: 전체 py_compile**

Run: `cd C:/Users/qq772/playball-fut/backend && python3 -m py_compile crawler/scheduler.py api/fcm_service.py api/milestone_detect.py`
Expected: 성공.

- [ ] **Step 2: 배포(scp) + 서버 pytest + 재시작**

```bash
KEY="/c/Users/qq772/Downloads/ssh-key-2026-03-28 (2).key"
W=C:/Users/qq772/playball-fut/backend
for f in api/milestone_detect.py api/fcm_service.py crawler/scheduler.py; do
  scp -i "$KEY" "$W/$f" "ubuntu@168.107.36.158:~/playball/backend/$f"; done
scp -i "$KEY" "$W/tests/test_team_records.py" ubuntu@168.107.36.158:~/playball/backend/tests/
ssh -i "$KEY" ubuntu@168.107.36.158 "cd ~/playball/backend && python3 -m pytest tests/test_team_records.py tests/test_milestone_expansion.py -q && python3 -c 'import crawler.scheduler' && sudo systemctl restart playball playball-scheduler && sleep 3 && bash ~/playball/scripts/smoke.sh | tail -4"
```
Expected: pytest passed · import OK · smoke ALL PASS.

- [ ] **Step 3: 라이브 스팟체크(수동 감지 재현)**

최근 대량득점 종료경기 gid로 수동 호출(dedup 1회):
```bash
ssh -i "$KEY" ubuntu@168.107.36.158 "cd ~/playball/backend && python3 -c \"from crawler.scheduler import _check_team_records; _check_team_records(<recent_gid>)\" 2>&1 | tail -5"
```
- gid 선택: `SELECT id FROM games WHERE status='종료' AND (home_score>=10 OR away_score>=10) AND game_date>=CURRENT_DATE-3 ORDER BY game_date DESC LIMIT 3;` 중 하나. 크래시 없이 완료(발송은 dedup/토큰 유저 有無에 따름, 로그로 감지 확인).
- ⚠️ 이미 알림 발송된 경기면 dedup으로 무발송(정상).

- [ ] **Step 4: 최종(문서/CLAUDE.md)** — subagent-driven 컨트롤러가 마무리 단계서 스펙/플랜/변경이력 커밋 + push + worktree 정리.

## Self-Review

**1. Spec coverage:**
- 선발 전원 안타/타점/득점(team_all_hit/rbi/run) → Task 3(game_rosters 선발 9명 × all_meet). ✅
- 팀 5홈런+(team_multi_hr) / 20안타+(team_many_hits) → Task 3(game_batters SUM per team_side). ✅
- 연속타자 홈런(team_consec_hr) → Task 3(PA inning-half max_consecutive_hr) + Task 1 헬퍼. ✅
- 팀팬 알림(notify_team_milestone 토글) + 라벨 + 문구 → Task 2. ✅
- collapse 분리(06-30) → Task 2(game_id=None + data.team_id 합성). ✅
- dedup notification_log(game,team,type) → Task 3(fire). ✅
- +27분 배치(PA 적재 후) → Task 3 Step 2. ✅
- 선발<9/PA미적재 스킵 → Task 3(all_meet len==9, PA 없으면 consec=0). ✅
- 순수 헬퍼 TDD → Task 1. ✅
- 배포/라이브 검증 → Task 4. ✅

**2. Placeholder scan:** 코드 스텝 전부 실제 코드. `<recent_gid>`는 검증용 사용자-선택 값(가짜 코드 아님, 쿼리로 선택 지시). placeholder 없음.

**3. Type consistency:** `max_consecutive_hr(list)->int`·`all_meet(list,int)->bool` Task1 정의=Task3 사용 일치. `notify_team_record(team_id,record_type,team_name,value)` Task2 정의=Task3 호출(`notify_team_record(tid, rtype, tname, value)`) 일치. `format_milestone_title` 기존 시그니처 재사용. `_already_notified/_mark_notified(game_id,type,sub_id)` 기존 시그니처 준수. ✅
