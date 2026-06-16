# 역대 데이터 UI 노출 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 적재된 역대(1982~) 선수 데이터(`historical_*`)를 통합검색·현역통산·은퇴상세·역대탭으로 앱/웹에 노출.

**Architecture:** Backend = 신규 `historical.py` 라우터(은퇴 상세 + 명예의전당 리더) + 기존 `/players/search` UNION + `/players/{id}` 역대시즌 머지. App = 통합검색 배지/라우팅 + 현역상세 시즌칩 확장(재사용) + 신규 `historical_player_detail_screen` + 역대탭. 정규시즌 = `series_type='정규'` 필터 일관 적용.

**Tech Stack:** FastAPI(psycopg2, 인메모리 `@cached`) · Flutter(dio, Provider) · PostgreSQL · pytest(scratch DB `playball_test`).

**Spec:** `docs/superpowers/specs/2026-06-16-historical-data-ui-design.md`

---

## File Structure

- `backend/api/routers/historical.py` (Create) — `/historical/{kbo_player_id}` 상세, `/historical/leaders`, 공용 집계 헬퍼(`_aggregate_career`, `_ip_to_outs`/`_outs_to_ip`).
- `backend/api/main.py` (Modify) — historical 라우터 등록.
- `backend/api/routers/players.py` (Modify) — `/search` UNION historical, `/{id}` 머지.
- `backend/tests/test_historical_ui.py` (Create) — career 집계·ip 변환 순수 테스트 + (DB) search union/상세.
- `app/lib/api/api_service.dart` (Modify) — `getHistoricalPlayer`, `getHistoricalLeaders`.
- `app/lib/screens/player/player_screen.dart` (Modify) — 검색결과 '역대' 배지·라우팅, 역대 탭.
- `app/lib/screens/player/historical_player_detail_screen.dart` (Create) — 은퇴선수 상세.
- `app/lib/screens/player/historical_leaders_screen.dart` (Create) — 명예의전당 리더보드.
- `app/lib/screens/player/player_detail_screen.dart` (Modify) — 수상 섹션(머지된 `awards` 렌더, 있으면).

---

## PHASE 1 — Backend 토대

### Task 1: 역대 집계 헬퍼 + 순수 테스트 (TDD)

**Files:**
- Create: `backend/api/routers/historical.py`
- Test: `backend/tests/test_historical_ui.py`

- [ ] **Step 1: Write the failing test**

```python
# backend/tests/test_historical_ui.py
from api.routers.historical import _ip_to_outs, _outs_to_ip, _aggregate_career


def test_ip_outs_roundtrip():
    # KBO 표기 6.1 = 6⅓이닝 = 19 아웃, 6.2 = 6⅔ = 20
    assert _ip_to_outs(6.1) == 19
    assert _ip_to_outs(6.2) == 20
    assert _ip_to_outs(7.0) == 21
    assert _outs_to_ip(19) == 6.1
    assert _outs_to_ip(20) == 6.2
    assert _outs_to_ip(21) == 7.0


def test_aggregate_career_batter():
    rows = [
        {"player_type": "타자", "at_bats": 100, "hits": 30, "doubles": 5,
         "triples": 1, "home_runs": 4, "walks": 10, "hbp": 2, "sac_flies": 1,
         "rbis": 20, "runs": 18, "strikeouts": 15, "stolen_bases": 3},
        {"player_type": "타자", "at_bats": 200, "hits": 50, "doubles": 8,
         "triples": 0, "home_runs": 10, "walks": 20, "hbp": 3, "sac_flies": 2,
         "rbis": 40, "runs": 35, "strikeouts": 30, "stolen_bases": 5},
    ]
    c = _aggregate_career(rows)
    assert c["at_bats"] == 300
    assert c["hits"] == 80
    assert c["home_runs"] == 14
    assert c["avg"] == round(80 / 300, 3)
    # tb = hits + doubles + 2*triples + 3*hr = 80 + 13 + 2 + 42 = 137
    assert c["slg"] == round(137 / 300, 3)


def test_aggregate_career_pitcher():
    rows = [
        {"player_type": "투수", "innings_pitched": 6.1, "earned_runs": 2,
         "hits_allowed": 5, "walks_allowed": 1, "strikeouts_pitched": 7,
         "wins": 1, "losses": 0, "saves": 0, "holds": 0},
        {"player_type": "투수", "innings_pitched": 6.2, "earned_runs": 3,
         "hits_allowed": 6, "walks_allowed": 2, "strikeouts_pitched": 5,
         "wins": 0, "losses": 1, "saves": 0, "holds": 0},
    ]
    c = _aggregate_career(rows)
    # outs 19+20=39 → 13.0 이닝
    assert c["innings_pitched"] == 13.0
    assert c["wins"] == 1
    assert c["strikeouts_pitched"] == 12
    # era = 5*9 / 13.0
    assert c["era"] == round(5 * 9 / 13.0, 2)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && python -m pytest tests/test_historical_ui.py -v`
Expected: FAIL — `ModuleNotFoundError`/`ImportError: cannot import name '_ip_to_outs'`

- [ ] **Step 3: Write minimal implementation**

