# 알림 지연 개선 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 한줄평(game_summary)·게임데이터 마일스톤을 종료 후 ~1-5분으로 단축(현 7-30분), 안전(오발송 없이) 유지.

**Architecture:** Part 1 = 종료경기 boxscore(result+game_batters) 크롤을 30s 루프서 즉시·반복 → result 채워지는 즉시 game_summary 발송. Part 2 = `_check_post_game_milestones`에서 게임데이터 감지블록을 신규 `_check_game_data_records`로 추출, game_batters 채워진 순간 조기 발송; 시즌/통산은 +27분 잔류. 순수판정 헬퍼 재사용. 앱/DB/fcm 무변경.

**Tech Stack:** Python, psycopg2. 기존 `get_game_record`/`save_game_record`(boxscore 크롤), `_check_team_records`, milestone_detect 헬퍼.

## Global Constraints
- 한글 파일 = Edit/Write 도구만. 커밋 메시지 `"` 금지.
- `py_compile` 통과 필수. 서버 기존 pytest 회귀 통과.
- 안전 불변: game_summary result-게이트 유지 · 데이터존재 게이트(PA/game_batters 없으면 스킵) · dedup(player_milestone_alerts·notification_log) · 블록별 예외격리 · 크롤 idempotent(save_game_record ON CONFLICT).
- 외부 하한(Naver boxscore·KBO 시즌스탯) 존중 — 그보다 빠르겐 불가.
- 신규 커넥션 try/finally.
- **Part 1(Task 1-2)은 독립 배포 가능**(Task 2 끝 배포·검증 후 Part 2 진행 권장).

---

### Task 1: `_crawl_game_boxscore(gid)` 단일경기 boxscore 크롤

**Files:** Modify `backend/crawler/scheduler.py`

**Interfaces:**
- Consumes: 기존 `get_game_record`, `save_game_record`, `_is_regular_game`, `get_connection`.
- Produces: `_crawl_game_boxscore(gid: int) -> bool` (result/게임기록 채우기 시도, 성공=True).

- [ ] **Step 1: 함수 추가**

`update_finished_game_records`(현 2907) 바로 위에 추가:
```python
def _crawl_game_boxscore(gid: int) -> bool:
    """단일 종료경기 boxscore(result+game_batters+innings) 즉시 크롤.
    update_finished_game_records의 per-game 파싱 추출 — 한줄평/게임데이터 마일스톤 조기화용.
    idempotent(save_game_record ON CONFLICT). 성공/시도=True, 스킵=False."""
    conn = get_connection()
    if not conn:
        return False
    try:
        cur = conn.cursor()
        cur.execute("SELECT naver_game_id FROM games WHERE id=%s AND status='종료'", (gid,))
        row = cur.fetchone()
        cur.close()
    except Exception:
        return False
    finally:
        conn.close()
    if not row or not row[0]:
        return False
    naver_game_id = row[0]
    if not _is_regular_game(naver_game_id):
        return False
    try:
        record = get_game_record(naver_game_id)
        if record:
            save_game_record(gid, record)
        return True
    except Exception as e:
        print(f"[boxscore] 크롤 오류 game={gid}: {e}")
        return False
```

- [ ] **Step 2: py_compile**

Run: `cd C:/Users/qq772/playball-fut/backend && python3 -m py_compile crawler/scheduler.py`
Expected: 성공(무출력).

- [ ] **Step 3: 커밋**

```bash
git -C C:/Users/qq772/playball-fut add backend/crawler/scheduler.py
git -C C:/Users/qq772/playball-fut commit -m "feat(latency): _crawl_game_boxscore per-game boxscore crawl"
```

---

### Task 2: 한줄평 result 대기 루프서 즉시 크롤

**Files:** Modify `backend/crawler/scheduler.py`

**Interfaces:** Consumes `_crawl_game_boxscore` (Task 1).

- [ ] **Step 1: game_summary 대기 루프서 result 미충원 시 즉시 크롤**

