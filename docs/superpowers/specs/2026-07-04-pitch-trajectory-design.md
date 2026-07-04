# 투구 궤적 시각화 (설계)

날짜: 2026-07-04
범위: 백엔드(스키마/크롤러/API/백필) + Flutter 앱(궤적 수학 + 뷰). 큰 기능 → 3층·단계화.

## 목적
투구위치 차트(플레이트면 dot)에 **투구 궤적**(9-파라미터 PITCHf/x 물리모델 기반) 추가: 무브먼트 꼬리 · 측면/상단 2D 비행 아크 · **3D 원근 회전 뷰**.

## 결정 사항 (브레인스톰 확정)
- 뷰 = **셋 다**(무브먼트 꼬리 + 2D 측면/상단 + 3D 원근 회전).
- 백필 = **전체 시즌 재크롤**(2024~, archive에 물리값 없어 Naver 재크롤 불가피).
- 3D = Flutter CustomPainter **원근 투영(pseudo-3D)** + 드래그 회전(3D 엔진 불요).

## 데이터 근거 (실측 확정)
Naver `ptsOptions`(pts) = 완전 9-파라미터: `x0,vx0,ax · y0,vy0,ay · z0,vz0,az` + `crossPlateX,crossPlateY,topSz,bottomSz,stance,pitchId,ballcount`. 위치(t)=p0+v0·t+½·a·t² (ft, y=거리 release→plate). 현 크롤러는 y/z만 위치계산에 쓰고 원값 버림. `game_relay_archive`엔 물리값 없음(백필 소스 불가).

---

## A. 데이터 레이어 (백엔드)

### A1. 스키마
`game_pitch_locations`에 물리컬럼 추가(전부 nullable — 기존 106k 행은 null):
```sql
ALTER TABLE game_pitch_locations
  ADD COLUMN x0 numeric, ADD COLUMN vx0 numeric, ADD COLUMN ax numeric,
  ADD COLUMN y0 numeric, ADD COLUMN vy0 numeric, ADD COLUMN ay numeric,
  ADD COLUMN z0 numeric, ADD COLUMN vz0 numeric, ADD COLUMN az numeric,
  ADD COLUMN cross_y numeric;
GRANT ALL ON game_pitch_locations TO playball_user;
```
마이그레이션 파일 `backend/database/migrations/2026-07-04_pitch_physics.sql`.

### A2. 크롤러
`crawler/crawl_pitch_locations.py::save_pitch_locations_for_game` — pts에서 9 파라미터 + crossPlateY 추출해 INSERT/UPSERT에 포함(현 x/z 계산은 유지, 원값 추가 저장). 기존 replace/idempotent 패턴 유지(ON CONFLICT UPDATE로 재크롤 시 물리값 채움).

### A3. API
`api/routers/games.py::get_pitch_locations` 응답 row에 물리 9값 + cross_y 추가(nullable → 클라 null 가드). @cached 유지.

### A4. 백필
전체 시즌(2024~) 재크롤 = 각 종료경기 `save_pitch_locations_for_game` 재실행 → 물리값 채움. 야간배치(라이브 회피, 기존 `backfill_seasons`/live-guard 패턴). ~수시간·대역 소. 신규 라이브 투구는 A2로 자동 획득. **전용 백필 스크립트** `crawler/backfill_pitch_physics.py`(위치 이미 있는 경기 재크롤, resume 안전).

---

## B. 궤적 수학 (Flutter 공유 유틸, 순수 Dart, TDD)