```python
# backend/api/routers/historical.py
from fastapi import APIRouter, HTTPException
from database.connection import get_connection
from api.cache import cached

router = APIRouter()


def _ip_to_outs(ip) -> int:
    """KBO 표기 이닝(6.1=6⅓) → 아웃수. .1=+1, .2=+2."""
    if ip is None:
        return 0
    ip = float(ip)
    whole = int(ip)
    frac = round((ip - whole) * 10)
    return whole * 3 + frac


def _outs_to_ip(outs: int) -> float:
    """아웃수 → KBO 표기 이닝."""
    return round(outs // 3 + (outs % 3) * 0.1, 1)


def _aggregate_career(rows: list[dict]) -> dict:
    """정규시즌 행들 통산 합산. 카운팅=합, 비율=원자료 재계산."""
    if not rows:
        return {}
    ptype = rows[0].get("player_type")
    out: dict = {"player_type": ptype}
    if ptype == "타자":
        keys = ["games", "pa", "at_bats", "runs", "hits", "doubles", "triples",
                "home_runs", "rbis", "walks", "hbp", "intentional_walks",
                "strikeouts", "stolen_bases", "caught_stealing", "gdp",
                "sac_hits", "sac_flies"]
        for k in keys:
            out[k] = sum((r.get(k) or 0) for r in rows)
        ab, h = out["at_bats"], out["hits"]
        tb = h + out["doubles"] + 2 * out["triples"] + 3 * out["home_runs"]
        obp_den = ab + out["walks"] + out["hbp"] + out["sac_flies"]
        out["avg"] = round(h / ab, 3) if ab else 0
        out["obp"] = round((h + out["walks"] + out["hbp"]) / obp_den, 3) if obp_den else 0
        out["slg"] = round(tb / ab, 3) if ab else 0
        out["ops"] = round(out["obp"] + out["slg"], 3)
    else:
        keys = ["games", "wins", "losses", "saves", "holds", "hits_allowed",
                "runs_allowed", "earned_runs", "walks_allowed", "hbp_allowed",
                "strikeouts_pitched", "home_runs_allowed", "qs",
                "complete_games", "shutouts"]
        for k in keys:
            out[k] = sum((r.get(k) or 0) for r in rows)
        outs = sum(_ip_to_outs(r.get("innings_pitched")) for r in rows)
        ip = _outs_to_ip(outs)
        out["innings_pitched"] = ip
        ip_full = outs / 3 if outs else 0
        out["era"] = round(out["earned_runs"] * 9 / ip_full, 2) if ip_full else 0
        out["whip"] = round((out["walks_allowed"] + out["hits_allowed"]) / ip_full, 2) if ip_full else 0
    return out
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && python -m pytest tests/test_historical_ui.py -v`
Expected: PASS (3 passed)

- [ ] **Step 5: Commit**

```bash
git add backend/api/routers/historical.py backend/tests/test_historical_ui.py
git commit -m "feat(historical): career 집계 헬퍼 + ip 변환 (역대UI P1)"
```

---

### Task 2: `/historical/{kbo_player_id}` 상세 엔드포인트

**Files:**
- Modify: `backend/api/routers/historical.py`
- Modify: `backend/api/main.py:5,184` (라우터 import + 등록)

- [ ] **Step 1: Add endpoint to historical.py**

`historical.py` 끝에 추가:

```python
def _stat_row(r: dict) -> dict:
    """historical_season_stats 행 dict → 표시용(타자/투수 분기). psycopg2 RealDict 가정."""
    return r  # RealDictCursor라 컬럼명 그대로. NUMERIC은 float 변환만 아래서.


@router.get("/{kbo_player_id}")
@cached(600)
def get_historical_player(kbo_player_id: int):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    # bio
    cur.execute("""
        SELECT hp.kbo_player_id, hp.player_id, hp.name, hp.player_type,
               hp.birth_date, hp.height, hp.weight, hp.throws, hp.bats,
               hp.position, hp.career, hp.draft_info, hp.debut_year, hp.final_year,
               hp.profile_image, hp.primary_team_id, t.name AS team, t.short_name AS team_code
        FROM historical_players hp
        LEFT JOIN teams t ON t.id = hp.primary_team_id
        WHERE hp.kbo_player_id = %s
    """, (kbo_player_id,))
    p = cur.fetchone()
    if not p:
        cur.close(); conn.close()
        raise HTTPException(status_code=404, detail="역대 선수를 찾을 수 없습니다")
    (kid, pid, name, ptype, birth, height, weight, throws, bats, position,
     career, draft, debut, final, img, prim_tid, team, team_code) = p

    def fnum(v):
        return float(v) if v is not None else None

    # 시즌 스탯 (정규만), 컬럼 광범위 → 동적 dict
    cur.execute("""
        SELECT season, team_name, player_type, games, pa, at_bats, runs, hits,
               doubles, triples, home_runs, rbis, walks, hbp, intentional_walks,
               strikeouts, stolen_bases, caught_stealing, gdp, sac_hits, sac_flies,
               avg, obp, slg, ops,
               wins, losses, saves, holds, innings_pitched, hits_allowed,
               runs_allowed, earned_runs, walks_allowed, hbp_allowed,
               strikeouts_pitched, home_runs_allowed, era, whip, qs,
               complete_games, shutouts, war, woba, wrc_plus, fip
        FROM historical_season_stats
        WHERE kbo_player_id = %s AND series_type = '정규'
        ORDER BY season DESC, team_name
    """, (kbo_player_id,))
    cols = [c[0] for c in cur.description]
    NUMERIC = {'avg','obp','slg','ops','innings_pitched','era','whip','war','woba','fip'}
    stats = []
    for row in cur.fetchall():
        d = dict(zip(cols, row))
        for k in NUMERIC:
            d[k] = fnum(d.get(k))
        stats.append(d)

    # 포스트시즌 (있으면)
    cur.execute("""
        SELECT season, series_type, team_name, player_type, games,
               at_bats, hits, home_runs, rbis, avg,
               innings_pitched, earned_runs, strikeouts_pitched, era
        FROM historical_season_stats
        WHERE kbo_player_id = %s AND series_type <> '정규'
        ORDER BY season DESC
    """, (kbo_player_id,))
    pcols = [c[0] for c in cur.description]
    postseason = [dict(zip(pcols, r)) for r in cur.fetchall()]
    for ps in postseason:
        for k in ('avg', 'innings_pitched', 'era'):
            ps[k] = fnum(ps.get(k))

    # 수상
    cur.execute("""
        SELECT season, award FROM historical_awards
        WHERE kbo_player_id = %s ORDER BY season DESC NULLS LAST, award
    """, (kbo_player_id,))
    awards = [{"season": r[0], "award": r[1]} for r in cur.fetchall()]

    # 스플릿 (있으면, 축별 그룹)
    cur.execute("""
        SELECT split_axis, split_value, season, games, pa, at_bats, hits,
               home_runs, rbis, avg, slg
        FROM historical_splits
        WHERE kbo_player_id = %s
        ORDER BY season DESC, split_axis, split_value
    """, (kbo_player_id,))
    splits: dict = {}
    for r in cur.fetchall():
        axis = r[0]
        splits.setdefault(axis, []).append({
            "value": r[1], "season": r[2], "games": r[3], "pa": r[4],
            "at_bats": r[5], "hits": r[6], "home_runs": r[7], "rbis": r[8],
            "avg": fnum(r[9]), "slg": fnum(r[10]),
        })

    # franchise 계보 (primary_team 기준 — 표시용)
    franchise_path = []
    if prim_tid:
        cur.execute("""
            SELECT team_name, start_year, end_year FROM team_franchises
            WHERE current_team_id = %s ORDER BY start_year
        """, (prim_tid,))
        franchise_path = [
            {"team_name": r[0], "start_year": r[1], "end_year": r[2]}
            for r in cur.fetchall()
        ]

    cur.close(); conn.close()
    career = _aggregate_career([s for s in stats]) if stats else {}
    return {
        "bio": {
            "kbo_player_id": kid, "player_id": pid, "name": name,
            "player_type": ptype, "birth_date": str(birth) if birth else None,
            "height": height, "weight": weight, "throws": throws, "bats": bats,
            "position": position, "career": career and career.get and None or career_str(career),
            "career_text": career_text(career_raw=career, raw=career),
            "draft_info": draft, "debut_year": debut, "final_year": final,
            "profile_image": img, "team": team, "team_code": team_code,
            "is_active": pid is not None,
        },
        "stats": stats,
        "career": career,
        "postseason": postseason,
        "awards": awards,
        "splits": splits,
        "franchise_path": franchise_path,
    }
```