game_summary 발송 루프(현 1887~1918)의 result 확인 블록에서, **result 미충원(`result_count < 1 and not is_draw`)일 때 continue 하기 전에 boxscore 즉시 크롤**하도록 수정. 현재:
```python
                if result_count < 1 and not is_draw:
                    print(f"[FCM] game_summary 대기 game={gid} (result 미충원)")
                    continue
```
→
```python
                if result_count < 1 and not is_draw:
                    # result 채우는 boxscore를 즉시 재크롤(5분 예약 대기 대신) → 다음 사이클서 발송
                    _crawl_game_boxscore(gid)
                    print(f"[FCM] game_summary 대기 game={gid} (result 미충원, boxscore 재크롤)")
                    continue
```

- [ ] **Step 2: post_finished 종료 감지 시 즉시 1회 크롤**

post_finished 블록서 종료경기 처리 시작부에 boxscore 즉시 크롤 추가. `save_game_pitches(gid, ...)` 호출부(현 1657 인근) **앞**에 추가(record/result 먼저 채워 game_summary·마일스톤 조기화):
```python
                    try:
                        _crawl_game_boxscore(gid)
                    except Exception as _bx:
                        print(f"[boxscore] post_finished 크롤 오류 game={gid}: {_bx}")
```
(정확 위치 = post_finished_done 처리 블록 내 save_game_pitches 직전. 구현 시 해당 gid 루프 안.)

- [ ] **Step 3: "5분 후" 예약 강등(선택, 보수적으로 유지 가능)**

현 `schedule.every(5).minutes.do(_run_once, update_finished_game_records)`(1947)는 **백업으로 유지**(즉시 크롤이 주 경로, 이건 안전망). 변경 없음 — 즉시 크롤이 대부분 커버, 실패 시 5분 백업.

- [ ] **Step 4: py_compile + 커밋**

Run: `cd C:/Users/qq772/playball-fut/backend && python3 -m py_compile crawler/scheduler.py`
Expected: 성공.
```bash
git -C C:/Users/qq772/playball-fut add backend/crawler/scheduler.py
git -C C:/Users/qq772/playball-fut commit -m "feat(latency): eager boxscore crawl for game_summary (result gate) + post_finished"
```

> **⚠️ Part 1 배포 체크포인트**: Task 2 후 컨트롤러가 Part 1만 먼저 배포·검증(다음 종료경기서 한줄평 지연 로그 재측정) 가능. Part 2는 그 후.

---

### Task 3: 게임데이터 마일스톤 추출 → `_check_game_data_records`

**Files:** Modify `backend/crawler/scheduler.py`

**Interfaces:**
- Consumes: milestone_detect 헬퍼(is_cycle/walkoff_type/max_consecutive_hr 등), `notify_milestone`, `_check_team_records`(내부 호출), `_is_walkoff`/`_walkoff_batter`, `_already_notified`/`_mark_notified`.
- Produces: `_check_game_data_records(gid: int)`.

**추출 대상 블록** (현 `_check_post_game_milestones` 내부 → 신규 함수로 **이동**):
- 완봉/완봉승/노히터/QS (`starters_cg` 루프, `game_cg`/`game_shutout`/`game_no_hitter`/`game_qs`).
- 사이클(`game_cycle`) · 다홈런(`game_multi_hr`) · 끝내기(`walkoff_*`) — 단일경기 블록.
- 전구단홈런(`season_hr_vs_all`) 블록.

**⚠️ 독립 쿼리화**: 이 블록들은 현재 `batters`(game_batters JOIN batter_stats) / `today_batter`를 재사용. 신규 함수는 **batter_stats 조인 없이 game_batters/game_pitchers/PA 단독 쿼리**로 재작성(로직·순수헬퍼 동일).

- [ ] **Step 1: `_check_game_data_records` 신규 함수 작성**

