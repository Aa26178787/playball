# 투구 궤적 시각화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 투구위치 차트에 궤적(9-파라미터 물리모델) 추가 — 무브먼트 꼬리 + 2D 측면/상단 + 3D 원근 회전 뷰.

**Architecture:** A(백엔드): game_pitch_locations에 9 물리컬럼 + 크롤러 원값저장 + API 노출 + 전체시즌 재크롤 백필. B: 순수 Dart 궤적 유틸(TDD). C: pitch_location_chart 확장(무브먼트꼬리·2D·3D CustomPainter). A→B→C 단계, A 독립배포.

**Tech Stack:** Python/psycopg2, Flutter/Dart CustomPainter. 데이터=Naver ptsOptions(x0/vx0/ax·y0/vy0/ay·z0/vz0/az·crossPlateX/Y).

## Global Constraints
- 한글 파일 = Edit/Write만. 커밋 `"` 금지. py_compile / `flutter analyze lib`=0 필수.
- 물리값 nullable — 기존 106k 행 null → 클라 null 가드(궤적 미표시, 위치 dot만).
- 웹 안전: CustomPainter만(NetworkImage/3D엔진/plugin 없음). 로컬 pytest 없음→dart 테스트도 서버/fallback.
- 백필 = game별 **DELETE + 재크롤 replace**(현 INSERT는 ON CONFLICT 없음, 재크롤 중복방지). live-guard(KST 17-23 회피)·resume.
- 신규 DB 컬럼 = `GRANT ALL ... TO playball_user`. DB 스키마 nullable 추가(무손상).
- 좌표계: y=거리(release→plate, ft 감소), z=높이, x=좌우. 위치(t)=p0+v0·t+½·a·t².

---

### Task 1: A1 스키마 마이그레이션

**Files:** Create `backend/database/migrations/2026-07-04_pitch_physics.sql`

- [ ] **Step 1: 마이그레이션 작성**
```sql
ALTER TABLE game_pitch_locations
  ADD COLUMN IF NOT EXISTS x0 numeric,  ADD COLUMN IF NOT EXISTS vx0 numeric, ADD COLUMN IF NOT EXISTS ax numeric,
  ADD COLUMN IF NOT EXISTS y0 numeric,  ADD COLUMN IF NOT EXISTS vy0 numeric, ADD COLUMN IF NOT EXISTS ay numeric,
  ADD COLUMN IF NOT EXISTS z0 numeric,  ADD COLUMN IF NOT EXISTS vz0 numeric, ADD COLUMN IF NOT EXISTS az numeric,
  ADD COLUMN IF NOT EXISTS cross_y numeric;
GRANT ALL ON game_pitch_locations TO playball_user;
```

- [ ] **Step 2: 커밋** (적용은 Task 4 배포 단계서 서버 psql 실행)
```bash
git -C C:/Users/qq772/playball-fut add backend/database/migrations/2026-07-04_pitch_physics.sql
git -C C:/Users/qq772/playball-fut commit -m "feat(trajectory): pitch physics columns migration"
```

---

### Task 2: A2 크롤러 물리값 저장

**Files:** Modify `backend/crawler/crawl_pitch_locations.py`

- [ ] **Step 1: rows 튜플 + INSERT에 9값+cross_y 추가**

`rows.append((...))`(현 125-130)에 물리값 추가:
```python
                rows.append((
                    game_id, inning, inning_half, pitcher_name, batter,
                    round(float(x), 4), z, classify(result_text),
                    pts.get('topSz'), pts.get('bottomSz'),
                    stuff, pts.get('stance', 'R'),
                    pts.get('x0'), pts.get('vx0'), pts.get('ax'),
                    pts.get('y0'), pts.get('vy0'), pts.get('ay'),
                    pts.get('z0'), pts.get('vz0'), pts.get('az'),
                    pts.get('crossPlateY'),
                ))
```
INSERT 컬럼/VALUES(현 135-140)에 추가:
```python
        cur.executemany("""
            INSERT INTO game_pitch_locations
                (game_id, inning, inning_half, pitcher_name, batter_name,
                 x, z, result, top_sz, bot_sz, pitch_type, stance,
                 x0, vx0, ax, y0, vy0, ay, z0, vz0, az, cross_y)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, rows)
```

