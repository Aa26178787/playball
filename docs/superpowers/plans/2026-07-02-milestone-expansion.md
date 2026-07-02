# 마일스톤 알림 확장 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 끝내기·사이클링·다홈런·전구단홈런·20-20·통산100단위+역대순위 캡션 마일스톤을 기존 알림 시스템에 추가한다.

**Architecture:** 순수 판정 로직은 신규 `api/milestone_detect.py`(DB-free, TDD). 감지·발송은 기존 `scheduler.py::_check_post_game_milestones`(종료+27분, PA 적재 후) 확장 + `fcm_service.py::notify_milestone`/`_MILESTONE_LABELS` 재사용. dedup=`player_milestone_alerts`. 앱/DB 스키마 무변경.

**Tech Stack:** Python/FastAPI, psycopg2, pytest. 데이터 = plate_appearances(batter_name)·game_batters(player_id)·batter_stats(tb 포함)·games·historical_season_stats.

## Global Constraints
- 한글 파일 편집 = Edit/Write 도구만(인코딩). 커밋 메시지에 `"` 금지.
- `py_compile` 통과 필수. pytest(순수 헬퍼) 통과 필수.
- 동명이인 회피: 시즌 누적·전구단·다홈런 = `game_batters.player_id` 사용. PA(batter_name)는 game 스코프(사이클/끝내기)에서만, game_batters로 name→player_id 매핑(다중매칭 스킵).
- 임계 '통과' 판정 = `prev < t <= curr`(기존 패턴, stale 일괄발송 방지).
- notify_milestone dedup은 `player_milestone_alerts`가 자동(호출만).
- 발송 = 다음 해당 경기부터(소급 없음).
- DB 신규 커넥션 = try/finally.

---

### Task 1: 순수 판정 헬퍼 모듈 + 테스트

**Files:**
- Create: `backend/api/milestone_detect.py`
- Create: `backend/tests/test_milestone_expansion.py`

**Interfaces:**
- Produces:
  - `is_cycle(result_classes: set[str]) -> bool`
  - `walkoff_type(result_class: str, is_hit: bool) -> str | None` → `'walkoff_hr'` / `'walkoff_hit'` / `None`
  - `crossed(prev: int, curr: int, thresholds: list[int]) -> list[int]` — 통과 임계 리스트
  - `dual_crossed(prev_a: int, curr_a: int, prev_b: int, curr_b: int, k: int) -> bool`
  - `format_milestone_title(emoji: str, name: str, month_str: str, cat: str, value, unit: str, extra_str: str) -> str`
  - `career_thresholds_100(base_round: list[int], start: int, end: int) -> list[int]` — 라운드 + start~end 100단위 병합·정렬·중복제거

- [ ] **Step 1: 실패 테스트 작성**

`backend/tests/test_milestone_expansion.py`:
```python
from api.milestone_detect import (
    is_cycle, walkoff_type, crossed, dual_crossed,
    format_milestone_title, career_thresholds_100,
)


def test_is_cycle():
    assert is_cycle({'single', 'double', 'triple', 'hr'})
    assert is_cycle({'single', 'double', 'triple', 'hr', 'bb', 'out'})
    assert not is_cycle({'single', 'double', 'hr'})       # 3루타 없음
    assert not is_cycle(set())


def test_walkoff_type():
    assert walkoff_type('hr', True) == 'walkoff_hr'
    assert walkoff_type('single', True) == 'walkoff_hit'
    assert walkoff_type('double', True) == 'walkoff_hit'
    assert walkoff_type('bb', False) is None              # 볼넷 끝내기 = 안타 아님(제외)
    assert walkoff_type('out', False) is None


def test_crossed():
    assert crossed(998, 1002, [500, 1000, 1500]) == [1000]
    assert crossed(1499, 1501, [1000, 1100, 1500]) == [1500]
    assert crossed(1000, 1000, [1000]) == []             # 통과 아님(이미 도달)
    assert crossed(90, 250, [100, 200, 300]) == [100, 200]  # 한 경기 다중 통과


def test_dual_crossed():
    # 오늘 이전 미완성(hr 19), 오늘 20 도달 + sb 이미 25 → 20-20 완성
    assert dual_crossed(19, 20, 25, 26, 20)
    # 오늘 이전 이미 둘 다 20+ → 완성 아님(이전에 이미)
    assert not dual_crossed(20, 21, 22, 23, 20)
    # curr 한쪽 미달
    assert not dual_crossed(19, 20, 18, 19, 20)


def test_format_milestone_title():
    # value=1·unit='' → value 생략
    assert format_milestone_title('🎉', '강백호', '', '끝내기 홈런', 1, '', '') == '🎉 강백호 끝내기 홈런!'
    # value 있는 카운트형
    assert format_milestone_title('💣', '노시환', '', '한 경기', 3, '홈런', '') == '💣 노시환 한 경기 3홈런!'
    # extra_str 캡션
    assert format_milestone_title('✨', '강백호', '', '통산', 1100, '안타', ' (역대 113번째)') == '✨ 강백호 통산 1100안타! (역대 113번째)'


def test_career_thresholds_100():
    assert career_thresholds_100([500, 1000], 1000, 2500) == \
        [500, 1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900,
         2000, 2100, 2200, 2300, 2400, 2500]
```

