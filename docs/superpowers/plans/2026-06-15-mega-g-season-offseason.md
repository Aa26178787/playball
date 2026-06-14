# 메가G v1 시즌 상태머신 + 오프시즌 모드 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use `- [ ]`.

**Goal:** 시즌 단계 자동 인지(상태머신) + 오프시즌 홈 UX + 연말결산 Wrapped 카드.

**Architecture:** 순수 `compute_phase`를 scheduler 일일 잡이 호출해 season_phase 갱신. 홈은 phase로 분기. Wrapped는 backend 집계 + 클라 카드(공유 재사용).

**Tech Stack:** Python(psycopg2)·pytest, Flutter, FCM 불요.

---

### Task 1: season.py compute_phase + 테스트

**Files:**
- Create: `backend/api/season.py`
- Test: `backend/tests/test_season.py`

- [ ] **Step 1: test_season.py (순수, DB 불요)**

```python
from datetime import date
from api.season import compute_phase


def test_preseason():
    assert compute_phase(date(2026, 3, 1), date(2026, 3, 22), date(2026, 10, 1), False) == 'preseason'


def test_regular_has_recent():
    assert compute_phase(date(2026, 6, 15), date(2026, 3, 22), date(2026, 10, 1), True) == 'regular'


def test_offseason_after_last():
    assert compute_phase(date(2026, 12, 1), date(2026, 3, 22), date(2026, 10, 1), False) == 'offseason'


def test_no_schedule_offseason():
    assert compute_phase(date(2026, 1, 5), None, None, False) == 'offseason'


def test_regular_during_window_no_recent_flag():
    # 시즌 기간 내지만 최근경기 플래그 False (올스타 휴식 등) → regular 유지
    assert compute_phase(date(2026, 7, 15), date(2026, 3, 22), date(2026, 10, 1), False) == 'regular'
```

- [ ] **Step 2: 실패 확인**

Run: `cd backend && py -3 -m py_compile api/season.py` (없으니 import 에러 — 테스트는 서버/CI서)
로컬 빠른 검증은 Step 4 `py -3 -c`로.

- [ ] **Step 3: season.py 구현**

```python
"""시즌 단계 상태머신 — 순수 판별 (DB 없음). scheduler가 일정으로 호출."""
from datetime import date


def compute_phase(today: date, first_game, last_game, has_recent: bool) -> str:
    """오늘 + 올해 정규경기 first/last(date|None) + 최근±10일 경기 유무 → 단계.
    postseason은 자동 판별 안 함(호출측 admin 핀)."""
    if first_game is None or last_game is None:
        return 'offseason'           # 일정 미정
    if today < first_game:
        return 'preseason'
    if today > last_game and not has_recent:
        return 'offseason'
    return 'regular'
```

- [ ] **Step 4: 로컬 검증 + 커밋**

Run: `cd backend && py -3 -c "import sys;sys.path.insert(0,'.');from datetime import date;from api.season import compute_phase as f;assert f(date(2026,3,1),date(2026,3,22),date(2026,10,1),False)=='preseason';assert f(date(2026,6,15),date(2026,3,22),date(2026,10,1),True)=='regular';assert f(date(2026,12,1),date(2026,3,22),date(2026,10,1),False)=='offseason';assert f(date(2026,1,5),None,None,False)=='offseason';print('ok')"`
Expected: ok

```bash
git add backend/api/season.py backend/tests/test_season.py
git commit -m "feat(season): compute_phase 상태머신 + 테스트 (메가G Task1)"
```

---

### Task 2: scheduler _update_season_phase + 등록

**Files:**
- Modify: `backend/crawler/scheduler.py`

- [ ] **Step 1: 캐시 무효화 패턴 확인**

`api/routers/admin.py`의 set_feature_flag(~634)에서 `/app-config` 캐시 무효화 방식 확인(cache 모듈 함수명). 동일 호출을 scheduler에서 재사용.

- [ ] **Step 2: 함수 추가** (`_purge_dead_refresh_tokens` 근처)