- [ ] **Step 2: py_compile + 커밋**
```bash
cd C:/Users/qq772/playball-fut/backend && python3 -m py_compile crawler/crawl_pitch_locations.py
git -C C:/Users/qq772/playball-fut add backend/crawler/crawl_pitch_locations.py
git -C C:/Users/qq772/playball-fut commit -m "feat(trajectory): crawler stores 9 physics params + cross_y"
```

---

### Task 3: A3 API 물리값 반환

**Files:** Modify `backend/api/routers/games.py` (`get_pitch_locations`, 현 1585~)

- [ ] **Step 1: SELECT + 응답 dict에 물리값 추가**

`get_pitch_locations`의 SELECT(현 ~1653 `FROM game_pitch_locations`)에 `x0,vx0,ax,y0,vy0,ay,z0,vz0,az,cross_y` 컬럼 추가, 응답 각 pitch dict에 `physics` 서브객체(전부 null-safe: 값 있으면 float, 없으면 None) 추가:
```python
                "physics": ({
                    "x0": _f(row_x0), "vx0": _f(row_vx0), "ax": _f(row_ax),
                    "y0": _f(row_y0), "vy0": _f(row_vy0), "ay": _f(row_ay),
                    "z0": _f(row_z0), "vz0": _f(row_vz0), "az": _f(row_az),
                    "cross_y": _f(row_cross_y),
                } if row_x0 is not None else None),
```
(`_f(v)=float(v) if v is not None else None`. 실제 인덱스는 SELECT 순서에 맞춰 구현 시 배선.)

- [ ] **Step 2: py_compile + 커밋**
```bash
cd C:/Users/qq772/playball-fut/backend && python3 -m py_compile api/routers/games.py
git -C C:/Users/qq772/playball-fut add backend/api/routers/games.py
git -C C:/Users/qq772/playball-fut commit -m "feat(trajectory): pitch-locations API returns physics"
```

---

### Task 4: A4 백필 스크립트 + Phase A 배포

**Files:** Create `backend/crawler/backfill_pitch_physics.py`

- [ ] **Step 1: 백필 스크립트(게임별 DELETE+재크롤 replace)**
```python
"""투구 물리값 백필 — 위치 있으나 물리값 없는 종료경기 재크롤(replace).
현 INSERT는 ON CONFLICT 없어 game별 DELETE 후 재삽입. live-guard·resume."""
import sys, time
from datetime import datetime
from database.connection import get_connection
from crawler.crawl_pitch_locations import save_pitch_locations_for_game


def _targets(limit):
    conn = get_connection(); cur = conn.cursor()
    cur.execute("""
        SELECT g.id, g.naver_game_id, COALESCE(MAX(gi.inning),9)
        FROM games g LEFT JOIN game_innings gi ON gi.game_id=g.id
        WHERE g.status='종료' AND g.naver_game_id IS NOT NULL
          AND EXISTS (SELECT 1 FROM game_pitch_locations l WHERE l.game_id=g.id)
          AND NOT EXISTS (SELECT 1 FROM game_pitch_locations l WHERE l.game_id=g.id AND l.x0 IS NOT NULL)
        GROUP BY g.id, g.naver_game_id ORDER BY g.game_date DESC LIMIT %s
    """, (limit,))
    rows = cur.fetchall(); cur.close(); conn.close()
    return rows


def main():
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 100000
    done = 0
    while True:
        batch = _targets(50)
        if not batch:
            break
        for gid, ngid, max_inn in batch:
            h = datetime.now().hour  # KST 서버 시간
            if 17 <= h < 23:
                print("[백필] live-guard 정지"); return
            try:
                c = get_connection(); cu = c.cursor()
                cu.execute("DELETE FROM game_pitch_locations WHERE game_id=%s", (gid,))
                c.commit(); cu.close(); c.close()
                n = save_pitch_locations_for_game(gid, ngid, int(max_inn))
                done += 1
                print(f"[백필] game={gid} {n}구 (누적 {done})", flush=True)
            except Exception as e:
                print(f"[백필] game={gid} ERROR {e}", flush=True)
            time.sleep(0.5)
            if done >= limit:
                return


if __name__ == '__main__':
    main()
```

