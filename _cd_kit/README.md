# _cd_kit — Claude Design 동기화용 PlayBall 실토큰 React 컴포넌트

목적: Claude Design(claude.ai/design)이 PlayBall 앱을 **정확히 인식**하도록, 실 디자인토큰으로
React 컴포넌트를 복제해 디자인 프로젝트에 제공. 에이전트가 이 컴포넌트+토큰으로 on-brand 디자인.

⚠️ 권위 소스 = `app/lib/utils/design_tokens.dart` · `team_theme.dart` · 각 화면 .dart. 이건 미러.
앱 디자인 바뀌면 여기도 동기 수정 후 재 push.

## 파일
- `pb-tokens.jsx` — Pal/SemColor/Typo/Radii/Space/팀컬러/adjustTeam 정확값 (window.PB)
- `pb-gamecard.jsx` — 게임카드 풀 + 상태pill + 최근5 + teamSide
- `pb-components.jsx` — 팀순위카드 + 선수행 + #번호아바타 + compact카드
- `pb-fieldview.jsx` — 필드뷰(다이아몬드+잔디+BSO+주자+타자+수비, SVG 300x310)
- `pb-*.html` — 프리뷰 (React UMD+babel, 무빌드)

## Claude Design 동기화
프로젝트 "111"(c76876af-2f37-4134-9891-677b56816afe)에 DesignSync로 push됨.
재 push = 파일 수정 후 DesignSync write_files(localDir=repo root, localPath=_cd_kit/...).

## 한계
- React 출력은 시각 미러 — Flutter 위젯 1:1 아님. 토큰값·좌표·구조는 dart 정확이식, 최종 룩은 Claude Design서 육안확인.
- 로고는 팀컬러 원형+코드 스탠드인(실앱=CachedNetworkImage).
