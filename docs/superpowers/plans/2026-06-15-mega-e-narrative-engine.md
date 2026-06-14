# 메가E v1 내러티브 엔진 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 경기 데이터를 한국어 문구로 바꾸는 순수 템플릿 엔진을 만들고 한줄평·WPA MVP·라이브 캡션 3 surface에 연결한다.

**Architecture:** `api/narrative.py`(DB 없는 순수 함수, dict→str, LLM 교체가능)가 코어. 종료 후처리(`_send_game_summary`)가 facts를 모아 한줄평/MVP를 만들어 `game_reviews`에 저장하고 기존 종료 푸시 본문을 교체. relay 응답에 라이브 캡션 주입. 경기상세가 review를 join해 배지/MVP칩 노출. 전부 `narrative` 킬스위치로 가드.

**Tech Stack:** Python(FastAPI·psycopg2), PostgreSQL, Flutter(Dart), pytest.

---

### Task 1: narrative.py 순수 엔진 + 테스트

**Files:**
- Create: `backend/api/narrative.py`
- Test: `backend/tests/test_narrative.py`

- [ ] **Step 1: 실패 테스트 작성** — `backend/tests/test_narrative.py`

```python
"""내러티브 엔진 순수 로직 테스트 (DB 불요)."""
from api.narrative import game_review, live_caption, mvp_line


def test_review_walkoff():
    s = game_review({"home_team": "LG", "away_team": "KT",
                     "home_score": 5, "away_score": 4, "walkoff": True})
    assert "LG" in s and "끝내기" in s and "5-4" in s


def test_review_extra_innings():
    s = game_review({"home_team": "두산", "away_team": "NC",
                     "home_score": 3, "away_score": 6, "extra_innings": True})
    assert "NC" in s and "연장" in s


def test_review_blowout():
    s = game_review({"home_team": "삼성", "away_team": "한화",
                     "home_score": 13, "away_score": 2})
    assert "삼성" in s and "대승" in s


def test_review_close():
    s = game_review({"home_team": "KIA", "away_team": "롯데",
                     "home_score": 2, "away_score": 1})
    assert "KIA" in s and ("진땀" in s or "1" in s)


def test_review_draw():
    s = game_review({"home_team": "SSG", "away_team": "키움",
                     "home_score": 3, "away_score": 3})
    assert "무승부" in s


def test_review_appends_mvp():
    s = game_review({"home_team": "LG", "away_team": "KT",
                     "home_score": 7, "away_score": 3,
                     "mvp_name": "오지환", "mvp_line": "3안타 2타점"})
    assert "오지환" in s and "3안타 2타점" in s


def test_review_missing_fields_safe():
    # 빈 dict 도 예외 없이 문자열
    assert isinstance(game_review({}), str)


def test_caption_bases_loaded():
    s = live_caption({"inning": 8, "half": "말", "out": 2,
                      "base1": True, "base2": True, "base3": True,
                      "home_score": 4, "away_score": 5})
    assert "8회말" in s and "2사" in s and "만루" in s


def test_caption_tie():
    s = live_caption({"inning": 9, "half": "초", "out": 0,
                      "base1": False, "base2": False, "base3": False,
                      "home_score": 2, "away_score": 2})
    assert "동점" in s


def test_caption_out_of_game_empty():
    assert live_caption({}) == ""
    assert live_caption({"inning": 0}) == ""


def test_mvp_line_formats():
    assert mvp_line({"hits": 3, "home_runs": 1, "rbis": 4}) != ""
    assert isinstance(mvp_line({}), str)
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd backend && JWT_SECRET_KEY=x LOG_DIR=/tmp/pblogs python3 -m pytest tests/test_narrative.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'api.narrative'`

- [ ] **Step 3: narrative.py 구현** — `backend/api/narrative.py`