> ⚠️ 위 `bio.career`/`career_text` 줄은 의도적 오류 유도(다음 스텝서 교체). 변수명 충돌(`career` = 경력 텍스트 컬럼 vs `_aggregate_career` 결과)을 드러내기 위함.

- [ ] **Step 2: Fix the career naming collision**

`career`(경력 텍스트 컬럼)와 통산 집계 결과가 이름 충돌. 통산 결과 변수명을 `career_totals`로 변경:

```python
    cur.close(); conn.close()
    career_totals = _aggregate_career(stats) if stats else {}
    return {
        "bio": {
            "kbo_player_id": kid, "player_id": pid, "name": name,
            "player_type": ptype, "birth_date": str(birth) if birth else None,
            "height": height, "weight": weight, "throws": throws, "bats": bats,
            "position": position, "career_text": career, "draft_info": draft,
            "debut_year": debut, "final_year": final, "profile_image": img,
            "team": team, "team_code": team_code, "is_active": pid is not None,
        },
        "stats": stats,
        "career": career_totals,
        "postseason": postseason,
        "awards": awards,
        "splits": splits,
        "franchise_path": franchise_path,
    }
```

(앞 Step 1 블록의 `return` 중 `"career": ...` 줄들과 `bio.career`/`career_text` 두 줄을 이 블록으로 통째 교체.)

- [ ] **Step 3: Register router in main.py**

`backend/api/main.py` line 5 import에 `historical` 추가:

```python
from api.routers import games, players, teams, auth, user, stadiums, widget, community, calendar, phone, email_verify, password_reset, search, news, prediction, app_config, admin, historical
```

line 184 부근(`bootstrap` 등록 뒤)에 추가:

```python
app.include_router(historical.router, prefix="/historical", tags=["역대"])
```

- [ ] **Step 4: 구문 검증**

Run: `cd backend && python -c "import api.main"`
Expected: 에러 없음 (import 성공). orjson deprecation 경고 1회는 정상.

- [ ] **Step 5: Commit**

```bash
git add backend/api/routers/historical.py backend/api/main.py
git commit -m "feat(historical): 은퇴선수 상세 엔드포인트 (역대UI P1)"
```

---

### Task 3: `/historical/leaders` 명예의전당 엔드포인트

**Files:**
- Modify: `backend/api/routers/historical.py`

- [ ] **Step 1: Add leaders endpoint**

`historical.py` 에 추가 (라우트 순서 주의 — `/{kbo_player_id}`보다 **먼저** 선언해야 `leaders`가 정수 경로로 안 먹힘):

> ⚠️ FastAPI 경로 우선순위: `/leaders`를 `/{kbo_player_id}` **위에** 배치. (CLAUDE.md user.py 라우트순서 규칙과 동일.)

```python
# 통산 리더 카테고리 → (player_type, 컬럼, 내림차순?, 규정 필요?)
_LEADER_CATS = {
    "home_runs":  ("타자", "home_runs", True, False),
    "hits":       ("타자", "hits", True, False),
    "stolen_bases": ("타자", "stolen_bases", True, False),
    "rbis":       ("타자", "rbis", True, False),
    "wins":       ("투수", "wins", True, False),
    "strikeouts_pitched": ("투수", "strikeouts_pitched", True, False),
    "saves":      ("투수", "saves", True, False),
}


@router.get("/leaders")
@cached(3600)
def get_historical_leaders(category: str = "home_runs", limit: int = 20):
    if category not in _LEADER_CATS:
        raise HTTPException(status_code=400, detail="알 수 없는 카테고리")
    ptype, col, desc, _qual = _LEADER_CATS[category]
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    # 통산 합산(정규만) → 카운팅 컬럼 SUM
    cur.execute(f"""
        SELECT hp.kbo_player_id, hp.name, hp.player_id,
               t.short_name AS team_code, t.name AS team,
               SUM(COALESCE(hss.{col}, 0)) AS total
        FROM historical_season_stats hss
        JOIN historical_players hp ON hp.kbo_player_id = hss.kbo_player_id
        LEFT JOIN teams t ON t.id = hp.primary_team_id
        WHERE hss.series_type = '정규' AND hss.player_type = %s
        GROUP BY hp.kbo_player_id, hp.name, hp.player_id, t.short_name, t.name
        ORDER BY total {'DESC' if desc else 'ASC'}
        LIMIT %s
    """, (ptype, limit))
    rows = cur.fetchall()
    cur.close(); conn.close()
    return {
        "category": category,
        "leaders": [
            {"kbo_player_id": r[0], "name": r[1], "is_active": r[2] is not None,
             "team_code": r[3], "team": r[4], "value": int(r[5] or 0)}
            for r in rows
        ],
    }
```

- [ ] **Step 2: 구문 검증 + 라우트 순서 확인**

Run: `cd backend && python -c "import api.main; from api.routers.historical import router; print([r.path for r in router.routes])"`
Expected: `/leaders`가 `/{kbo_player_id}` 보다 앞에 출력.

- [ ] **Step 3: Commit**

```bash
git add backend/api/routers/historical.py
git commit -m "feat(historical): 명예의전당 통산 리더 엔드포인트 (역대UI P1)"
```

---

### Task 4: `/players/search` UNION + `/players/{id}` 역대 머지

**Files:**
- Modify: `backend/api/routers/players.py:9-46` (search), `players.py:958-1183` (detail)