`_check_post_game_milestones` 위에 추가. game_batters/game_pitchers/PA 단독 쿼리 사용:
```python
def _check_game_data_records(gid: int):
    """게임데이터 기반 기록(완봉/QS/노히터·사이클·다홈런·끝내기·전구단·팀기록) 조기 발송.
    KBO 시즌스탯 불요 — game_batters/game_pitchers/PA만 사용. dedup으로 재호출 안전."""
    from datetime import date as _dt
    season = _dt.today().year
    month = 0
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        # 팀명/투수(완봉·QS·노히터: 선발 = (game,side) MIN(pitching_order))
        cur.execute("""
            SELECT gp.player_id, p.name, t.name, gp.innings_pitched, gp.earned_runs,
                   gp.hits_allowed, gp.team_side
            FROM game_pitchers gp JOIN players p ON p.id=gp.player_id JOIN teams t ON t.id=p.team_id
            WHERE gp.game_id=%s AND gp.pitching_order=(
                SELECT MIN(g2.pitching_order) FROM game_pitchers g2
                WHERE g2.game_id=gp.game_id AND g2.team_side=gp.team_side)
        """, (gid,))
        starters_cg = cur.fetchall()
        # 타자(game_batters 단독): 오늘 HR/hits + 이름/팀
        cur.execute("""
            SELECT gb.player_id, p.name, t.name, COALESCE(gb.home_runs,0), COALESCE(gb.hits,0)
            FROM game_batters gb JOIN players p ON p.id=gb.player_id JOIN teams t ON t.id=p.team_id
            WHERE gb.game_id=%s
        """, (gid,))
        batters_gd = cur.fetchall()   # (pid, name, team, hr_today, hits_today)
        cur.close()
    except Exception as e:
        print(f"[게임기록] 쿼리 오류: {e}")
        return
    finally:
        conn.close()
    # game_batters 미적재면 boxscore 블록 스킵(완봉/다홈런/전구단), PA 블록은 별도 게이트
    try:
        from api.fcm_service import notify_milestone
        from api.milestone_detect import is_cycle, walkoff_type
        # ── 완봉/완봉승/노히터/QS ── (기존 로직 이동)
        for row in starters_cg:
            pid, pname, tname = row[0], row[1], row[2]
            ip_val = _parse_ip(row[3]); er = row[4] or 0; ha = row[5] or 0
            if ip_val >= 9.0:
                notify_milestone(pid, pname, tname, 'game_cg', 1, season, month, gid)
                if er == 0:
                    notify_milestone(pid, pname, tname, 'game_shutout', 1, season, month, gid)
                if ha == 0:
                    notify_milestone(pid, pname, tname, 'game_no_hitter', 1, season, month, gid)
            elif ip_val >= 6.0 and er <= 3:
                notify_milestone(pid, pname, tname, 'game_qs', 1, season, month, gid)
        # ── 다홈런 ──
        for r in batters_gd:
            if (r[3] or 0) >= 3:
                notify_milestone(r[0], r[1], r[2], 'game_multi_hr', r[3], season, gid, gid)
        # ── 사이클 (PA) ── (기존 로직 이동, name→pid via batters_gd)
        _bname_to_pid = {}
        for r in batters_gd:
            _bname_to_pid.setdefault(r[1], []).append((r[0], r[2]))
        try:
            c2 = get_connection()
            if c2:
                try:
                    cc = c2.cursor()
                    cc.execute("""SELECT batter_name, array_agg(DISTINCT result_class)
                                  FROM plate_appearances WHERE game_id=%s GROUP BY batter_name""", (gid,))
                    for bname, classes in cc.fetchall():
                        if is_cycle(set(classes or [])):
                            pids = _bname_to_pid.get(bname, [])
                            if len(pids) == 1:
                                notify_milestone(pids[0][0], bname, pids[0][1], 'game_cycle', 1, season, gid, gid)
                    cc.close()
                finally:
                    c2.close()
        except Exception as _e:
            print(f"[게임기록] 사이클 오류: {_e}")
        # ── 끝내기 (PA) ──
        try:
            if _is_walkoff(gid):
                wb = _walkoff_batter(gid)
                if wb:
                    wtype = walkoff_type(wb[1] or '', bool(wb[2]))
                    pids = _bname_to_pid.get(wb[0], [])
                    if wtype and len(pids) == 1:
                        notify_milestone(pids[0][0], wb[0], pids[0][1], wtype, 1, season, gid, gid)
        except Exception as _e:
            print(f"[게임기록] 끝내기 오류: {_e}")
        # ── 전구단 상대 홈런 ── (기존 블록 이동: 오늘 홈런친 pid = batters_gd hr>0)
        _check_vs_all_hr(gid, season, [(r[0], r[1], r[2]) for r in batters_gd if (r[3] or 0) > 0])
    except Exception as e:
        print(f"[게임기록] 발송 오류: {e}")
    # 팀기록 동반 (game_batters 기반)
    try:
        _check_team_records(gid)
    except Exception as e:
        print(f"[게임기록] 팀기록 오류: {e}")
```
> `_check_vs_all_hr(gid, season, hr_pids)` = 기존 전구단홈런 블록(현 `_check_post_game_milestones` 내)을 **헬퍼로 추출**해 재사용(오늘 홈런친 (pid,name,team) 리스트 받아 시즌 상대팀 셋 완성 감지 + `season_hr_vs_all` 발송). 구현 시 기존 SQL·게이트 그대로 이동.
> ⚠️ dedup: notify_milestone은 player_milestone_alerts 자동 dedup(month=gid인 per-game 타입/ season=season). 06-30 이후 per-game 타입은 month=gid 규약 유지(사이클/끝내기/다홈런).