```python
"""내러티브 엔진 — 경기 데이터 → 한국어 문구 (템플릿 v1, DB 없음).

generate 인터페이스를 추상화: 추후 LLM 백엔드는 game_review/live_caption을
동일 시그니처로 교체하면 된다. 모든 함수는 입력 누락/빈값에 안전(예외 던지지 않음).
"""


def mvp_line(mvp: dict) -> str:
    """타자 성적 → '3안타 2타점' 류 한 줄. 빈 입력은 빈 문자열."""
    parts = []
    h = mvp.get("hits") or 0
    hr = mvp.get("home_runs") or 0
    rbi = mvp.get("rbis") or 0
    if hr:
        parts.append(f"{hr}홈런")
    if h:
        parts.append(f"{h}안타")
    if rbi:
        parts.append(f"{rbi}타점")
    return " ".join(parts)


def game_review(facts: dict) -> str:
    """종료 한줄평. 분기 우선순위: 무승부 > 끝내기 > 연장 > 대승 > 접전 > 평이."""
    h = facts.get("home_team", "")
    a = facts.get("away_team", "")
    hs = facts.get("home_score", 0) or 0
    as_ = facts.get("away_score", 0) or 0

    if hs == as_:
        return f"{h} {hs}-{as_} {a}, 팽팽한 무승부"

    winner = h if hs > as_ else a
    loser = a if hs > as_ else h
    wscore, lscore = (max(hs, as_), min(hs, as_))
    diff = wscore - lscore

    if facts.get("walkoff"):
        lead = f"{winner}, {wscore}-{lscore} 끝내기 승리"
    elif facts.get("extra_innings"):
        lead = f"{winner}, 연장 접전 끝 {wscore}-{lscore} 승"
    elif diff >= 8:
        lead = f"{winner}, {wscore}-{lscore} 대승"
    elif diff <= 1:
        lead = f"{winner}, {wscore}-{lscore} 진땀승"
    else:
        lead = f"{winner}, {wscore}-{lscore}로 {loser} 제압"

    mvp_name = facts.get("mvp_name", "")
    mvp_l = facts.get("mvp_line", "")
    if mvp_name and mvp_l:
        return f"{lead}. {mvp_name} {mvp_l}"
    if facts.get("win_pitcher"):
        return f"{lead}. 승리투수 {facts['win_pitcher']}"
    return lead


def _runners_phrase(b1: bool, b2: bool, b3: bool) -> str:
    if b1 and b2 and b3:
        return "만루"
    n = int(b1) + int(b2) + int(b3)
    if n == 0:
        return "주자 없음"
    if b2 or b3:
        return "득점권 주자"
    return "1루 주자"


def live_caption(state: dict) -> str:
    """relay current_state → 짧은 상황 한 줄. 경기 외/데이터 부족이면 빈 문자열."""
    inning = state.get("inning") or state.get("current_inning") or 0
    if not inning:
        return ""
    half = state.get("half") or state.get("inning_half") or ""
    out = state.get("out", 0) or 0
    b1 = bool(state.get("base1"))
    b2 = bool(state.get("base2"))
    b3 = bool(state.get("base3"))
    hs = state.get("home_score", 0) or 0
    as_ = state.get("away_score", 0) or 0
    diff = abs(hs - as_)

    runners = _runners_phrase(b1, b2, b3)
    situation = f"{inning}회{half} {out}사 {runners}"

    if diff == 0:
        tone = "동점 승부"
    elif diff <= 1:
        tone = "1점차 접전"
    elif diff <= 3:
        tone = f"{diff}점차"
    else:
        tone = f"{diff}점차 리드"
    return f"{situation}, {tone}"
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd backend && JWT_SECRET_KEY=x LOG_DIR=/tmp/pblogs python3 -m pytest tests/test_narrative.py -v`
Expected: PASS (11 passed)

- [ ] **Step 5: 커밋**

```bash
git add backend/api/narrative.py backend/tests/test_narrative.py
git commit -m "feat(narrative): 내러티브 엔진 코어 + 테스트 (메가E)"
```

---

### Task 2: game_reviews 테이블

**Files:**
- Modify (서버 DB): 직접 psql 실행 (마이그레이션 파일 없는 프로젝트 — ad-hoc DDL + GRANT 패턴)
- Create: `backend/database/migrations/2026-06-15_game_reviews.sql` (기록용, 재구축 시 재적용)

- [ ] **Step 1: DDL 파일 작성** — `backend/database/migrations/2026-06-15_game_reviews.sql`

```sql
CREATE TABLE IF NOT EXISTS game_reviews (
    game_id        INT PRIMARY KEY REFERENCES games(id) ON DELETE CASCADE,
    review_text    TEXT,
    mvp_player_id  INT REFERENCES players(id) ON DELETE SET NULL,
    mvp_name       TEXT,
    mvp_line       TEXT,
    created_at     TIMESTAMPTZ DEFAULT now()
);
GRANT ALL ON game_reviews TO playball_user;
```

- [ ] **Step 2: 서버에 적용**

