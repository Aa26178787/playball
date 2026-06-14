# 메가F v1 리텐션 점화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use `- [ ]`.

**Goal:** 꺼져 있던 포인트/예측 리텐션 루프를 회귀 테스트로 안전망을 깐 뒤 켜고, 예측 결과 푸시·마감 카운트다운을 추가한다.

**Architecture:** 신규 빌드 최소(테스트·결과푸시·카운트다운). 정산 루프(scheduler)에서 award 후 예측자별 결과 푸시. 마지막에 points 킬스위치 ON.

**Tech Stack:** Python(psycopg2)·pytest, Flutter, FCM.

---

### Task 1: 회귀 테스트 (켜기 전 안전망)

**Files:**
- Create: `backend/tests/test_badges.py`
- Modify: `backend/tests/test_points.py` (mission_weekly 멱등 케이스 추가)

- [ ] **Step 1: test_badges.py 작성**

```python
"""뱃지 엔진 회귀 (DB 필요). evaluate_badges 멱등 + 임계값 경계."""
import os
import pytest

pytestmark = pytest.mark.skipif(
    not os.environ.get("TEST_DATABASE_URL"), reason="no test db")


def _setup(conn):
    cur = conn.cursor()
    for ddl in [
        "DROP TABLE IF EXISTS user_badges",
        "DROP TABLE IF EXISTS point_ledger",
        "DROP TABLE IF EXISTS user_stadium_visits",
        "DROP TABLE IF EXISTS games",
        "CREATE TABLE user_badges (user_id INT, badge_id TEXT, UNIQUE(user_id, badge_id))",
        "CREATE TABLE point_ledger (id SERIAL PRIMARY KEY, user_id INT, points INT, reason TEXT, ref_key TEXT, UNIQUE(user_id,reason,ref_key))",
        "CREATE TABLE games (id INT PRIMARY KEY, stadium_id INT)",
        "CREATE TABLE user_stadium_visits (user_id INT, game_id INT)",
    ]:
        cur.execute(ddl)
    cur.close()


def test_badges_earn_and_idempotent(db):
    _setup(db)
    from api.badges import evaluate_badges
    cur = db.cursor()
    # 적중 1회(50P) + 출석 7일 → pred_win_1, attend_7 충족 / pred_win_10 미충족
    cur.execute("INSERT INTO point_ledger (user_id,points,reason,ref_key) VALUES (1,50,'prediction_win','pred:1')")
    for i in range(7):
        cur.execute("INSERT INTO point_ledger (user_id,points,reason,ref_key) VALUES (1,5,'attendance',%s)", (f'd{i}',))
    out = evaluate_badges(cur, 1)
    earned = {b['id'] for b in out if b['earned']}
    assert 'pred_win_1' in earned
    assert 'attend_7' in earned
    assert 'pred_win_10' not in earned
    # 멱등: 재평가해도 user_badges 중복 없음
    n1 = (cur.execute("SELECT COUNT(*) FROM user_badges WHERE user_id=1"), cur.fetchone()[0])[1]
    evaluate_badges(cur, 1)
    cur.execute("SELECT COUNT(*) FROM user_badges WHERE user_id=1")
    assert cur.fetchone()[0] == n1
```

- [ ] **Step 2: test_points.py에 mission_weekly 멱등 추가**

test_points.py의 test_award_idempotent 아래에 추가:
```python
def test_award_mission_weekly_idempotent(db):
    from api.points import award
    cur = db.cursor()
    cur.execute("DROP TABLE IF EXISTS point_ledger")
    cur.execute("""CREATE TABLE point_ledger (id SERIAL PRIMARY KEY, user_id INT,
        points INT, reason TEXT, ref_key TEXT, UNIQUE(user_id, reason, ref_key))""")
    assert award(cur, 1, "mission_weekly", "2026-W24", points=100) == 1
    assert award(cur, 1, "mission_weekly", "2026-W24", points=100) == 0
```
(award 시그니처에 points 명시 가능 — POINTS에 mission_weekly 없으면 명시 필요)

- [ ] **Step 3: 서버 pytest (scratch DB)**

오늘 패턴으로 실행. Expected: test_badges 1 + test_points 2 통과 (전체 그린).

- [ ] **Step 4: 커밋**

```bash
git add backend/tests/test_badges.py backend/tests/test_points.py
git commit -m "test: 뱃지 엔진+미션보상 멱등 회귀 (메가F Task1 안전망)"
```

---

### Task 2: notify_prediction_result (fcm_service)

**Files:**
- Modify: `backend/api/fcm_service.py`

