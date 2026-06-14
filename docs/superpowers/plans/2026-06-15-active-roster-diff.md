# 1군 등록현황 diff Implementation Plan

> REQUIRED SUB-SKILL: superpowers:executing-plans. Steps `- [ ]`.

**Goal:** KBO 1군 등록현황 크롤 → DB diff → 1군 이탈자 '등록말소' 자동 표기(문동주류), 복귀 자동해제, 알림 스팸 없이.

**Architecture:** 순수 diff 판정 함수(테스트) + 셀레늄 크롤(10팀 등록명단) + sync(player_roster_changes insert) + notify '(자동)' 스킵 가드 + 스케줄러 일일.

**Tech Stack:** Python/selenium(ARM snap chromium)·psycopg2·pytest.

---

### Task 1: diff 순수 판정 함수 + 테스트

**Files:** Create `backend/crawler/roster_diff.py`, `backend/tests/test_roster_diff.py`

- [ ] **Step 1: test 작성** (DB/크롤 불요)

```python
from crawler.roster_diff import classify_roster_diff

def test_departed():
    # 1군 활동 있는데 등록명단 부재 + 최신상태!=말소 → 등록말소
    out = classify_roster_diff(
        registered={'김선수'}, db_players=[
            {'name': '문동주', 'had_1gun': True, 'latest': None},
            {'name': '김선수', 'had_1gun': True, 'latest': None},
        ])
    assert ('문동주', '등록말소') in out
    assert all(n != '김선수' for n, _ in out)  # 등록돼 있으면 변화 없음

def test_returned():
    out = classify_roster_diff(
        registered={'문동주'}, db_players=[
            {'name': '문동주', 'had_1gun': True, 'latest': '등록말소'}])
    assert ('문동주', '1군등록') in out

def test_no_1gun_skipped():
    # 2군/미debut(1군 활동 없음) → 등록 부재여도 말소 안 함
    out = classify_roster_diff(
        registered=set(), db_players=[
            {'name': '유망주', 'had_1gun': False, 'latest': None}])
    assert out == []

def test_already_marked_no_dup():
    out = classify_roster_diff(
        registered=set(), db_players=[
            {'name': '문동주', 'had_1gun': True, 'latest': '등록말소'}])
    assert out == []  # 이미 말소 → 재insert 안 함
```

- [ ] **Step 2: roster_diff.py 구현**

```python
"""1군 등록현황 ↔ DB diff 순수 판정 (DB/크롤 없음)."""

def classify_roster_diff(registered: set, db_players: list[dict]) -> list[tuple]:
    """registered: 현재 1군 등록 선수명 집합.
    db_players: [{'name', 'had_1gun': bool(2026 1군 출전), 'latest': 최신 change_type|None}]
    반환: [(name, '등록말소'|'1군등록'), ...] — 적용할 변경만."""
    out = []
    for p in db_players:
        name, had, latest = p['name'], p['had_1gun'], p['latest']
        in_reg = name in registered
        if not in_reg and had and latest != '등록말소':
            out.append((name, '등록말소'))
        elif in_reg and latest == '등록말소':
            out.append((name, '1군등록'))
    return out
```

- [ ] **Step 3: 로컬 검증** `cd backend && py -3 -c "import sys;sys.path.insert(0,'.');from crawler.roster_diff import classify_roster_diff; print('ok')"` (+ pytest는 서버 Task6)
- [ ] **Step 4: 커밋** `feat(roster): 등록현황 diff 순수 판정 + 테스트`

---

### Task 2: crawl_active_rosters (10팀 1군 등록명단)

**Files:** Modify `backend/crawler/kbo_roster_crawler.py`

- [ ] **Step 1: 서버 probe** — Register.aspx 구단별 등록현황의 **팀 선택 셀렉터** 확정
  (드롭다운/팀 탭). 각 팀 선택 후 투수/포수/내야수/외야수 테이블서 선수명 수집 가능한지 검증.
  (probe 스크립트 = 본 plan 외부, 서버서 1회)
- [ ] **Step 2: `_get_driver` driver_util 경유 확인** — 아니면 `driver_util.arm_or_wdm_chrome`로 교체
- [ ] **Step 3: crawl_active_rosters 구현** — 팀 순회, {team_id: set(names)} 반환, 팀 0명이면 제외
- [ ] **Step 4: py_compile + 커밋**

---

### Task 3: sync_active_roster (insert/dedup)

**Files:** Modify `backend/crawler/kbo_roster_crawler.py`

- [ ] **Step 1: 구현** — crawl 결과 + DB조회(team별 is_active+2026 1군출전+최신 roster_change) →
  classify_roster_diff → 각 (name,type) INSERT player_roster_changes(reason='1군 미등록(자동)' /
  '복귀(자동)', change_date=today, ON CONFLICT DO NOTHING). player_id=_find_player_id.
  성공 크롤 팀만 처리.
- [ ] **Step 2: py_compile + 커밋**

---

### Task 4: 알림 스팸 방지 가드

**Files:** Modify `backend/crawler/crawl_player_events.py` (또는 알림 발송 경로)

- [ ] **Step 1: 발송 경로 확인** — player_roster_changes → 알림 발송 지점 grep
- [ ] **Step 2: 가드** — reason LIKE '%(자동)%' 행은 알림 스킵 (인앱/푸시 모두)
- [ ] **Step 3: py_compile + 커밋**

---

### Task 5: 스케줄러 + 백필

- [ ] **Step 1: 스케줄러** — `_update_roster_changes` 뒤 또는 별도 일일 잡에 sync_active_roster 등록
- [ ] **Step 2: 커밋**

---

### Task 6: 배포 + 검증

- [ ] pull + py_compile + restart scheduler
- [ ] 서버 pytest(scratch DB) — test_roster_diff 포함 통과
- [ ] **1회 백필**: sync_active_roster 수동 실행
- [ ] 검증: 문동주 roster_status='등록말소' + 알림 로그 무발송 + smoke
- [ ] 오말소 sanity: 표기된 선수 수 합리적인지(스타 regulars만, 대량 아님) 확인

## Self-Review
- spec 매핑: 크롤(T2)·diff(T1)·sync(T3)·알림가드(T4)·스케줄러/백필(T5)·검증(T6). 전부.
- 안전: 2026 1군 출전 가드(2군 오말소 방지)·팀 0명 스킵·'(자동)' 알림 스킵·is_active 무변경.
- impl 미지: 팀셀렉터(T2 probe)·notify 경로(T4 grep)·_get_driver(T2).