Run:
```bash
ssh -i "<key>" ubuntu@168.107.36.158 'sudo -u postgres psql -d playball -f -' < backend/database/migrations/2026-06-15_game_reviews.sql
```
(또는 파일 내용을 psql heredoc로 실행)
Expected: `CREATE TABLE` + `GRANT`

- [ ] **Step 3: 적용 검증**

Run: `ssh ... 'sudo -u postgres psql -d playball -c "\d game_reviews"'`
Expected: 6 컬럼 출력, game_id PK

- [ ] **Step 4: 커밋**

```bash
git add backend/database/migrations/2026-06-15_game_reviews.sql
git commit -m "feat(db): game_reviews 테이블 (메가E 한줄평/MVP 영속)"
```

---

### Task 3: WPA MVP + _send_game_summary 통합 + notify_game_summary review_text

**Files:**
- Modify: `backend/crawler/scheduler.py` (`_send_game_summary`, ~1095-1167)
- Modify: `backend/api/fcm_service.py` (`notify_game_summary`)

- [ ] **Step 1: notify_game_summary에 review_text 파라미터 추가**

`fcm_service.py`의 `notify_game_summary` 시그니처 끝에 `review_text: str = ""` 추가.
함수 내 푸시 body 조립부에서, `review_text`가 있으면 그것을 body로 사용 (없으면 기존 조립 유지):

```python
def notify_game_summary(game_id, home_team, away_team, home_score, away_score,
                        home_team_id, away_team_id, *, win_pitcher="", win_ip="",
                        win_er=0, loss_pitcher="", hold_pitcher="", save_pitcher="",
                        mvp_name="", mvp_hits=0, mvp_hr=0, mvp_rbi=0,
                        review_text=""):
    ...
    # body 조립 직전:
    body = review_text if review_text else <기존 조립 로직 결과>
    ...
```
(기존 조립 로직은 그대로 두고, 최종 body 변수를 review_text로 오버라이드)

- [ ] **Step 2: _send_game_summary에 WPA MVP 쿼리 추가**

`_send_game_summary`의 mvp_row 쿼리(~1135-1144) **다음에** WPA MVP 쿼리 추가.
WPA는 홈 기준(0~100) → 원정 타자는 부호 반전. 승팀에서 |Σ(after-before)| 최대:

```python
        # WPA 기반 MVP (plate_appearances) — 승팀 최대 기여 타자
        cur.execute("""
            SELECT pa.batter_name,
                   SUM(CASE WHEN pa.inning_half = '말'
                            THEN (pa.win_rate_after - pa.win_rate_before)
                            ELSE -(pa.win_rate_after - pa.win_rate_before) END) AS wpa
            FROM plate_appearances pa
            WHERE pa.game_id = %s
              AND pa.win_rate_before IS NOT NULL
              AND pa.win_rate_after IS NOT NULL
              AND pa.inning_half = %s
            GROUP BY pa.batter_name
            ORDER BY wpa DESC
            LIMIT 1
        """, (game_id, '말' if winner_side == 'home' else '초'))
        wpa_row = cur.fetchone()
```
(설명: 승팀이 home이면 '말' 타석만 보고 그대로, away면 '초' 타석을 보고 부호 반전.
위 CASE는 홈기준이라 '초' 그룹에선 -(after-before)가 원정팀 관점 +WPA가 됨.)

WPA MVP 있으면 그 선수의 game_batters 라인으로 mvp 구성, 없으면 기존 mvp_row 폴백.

- [ ] **Step 3: facts 조립 + narrative 호출 + game_reviews 저장**

`_send_game_summary`에서 game_event_stream으로 walkoff/extra_innings 플래그 조회:

```python
        cur.execute("""
            SELECT type FROM game_event_stream
            WHERE game_id = %s AND type IN ('walkoff', 'extra_innings')
        """, (game_id,))
        flags = {r[0] for r in cur.fetchall()}
```

mvp 선정(WPA 우선, 폴백 rbis)을 mvp_name/mvp_hits/mvp_hr/mvp_rbi/mvp_player_id로 정리한 뒤:

```python
    from api.narrative import game_review, mvp_line as _mvp_line
    mvp_l = _mvp_line({"hits": mvp_hits, "home_runs": mvp_hr, "rbis": mvp_rbi}) if mvp_name else ""
    review = game_review({
        "home_team": home_team, "away_team": away_team,
        "home_score": home_score, "away_score": away_score,
        "win_pitcher": win_pitcher, "save_pitcher": save_pitcher,
        "mvp_name": mvp_name, "mvp_line": mvp_l,
        "walkoff": "walkoff" in flags, "extra_innings": "extra_innings" in flags,
    })
    # game_reviews 저장 (실패 격리 — 푸시는 계속)
    try:
        c2 = get_connection()
        if c2:
            cur2 = c2.cursor()
            cur2.execute("""
                INSERT INTO game_reviews (game_id, review_text, mvp_player_id, mvp_name, mvp_line)
                VALUES (%s,%s,%s,%s,%s)
                ON CONFLICT (game_id) DO UPDATE SET
                  review_text=EXCLUDED.review_text, mvp_player_id=EXCLUDED.mvp_player_id,
                  mvp_name=EXCLUDED.mvp_name, mvp_line=EXCLUDED.mvp_line, created_at=now()
            """, (game_id, review, mvp_player_id, mvp_name, mvp_l))
            c2.commit(); cur2.close(); c2.close()
    except Exception as e:
        print(f"[narrative] game_reviews 저장 오류 game={game_id}: {e}")
```

`notify_game_summary(...)` 호출에 `review_text=review` 추가.

- [ ] **Step 4: 서버 py_compile + pytest**

Run: `ssh ... 'cd ~/playball && git pull && python3 -m py_compile backend/crawler/scheduler.py backend/api/fcm_service.py backend/api/narrative.py'`
Expected: 오류 없음

- [ ] **Step 5: 커밋**

```bash
git add backend/crawler/scheduler.py backend/api/fcm_service.py
git commit -m "feat(narrative): 종료 한줄평+WPA MVP를 game_summary에 통합"
```

---

### Task 4: relay 라이브 캡션 주입

**Files:**
- Modify: `backend/api/routers/games.py` (relay 엔드포인트의 field_view/current_state 조립부)

- [ ] **Step 1: 캡션 주입 위치 확인**

`games.py`에서 relay 응답의 `current_state` 또는 `field_view` dict를 만드는 곳을 찾는다
(grep `current_state` / `field_view`).

- [ ] **Step 2: live_caption 주입**

current_state(또는 field_view)에 base1~3/out/inning/score가 있는 dict를 narrative에 전달:

```python
from api.narrative import live_caption
# field_view 조립 직후:
try:
    field_view["situation_caption"] = live_caption({
        "inning": current_inning, "half": inning_half, "out": out_count,
        "base1": base1, "base2": base2, "base3": base3,
        "home_score": home_score, "away_score": away_score,
    })
except Exception:
    field_view["situation_caption"] = ""
```
(실제 변수명은 해당 함수 컨텍스트에 맞춰 매핑 — 진행 중 경기만 호출됨)

- [ ] **Step 3: 서버 py_compile + 라이브 검증(선택)**

Run: `python3 -m py_compile backend/api/routers/games.py`
진행 중 경기 있으면: `curl .../games/<id>/relay | grep situation_caption`

- [ ] **Step 4: 커밋**

```bash
git add backend/api/routers/games.py
git commit -m "feat(narrative): relay field_view에 라이브 상황 캡션 주입"
```

---

### Task 5: game detail에 review join

**Files:**
- Modify: `backend/api/routers/games.py` (game detail 엔드포인트 `/games/{id}`)

- [ ] **Step 1: review 조회 추가**

game detail 응답 dict에 game_reviews LEFT JOIN 결과를 `review` 키로 추가:

```python
    cur.execute("""
        SELECT review_text, mvp_name, mvp_line FROM game_reviews WHERE game_id = %s
    """, (game_id,))
    _rv = cur.fetchone()
    result["review"] = ({
        "text": _rv[0], "mvp_name": _rv[1], "mvp_line": _rv[2]
    } if _rv else None)
```
(result = game detail 응답 dict 이름에 맞춰 매핑)

- [ ] **Step 2: py_compile**

Run: `python3 -m py_compile backend/api/routers/games.py`

- [ ] **Step 3: 커밋**

```bash
git add backend/api/routers/games.py
git commit -m "feat(narrative): game detail 응답에 review(한줄평+MVP) 포함"
```

---

### Task 6: 클라이언트 — 배지·MVP칩·캡션 + 킬스위치

**Files:**
- Modify: `app/lib/screens/game/game_detail_screen.dart` (상단 review 배지 + MVP칩, 필드뷰 캡션)
- Modify: `backend/api/routers/admin.py`(또는 FEATURES 정의처) — FEATURES에 `narrative` 추가
- 확인: `app/lib/...AppConfig.enabled` 가드 사용처 패턴