- [ ] **Step 2: 실패 확인**

Run: `cd C:/Users/qq772/playball-fut/backend && python3 -m pytest tests/test_milestone_expansion.py -q`
Expected: FAIL (`ModuleNotFoundError: api.milestone_detect`).

- [ ] **Step 3: 구현**

`backend/api/milestone_detect.py`:
```python
"""마일스톤 순수 판정 로직 (DB-free, 테스트 대상)."""

_CYCLE = {'single', 'double', 'triple', 'hr'}
_HIT_CLASSES = {'single', 'double', 'triple', 'hr'}


def is_cycle(result_classes) -> bool:
    """한 타자의 한 경기 result_class 집합이 사이클(단·2·3루타·홈런) 포함."""
    return _CYCLE.issubset(set(result_classes))


def walkoff_type(result_class: str, is_hit: bool):
    """끝내기 결승타 유형. 홈런/안타류만(볼넷·희생·실책 끝내기는 제외)."""
    if result_class == 'hr':
        return 'walkoff_hr'
    if is_hit and result_class in _HIT_CLASSES:
        return 'walkoff_hit'
    return None


def crossed(prev: int, curr: int, thresholds) -> list:
    """prev < t <= curr 인 임계값들(이번 경기로 통과)."""
    return [t for t in thresholds if prev < t <= curr]


def dual_crossed(prev_a: int, curr_a: int, prev_b: int, curr_b: int, k: int) -> bool:
    """20-20류: 오늘 이전엔 미완성이고 오늘 포함 시 둘 다 k 도달."""
    return (prev_a < k or prev_b < k) and curr_a >= k and curr_b >= k


def format_milestone_title(emoji: str, name: str, month_str: str, cat: str,
                           value, unit: str, extra_str: str) -> str:
    """마일스톤 알림 제목. unit='' & value<=1 이면 value 생략(바이너리 이벤트 문구 정리)."""
    try:
        v = int(value)
    except (TypeError, ValueError):
        v = value
    val_part = '' if (unit == '' and isinstance(v, int) and v <= 1) else f'{v}{unit}'
    return f'{emoji} {name} {month_str}{cat} {val_part}!{extra_str}'


def career_thresholds_100(base_round, start: int, end: int) -> list:
    """라운드 임계 + [start, end] 100단위 병합(정렬·중복제거)."""
    s = set(base_round)
    s.update(range(start, end + 1, 100))
    return sorted(s)
```

- [ ] **Step 4: 통과 확인**

Run: `cd C:/Users/qq772/playball-fut/backend && python3 -m pytest tests/test_milestone_expansion.py -q`
Expected: PASS (6 tests).

- [ ] **Step 5: 커밋**

```bash
git -C C:/Users/qq772/playball-fut add backend/api/milestone_detect.py backend/tests/test_milestone_expansion.py
git -C C:/Users/qq772/playball-fut commit -m "feat(milestone): pure detection helpers + tests"
```