- [ ] **Step 1: search 확장 — historical UNION**

`search_players`(players.py:10) 의 본문을 교체. 현역 결과(기존) + 은퇴(브릿지 없는 historical) 추가:

```python
@router.get("/search")
def search_players(q: str, player_type: str = None):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    # ── 현역 (players) ──
    pt_sql = " AND p.player_type = %s" if player_type else ""
    pt_params = [player_type] if player_type else []
    cur.execute(f"""
        SELECT p.id, p.name, t.name AS team, p.player_type,
               p.position, p.number, p.profile_image, p.throws, p.bats,
               t.short_name AS team_code
        FROM players p JOIN teams t ON p.team_id = t.id
        WHERE p.name LIKE %s{pt_sql}
        ORDER BY p.name LIMIT 20
    """, [f"%{q}%"] + pt_params)
    active = [
        {"id": r[0], "name": r[1], "team": r[2], "player_type": r[3],
         "position": r[4], "number": r[5], "profile_image": r[6],
         "throws": r[7], "bats": r[8], "team_code": r[9],
         "key_type": "active", "is_historical": False}
        for r in cur.fetchall()
    ]
    # ── 은퇴 (historical_players, 현역 브릿지 없는 사람만) ──
    hpt_sql = " AND hp.player_type = %s" if player_type else ""
    cur.execute(f"""
        SELECT hp.kbo_player_id, hp.name, t.name AS team, hp.player_type,
               hp.position, hp.profile_image, hp.debut_year, hp.final_year,
               t.short_name AS team_code
        FROM historical_players hp
        LEFT JOIN teams t ON t.id = hp.primary_team_id
        WHERE hp.name LIKE %s AND hp.player_id IS NULL{hpt_sql}
        ORDER BY hp.final_year DESC NULLS LAST, hp.name LIMIT 20
    """, [f"%{q}%"] + pt_params)
    historical = [
        {"id": r[0], "name": r[1], "team": r[2] or "역대", "player_type": r[3],
         "position": r[4], "number": None, "profile_image": r[5],
         "debut_year": r[6], "final_year": r[7],
         "years": (f"{r[6]}~{r[7]}" if r[6] and r[7] else None),
         "team_code": r[8], "key_type": "historical", "is_historical": True}
        for r in cur.fetchall()
    ]
    cur.close(); conn.close()
    return {"players": active + historical}
```

- [ ] **Step 2: detail 머지 — historical 시즌 + 수상**

`get_player_detail`(players.py:958) 의 `result["roster_status"] = ...` 블록 **앞**(cur.close 전)에 삽입:

```python
    # ── 역대(2023↓) 시즌 + 수상 머지 (현역 브릿지 있을 때) ──
    cur.execute("SELECT kbo_player_id FROM historical_players WHERE player_id = %s", (player_id,))
    hp = cur.fetchone()
    if hp:
        kid = hp[0]
        if player[2] == "타자":
            cur.execute("""
                SELECT season, games, at_bats, runs, hits, doubles, triples,
                    home_runs, rbis, walks, strikeouts, stolen_bases,
                    avg, obp, slg, ops, war, woba, wrc_plus, NULL AS babip,
                    NULL AS iso, pa, hbp
                FROM historical_season_stats
                WHERE kbo_player_id = %s AND series_type = '정규' AND season < 2024
                ORDER BY season DESC
            """, (kid,))
            for r in cur.fetchall():
                result["stats"].append({
                    "season": r[0], "games": r[1], "at_bats": r[2], "runs": r[3],
                    "hits": r[4], "doubles": r[5], "triples": r[6], "home_runs": r[7],
                    "rbis": r[8], "walks": r[9], "strikeouts": r[10], "stolen_bases": r[11],
                    "avg": float(r[12]) if r[12] else 0, "obp": float(r[13]) if r[13] else 0,
                    "slg": float(r[14]) if r[14] else 0, "ops": float(r[15]) if r[15] else 0,
                    "war": float(r[16]) if r[16] else 0, "woba": float(r[17]) if r[17] else 0,
                    "wrc_plus": r[18], "pa": r[21], "hbp": r[22], "historical": True,
                })
        else:
            cur.execute("""
                SELECT season, games, wins, losses, saves, holds,
                    innings_pitched, hits_allowed, runs_allowed, earned_runs,
                    walks_allowed, strikeouts_pitched, home_runs_allowed,
                    era, whip, war, fip, qs, complete_games, shutouts
                FROM historical_season_stats
                WHERE kbo_player_id = %s AND series_type = '정규' AND season < 2024
                ORDER BY season DESC
            """, (kid,))
            for r in cur.fetchall():
                result["stats"].append({
                    "season": r[0], "games": r[1], "wins": r[2], "losses": r[3],
                    "saves": r[4], "holds": r[5],
                    "innings_pitched": float(r[6]) if r[6] else 0,
                    "hits_allowed": r[7], "runs_allowed": r[8], "earned_runs": r[9],
                    "walks": r[10], "strikeouts": r[11], "home_runs_allowed": r[12],
                    "era": float(r[13]) if r[13] else 0, "whip": float(r[14]) if r[14] else 0,
                    "war": float(r[15]) if r[15] else 0, "fip": float(r[16]) if r[16] else 0,
                    "qs": r[17], "cg": r[18], "sho": r[19], "historical": True,
                })
        # season DESC 재정렬 (현역 24~26 + 역대 ~23 혼합)
        result["stats"].sort(key=lambda s: -(s["season"] or 0))
        cur.execute("""
            SELECT season, award FROM historical_awards
            WHERE kbo_player_id = %s ORDER BY season DESC NULLS LAST, award
        """, (kid,))
        result["awards"] = [{"season": a[0], "award": a[1]} for a in cur.fetchall()]
```

> ⚠️ 컬럼 키 매핑: 투수 `walks_allowed`→`walks`, `strikeouts_pitched`→`strikeouts`, `complete_games`→`cg`, `shutouts`→`sho` (앱 시즌그리드 키와 일치). 타자는 batter_stats 키와 동일 컬럼명이라 매핑 최소.

- [ ] **Step 3: 구문 검증**

Run: `cd backend && python -c "import api.main"`
Expected: import 성공.

- [ ] **Step 4: (DB) 통합 테스트 — scratch DB 있으면**

`backend/tests/test_historical_ui.py` 에 추가 (DB 필요, `TEST_DATABASE_URL` 없으면 skip):