`app/lib/utils/pitch_trajectory.dart`:
- `class Vec3 { final double x, y, z; }` (또는 record).
- `List<Vec3> pitchTrajectory(PitchPhysics p, {int samples=24})` — t_plate = y(t)=cross_y 해(2차 근): `ay/2·t²+vy0·t+(y0-cross_y)=0` 양근 중 유효. t∈[0,t_plate] 샘플, 각 축 위치(t)=p0+v0·t+½a·t² → Vec3(x,y,z).
- `(double, double) pitchMovement(PitchPhysics p)` — 무브먼트(break) = (pfx_x, pfx_z) inch: 실제 plate 도달(x,z) vs 무회전(중력만: ax=0, az=-32.174 ft/s²) 기준선 차.
- 2D 투영 헬퍼: `side(Vec3)->Offset`(y거리축, z높이) · `top(Vec3)->Offset`(y거리, x좌우) · `plate(Vec3)->Offset`(x,z).
- `PitchPhysics` = 9값 + cross_y (nullable 소스서 생성, 없으면 null → 궤적 미표시).
- 테스트: t_plate 해·궤적 시작(=release p0)·끝(=plate cross)·무회전 대비 break 부호(싱커=하강, 커브=낙차 등 물리 정합).

## C. 뷰 (프론트, `screens/game/pitch_location_chart.dart` 확장)

### C1. 플레이트 무브먼트 꼬리
`_StrikeZonePainter`에 투구 dot마다 **무브먼트 꼬리**(무회전 기준점→실제점 짧은 곡선, 변화구 휨 시각화). 물리값 있는 투구만.

### C2. 2D 측면/상단 비행 아크 패널
투구 선택(탭) or 전체 오버레이 → 측면(상하 브레이크)·상단(좌우 브레이크) 아크. 신규 `_TrajectorySidePainter`/`_TrajectoryTopPainter`.

### C3. 3D 원근 회전 뷰
- 신규 `_Trajectory3DView`(StatefulWidget) + `_Trajectory3DPainter`.
- 3D 점(Vec3) → **회전(yaw θ, pitch φ) + 원근 투영** → Offset. `GestureDetector` 드래그 → θ/φ 갱신 → repaint(드래그 회전).
- 스트존 3D 프레임(홈플레이트 사각·존 박스) + 궤적 곡선(구속 그라디언트/구질 색). 선택 투구 강조, 다중 오버레이 옵션.
- Flutter 순수 CustomPainter(3D 엔진·plugin 불요, 웹 안전).

### 뷰 진입/구성
- 기존 투구위치 시트에 탭/토글: [위치] [궤적]. 궤적 탭 = 무브먼트 꼬리(C1)+2D(C2)+3D(C3) 구성. 투구 리스트/dot 탭 = 선택.
- 물리값 없는 경기(백필 전) = 궤적 탭 비활성 or "궤적 데이터 없음"(위치는 표시).

## 안전/엣지
- 물리값 null(기존 미백필) → 궤적 미표시(위치 dot만), 궤적 탭 graceful. 웹 = CustomPainter(NetworkImage 없음, 안전). t_plate 무해(허근 시 스킵). 백필 = live-guard·resume·idempotent.

## 단계화 (플랜 분리)
1. **A(데이터)**: 스키마+크롤러+API+백필 스크립트 — 독립 배포, 신규 투구 물리 획득 시작. 백필은 야간 가동.
2. **B(수학)**: pitch_trajectory.dart + 테스트.
3. **C-1/C-2(2D)**: 무브먼트 꼬리 + 측면/상단.
4. **C-3(3D)**: 원근 회전 뷰.
A→B→C 순, 각 단계 배포 가능.

## 비목표
- 실시간 라이브 궤적(종료경기 위주) · 구질별 평균궤적 · 스트라이크존 판정보조 · 릴리스포인트 통계 = 후속.
- APK 네이티브(웹+서버 라인, 관행).

## 영향 파일
- `backend/database/migrations/2026-07-04_pitch_physics.sql`(신규) · `crawler/crawl_pitch_locations.py` · `crawler/backfill_pitch_physics.py`(신규) · `api/routers/games.py`.
- `app/lib/utils/pitch_trajectory.dart`(신규) · `app/test/pitch_trajectory_test.dart`(신규) · `app/lib/screens/game/pitch_location_chart.dart`.
- DB 스키마 변경(컬럼 추가, nullable — 무손상).