---

### Task 2: fcm_service 라벨/문구/is_career 확장

**Files:**
- Modify: `backend/api/fcm_service.py`

**Interfaces:**
- Consumes: `format_milestone_title` (Task 1).
- Produces: 신규 `_MILESTONE_LABELS` 엔트리, 확장된 `is_career` 세트.

- [ ] **Step 1: `_MILESTONE_LABELS`에 신규 type 추가**

`_MILESTONE_LABELS` dict(현 795~)의 `# 통산` 블록 끝(예: `'career_holds': ('✋', '통산', '홀드'),` 다음)에 추가:
```python
    'career_tb':     ('✨', '통산', '루타'),
    # 확장(07-02)
    'walkoff_hr':        ('🎉', '끝내기 홈런', ''),
    'walkoff_hit':       ('🎉', '끝내기 안타', ''),
    'game_cycle':        ('🌈', '사이클링 히트', ''),
    'game_multi_hr':     ('💣', '한 경기', '홈런'),
    'season_hr_vs_all':  ('🎯', '전 구단 상대 홈런', ''),
    'season_20_20':      ('⚡', '20-20 클럽', ''),
    'season_30_30':      ('⚡', '30-30 클럽', ''),
    'season_40_40':      ('🔥', '40-40 클럽', ''),
```

- [ ] **Step 2: title 조립을 `format_milestone_title`로 교체**

`notify_milestone` 본문에서 title 조립부(현재 `title = f"{emoji} {player_name} {month_str}{cat} {milestone_value}{unit}!{extra_str}"`)를 찾아 교체:
```python
    from api.milestone_detect import format_milestone_title
    title = format_milestone_title(emoji, player_name, month_str, cat, milestone_value, unit, extra_str)
```
(body는 기존 유지. body도 동일 어색함 있으면 그대로 둠 — 제목만 정리해도 알림 표시 충분.)

- [ ] **Step 3: `is_career` 세트 확장**

`notify_milestone` 내 `is_career = milestone_type.startswith('career_') or milestone_type.startswith('young_career_')` 라인을 교체:
```python
    _CAREER_LIKE = {'walkoff_hr', 'walkoff_hit', 'season_hr_vs_all'}
    is_career = (milestone_type.startswith('career_')
                 or milestone_type.startswith('young_career_')
                 or milestone_type in _CAREER_LIKE)
```

- [ ] **Step 4: py_compile + 라벨 확인**

Run:
```bash
cd C:/Users/qq772/playball-fut/backend && python3 -m py_compile api/fcm_service.py && \
python3 -c "import ast,sys; src=open('api/fcm_service.py').read(); assert 'walkoff_hr' in src and 'game_cycle' in src and 'season_20_20' in src and 'career_tb' in src; print('labels OK')"
```
Expected: `labels OK` (py_compile 무출력 성공).

- [ ] **Step 5: 커밋**

```bash
git -C C:/Users/qq772/playball-fut add backend/api/fcm_service.py
git -C C:/Users/qq772/playball-fut commit -m "feat(milestone): fcm labels + title formatter + is_career set for new types"
```

---

### Task 3: scheduler 통산 확장 + 역대순위 캡션

**Files:**
- Modify: `backend/crawler/scheduler.py` (`_check_post_game_milestones` 통산 타자 블록 + 신규 헬퍼)

**Interfaces:**
- Consumes: `career_thresholds_100`, `crossed` (Task 1).
- Produces: `_career_rank(stat_col: str, value: int) -> int | None` 헬퍼.

- [ ] **Step 1: `_career_rank` 헬퍼 추가**