- [ ] **Step 1: 함수 추가** (notify_game_summary 근처)

```python
def notify_prediction_result(user_id: int, game_id: int, home_team: str,
                             away_team: str, outcome: str, points: int):
    """승부예측 정산 결과 — 예측한 본인에게. outcome ∈ win/lose/draw.
    notification_log dedup은 호출측(정산)에서 (game_id,'prediction_result',user_id)."""
    if outcome == 'win':
        title = "🎯 예측 적중!"
        body = f"{home_team} vs {away_team} — 적중! +{points}P"
    elif outcome == 'draw':
        title = "⚾ 무승부"
        body = f"{home_team} vs {away_team} — 무승부 참여 +{points}P"
    else:
        title = "예측 결과"
        body = f"{home_team} vs {away_team} — 아쉽게 빗나감 +{points}P"
    _send([user_id], title, body,
          {"game_id": str(game_id), "type": "prediction_result"},
          "prediction_result", game_id)
```
(`_send(targets, title, body, data, ntype, game_id)` 시그니처 확인 — notify_game_summary의 _send 호출과 동일 형태. targets는 user_id 리스트. ntype='prediction_result'는 채널 라우팅 기본값으로 떨어짐 — 확인)

- [ ] **Step 2: py_compile**

Run: `py -3 -m py_compile backend/api/fcm_service.py` → exit 0

- [ ] **Step 3: 커밋**

```bash
git add backend/api/fcm_service.py
git commit -m "feat(predict): notify_prediction_result 푸시 함수 (메가F Task2)"
```

---

### Task 3: 정산 루프에 결과 푸시 통합 (scheduler)

**Files:**
- Modify: `backend/crawler/scheduler.py` (정산 루프 ~1662-1683)

- [ ] **Step 1: 결과 수집 + 푸시**

정산 루프(`for _uid, _pick in cur_pt.fetchall():`)에서 outcome을 리스트에 수집:
```python
                                    _results = []  # (uid, outcome)
                                    for _uid, _pick in cur_pt.fetchall():
                                        if _winner is None:
                                            award(cur_pt, _uid, 'prediction_draw', f'pred:{gid}')
                                            _n_part += 1; _results.append((_uid, 'draw'))
                                        elif _pick == _winner:
                                            award(cur_pt, _uid, 'prediction_win', f'pred:{gid}')
                                            _n_win += 1; _results.append((_uid, 'win'))
                                        else:
                                            award(cur_pt, _uid, 'prediction_lose', f'pred:{gid}')
                                            _n_part += 1; _results.append((_uid, 'lose'))
                                    conn_pt.commit()
                                    # 결과 푸시 (팀명 1회 조회 → 예측자별, dedup은 _send/_mark)
                                    try:
                                        cur_pt.execute("""SELECT t1.name, t2.name FROM games g
                                            JOIN teams t1 ON t1.id=g.home_team_id
                                            JOIN teams t2 ON t2.id=g.away_team_id WHERE g.id=%s""", (gid,))
                                        _tn = cur_pt.fetchone()
                                        if _tn:
                                            from api.fcm_service import notify_prediction_result
                                            _pts = {'win': 50, 'draw': 10, 'lose': 10}
                                            for _uid, _oc in _results:
                                                try:
                                                    notify_prediction_result(_uid, gid, _tn[0], _tn[1], _oc, _pts[_oc])
                                                except Exception as _pe:
                                                    print(f"[predict] 결과푸시 오류 uid={_uid}: {_pe}")
                                    except Exception as _te:
                                        print(f"[predict] 결과푸시 팀조회 오류 game={gid}: {_te}")
                                    cur_pt.close()
```
(기존 `conn_pt.commit(); cur_pt.close()` 블록을 위로 대체. dedup은 notification_log — _send가 ntype+game_id로 기록하나 user별 구분 필요 시 sub_id. 정산은 ref_key가 award 멱등 보장하므로 재실행 시 award는 0이지만 푸시는 재발송될 수 있음 → notification_log (game_id,'prediction_result',uid) 가드를 _already_notified/_mark_notified로 추가, 또는 _send 자체 dedup 확인. 실행 시 notification_log 패턴 확인 후 user별 dedup 적용.)

- [ ] **Step 2: notification_log user별 dedup 적용**

정산 재실행 시 중복 푸시 방지: 각 푸시 전 `_already_notified(gid, 'prediction_result', uid)` 체크, 발송 후 `_mark_notified(gid, 'prediction_result', uid)`. (scheduler의 기존 dedup 헬퍼 시그니처 확인 후 sub_id=uid로 사용)