- [ ] **Step 2: 커밋**
```bash
git -C C:/Users/qq772/playball-fut add backend/crawler/backfill_pitch_physics.py
git -C C:/Users/qq772/playball-fut commit -m "feat(trajectory): backfill_pitch_physics script (delete+recrawl replace)"
```

- [ ] **Step 3: Phase A 배포 (컨트롤러 수행)** — 마이그레이션 적용 + scp + 재시작 + smoke + 백필 착수(nohup). 신규 라이브 투구 물리 획득 시작. 백필은 야간 진행.

> **⚠️ Phase A 배포 체크포인트**: 여기까지 독립 배포. 백필 가동 후 Phase B/C 진행(궤적 표시엔 물리값 필요 — 백필된 경기부터 궤적 뜸).

---

### Task 5: B 궤적 수학 유틸 + 테스트

**Files:** Create `app/lib/utils/pitch_trajectory.dart`, `app/test/pitch_trajectory_test.dart`

**Interfaces (Produces):**
- `class Vec3 { final double x, y, z; const Vec3(this.x, this.y, this.z); }`
- `class PitchPhysics { x0,vx0,ax,y0,vy0,ay,z0,vz0,az,crossY (double); PitchPhysics.fromJson(Map?)->PitchPhysics? }`
- `List<Vec3> pitchTrajectory(PitchPhysics p, {int samples=24})`
- `(double, double) pitchMovement(PitchPhysics p)` — (pfxX, pfxZ) inch.

- [ ] **Step 1: 실패 테스트 작성**

`app/test/pitch_trajectory_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:playball/utils/pitch_trajectory.dart';

// 대략 직구: release 55ft, 145km/h, 약간 라이즈 무브먼트
const _p = PitchPhysics(
  x0: 0.0, vx0: 0.0, ax: 0.0,
  y0: 50.0, vy0: -130.0, ay: 25.0,
  z0: 6.0, vz0: -5.0, az: -15.0, crossY: 1.417,
);

void main() {
  test('trajectory starts at release, ends at plate', () {
    final t = pitchTrajectory(_p);
    expect(t.length, greaterThan(2));
    // 시작 = release 근처(y≈y0=50)
    expect((t.first.y - 50.0).abs() < 0.5, isTrue);
    // 끝 = plate(y≈crossY=1.417)
    expect((t.last.y - 1.417).abs() < 0.5, isTrue);
  });

  test('trajectory z decreases toward plate (gravity)', () {
    final t = pitchTrajectory(_p);
    expect(t.last.z < t.first.z, isTrue);   // 홈 도달 시 낮아짐
  });

  test('fromJson null-safe', () {
    expect(PitchPhysics.fromJson(null), isNull);
    expect(PitchPhysics.fromJson({'x0': null}), isNull);
    final p = PitchPhysics.fromJson({
      'x0': 0.0,'vx0':0.0,'ax':0.0,'y0':50.0,'vy0':-130.0,'ay':25.0,
      'z0':6.0,'vz0':-5.0,'az':-15.0,'cross_y':1.417});
    expect(p, isNotNull);
  });

  test('movement returns finite pfx', () {
    final (px, pz) = pitchMovement(_p);
    expect(px.isFinite && pz.isFinite, isTrue);
  });
}
```

- [ ] **Step 2: 실패 확인** — `cd app && flutter test test/pitch_trajectory_test.dart` (서버 or 로컬 flutter). Expected: FAIL(미존재).

- [ ] **Step 3: 구현**