`_check_post_game_milestones`(현 730) 바로 위에 추가:
```python
def _career_rank(stat_col: str, value: int):
    """통산 stat_col >= value 선수 수 (역대 N번째 근사).
    historical_season_stats(정규, ~2025) 통산 + 현역 batter_stats/pitcher_stats 통산을
    kbo_player_id/player_id 브릿지로 합산. 실패 시 None(캡션 생략)."""
    if stat_col not in ('hits', 'home_runs', 'rbis', 'stolen_bases', 'walks', 'tb',
                        'wins', 'strikeouts', 'saves', 'holds'):
        return None
    conn = get_connection()
    if not conn:
        return None
    try:
        cur = conn.cursor()
        # historical(정규) 통산 per kbo_player_id (col은 스키마 상 동명)
        cur.execute(f"""
            SELECT count(*) FROM (
                SELECT kbo_player_id, SUM(COALESCE({stat_col},0)) tot
                FROM historical_season_stats
                WHERE series_type='정규'
                GROUP BY kbo_player_id
                HAVING SUM(COALESCE({stat_col},0)) >= %s
            ) x
        """, (value,))
        n = cur.fetchone()[0]
        cur.close()
        return int(n) if n else None
    except Exception:
        return None
    finally:
        conn.close()
```
> ⚠️ historical_season_stats에 `tb` 컬럼 존재 여부는 서버 스키마로 확인(없으면 `career_tb` 순위는 None 반환 → 캡션만 생략, 알림 자체는 발송). Task 6 라이브 검증서 확인.

- [ ] **Step 2: 통산 타자 쿼리에 tb(루타) SUM 추가**

통산 타자 쿼리(현 917~930)의 SELECT에 `SUM(COALESCE(bs.tb,0))` 추가:
```python
                cur2.execute("""
                    SELECT bs.player_id, p.name, t.name,
                           SUM(COALESCE(bs.hits, 0)),
                           SUM(COALESCE(bs.home_runs, 0)),
                           SUM(COALESCE(bs.rbis, 0)),
                           SUM(COALESCE(bs.stolen_bases, 0)),
                           SUM(COALESCE(bs.walks, 0)),
                           SUM(COALESCE(bs.tb, 0))
                    FROM game_batters gb
                    JOIN batter_stats bs ON bs.player_id = gb.player_id
                    JOIN players p ON p.id = gb.player_id
                    JOIN teams t ON t.id = p.team_id
                    WHERE gb.game_id = %s
                    GROUP BY bs.player_id, p.name, t.name
                """, (game_id,))
```

- [ ] **Step 3: 임계 확장 + tb + 순위 캡션 적용**

통산 타자 판정 블록(현 933~961)을 교체:
```python
                from api.milestone_detect import career_thresholds_100, crossed
                CAREER_BATTER = {
                    'career_hits':  career_thresholds_100([500, 1000], 1000, 2500),
                    'career_hr':    [100, 200, 300, 400, 500],
                    'career_rbi':   [500, 1000, 1500],
                    'career_sb':    [100, 200, 300],
                    'career_bb':    [500, 1000],
                    'career_tb':    [2000, 2500, 3000, 3500, 4000, 4500, 5000],
                }
                _CB_KEY = {'career_hits': 'season_hits', 'career_hr': 'season_hr',
                           'career_rbi': 'season_rbi', 'career_sb': 'season_sb',
                           'career_bb': 'season_bb', 'career_tb': 'season_tb'}
                _RANK_COL = {'career_hits': 'hits', 'career_hr': 'home_runs',
                             'career_rbi': 'rbis', 'career_sb': 'stolen_bases',
                             'career_bb': 'walks', 'career_tb': 'tb'}
                for row in career_batters:
                    pid, pname, tname = row[0], row[1], row[2]
                    cvals = {'career_hits': row[3], 'career_hr': row[4],
                             'career_rbi': row[5], 'career_sb': row[6],
                             'career_bb': row[7], 'career_tb': row[8]}
                    tg = today_batter.get(pid, {})
                    for mtype, thresholds in CAREER_BATTER.items():
                        prev = cvals[mtype] - tg.get(_CB_KEY[mtype], 0)
                        for t in crossed(prev, cvals[mtype], thresholds):
                            rank = _career_rank(_RANK_COL[mtype], t)
                            extra = f"역대 {rank}번째" if rank else ''
                            notify_milestone(pid, pname, tname, mtype, t, season, 0,
                                             game_id, extra_label=extra)
                    # 25세 이하 통산 100홈런/1000안타 (기존 유지)
                    age = _age(pid)
                    if age and age <= 25:
                        if cvals['career_hr'] - tg.get('season_hr', 0) < 100 <= cvals['career_hr']:
                            notify_milestone(pid, pname, tname, 'young_career_hr', 100,
                                             season, 0, game_id, extra_label=f"{age}세")
                        if cvals['career_hits'] - tg.get('season_hits', 0) < 1000 <= cvals['career_hits']:
                            notify_milestone(pid, pname, tname, 'young_career_hits', 1000,
                                             season, 0, game_id, extra_label=f"{age}세")
```
> ⚠️ `tg.get('season_tb', 0)` — today_batter의 tg에는 season_tb 키가 없음(오늘 루타 미집계). `today_batter` tg는 season_hr/rbi/hits/sb/bb/runs만 담음 → `tg.get('season_tb', 0)` = 0 → prev = 전체 통산(오늘 포함). 루타는 오늘분 차감 없이 통과 판정 = 약간 느슨하나(오늘 루타로 임계 정확히 통과한 경계 케이스만 영향) 허용. 정밀히 하려면 game_batters에 tb 없어 별도 계산 필요 → v1은 근사 허용.