```python
import os
import pytest

pytestmark_db = pytest.mark.skipif(
    not os.getenv("TEST_DATABASE_URL"), reason="DB 필요")


@pytest.mark.skipif(not os.getenv("TEST_DATABASE_URL"), reason="DB 필요")
def test_search_returns_key_type(db_conn):
    # db_conn fixture = conftest 제공(기존 패턴). 최소 검증: 응답 구조.
    from fastapi.testclient import TestClient
    from api.main import app
    c = TestClient(app)
    r = c.get("/players/search", params={"q": "김"})
    assert r.status_code == 200
    for p in r.json()["players"]:
        assert p["key_type"] in ("active", "historical")
```

Run: `cd backend && TEST_DATABASE_URL=$TEST_DATABASE_URL python -m pytest tests/test_historical_ui.py -v`
Expected: 순수 3 PASS + DB테스트 PASS(DB 있을 때) 또는 SKIP.

- [ ] **Step 5: Commit**

```bash
git add backend/api/routers/players.py backend/tests/test_historical_ui.py
git commit -m "feat(historical): /search UNION + /{id} 역대시즌·수상 머지 (역대UI P1)"
```

---

### Task 5: P1 서버 배포 + 라이브 검증

- [ ] **Step 1: 푸시 + 서버 배포**

```bash
git push origin main
ssh -i "C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key" ubuntu@168.107.36.158 \
  "cd ~/playball && git pull origin main --rebase && sudo systemctl restart playball && sudo systemctl restart playball-scheduler"
```

- [ ] **Step 2: 스모크 + 라이브 스팟체크**

```bash
ssh ... "bash ~/playball/scripts/smoke.sh"
# 이승엽 kbo_player_id 조회(서버 psql) 후:
curl -s "https://playball.duckdns.org/historical/<이승엽_kbo_id>" | python3 -m json.tool | head -40
curl -s "https://playball.duckdns.org/historical/leaders?category=home_runs" | python3 -m json.tool | head -30
curl -s "https://playball.duckdns.org/players/search?q=이승엽" | python3 -m json.tool
```
Expected: 스모크 ALL PASS · 이승엽 career.home_runs=467 · leaders HR 상위에 이승엽 · search에 `key_type:"historical"` 행.

- [ ] **Step 3: CLAUDE.md 갱신** (체크리스트 `API` 항목 [x] + 진행로그)

---

## PHASE 2 — App 현역 통산 + 검색 배지/라우팅

### Task 6: 검색결과 '역대' 배지 + 라우팅

**Files:**
- Modify: `app/lib/screens/player/player_screen.dart:437-446` (`_openDetail`), `:817-840` (검색 tile)

- [ ] **Step 1: `_openDetail` 라우팅 분기**

`_openDetail`(player_screen.dart:437) 교체:

```dart
  void _openDetail(Map p) {
    if (p['is_historical'] == true) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => HistoricalPlayerDetailScreen(
          kboPlayerId: p['id'],
          initialName: p['name'],
        ),
      )).then((_) { if (mounted) _loadRecent(); });
      return;
    }
    final code = p['team_code'] as String? ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerDetailScreen(
        playerId: p['id'],
        initialData: {'name': p['name'], 'team': teamDisplayName(code), 'profile_image': p['profile_image'], 'number': p['number'], 'player_type': p['player_type'], 'team_code': code},
      )),
    ).then((_) { if (mounted) _loadRecent(); });
  }
```

(import 추가: `import 'historical_player_detail_screen.dart';` — Task 8서 파일 생성. 그 전까진 analyze 에러나니 Task 8 먼저 하거나 동시 PR.)

- [ ] **Step 2: 검색 tile에 '역대' 배지 + 활동연도**

검색 tile(player_screen.dart:830 `Text(p['name']...)` 행 부근)에서 이름 옆 배지 + 서브라인 연도 분기:

```dart
                                    Row(children: [
                                      Flexible(child: Text(p['name'] ?? '',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: Typo.body, fontWeight: Typo.bold, color: ink))),
                                      if (p['is_historical'] == true) ...[
                                        const SizedBox(width: Space.xs),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: sub.withValues(alpha: 0.15),
                                            borderRadius: Radii.xs),
                                          child: Text('역대', style: TextStyle(fontSize: Typo.micro, color: sub, fontWeight: Typo.bold))),
                                      ],
                                    ]),
                                    const SizedBox(height: Space.xs),
                                    Text(
                                      p['is_historical'] == true
                                        ? '${p['team'] ?? '역대'} · ${p['position'] ?? ''}${p['years'] != null ? ' · ${p['years']}' : ''}'
                                        : '${p['team'] ?? ''} · ${p['position'] ?? p['player_type'] ?? ''} · #${p['number'] ?? '-'}',
                                      style: TextStyle(fontSize: Typo.mini, color: ink3)),
```

(`_numAvatar`는 historical도 number null이면 이니셜 폴백 필요 — Step 3.)

- [ ] **Step 3: `_numAvatar` historical 폴백**

`_numAvatar`(player_screen.dart:449) fallback Text를 number 없으면 이름 첫글자로:

```dart
        child: Text(
            p['number'] != null ? '#${p['number']}' : (p['name'] as String? ?? '?').characters.first,
            style: TextStyle(color: Colors.white, fontSize: size * 0.28,
                fontWeight: Typo.extra, letterSpacing: 0)),
```

- [ ] **Step 4: analyze (Task 8 완료 후 통과)**

Run: `cd app && flutter analyze lib`
Expected: 0 issues (HistoricalPlayerDetailScreen import 해소 = Task 8 선행).

- [ ] **Step 5: Commit** (Task 8과 묶어 커밋 가능)

---

### Task 7: 현역상세 수상 섹션

**Files:**
- Modify: `app/lib/screens/player/player_detail_screen.dart` (세부 그리드 섹션 근처, ~1657행)

- [ ] **Step 1: awards 섹션 위젯 추가**

`player_detail_screen.dart` 세부/고급/수비 그리드 렌더 뒤(~1659행 `if (hasDefense)...` 다음)에 수상 섹션 삽입:

```dart
      if ((player['awards'] as List?)?.isNotEmpty ?? false)
        _awardsSection((player['awards'] as List).cast<Map>()),
```

그리고 `_seasonGridSection` 근처에 헬퍼 추가:

```dart
  Widget _awardsSection(List<Map> awards) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('수상 경력'),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          for (final a in awards)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Pal.paper2(isDark), borderRadius: Radii.sm),
              child: Text(
                '${a['season'] ?? ''} ${a['award'] ?? ''}'.trim(),
                style: TextStyle(fontSize: Typo.small, color: Pal.ink(isDark), fontWeight: Typo.semibold))),
        ]),
      ]),
    );
  }
```

(`_sectionLabel` = 기존 헬퍼 재사용 확인. 없으면 인라인 Text.)

- [ ] **Step 2: analyze**

Run: `cd app && flutter analyze lib`
Expected: 0 issues.

- [ ] **Step 3: Commit**

```bash
git add app/lib/screens/player/player_detail_screen.dart
git commit -m "feat(historical): 현역상세 수상 섹션 (역대UI P2)"
```

---

## PHASE 3 — 은퇴 상세 화면

### Task 8: ApiService + `historical_player_detail_screen`

**Files:**
- Modify: `app/lib/api/api_service.dart` (메서드 2개)
- Create: `app/lib/screens/player/historical_player_detail_screen.dart`

- [ ] **Step 1: ApiService 메서드**

`api_service.dart` searchPlayers(:541) 뒤에 추가:

```dart
  static Future<Map<String, dynamic>> getHistoricalPlayer(int kboPlayerId) async {
    final res = await _dio.get('/historical/$kboPlayerId');
    return res.data;
  }

  static Future<Map<String, dynamic>> getHistoricalLeaders(
      {String category = 'home_runs', int limit = 20}) async {
    final res = await _dio.get('/historical/leaders',
        queryParameters: {'category': category, 'limit': limit});
    return res.data;
  }
```

- [ ] **Step 2: 신규 상세화면**

`historical_player_detail_screen.dart` 생성. 구조: FutureBuilder → 히어로(bio) + 통산 + 시즌별 표 + 포스트시즌 + 수상 + 스플릿 + franchise. 웹이미지 규칙(netImage) 준수, profile_image 없으면 이니셜.