- [ ] **Step 2: `_check_vs_all_hr` 헬퍼 추출**

기존 `_check_post_game_milestones`의 전구단홈런 블록을 `def _check_vs_all_hr(gid, season, hr_pid_rows):`로 추출(로직 동일, 입력 = 오늘 홈런친 (pid,name,team) 리스트). Step 1이 이걸 호출.

- [ ] **Step 3: py_compile**

Run: `cd C:/Users/qq772/playball-fut/backend && python3 -m py_compile crawler/scheduler.py`
Expected: 성공.

- [ ] **Step 4: 커밋**

```bash
git -C C:/Users/qq772/playball-fut add backend/crawler/scheduler.py
git -C C:/Users/qq772/playball-fut commit -m "feat(latency): extract _check_game_data_records (early game-data milestones)"
```

---

### Task 4: `_check_post_game_milestones`서 게임데이터 블록 제거 + 조기 배선

**Files:** Modify `backend/crawler/scheduler.py`

- [ ] **Step 1: 이동한 블록 제거**

`_check_post_game_milestones`에서 **Task 3으로 옮긴 블록 삭제**: 완봉/QS/노히터(`starters_cg` 루프) · 단일경기(사이클/다홈런/끝내기) 블록 · 전구단홈런 블록. (`starters_cg` fetch 쿼리도 이 함수서 불필요하면 제거.) **시즌/월간/통산/20-20/young/streak/personal은 그대로 유지.**

- [ ] **Step 2: 조기 호출 배선 (smart_update 루프, game_batters 채워진 순간 1회)**

game_summary 발송 루프(현 1887~) 인근/후에, 종료경기의 game_batters 존재 + 미처리 시 `_check_game_data_records` 1회 호출 + dedup:
```python
        # 게임데이터 마일스톤/팀기록 조기 발송 (game_batters 채워진 뒤 1회)
        for gid, curr in curr_details.items():
            if curr.get('status') != '종료':
                continue
            if _already_notified(gid, 'game_data_records'):
                continue
            try:
                _c = get_connection()
                has_gb = False
                if _c:
                    try:
                        _cc = _c.cursor()
                        _cc.execute("SELECT 1 FROM game_batters WHERE game_id=%s LIMIT 1", (gid,))
                        has_gb = _cc.fetchone() is not None
                        _cc.close()
                    finally:
                        _c.close()
                if has_gb:
                    _mark_notified(gid, 'game_data_records')
                    _check_game_data_records(gid)
            except Exception as _e:
                print(f"[게임기록] 조기배선 오류 game={gid}: {_e}")
```

- [ ] **Step 3: 기존 `_check_team_records` +27분 스케줄 제거**

`schedule.every(27).minutes.do(_run_once, _check_team_records, gid)`(07-02c 추가분) **삭제** — 이제 `_check_game_data_records`가 조기 호출. (`_check_post_game_milestones` +27분 스케줄은 시즌/통산용으로 유지.)

- [ ] **Step 4: py_compile + 커밋**