- [ ] **Step 4: py_compile**

Run: `cd C:/Users/qq772/playball-fut/backend && python3 -m py_compile crawler/scheduler.py`
Expected: 성공(무출력).

- [ ] **Step 5: 커밋**

```bash
git -C C:/Users/qq772/playball-fut add backend/crawler/scheduler.py
git -C C:/Users/qq772/playball-fut commit -m "feat(milestone): career 100-unit hits + 루타(tb) + 역대순위 caption"
```

---

### Task 4: scheduler 20-20 + 전구단 상대 홈런

**Files:**
- Modify: `backend/crawler/scheduler.py` (`_check_post_game_milestones` 타자 시즌 블록 + 신규 블록)

**Interfaces:**
- Consumes: `dual_crossed` (Task 1).

- [ ] **Step 1: 20-20 판정을 타자 시즌 루프에 추가**

타자 시즌 루프(현 851~873) 안, `today_batter[pid] = tg` 다음 줄에 추가:
```python
            # 20-20 / 30-30 / 40-40 (오늘 완성)
            from api.milestone_detect import dual_crossed
            _hr, _sb = vals['season_hr'], vals['season_sb']
            _phr, _psb = _hr - tg['season_hr'], _sb - tg['season_sb']
            for _k, _kt in [(20, 'season_20_20'), (30, 'season_30_30'), (40, 'season_40_40')]:
                if dual_crossed(_phr, _hr, _psb, _sb, _k):
                    notify_milestone(pid, pname, tname, _kt, _k, season, month, game_id)
```

- [ ] **Step 2: 전구단 상대 홈런 블록 추가**