```dart
import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../utils/design_tokens.dart';
import '../../utils/team_theme.dart';
import '../../widgets/app_error_view.dart';

class HistoricalPlayerDetailScreen extends StatefulWidget {
  final int kboPlayerId;
  final String? initialName;
  const HistoricalPlayerDetailScreen({super.key, required this.kboPlayerId, this.initialName});
  @override
  State<HistoricalPlayerDetailScreen> createState() => _HistoricalPlayerDetailScreenState();
}

class _HistoricalPlayerDetailScreenState extends State<HistoricalPlayerDetailScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiService.getHistoricalPlayer(widget.kboPlayerId);
      if (mounted) setState(() { _data = d; _loading = false; });
    } catch (e) {
      debugPrint('historical_detail: $e');
      if (mounted) setState(() { _error = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Pal.bg(isDark),
      appBar: AppBar(title: Text(widget.initialName ?? '역대 선수')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error || _data == null
              ? AppErrorView(onRetry: () { setState(() { _loading = true; _error = false; }); _load(); })
              : _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    final bio = (_data!['bio'] as Map?) ?? {};
    final career = (_data!['career'] as Map?) ?? {};
    final stats = (_data!['stats'] as List?) ?? [];
    final awards = (_data!['awards'] as List?) ?? [];
    final splits = (_data!['splits'] as Map?) ?? {};
    final post = (_data!['postseason'] as List?) ?? [];
    final fr = (_data!['franchise_path'] as List?) ?? [];
    final isPitcher = bio['player_type'] == '투수';
    return ListView(padding: const EdgeInsets.all(16), children: [
      _hero(bio, isDark),
      const SizedBox(height: Space.lg),
      if (career.isNotEmpty) _careerCard(career, isPitcher, isDark),
      if (stats.isNotEmpty) _seasonTable(stats.cast<Map>(), isPitcher, isDark),
      if (post.isNotEmpty) _postseasonCard(post.cast<Map>(), isPitcher, isDark),
      if (awards.isNotEmpty) _awardsCard(awards.cast<Map>(), isDark),
      for (final axis in splits.keys) _splitTable(axis, (splits[axis] as List).cast<Map>(), isDark),
      if (fr.isNotEmpty) _franchiseCaption(fr.cast<Map>(), isDark),
    ]);
  }

  // 히어로: 이름·팀·생년/신장체중·투타·career_text·draft·debut~final
  Widget _hero(Map bio, bool isDark) {
    final code = bio['team_code'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: teamColor(code).withValues(alpha: 0.12),
        borderRadius: Radii.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(bio['name'] ?? '', style: TextStyle(fontSize: Typo.h2, fontWeight: Typo.black, color: Pal.ink(isDark))),
        const SizedBox(height: Space.xs),
        Text([
          bio['team'], bio['position'],
          if (bio['debut_year'] != null) '${bio['debut_year']}~${bio['final_year'] ?? ''}',
        ].where((e) => e != null && e != '').join(' · '),
            style: TextStyle(fontSize: Typo.small, color: Pal.sub(isDark))),
        if (bio['draft_info'] != null) ...[
          const SizedBox(height: Space.sm),
          Text('지명 ${bio['draft_info']}', style: TextStyle(fontSize: Typo.caption, color: Pal.sub(isDark))),
        ],
        if (bio['career_text'] != null) ...[
          const SizedBox(height: Space.xs),
          Text(bio['career_text'], style: TextStyle(fontSize: Typo.caption, color: Pal.ink3(isDark))),
        ],
      ]),
    );
  }

  Widget _careerCard(Map c, bool isPitcher, bool isDark) {
    final items = isPitcher
        ? [('경기', '${c['games'] ?? '-'}'), ('승', '${c['wins'] ?? '-'}'), ('패', '${c['losses'] ?? '-'}'),
           ('SV', '${c['saves'] ?? '-'}'), ('이닝', '${c['innings_pitched'] ?? '-'}'),
           ('ERA', _f(c['era'])), ('탈삼진', '${c['strikeouts_pitched'] ?? '-'}'), ('WHIP', _f(c['whip']))]
        : [('경기', '${c['games'] ?? '-'}'), ('타율', _f(c['avg'])), ('안타', '${c['hits'] ?? '-'}'),
           ('홈런', '${c['home_runs'] ?? '-'}'), ('타점', '${c['rbis'] ?? '-'}'), ('도루', '${c['stolen_bases'] ?? '-'}'),
           ('OPS', _f(c['ops'])), ('출루', _f(c['obp']))];
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('통산', style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra, color: Pal.ink(isDark))),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          for (final it in items)
            Container(width: 78, padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: Pal.paper2(isDark), borderRadius: Radii.sm),
              child: Column(children: [
                Text(it.$2, style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.black, color: Pal.ink(isDark))),
                Text(it.$1, style: TextStyle(fontSize: Typo.micro, color: Pal.sub(isDark))),
              ])),
        ]),
      ]),
    );
  }

  Widget _seasonTable(List<Map> rows, bool isPitcher, bool isDark) {
    final headers = isPitcher
        ? ['시즌', '팀', '경기', '승', '패', 'ERA', '이닝', 'K']
        : ['시즌', '팀', '경기', '타율', 'HR', '타점', 'OPS'];
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('시즌별', style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra, color: Pal.ink(isDark))),
        const SizedBox(height: Space.sm),
        Table(
          border: TableBorder(horizontalInside: BorderSide(color: Pal.line(isDark))),
          columnWidths: const {0: FixedColumnWidth(52), 1: FlexColumnWidth(1.4)},
          children: [
            TableRow(children: [for (final h in headers) _cell(h, isDark, head: true)]),
            for (final r in rows)
              TableRow(children: isPitcher
                ? [_cell('${r['season']}', isDark), _cell('${r['team_name'] ?? ''}', isDark),
                   _cell('${r['games'] ?? ''}', isDark), _cell('${r['wins'] ?? ''}', isDark),
                   _cell('${r['losses'] ?? ''}', isDark), _cell(_f(r['era']), isDark),
                   _cell('${r['innings_pitched'] ?? ''}', isDark), _cell('${r['strikeouts_pitched'] ?? ''}', isDark)]
                : [_cell('${r['season']}', isDark), _cell('${r['team_name'] ?? ''}', isDark),
                   _cell('${r['games'] ?? ''}', isDark), _cell(_f(r['avg']), isDark),
                   _cell('${r['home_runs'] ?? ''}', isDark), _cell('${r['rbis'] ?? ''}', isDark),
                   _cell(_f(r['ops']), isDark)]),
          ],
        ),
      ]),
    );
  }

  Widget _postseasonCard(List<Map> rows, bool isPitcher, bool isDark) =>
      _simpleListCard('포스트시즌', [
        for (final r in rows)
          '${r['season']} ${r['series_type']}: ' +
          (isPitcher ? 'ERA ${_f(r['era'])} ${r['innings_pitched'] ?? ''}이닝'
                     : '${_f(r['avg'])} ${r['home_runs'] ?? 0}HR ${r['rbis'] ?? 0}타점'),
      ], isDark);

  Widget _awardsCard(List<Map> awards, bool isDark) => Padding(
    padding: const EdgeInsets.only(top: Space.lg),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('수상', style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra, color: Pal.ink(isDark))),
      const SizedBox(height: Space.sm),
      Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
        for (final a in awards)
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Pal.paper2(isDark), borderRadius: Radii.sm),
            child: Text('${a['season'] ?? ''} ${a['award'] ?? ''}'.trim(),
              style: TextStyle(fontSize: Typo.small, color: Pal.ink(isDark), fontWeight: Typo.semibold))),
      ]),
    ]),
  );

  Widget _splitTable(String axis, List<Map> rows, bool isDark) => _simpleListCard(
    '스플릿 · $axis',
    [for (final r in rows) '${r['season']} ${r['value']}: ${_f(r['avg'])} (${r['home_runs'] ?? 0}HR)'],
    isDark);

  Widget _franchiseCaption(List<Map> fr, bool isDark) => Padding(
    padding: const EdgeInsets.only(top: Space.lg),
    child: Text('구단 계보: ' + fr.map((f) => '${f['team_name']}(${f['start_year']}~${f['end_year'] ?? ''})').join(' → '),
        style: TextStyle(fontSize: Typo.caption, color: Pal.sub(isDark))),
  );

  Widget _simpleListCard(String title, List<String> lines, bool isDark) => Padding(
    padding: const EdgeInsets.only(top: Space.lg),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra, color: Pal.ink(isDark))),
      const SizedBox(height: Space.sm),
      for (final l in lines)
        Padding(padding: const EdgeInsets.only(bottom: 4),
          child: Text(l, style: TextStyle(fontSize: Typo.small, color: Pal.ink3(isDark)))),
    ]),
  );

  Widget _cell(String t, bool isDark, {bool head = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
    child: Text(t, textAlign: TextAlign.center,
      style: TextStyle(fontSize: Typo.mini,
        fontWeight: head ? Typo.extra : Typo.normal,
        color: head ? Pal.sub(isDark) : Pal.ink(isDark))),
  );

  String _f(v) => v == null ? '-' : (v is num ? v.toStringAsFixed(3).replaceFirst('0.', '.') : '$v');
}
```

> ⚠️ 검증 필요(코딩 시): `app_error_view.dart`의 `AppErrorView` 시그니처(`onRetry`)·`Pal.bg/ink/ink3/sub/paper2/line`·`Radii.sm/lg/xs`·`Typo.*`·`teamColor` 존재 여부. 토큰 누락 시 기존 화면(player_detail_screen) 참조해 정확한 멤버명으로 교정. `_f` ERA는 3자리라 부적절 → ERA/WHIP/이닝은 그대로 문자열(서버가 float). 표시 정밀도는 코딩 시 조정.

- [ ] **Step 3: analyze**

Run: `cd app && flutter analyze lib`
Expected: 0 issues. (Pal/Typo/Radii/AppErrorView 멤버명 실제와 일치 확인.)

- [ ] **Step 4: Commit**

```bash
git add app/lib/api/api_service.dart app/lib/screens/player/historical_player_detail_screen.dart app/lib/screens/player/player_screen.dart
git commit -m "feat(historical): 은퇴선수 상세화면 + 검색 라우팅 (역대UI P3)"
```

---

## PHASE 4 — 역대 탭 (명예의전당)

### Task 9: 역대 리더보드 화면 + 탭 진입

**Files:**
- Create: `app/lib/screens/player/historical_leaders_screen.dart`
- Modify: `app/lib/screens/player/player_screen.dart` (헤더 메뉴/탭에 '역대' 진입 추가)