Run: `cd C:/Users/qq772/playball-fut/backend && python3 -m py_compile crawler/scheduler.py`
Expected: 성공.
```bash
git -C C:/Users/qq772/playball-fut add backend/crawler/scheduler.py
git -C C:/Users/qq772/playball-fut commit -m "feat(latency): strip game-data blocks from +27min milestone, wire early dispatch"
```

---

### Task 5: 검증 + 배포

- [ ] **Step 1: 전체 py_compile + 서버 회귀 pytest**

Run:
```bash
KEY="/c/Users/qq772/Downloads/ssh-key-2026-03-28 (2).key"
cd C:/Users/qq772/playball-fut/backend && python3 -m py_compile crawler/scheduler.py
scp -i "$KEY" crawler/scheduler.py ubuntu@168.107.36.158:~/playball/backend/crawler/scheduler.py
ssh -i "$KEY" ubuntu@168.107.36.158 "cd ~/playball/backend && python3 -m pytest tests/test_milestone_expansion.py tests/test_team_records.py -q && python3 -c 'import crawler.scheduler; print(\"import OK\")'"
```
Expected: pytest pass · import OK.

- [ ] **Step 2: 재시작 + smoke**

Run: `ssh -i "$KEY" ubuntu@168.107.36.158 "sudo systemctl restart playball playball-scheduler && sleep 3 && bash ~/playball/scripts/smoke.sh | tail -4"`
Expected: ALL PASS.

- [ ] **Step 3: 라이브 수동 검증(무크래시)**

최근 종료경기 gid로:
```bash
ssh -i "$KEY" ubuntu@168.107.36.158 "cd ~/playball/backend && python3 -c \"from crawler.scheduler import _crawl_game_boxscore, _check_game_data_records; print(_crawl_game_boxscore(<gid>)); _check_game_data_records(<gid>); print('ran OK')\" 2>&1 | tail -5"
```
Expected: 크래시 없이 완료(dedup으로 재발송 없음).
- ⚠️ **실 지연 효과 = 다음 라이브 종료경기 로그 재측정**(종료→한줄평/게임데이터 마일스톤 델타 <5분). 헤드리스 불가 → 관측 권장.

- [ ] **Step 4: 최종(문서/CLAUDE.md)** — 컨트롤러가 스펙/플랜/변경이력 커밋 + push + worktree 정리.

## Self-Review

**1. Spec coverage:**
- Part 1 한줄평 boxscore 가속(즉시+반복 크롤) → Task 1(`_crawl_game_boxscore`)+Task 2(대기루프·post_finished 배선). ✅
- Part 2 게임데이터 조기(사이클/끝내기/완봉·QS/다홈런/전구단/팀기록) → Task 3(`_check_game_data_records` 추출)+Task 4(원블록 제거·조기배선). ✅
- 시즌/통산/20-20/streak +27분 잔류 → Task 4 Step 1(제거 대상서 제외). ✅
- 안전(result게이트·데이터게이트·dedup·예외격리) → Task 2/3/4 각 게이트·try. ✅
- Part 1 독립 배포 → Task 2 체크포인트. ✅
- 검증/배포 → Task 5. ✅

**2. Placeholder scan:** Part 1 완전코드. Part 2는 **이동-리팩터**라 기존 블록 이동+독립쿼리 재작성(코드 제시)+`_check_vs_all_hr`/전구단 블록은 "기존 로직 이동" 명시(구현자가 실코드 이동). `<gid>`=검증용 사용자값. 순수 placeholder 없음(이동지침은 리팩터 특성).

**3. Type consistency:** `_crawl_game_boxscore(gid)->bool` Task1 정의=Task2 사용. `_check_game_data_records(gid)` Task3 정의=Task4 배선. `_check_vs_all_hr(gid,season,rows)` Task3 호출=Task3 Step2 정의. `notify_milestone(pid,name,team,type,value,season,month,gid)` per-game month=gid 규약(06-30). ✅

## 리스크 노트
- Task 3/4 = 최근 배포(07-02b/c) 코드 리팩터 → **리뷰 강화**(이동 로직 동일성·dedup·month=gid 규약·독립쿼리 정확성). 이동한 블록이 `_check_post_game_milestones`서 완전 제거됐는지(이중발송/누락) 최종리뷰 필수.