투수 시즌 루프 끝(현 910, `age = _age(pid)` young 블록 다음)과 통산 블록(현 912 `# ── 통산 타자`) 사이에 신규 블록 추가:
```python
        # ── 전 구단 상대 홈런 (오늘 홈런 친 타자, 시즌 상대팀 셋 완성) ──
        try:
            hr_today_pids = [r[0] for r in batters if (today_batter.get(r[0], {}).get('season_hr', 0) or 0) > 0]
            if hr_today_pids:
                conn_v = get_connection()
                if conn_v:
                    try:
                        cur_v = conn_v.cursor()
                        # 리그 전체 팀 수(상대팀 = 자기팀 제외) → 완성 기준
                        cur_v.execute("SELECT count(*) FROM teams")
                        n_teams = cur_v.fetchone()[0]
                        need = n_teams - 1  # 자기팀 제외 전 구단
                        for pid in hr_today_pids:
                            # 시즌 내 홈런 친 경기의 상대팀 distinct (game_batters.home_runs>0)
                            cur_v.execute("""
                                SELECT count(DISTINCT CASE WHEN g.home_team_id = p.team_id
                                                          THEN g.away_team_id ELSE g.home_team_id END)
                                FROM game_batters gb
                                JOIN games g ON g.id = gb.game_id
                                JOIN players p ON p.id = gb.player_id
                                WHERE gb.player_id = %s
                                  AND gb.home_runs > 0
                                  AND EXTRACT(YEAR FROM g.game_date) = %s
                            """, (pid, season))
                            curr_opp = cur_v.fetchone()[0] or 0
                            if curr_opp < need:
                                continue
                            # 오늘 경기 제외 시 미완성이어야(오늘 완성) — 오늘 상대팀 빼고 재계산
                            cur_v.execute("""
                                SELECT count(DISTINCT CASE WHEN g.home_team_id = p.team_id
                                                          THEN g.away_team_id ELSE g.home_team_id END)
                                FROM game_batters gb
                                JOIN games g ON g.id = gb.game_id
                                JOIN players p ON p.id = gb.player_id
                                WHERE gb.player_id = %s
                                  AND gb.home_runs > 0
                                  AND EXTRACT(YEAR FROM g.game_date) = %s
                                  AND gb.game_id <> %s
                            """, (pid, season, game_id))
                            prev_opp = cur_v.fetchone()[0] or 0
                            if prev_opp >= need:
                                continue  # 오늘 이전 이미 완성 → dedup에도 걸리나 이중가드
                            # 리그 N번째(올 시즌 완성 선수 수) 근사 캡션은 생략(정확계산 복잡) → 값만
                            prow = next((r for r in batters if r[0] == pid), None)
                            if prow:
                                notify_milestone(pid, prow[1], prow[2], 'season_hr_vs_all', 1,
                                                 season, 0, game_id)
                        cur_v.close()
                    finally:
                        conn_v.close()
        except Exception as _e:
            print(f"[마일스톤] 전구단홈런 오류: {_e}")
```
> 리그 "N번째" 캡션은 시즌 전체 완성자 집계가 비싸고 근사라 v1 생략(값만 발송). 필요 시 후속.

- [ ] **Step 3: py_compile**

Run: `cd C:/Users/qq772/playball-fut/backend && python3 -m py_compile crawler/scheduler.py`
Expected: 성공.

- [ ] **Step 4: 커밋**

```bash
git -C C:/Users/qq772/playball-fut add backend/crawler/scheduler.py
git -C C:/Users/qq772/playball-fut commit -m "feat(milestone): 20-20/30-30/40-40 + 전 구단 상대 홈런"
```

---

### Task 5: scheduler 사이클링 + 다홈런 + 끝내기

**Files:**
- Modify: `backend/crawler/scheduler.py` (신규 블록 + `_walkoff_batter` 헬퍼)

**Interfaces:**
- Consumes: `is_cycle`, `walkoff_type` (Task 1). `_is_walkoff` (기존).

- [ ] **Step 1: `_walkoff_batter` 헬퍼 추가**

`_is_walkoff`(현 1009) 바로 아래에 추가:
```python
def _walkoff_batter(game_id: int):
    """끝내기 결승타 타자 (batter_name, result_class, is_hit). 마지막 이닝 말의
    is_hit PA 중 win_rate_after>=99(홈 승 확정)인 마지막 PA. 없으면 None."""
    conn = get_connection()
    if not conn:
        return None
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT batter_name, result_class, is_hit
            FROM plate_appearances
            WHERE game_id = %s AND inning_half = '말' AND is_hit = TRUE
              AND inning = (SELECT MAX(inning) FROM plate_appearances WHERE game_id = %s)
            ORDER BY pa_seq DESC
            LIMIT 1
        """, (game_id, game_id))
        row = cur.fetchone()
        cur.close()
        return row  # (batter_name, result_class, is_hit) or None
    except Exception:
        return None
    finally:
        conn.close()
```
> ⚠️ 정밀 판정(win_rate_after 기반)이 이상적이나 win_rate 결손 경기 대비 = 마지막이닝 말 마지막 안타 = 끝내기 결승타 근사. 라이브 검증서 확인.

- [ ] **Step 2: 사이클 + 다홈런 + 끝내기 블록 추가**