- [ ] **Step 3: py_compile**

Run: `py -3 -m py_compile backend/crawler/scheduler.py` → exit 0

- [ ] **Step 4: 커밋**

```bash
git add backend/crawler/scheduler.py
git commit -m "feat(predict): 정산 시 예측 결과 푸시 (메가F Task3)"
```

---

### Task 4: 예측 마감 카운트다운 (클라)

**Files:**
- Modify: `app/lib/screens/home/home_screen.dart` (`_PredictionBar` / `_PredictionBarState`)

- [ ] **Step 1: 카운트다운 표시**

`_PredictionBar`는 game.startTime + status('예정'/'라인업')에서만 투표 가능. 마감 = 경기 시작.
투표 버튼 영역 상단/근처에 "마감 N분 전" 텍스트 추가:
```dart
// game.startTime "HH:MM" + game.gameDate → 시작 DateTime. now와 차이로 라벨.
// 시작 지났으면 '투표 마감' + 버튼 disable.
String _deadlineLabel() {
  final st = widget.game.startTime;  // "18:30"
  if (st == null || st.isEmpty) return '';
  // gameDate(yyyy-MM-dd) + st 파싱 → DateTime
  // 남은 분 = diff.inMinutes; >0 이면 "마감 {hh시간 mm분} 전", <=0 "마감"
}
```
1분 주기 갱신: `_PredictionBarState`에 `Timer.periodic(1분)` → setState (dispose에서 cancel). 또는 build 시 계산(폴링 의존). 경량 Timer 권장.

- [ ] **Step 2: 투표 잠금**

시작 지나면 픽 버튼 onTap null + 시각적 disable.

- [ ] **Step 3: flutter analyze**

Run: `flutter analyze lib/screens/home/home_screen.dart` → No issues

- [ ] **Step 4: 커밋**

```bash
git add app/lib/screens/home/home_screen.dart
git commit -m "feat(predict): 예측 마감 카운트다운+잠금 (메가F Task4)"
```

---

### Task 5: 배포 + 검증 (활성화 전)

- [ ] **Step 1: 서버 배포** — pull + py_compile(fcm/scheduler) + restart playball·scheduler
- [ ] **Step 2: 서버 pytest** (scratch DB) — badges/points 포함 전체 통과
- [ ] **Step 3: smoke** ALL PASS
- [ ] **Step 4: 웹 재빌드+배포** (카운트다운 클라 변경)
- [ ] **Step 5: CI green**

---

### Task 6: points 활성화 (마지막)

- [ ] **Step 1: admin으로 points ON**

`POST /admin/feature-flags` (X-Admin-Key) body `{"points": true}` 또는 kill_switches에서 points 제거.
실행: `curl -X POST https://playball.duckdns.org/admin/feature-flags -H "X-Admin-Key: $KEY" -H "Content-Type: application/json" -d '{"feature":"points","enabled":true}'`
(실제 페이로드 형식은 admin.py POST 핸들러 확인 후 맞춤)

- [ ] **Step 2: 확인**

`/app-config` kill_switches에 points=false 없음(또는 true) 확인. 앱/웹서 게임카드 팬투표·마이페이지 포인트 노출 확인.

- [ ] **Step 3: (선택) 라이브 검증**

진행/종료 경기로 예측→정산→결과 푸시 로그 확인.

---

## Self-Review
- **Spec coverage**: 활성화(T6)·회귀테스트(T1)·결과푸시(T2,T3)·카운트다운(T4)·배포검증(T5). 전부 매핑.
- **Placeholder**: T2 _send 시그니처·T3 notification_log dedup 헬퍼·T4 startTime 파싱·T6 admin 페이로드는 실행 시 해당 코드 확인해 핀(정확한 형태 grep). 테스트(T1)·fcm 함수(T2)는 구체 코드.
- **순서 안전**: 신규 코드(T1-T5) 먼저 배포·검증 → T6 활성화 마지막. 켜진 채 미검증 코드 노출 방지.
- **dedup**: award는 ref_key 멱등. 푸시는 notification_log (game_id,'prediction_result',uid)로 별도 가드(T3 Step2).

## 실행 시 grep으로 핀
- `_send` 시그니처 + ntype→채널 매핑 (fcm_service.py)
- `_already_notified`/`_mark_notified` 시그니처 (scheduler.py)
- `_PredictionBar` 투표 버튼/startTime 접근 (home_screen.dart)
- admin POST /feature-flags 페이로드 형식 (admin.py)