- [ ] **Step 1: backend FEATURES에 narrative 추가**

admin feature-flags의 FEATURES 리스트(grep `FEATURES`)에 `"narrative"` 추가.

- [ ] **Step 2: game_detail 상단 한줄평 배지 + MVP칩**

game detail 데이터(`_gameData`)에서 `review`를 읽어, 필드뷰 위(또는 스코어보드 아래)에
`AppConfig.enabled('narrative')` && review!=null 일 때만 배지 렌더:

```dart
if (AppConfig.enabled('narrative') && review != null && (review['text'] as String?）?.isNotEmpty == true)
  Container(  // 한줄평 배지
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Row(children: [
      const Icon(Icons.auto_awesome, size: 14),
      const SizedBox(width: 6),
      Expanded(child: Text(review['text'], style: ...)),
    ]),
  ),
// MVP 칩: review['mvp_name'] != null 일 때 "오늘의 MVP {name} {line}"
```
(정확한 위치·스타일은 game_detail 기존 카드 패턴 따름)

- [ ] **Step 3: 필드뷰 라이브 캡션**

필드뷰 위젯에서 relay `field_view['situation_caption']`을 읽어
`AppConfig.enabled('narrative')` && 비어있지 않을 때 한 줄 표시.

- [ ] **Step 4: flutter analyze**

Run: `cd app && flutter analyze lib/screens/game/game_detail_screen.dart`
Expected: No issues

- [ ] **Step 5: 커밋**

```bash
git add app/lib/screens/game/game_detail_screen.dart backend/api/routers/admin.py
git commit -m "feat(narrative): 경기상세 한줄평 배지·MVP칩·라이브 캡션 + narrative 킬스위치"
```

---

### Task 7: 배포 + 검증

- [ ] **Step 1: 서버 배포**

```bash
ssh ... 'cd ~/playball && git pull origin main --rebase && python3 -m py_compile backend/api/narrative.py backend/crawler/scheduler.py backend/api/fcm_service.py backend/api/routers/games.py && sudo systemctl restart playball && sudo systemctl restart playball-scheduler'
```

- [ ] **Step 2: 서버 pytest (scratch DB)**

오늘 패턴: playball_test 생성 → `pytest tests -v` → drop. test_narrative 11 + 기존 7 통과.

- [ ] **Step 3: smoke**

Run: `ssh ... 'bash ~/playball/scripts/smoke.sh'`
Expected: ALL PASS

- [ ] **Step 4: 웹 재빌드+배포** (클라 변경 동반 — CLAUDE.md 원칙)

```bash
cd app && MSYS_NO_PATHCONV=1 flutter build web --wasm --release --base-href "/app/" --no-web-resources-cdn --pwa-strategy=none
# tar → scp → /var/www/playball_web 클린 교체 → HTTPS 200 확인
```

- [ ] **Step 5: CI 확인**

`gh run list` — backend-test job(test_narrative 포함) green.

---

## Self-Review

- **Spec coverage**: narrative.py(T1)·game_reviews(T2)·WPA MVP+한줄평 통합(T3)·라이브 캡션(T4)·game detail review(T5)·클라 배지/칩/캡션+킬스위치(T6)·배포/검증(T7). spec 7항목 전부 매핑됨.
- **Placeholder**: 통합 태스크(3·4·5·6)는 기존 함수 수정이라 정확한 변수명은 실행 시 해당 파일 grep로 핀. 추가 코드·SQL·위치는 구체 명시. narrative.py·테스트·DDL은 완전 코드.
- **Type consistency**: game_review/live_caption/mvp_line 시그니처 T1 정의와 T3·T4 호출 일치. review 키(text/mvp_name/mvp_line) T5 생성 ↔ T6 소비 일치. review_text 파라미터 T3 fcm ↔ scheduler 일치.
- **WPA 부호**: 홈기준 CASE에서 winner=home→'말' 그대로, winner=away→'초' 그룹에 -(after-before) 적용해 원정 +WPA. (검증 = 라이브/백필 데이터로 확인)

## 참고 (실행 시 grep으로 핀할 것)
- `notify_game_summary` body 조립부 (fcm_service.py)
- relay current_state/field_view 변수명 (games.py)
- game detail 응답 dict 이름 (games.py)
- admin FEATURES 리스트 위치
- AppConfig.enabled 가드 기존 사용처 (game_detail 내 win_prob/bullpen 가드 패턴 복사)