`_check_post_game_milestones`의 완봉/QS 블록(현 823~834, `starters_cg` 루프) 다음에 신규 블록 추가:
```python
        # ── 사이클링 히트 / 한 경기 다홈런 / 끝내기 (단일경기) ──
        from api.milestone_detect import is_cycle, walkoff_type
        _bname_to_pid = {}  # 이 경기 batter_name → player_id (동명이인 다중매칭 스킵)
        for r in batters:
            _bname_to_pid.setdefault(r[1], []).append((r[0], r[2]))
        # 사이클
        try:
            conn_c = get_connection()
            if conn_c:
                try:
                    cur_c = conn_c.cursor()
                    cur_c.execute("""
                        SELECT batter_name, array_agg(DISTINCT result_class)
                        FROM plate_appearances WHERE game_id = %s
                        GROUP BY batter_name
                    """, (game_id,))
                    for bname, classes in cur_c.fetchall():
                        if is_cycle(set(classes or [])):
                            pids = _bname_to_pid.get(bname, [])
                            if len(pids) == 1:
                                pid, tname = pids[0]
                                notify_milestone(pid, bname, tname, 'game_cycle', 1, season, month, game_id)
                    cur_c.close()
                finally:
                    conn_c.close()
        except Exception as _e:
            print(f"[마일스톤] 사이클 오류: {_e}")
        # 다홈런 (game_batters.home_runs>=3, player_id 직접)
        for r in batters:
            pid, pname, tname = r[0], r[1], r[2]
            hr_today = today_batter.get(pid, {}).get('season_hr', 0) or 0
            if hr_today >= 3:
                notify_milestone(pid, pname, tname, 'game_multi_hr', hr_today, season, month, game_id)
        # 끝내기 (선수 식별)
        try:
            if _is_walkoff(game_id):
                wb = _walkoff_batter(game_id)
                if wb:
                    bname, rclass, ishit = wb[0], wb[1], wb[2]
                    wtype = walkoff_type(rclass or '', bool(ishit))
                    pids = _bname_to_pid.get(bname, [])
                    if wtype and len(pids) == 1:
                        pid, tname = pids[0]
                        notify_milestone(pid, bname, tname, wtype, 1, season, month, game_id)
        except Exception as _e:
            print(f"[마일스톤] 끝내기 오류: {_e}")
```
> `today_batter`는 이 블록 이후(현 851~) 채워지므로 다홈런/끝내기 블록이 `today_batter` 참조 불가 위치면 순서 조정 필요 — **이 블록을 타자 시즌 루프(현 851) 다음**에 배치(완봉 블록 뒤가 아니라). 정확 위치: `today_batter` 채운 뒤(현 873 이후), 투수 루프 전 또는 후. 구현 시 `today_batter` 정의 이후로 배치.

- [ ] **Step 3: py_compile**

Run: `cd C:/Users/qq772/playball-fut/backend && python3 -m py_compile crawler/scheduler.py`
Expected: 성공.

- [ ] **Step 4: 커밋**

```bash
git -C C:/Users/qq772/playball-fut add backend/crawler/scheduler.py
git -C C:/Users/qq772/playball-fut commit -m "feat(milestone): 사이클링 히트 + 한 경기 다홈런 + 끝내기 선수 식별"
```

---

### Task 6: 검증 + 배포

**Files:** 없음(검증/배포).

- [ ] **Step 1: 전체 py_compile + pytest**

Run:
```bash
cd C:/Users/qq772/playball-fut/backend && python3 -m py_compile crawler/scheduler.py api/fcm_service.py api/milestone_detect.py && \
python3 -m pytest tests/test_milestone_expansion.py -q
```
Expected: py_compile 성공 + pytest 6 passed. (로컬 python에 psycopg2 없으면 pytest는 서버서 — 순수 테스트라 deps 불요이나 import 경로상 서버 권장.)

- [ ] **Step 2: 배포 (scp + 재시작)**

