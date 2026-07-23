# 투수 스프라이트 (3D 궤적 뷰 빌보드)

경기상세 → 투구위치 → **궤적 → 3D 뷰**에서 릴리스 지점에 서 있는 투수 그림.
공이 어느 방향에서 오는지 직관적으로 보여주는 **방향 큐**.

## 무엇인가
- 파일: `app/assets/pitcher.png` (투명 PNG)
- 현재 = **자작 실루엣**(하이 레그킥 딜리버리, 저작권 free) — **플레이스홀더**.
- 코드: `app/lib/screens/game/pitch_location_chart.dart`
  - 로더: `_loadPitcherSprite()` (전역 1회 로드+캐시)
  - 렌더: `_Trajectory3DPainter._drawPitcherSprite()` (빌보드)
  - 폴백: 이미지 미로딩/부재 시 벡터 실루엣 `_drawPitcher()`

## 실제 이미지로 교체하는 법
1. 원하는 투수 이미지를 **투명 배경 PNG**로 준비 (정면 또는 3/4 딜리버리 권장,
   세로형, 발이 이미지 하단 근처에 오게).
2. `app/assets/pitcher.png`에 **덮어쓰기** (파일명 동일).
3. 재배포: `bash deploy_web.sh` (웹) / APK 재빌드.
   → 위치·크기 **자동** (코드 수정 불필요).

## ⚠️ 컬러 이미지로 바꿀 때 (톤 입힘 제거)
현재는 **흰 실루엣**을 기준으로 `BlendMode.modulate`로 회색 톤+반투명을 입힘.
컬러 사진/렌더를 넣으면 이 톤이 색을 살짝 회색으로 죽임 → 원본 색 그대로 쓰려면
`_drawPitcherSprite()`의 `tint`를 **흰색(무변형)**으로:

```dart
// 톤 입힘 제거 (원본 색 유지, 반투명만)
final tint = Colors.white.withValues(alpha: 0.6); // 0.6 = 투명도(1.0=불투명)
```

불투명하게 100% 원본이면 `ColorFilter` 줄을 아예 지우고 `Paint()`만 사용.

## 배치·스케일 튜닝 (필요 시)
`_drawPitcherSprite()` 안:
- 발 앵커 = `_proj(hx, hy, 0.0)` (지면), 높이 = `_proj(hx, hy, 8.2)` 투영 거리.
  - 투수를 크게/작게 → `8.2`(ft) 값 조정 (크게=값↑).
- 초기 시야 각도 = `_Trajectory3DViewState._yaw = 0.14` (~8°).
  - 릴리스가 존서 ~49ft 뒤라 **큰 각도서 화면 밖**으로 나감 → 낮은 각도라야 투수+존
    동시 노출. (사용자 드래그로 더 회전 가능.)

## 한계 (빌보드 방식)
- 이미지는 **회전 안 함**(항상 정면). 크게 돌리면 측면 각도서 정면 컷아웃이라 어색.
- 진짜 3D 리그 모델(관절 회전)은 뷰 전체를 GL로 재작성해야 함(웹/wasm 리스크) — 비추천.

## 관련
- 궤적 좌표 정렬: 궤적 y는 PITCHf/x 원좌표(포수쪽 `cross_y`서 판정)라 존 평면(world y=0)
  보다 앞에서 끝남 → 3개 페인터(side/top/3D) 모두 `y - crossY`로 존에 닿게 정렬.
- 릴리스점 = `(x0, y0-crossY, z0)` 평균 (`game_pitch_locations` 물리 컬럼).