`app/lib/utils/pitch_trajectory.dart`:
```dart
import 'dart:math' as math;

class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);
}

class PitchPhysics {
  final double x0, vx0, ax, y0, vy0, ay, z0, vz0, az, crossY;
  const PitchPhysics({
    required this.x0, required this.vx0, required this.ax,
    required this.y0, required this.vy0, required this.ay,
    required this.z0, required this.vz0, required this.az,
    required this.crossY,
  });
  static PitchPhysics? fromJson(Map? j) {
    if (j == null) return null;
    double? d(String k) => (j[k] is num) ? (j[k] as num).toDouble() : null;
    final v = [d('x0'), d('vx0'), d('ax'), d('y0'), d('vy0'), d('ay'),
              d('z0'), d('vz0'), d('az'), d('cross_y')];
    if (v.any((e) => e == null)) return null;
    return PitchPhysics(
      x0: v[0]!, vx0: v[1]!, ax: v[2]!, y0: v[3]!, vy0: v[4]!, ay: v[5]!,
      z0: v[6]!, vz0: v[7]!, az: v[8]!, crossY: v[9]!);
  }
}

double _pos(double p0, double v0, double a, double t) => p0 + v0 * t + 0.5 * a * t * t;

// y(t)=crossY 되는 t (양근 중 최소 양수)
double _tPlate(PitchPhysics p) {
  final a = 0.5 * p.ay, b = p.vy0, c = p.y0 - p.crossY;
  if (a.abs() < 1e-9) return (b.abs() < 1e-9) ? 0.0 : (-c / b);
  final disc = b * b - 4 * a * c;
  if (disc < 0) return 0.0;
  final s = math.sqrt(disc);
  final t1 = (-b - s) / (2 * a), t2 = (-b + s) / (2 * a);
  final cands = [t1, t2].where((t) => t > 1e-6).toList()..sort();
  return cands.isEmpty ? 0.0 : cands.first;
}

List<Vec3> pitchTrajectory(PitchPhysics p, {int samples = 24}) {
  final tp = _tPlate(p);
  if (tp <= 0) return const [];
  final out = <Vec3>[];
  for (int i = 0; i <= samples; i++) {
    final t = tp * i / samples;
    out.add(Vec3(_pos(p.x0, p.vx0, p.ax, t), _pos(p.y0, p.vy0, p.ay, t), _pos(p.z0, p.vz0, p.az, t)));
  }
  return out;
}

// 무브먼트(inch) = 실제 plate 도달 - 무회전(중력만: ax=0, az=-32.174) 기준
(double, double) pitchMovement(PitchPhysics p) {
  final tp = _tPlate(p);
  if (tp <= 0) return (0, 0);
  final actX = _pos(p.x0, p.vx0, p.ax, tp), actZ = _pos(p.z0, p.vz0, p.az, tp);
  final refX = _pos(p.x0, p.vx0, 0.0, tp), refZ = _pos(p.z0, p.vz0, -32.174, tp);
  return ((actX - refX) * 12.0, (actZ - refZ) * 12.0);
}
```

- [ ] **Step 4: 통과 확인** — `flutter test test/pitch_trajectory_test.dart` → PASS(4).
- [ ] **Step 5: 커밋**
```bash
git -C C:/Users/qq772/playball-fut add app/lib/utils/pitch_trajectory.dart app/test/pitch_trajectory_test.dart
git -C C:/Users/qq772/playball-fut commit -m "feat(trajectory): pitch_trajectory math util + tests"
```

---

### Task 6: C-1 플레이트 무브먼트 꼬리

**Files:** Modify `app/lib/screens/game/pitch_location_chart.dart`

- [ ] **Step 1**: pitch-locations 응답의 `physics`를 `PitchPhysics.fromJson`으로 파싱해 투구 모델에 보관(null 허용). `_StrikeZonePainter`에서 물리값 있는 투구마다 `pitchMovement`로 무브먼트 벡터 계산 → dot에서 **무회전 기준점→실제점 짧은 곡선/꼬리**(변화구 휨) 그림. 물리값 null이면 기존 dot만.
- [ ] **Step 2**: `flutter analyze lib`=0 확인.
- [ ] **Step 3**: 커밋 `feat(trajectory): plate movement tail on strike-zone chart`.

> 렌더 상세(꼬리 길이/색/곡률)는 구현자가 기존 페인터 스타일 준수. ⚠️육안 검증(헤드리스 불가) = 사용자 스팟체크.

---

### Task 7: C-2 2D 측면/상단 비행 아크

**Files:** Modify `app/lib/screens/game/pitch_location_chart.dart`