```python
def _update_season_phase():
    """매일: games 일정으로 시즌 단계 자동 갱신. postseason(admin 핀)은 보존."""
    import json
    from datetime import datetime, timedelta
    from api.season import compute_phase
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        yr = datetime.now().year
        cur.execute("""SELECT MIN(game_date), MAX(game_date),
            BOOL_OR(game_date BETWEEN %s AND %s)
            FROM games WHERE EXTRACT(YEAR FROM game_date) = %s""",
            (datetime.now().date() - timedelta(days=10),
             datetime.now().date() + timedelta(days=10), yr))
        row = cur.fetchone()
        first_g, last_g, has_recent = (row[0], row[1], bool(row[2])) if row else (None, None, False)
        phase = compute_phase(datetime.now().date(), first_g, last_g, has_recent)
        cur.execute("SELECT value FROM app_config WHERE key='season_phase'")
        r = cur.fetchone()
        current = r[0] if r else None  # jsonb → str
        if current == 'postseason':
            cur.close(); return          # admin 핀 보존
        if current != phase:
            cur.execute("UPDATE app_config SET value=%s WHERE key='season_phase'",
                        (json.dumps(phase),))
            conn.commit()
            print(f"[{datetime.now()}] season_phase {current}→{phase}")
            # /app-config 캐시 무효화 (admin 패턴 동일 함수 호출)
        cur.close()
    except Exception as e:
        print(f"[season_phase] 오류: {e}")
    finally:
        conn.close()
```
(※ season_phase는 jsonb str — `value::text` 비교 or psycopg2가 str로 반환하는지 확인. UPDATE는 json.dumps. current 비교는 따옴표 포함 여부 주의 — 실행 시 `SELECT value::text` vs `value` 반환형 확인 후 맞춤.)

- [ ] **Step 3: 등록** (run_scheduler 내, _purge 등록 근처)

```python
    # 매일 UTC 18:30 (KST 03:30): 시즌 단계 자동 갱신
    schedule.every().day.at("18:30").do(_update_season_phase)
```

- [ ] **Step 4: py_compile + 커밋**

```bash
py -3 -m py_compile backend/crawler/scheduler.py
git add backend/crawler/scheduler.py
git commit -m "feat(season): scheduler 시즌 단계 자동 갱신 잡 (메가G Task2)"
```

---

### Task 3: backend /user/season-wrapped

**Files:**
- Modify: `backend/api/routers/user.py`

- [ ] **Step 1: 엔드포인트 추가**

`weekly_missions`(1025) 근처에 추가. get_current_user 의존. 집계 쿼리(연도 파라미터):

```python
@router.get("/season-wrapped")
def season_wrapped(year: int | None = None, current_user: dict = Depends(get_current_user)):
    from datetime import datetime
    uid = current_user['user_id']
    yr = year or datetime.now().year
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    out = {"year": yr}
    try:
        # 직관: 횟수 + 승/패/무 + 구장 수
        cur.execute("""SELECT COUNT(*),
            COUNT(*) FILTER (WHERE v.result='win'),
            COUNT(*) FILTER (WHERE v.result='loss'),
            COUNT(*) FILTER (WHERE v.result='draw'),
            COUNT(DISTINCT g.stadium_id)
            FROM user_stadium_visits v JOIN games g ON g.id=v.game_id
            WHERE v.user_id=%s AND EXTRACT(YEAR FROM g.game_date)=%s""", (uid, yr))
        r = cur.fetchone()
        out["visits"] = {"total": r[0], "wins": r[1], "losses": r[2], "draws": r[3], "stadiums": r[4]}
        # 예측 적중/참여 + 포인트 + 출석 (point_ledger)
        cur.execute("""SELECT
            COUNT(*) FILTER (WHERE reason='prediction_win'),
            COUNT(*) FILTER (WHERE reason IN ('prediction_win','prediction_lose','prediction_draw')),
            COUNT(*) FILTER (WHERE reason='attendance'),
            COALESCE(SUM(points),0)
            FROM point_ledger WHERE user_id=%s""", (uid,))
        r = cur.fetchone()
        out["predictions"] = {"correct": r[0], "total": r[1]}
        out["attendance_days"] = r[2]
        out["points"] = int(r[3])
        cur.close()
    except Exception as e:
        cur.close()
        # 부분 실패 허용
        out.setdefault("visits", {}); out.setdefault("predictions", {})
    finally:
        conn.close()
    return out
```
(※ user_stadium_visits에 result 컬럼 있는지 실행 시 확인 — 없으면 visit_record 스키마 맞춰 조정. point_ledger 컬럼은 확인됨.)

- [ ] **Step 2: ApiService 메서드 + py_compile**

`app/lib/api/api_service.dart`에 `getSeasonWrapped({int? year})` 추가(authHeaders 필수).
Run: `py -3 -m py_compile backend/api/routers/user.py`