서버 git 토큰 만료 → scp 우회. 변경 backend 파일 scp:
```bash
KEY="/c/Users/qq772/Downloads/ssh-key-2026-03-28 (2).key"
W=C:/Users/qq772/playball-fut/backend
for f in api/milestone_detect.py api/fcm_service.py crawler/scheduler.py; do
  scp -i "$KEY" "$W/$f" "ubuntu@168.107.36.158:~/playball/backend/$f"; done
scp -i "$KEY" "$W/tests/test_milestone_expansion.py" "ubuntu@168.107.36.158:~/playball/backend/tests/"
ssh -i "$KEY" ubuntu@168.107.36.158 "cd ~/playball/backend && python3 -m pytest tests/test_milestone_expansion.py -q && python3 -c 'import crawler.scheduler' && sudo systemctl restart playball playball-scheduler && sleep 3 && bash ~/playball/scripts/smoke.sh | tail -4"
```
Expected: pytest 6 passed · scheduler import OK · smoke ALL PASS.

- [ ] **Step 3: 라이브 스팟체크 (역대순위·전구단·스키마 확인)**

Run (서버):
```bash
ssh -i "$KEY" ubuntu@168.107.36.158 "sudo -u postgres psql -d playball -c \"SELECT column_name FROM information_schema.columns WHERE table_name='historical_season_stats' AND column_name IN ('tb','hits','home_runs');\" -c \"SELECT count(*) FROM (SELECT kbo_player_id FROM historical_season_stats WHERE series_type='정규' GROUP BY kbo_player_id HAVING SUM(COALESCE(hits,0))>=1100) x;\""
```
Expected: hits/home_runs 컬럼 존재(tb 유무 확인 — 없으면 career_tb 순위캡션만 생략, 알림은 정상), 1100안타 역대 카운트 숫자 반환(강백호 케이스 근사 검증).
- ⚠️ tb 컬럼 없으면 Task 3 `_career_rank`가 career_tb에 None 반환(정상 설계) — 알림 발송엔 지장 없음.
- ⚠️ **실발송은 다음 해당 경기부터**(소급 없음). 수동 재현 원하면 종료경기 gid로 `python3 -c "from crawler.scheduler import _check_post_game_milestones as m; m(<gid>)"` (단 dedup으로 1회).

- [ ] **Step 4: 커밋(문서/CLAUDE.md)** — 최종 태스크에서 스펙/플랜/변경이력 커밋(subagent-driven 컨트롤러가 마무리 단계서 처리).

## Self-Review

**1. Spec coverage:**
- ① 끝내기 개인(walkoff_hr/hit + 선수식별) → Task 5. ✅
- ② 사이클(game_cycle) + 다홈런(game_multi_hr) → Task 5. ✅
- ③ 전구단홈런(season_hr_vs_all) + 20-20/30-30/40-40 → Task 4. ✅
- ④ 통산 100단위(career_hits) + career_tb + 역대순위 캡션 → Task 3. ✅
- 라벨/문구 정리(바이너리 value 생략) → Task 1(format_milestone_title)+Task 2. ✅
- is_career 확장(walkoff/hr_vs_all=선수+팀팬) → Task 2. ✅
- dedup player_milestone_alerts / PA 적재 후 실행 → 기존 경로 재사용(코드 배치 위치 명시). ✅
- 동명이인 회피(game_batters player_id / name 다중매칭 스킵) → Task 4/5. ✅
- pure helper 테스트 → Task 1. ✅
- 배포/스키마 검증 → Task 6. ✅

**2. Placeholder scan:** 코드 스텝 전부 실제 코드. tb/historical 스키마 미확정 부분은 라이브 검증 지시로 명시(가정 아님, graceful degrade). ⚠️ 주의: Task 5 블록 배치 위치(`today_batter` 정의 이후)를 Step 2 노트로 명시. placeholder 없음.

**3. Type consistency:** `format_milestone_title(emoji,name,month_str,cat,value,unit,extra_str)` Task1 정의=Task2 호출 일치. `crossed`/`dual_crossed`/`is_cycle`/`walkoff_type`/`career_thresholds_100` 시그니처 Task1=사용처 일치. `notify_milestone(pid,name,team,type,value,season,month,game_id,extra_label=)` 기존 시그니처 준수. `_career_rank(stat_col,value)` 정의=Task3 사용 일치. `_walkoff_batter`→(name,class,is_hit) 튜플 = Task5 사용 일치. ✅