- [ ] **Step 1**: 신규 `_TrajectorySidePainter`(축 y거리×z높이)·`_TrajectoryTopPainter`(y거리×x좌우) — 선택/오버레이 투구의 `pitchTrajectory` 폴리라인 그림 + 스트존/플레이트 기준선. 투구위치 시트에 [위치]/[궤적] 토글 추가, 궤적 탭에 측면/상단 패널.
- [ ] **Step 2**: `flutter analyze lib`=0.
- [ ] **Step 3**: 커밋 `feat(trajectory): 2D side/top flight arc panels + 궤적 tab`.

---

### Task 8: C-3 3D 원근 회전 뷰

**Files:** Modify `app/lib/screens/game/pitch_location_chart.dart`

- [ ] **Step 1**: 신규 `_Trajectory3DView`(StatefulWidget, yaw θ/pitch φ 상태) + `_Trajectory3DPainter`.
  - 투영: Vec3 → 회전(θ,φ) → 원근(카메라 거리 d): `screen = project(rotate(v, θ, φ), d)`. 회전 = y축(θ)·x축(φ) 회전행렬, 원근 = `f/(f+depth)` 스케일. 좌표 정규화(궤적 bounding box 중심·스케일).
  - `GestureDetector.onPanUpdate` → θ/φ 갱신 → setState 재페인트(드래그 회전).
  - 그림: 홈플레이트 오각형·스트존 박스(3D 프레임) + 궤적 곡선(구속/구질 색) + release/plate 점. 선택 투구 강조.
- [ ] **Step 2**: `flutter analyze lib`=0.
- [ ] **Step 3**: 커밋 `feat(trajectory): 3D perspective rotating view`.

> ⚠️ 투영/회전 수학은 구현자가 표준 원근투영으로 작성(순수 CustomPainter, 3D엔진 없음). **육안 검증 필수**(헤드리스 불가) — 회전·원근·궤적 형태 사용자 스팟체크.

---

### Task 9: 검증 + 웹 빌드/배포

- [ ] **Step 1**: `cd app && flutter analyze lib && flutter test` (신규 궤적 테스트 + 골든 회귀).
- [ ] **Step 2**: 웹 wasm 빌드(`--wasm --release --base-href "/app/" --no-web-resources-cdn --pwa-strategy=none`).
- [ ] **Step 3**: rsync 배포 + `/app/` 200 + smoke.
- [ ] **Step 4**: 스팟체크 안내 — 궤적 있는 경기(백필 완료분/신규)서 무브먼트꼬리·2D·3D 회전 육안 확인(헤드리스 불가).
- [ ] **Step 5**: 문서/CLAUDE.md(컨트롤러).

## Self-Review

**1. Spec coverage:**
- A1 스키마 → Task 1. A2 크롤러 → Task 2. A3 API → Task 3. A4 백필 → Task 4. ✅
- B 궤적수학(궤적/무브먼트/투영/null-safe) → Task 5(+테스트). ✅
- C-1 무브먼트꼬리 → Task 6. C-2 2D → Task 7. C-3 3D → Task 8. ✅
- 물리 nullable 가드 → Task 3(physics=null)·5(fromJson null)·6/7/8(궤적 미표시). ✅
- 웹 배포 → Task 9. 단계화(A 체크포인트) → Task 4 이후. ✅

**2. Placeholder scan:** A/B 완전코드. C(뷰)는 렌더 상세를 구현자+육안검증에 위임(헤드리스 렌더 불가라 코드보다 관측이 검증 — 명시). API SELECT 인덱스 배선은 "구현 시 순서 맞춤"(가짜 아님, 실코드 의존). placeholder 없음.

**3. Type consistency:** `PitchPhysics`/`Vec3`/`pitchTrajectory`/`pitchMovement` Task5 정의 = Task6/7/8 사용. `save_pitch_locations_for_game(gid,ngid,max_inn)` 기존 시그니처 = Task4 백필 재사용. INSERT 컬럼순=rows 튜플순 일치(Task2). ✅

## 리스크/노트
- **백필 무거움**(전 시즌 재크롤, ~수시간·야간). Task 4 배포 후 nohup 가동, 진행 모니터.
- **C-3 3D = 최고 난이도·육안 검증만**(헤드리스 렌더 불가). 사용자 반복 스팟체크로 다듬기 예상.
- 크롤러 재크롤 시 DELETE+INSERT(replace) — game 단위라 안전(라이브 경기 회피 live-guard).
