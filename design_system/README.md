# PlayBall 디자인시스템 (Claude Design 동기화용)

`app/lib/utils/design_tokens.dart`의 토큰을 HTML 프리뷰 카드로 추출한 것.
Claude Design(claude.ai/design)에 `/design-sync` 스킬로 push 하는 로컬 컴포넌트 라이브러리.

## 카드 (각 파일 1행 `@dsCard` 마커 = Design System 패널 인덱싱)
- `colors/neutrals.html` — Pal 9단계 중성팔레트 (라이트/다크 쌍)
- `colors/semantic.html` — SemColor (상태/BSO/베이스/패널)
- `type/scale.html` — Typo 크기 11단계 + 굵기 7단계
- `foundations/spacing-radii.html` — Space 6단계 + Radii 6단계

## 동기화 (사용자가 직접 실행 — 스킬은 model-invocation 불가)
```
/design-sync
```
→ list_projects → (없으면 create_project) → finalize_plan(writes: `design_system/**`) → write_files.
첫 실행 시 claude.ai 로그인에 design-system 권한 추가 프롬프트.

## 갱신 원칙
- design_tokens.dart 변경 시 해당 카드 HTML 동기 수정 후 재 sync (1 컴포넌트씩 증분, 통째 replace 금지)
- 권위 소스 = design_tokens.dart. 이 카드는 시각 카탈로그/협업용 미러.