- [ ] **Step 3: 커밋**

```bash
git add backend/api/routers/user.py app/lib/api/api_service.dart
git commit -m "feat(wrapped): /user/season-wrapped 집계 + 클라 API (메가G Task3)"
```

---

### Task 4: 클라 season_wrapped_screen + 마이페이지 진입

**Files:**
- Create: `app/lib/screens/wrapped/season_wrapped_screen.dart`
- Modify: `app/lib/screens/mypage/my_page_screen.dart` (진입 버튼)

- [ ] **Step 1: Wrapped 화면**

`getSeasonWrapped` 호출 → 카드형 요약(직관 N회 W승L패·구장 N곳 / 예측 적중 X/Y / 누적 Z P /
출석 D일 / 최애 팀·선수). share_cards.dart 톤. 하단 `AppConfig.enabled('share')`면 공유 버튼
→ `showShareCardDialog(context, card: ..., filename: 'playball_wrapped')`.

- [ ] **Step 2: 마이페이지 진입**

마이페이지 '기타' 또는 상단에 "내 시즌 결산" 행 → `Navigator.push(SeasonWrappedScreen())`.

- [ ] **Step 3: flutter analyze**

Run: `flutter analyze lib/screens/wrapped/season_wrapped_screen.dart lib/screens/mypage/my_page_screen.dart`
Expected: No issues

- [ ] **Step 4: 커밋**

```bash
git add app/lib/screens/wrapped/ app/lib/screens/mypage/my_page_screen.dart
git commit -m "feat(wrapped): 연말결산 화면 + 마이페이지 진입 (메가G Task4)"
```

---

### Task 5: 홈 오프시즌 분기

**Files:**
- Modify: `app/lib/screens/home/home_screen.dart`

- [ ] **Step 1: offseason 분기**

홈 게임리스트 영역에서 `AppConfig.seasonPhase == 'offseason'`일 때:
- 마이팀 다음 경기(미래 일정) 있으면 D-day 카드, 없으면 "다음 시즌을 기다려요" 안내.
- "내 시즌 결산 보기" 버튼 → SeasonWrappedScreen.
정규시즌(regular/preseason)엔 기존 동작 유지(분기만 추가, 무가드).

- [ ] **Step 2: flutter analyze → No issues**

- [ ] **Step 3: 커밋**

```bash
git add app/lib/screens/home/home_screen.dart
git commit -m "feat(season): 오프시즌 홈 — 다음경기 D-day + 결산 진입 (메가G Task5)"
```

---

### Task 6: 배포 + 검증

- [ ] **Step 1: 배포** — pull + py_compile(season/scheduler/user) + restart playball·scheduler
- [ ] **Step 2: pytest** (scratch DB) — test_season 포함 전체 통과
- [ ] **Step 3: 상태머신 1회 실행 확인** — season_phase=='regular' 유지(현재 정규)
- [ ] **Step 4: smoke** ALL PASS
- [ ] **Step 5: 웹 재빌드+배포** (Wrapped·홈 클라 변경)
- [ ] **Step 6: CI green**
- [ ] **Step 7: (선택) 미리보기** — admin으로 season_phase 임시 offseason → 홈/Wrapped 육안 → regular 복원

---

## Self-Review
- **Spec coverage**: 상태머신(T1,T2)·오프시즌 홈(T5)·Wrapped(T3,T4)·배포(T6). 전부 매핑.
- **Placeholder**: season.py·test·wrapped 쿼리는 구체. 실행 시 핀: season_phase jsonb 반환형(T2), user_stadium_visits.result 컬럼(T3), 캐시 무효화 함수명(T2), share_cards 톤(T4), 마이페이지/홈 삽입점(T4,T5).
- **Type consistency**: compute_phase 시그니처 T1↔T2 일치. season-wrapped 반환 키(visits/predictions/points/attendance_days) T3↔T4 일치.
- **순서**: 토대(T1,T2) → Wrapped(T3,T4) → 홈(T5) → 배포(T6).

## 실행 시 grep으로 핀
- season_phase app_config 저장/반환형 (app_config.py, admin.py)
- /app-config 캐시 무효화 함수 (admin.py set_feature_flag ~634, cache.py)
- user_stadium_visits 스키마 (result 컬럼 유무)
- share_cards.dart / showShareCardDialog 시그니처
- 마이페이지 '기타' 섹션 + 홈 게임리스트 분기점