- [ ] **Step 1: 리더보드 화면**

`historical_leaders_screen.dart` 생성. 카테고리 칩(홈런/안타/도루/타점/승/탈삼진/세이브) + TOP N 리스트, 행 탭→`HistoricalPlayerDetailScreen`.

```dart
import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../utils/design_tokens.dart';
import '../../utils/team_theme.dart';
import 'historical_player_detail_screen.dart';

class HistoricalLeadersScreen extends StatefulWidget {
  const HistoricalLeadersScreen({super.key});
  @override
  State<HistoricalLeadersScreen> createState() => _HistoricalLeadersScreenState();
}

class _HistoricalLeadersScreenState extends State<HistoricalLeadersScreen> {
  static const _cats = [
    ('home_runs', '홈런'), ('hits', '안타'), ('stolen_bases', '도루'),
    ('rbis', '타점'), ('wins', '승'), ('strikeouts_pitched', '탈삼진'), ('saves', '세이브'),
  ];
  String _cat = 'home_runs';
  List _leaders = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await ApiService.getHistoricalLeaders(category: _cat, limit: 25);
      if (mounted) setState(() { _leaders = d['leaders'] ?? []; _loading = false; });
    } catch (e) {
      debugPrint('historical_leaders: $e');
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Pal.bg(isDark),
      appBar: AppBar(title: const Text('역대 기록실')),
      body: Column(children: [
        SizedBox(height: 48, child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final c in _cats)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: ChoiceChip(
                  label: Text(c.$2), selected: _cat == c.$1,
                  onSelected: (_) { setState(() => _cat = c.$1); _load(); })),
          ])),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: _leaders.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: Pal.line(isDark)),
              itemBuilder: (_, i) {
                final p = _leaders[i] as Map;
                return ListTile(
                  leading: Text('${i + 1}', style: TextStyle(fontWeight: Typo.black, color: Pal.sub(isDark))),
                  title: Text(p['name'] ?? '', style: TextStyle(color: Pal.ink(isDark), fontWeight: Typo.bold)),
                  subtitle: Text(p['team'] ?? '', style: TextStyle(color: Pal.sub(isDark), fontSize: Typo.mini)),
                  trailing: Text('${p['value']}', style: TextStyle(fontWeight: Typo.black, fontSize: Typo.subtitle, color: teamColor(p['team_code'] ?? ''))),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => HistoricalPlayerDetailScreen(
                      kboPlayerId: p['kbo_player_id'], initialName: p['name']))),
                );
              })),
      ]),
    );
  }
}
```

- [ ] **Step 2: player_screen 헤더에 '역대 기록실' 진입**

`player_screen.dart` 헤더 아이콘 버튼(마이페이지 옆, :885 부근)에 추가:

```dart
                  _headerIconBtn(Icons.emoji_events_outlined, '역대 기록실',
                      () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const HistoricalLeadersScreen()))),
                  const SizedBox(width: 7),
```

import 추가: `import 'historical_leaders_screen.dart';`

- [ ] **Step 3: analyze**

Run: `cd app && flutter analyze lib`
Expected: 0 issues.

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/player/historical_leaders_screen.dart app/lib/screens/player/player_screen.dart
git commit -m "feat(historical): 역대 기록실(명예의전당) 탭 (역대UI P4)"
```

---

### Task 10: 웹 동반 빌드 + 배포 + 최종 검증

- [ ] **Step 1: 웹 빌드** (Git Bash)

```bash
cd /c/Users/qq772/playball/app && MSYS_NO_PATHCONV=1 flutter build web --wasm --release --base-href "/app/" --no-web-resources-cdn --pwa-strategy=none
```
Expected: 빌드 성공.

- [ ] **Step 2: 웹 배포 (rsync)**

```bash
cd build/web && tar czf /tmp/playweb.tgz . && \
scp -i "<key>" /tmp/playweb.tgz ubuntu@168.107.36.158:/tmp/ && \
ssh -i "<key>" ubuntu@168.107.36.158 "cd /var/www/playball_web && sudo tar xzf /tmp/playweb.tgz"
```

- [ ] **Step 3: 최종 검증**

```bash
curl -s -o /dev/null -w "%{http_code}" https://playball.duckdns.org/app/   # 200
```
육안(헤드리스/실기기): 검색 '이승엽' → 역대 배지 행 → 탭 → 은퇴상세(통산 467HR·시즌별·수상) / 역대 기록실 홈런 TOP에 이승엽 / 현역(양현종) 상세 시즌칩에 과거시즌+통산.

- [ ] **Step 4: analyze + 골든 회귀**

Run: `cd app && flutter analyze lib && flutter test test/golden`
Expected: analyze 0 · 골든 PASS(기존 화면 불변).

- [ ] **Step 5: CLAUDE.md 최종 갱신**

체크리스트 `앱`·`웹 동반 빌드+배포` [x], 진행로그 완료 기록, 섹션 헤더 → 완료. 데이터 스냅샷에 UI 노출 완료 한 줄.

- [ ] **Step 6: Commit + Push**

```bash
git add CLAUDE.md && git commit -m "docs(역대UI): 구현 완료 (P1~P4 배포)" && git push origin main
```

---

## Self-Review (작성자 체크 — 완료)

- **Spec coverage**: 통합검색(Task4/6)·현역통산(Task4/7)·은퇴상세(Task2/8)·역대탭(Task3/9)·스플릿(Task2/8)·franchise(Task2/8)·수상(Task2/4/7/8)·series_type='정규' 필터(Task2/3/4) 전부 태스크 매핑됨. ✓
- **Placeholder scan**: Task2 Step1의 `career`/`career_text` 오류줄은 **의도적 TDD 유도**(Step2서 즉시 교체) — placeholder 아님. Flutter 토큰 멤버명(`Pal.*`/`Typo.*`/`Radii.*`/`AppErrorView`)은 ⚠️로 코딩 시 실제 확인 명시. ✓
- **Type consistency**: `key_type`/`is_historical`/`kbo_player_id`/`years` 검색응답 ↔ 앱 라우팅 일치. `_aggregate_career` 키 ↔ career 카드 키(타자 avg/ops/obp·투수 era/whip/strikeouts_pitched) 일치. 투수 머지 키매핑(walks_allowed→walks 등) 명시. ✓
- **YAGNI**: 투수스플릿/WAR표시/역대비교·공유 = 비목표(스펙). ✓
```
