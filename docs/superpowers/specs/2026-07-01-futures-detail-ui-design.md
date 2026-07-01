# 퓨처스 경기 상세 풀스크린 (설계)

날짜: 2026-07-01
범위: Flutter 앱(웹 동반) — 백엔드 변경 없음

## 목적
퓨처스(2군) 경기 상세를 단순 바텀시트에서 **1군 KBO detail 느낌의 풀스크린**으로 개선한다. 2군은 라이브/문자중계/투구 데이터가 없으므로(C2에서 소스 부재 확정) 박스스코어 중심으로, 히어로 스코어보드 + 라인스코어 + 타자/투수 기록 탭 + 주요기록 구성.

## 결정 사항 (브레인스톰 확정)
1. 화면 형태 = **풀스크린** `FuturesGameDetailScreen` (바텀시트 대체).
2. 기록 구성 = **탭 분리** [타자 | 투수] (KBO 기록탭 미러). 히어로·라인스코어는 탭 위 고정.
3. 백엔드 무변경 — 기존 `GET /futures/games/{game_id}/box`가 이미 전 필드 반환.

## 데이터 소스 (기존, 무변경)
`GET /futures/games/{game_id}/box` → `api_service.getFuturesBox(gameId)`:
- `meta`: game_id, game_date, away_code/away_label, home_code/home_label, away_score, home_score, stadium, status, series_id
- `scoreboard`: `{away:{team, innings:[...], r,h,e,b}, home:{...}}`
- `away_batters` / `home_batters`: `[{order, pos, name, ab, r, h, rbi, avg}]`
- `pitchers`: `[{result, side, name, ip, ab, batters, pitches, h, r, er, hr, bb_hbp, so, w, l, sv, era}]` (side로 원정/홈 구분)
- `summary`: `{결승타, 홈런, 2루타, 3루타, 병살타, 도루자, 폭투, 심판, ...}` (키 가변, 값 문자열)

## 화면 구조 (위 → 아래)
1. **AppBar** — 뒤로가기 + 타이틀 `{away_label} vs {home_label}`.
2. **히어로 헤더** (고정) — 원정 로고+팀명 / 중앙 최종 스코어(`away_score : home_score`, 승팀 강조·패팀 흐림, 취소=‘취소’·예정=시간/‘예정’) / 홈 로고+팀명. 아래 줄 = 날짜 · 구장 · 상태. TeamLogo(teamCode) 사용(2군 팀코드; 상무 SM/울산 UL/소프트뱅크 SO는 로고 폴백).
3. **라인스코어 카드** (고정) — 이닝별 + R/H/E. 현 `futures_box_sheet._lineScore` 로직 이식(원정 위/홈 아래, 팀 라벨 좌측 고정, R 볼드).
4. **탭바 [타자 | 투수]** — 고정. 아래 `TabBarView`만 스크롤/전환.
   - **타자 탭**: 원정팀 표 → 홈팀 표(각 팀 라벨 헤더). 표 컬럼 = `타순 | 위치 | 이름 | 타수 | 안타 | 타점 | 득점 | 타율`. order 오름차순. 이름 좌측 정렬, 숫자 우측 정렬, 헤더행 sub 색. 화면폭 내 배치(숫자 컬럼 폭 최소화, tabularFigures).
   - **투수 탭**: 원정팀(side=원정) 표 → 홈팀 표. 컬럼 = `결과 | 이름 | 이닝 | 투구수 | 상대 | 피안타 | 실점 | 자책 | 볼넷 | 삼진 | 홈런 | 평자책`. 컬럼 多 → **[결과·이름] 좌측 고정 + 나머지 스탯 가로 스크롤**(KBO 박스스코어 패턴, `SingleChildScrollView(horizontal)`). bb_hbp=볼넷/사구 합.
   - **주요기록**은 각 탭 스크롤 내용의 **맨 끝**에 공유 위젯(`_summary`)으로 렌더(타자 탭·투수 탭 둘 다 동일 위젯 호출 — 고정 푸터 아님, 탭 콘텐츠 tail). 결승타·홈런·2/3루타·병살·도루자·폭투·심판 — 라벨(sub) + 값(ink) 행. 빈 값/‘없음’ 제외(현 `_summary` 규칙 유지).
   - 레이아웃: 히어로+라인스코어+탭바 = 상단 고정(`Column`), 그 아래 `Expanded(TabBarView)` — 각 탭은 독립 `ListView`(표 + 주요기록).
5. **로딩/에러** — FutureBuilder: 대기=중앙 스피너, 실패/404=‘기록 없음’ 안내(현 시트 패턴 준용, box 없는 경기는 애초에 탭 비활성이라 진입 안 함).

## 컴포넌트 분리
- **신규 `app/lib/screens/futures/futures_game_detail_screen.dart`**: `FuturesGameDetailScreen(gameId)` StatefulWidget + `SingleTickerProviderStateMixin`(TabController length 2). FutureBuilder(getFuturesBox). 내부 위젯: `_hero`, `_lineScore`(이식), `_batterTable(rows, label)`, `_pitcherTable(rows, label)`, `_summary`.
- **`futures_box_sheet.dart` 제거**: 유일 소비자(홈 `_buildFuturesList`)를 풀스크린 push로 교체. `_lineScore`/`_summary` 로직은 신규 화면으로 이식.
- **홈 `home_screen.dart` `_buildFuturesList`**: onTap `showFuturesBoxSheet(context, id)` → `Navigator.push(MaterialPageRoute(builder: (_) => FuturesGameDetailScreen(gameId: id)))`. import 교체.

## 경계/인터페이스
- `FuturesGameDetailScreen({required String gameId})` — box를 스스로 fetch, 자립. 의존 = `ApiService.getFuturesBox`, `TeamLogo`, 디자인 토큰.
- 표 위젯 = 입력 rows(List<Map>) + 팀 라벨 → 표 렌더. 내부 몰라도 사용 가능.

## 디자인/제약
- 디자인 토큰만(Typo/Pal/SemColor/Radii/Space). 인라인 hex 지양.
- TeamLogo 파라미터 `teamCode`. NetworkImage 금지(웹) — TeamLogo만 사용(개별 선수 이미지 없음 → 웹 이미지 규칙 무관).
- 승팀 강조 = ink / 패팀 = sub 흐림(1군 카드 규칙 통일). 취소 경기 = 스코어 자리 ‘취소’.
- 숫자 tabularFigures. 표 행 높이 컴팩트.

## 비목표 (YAGNI / 데이터 부재)
- 필드뷰·이닝별 문자중계·투구위치/존·하이라이트·라인업 탭 (2군 소스 없음).
- 선수 프로필 이미지/링크(박스 행 = 이름만, kbo_player_id 미연결 — C2 확정). 표에서 이름 탭 → 선수상세 이동 = 비목표(추후, 매칭 필요).
- 승률/WPA/AI 한줄평 (PA 데이터 없음).

## 테스트/검증
- `flutter analyze lib` = 0.
- 골든 회귀 통과.
- 수동/웹 스팟체크(헤드리스 렌더 불가): 퓨처스 카드 탭 → 풀스크린 진입, 히어로·라인스코어·타자/투수 탭 표·가로스크롤·주요기록 표시, 뒤로가기.
- 웹 wasm 재빌드+배포(`/app/` 200).

## 영향 파일 요약
- `app/lib/screens/futures/futures_game_detail_screen.dart` — 신규(주).
- `app/lib/screens/futures/futures_box_sheet.dart` — 제거.
- `app/lib/screens/home/home_screen.dart` — `_buildFuturesList` onTap + import 교체.
- `app/lib/api/api_service.dart` — `getFuturesBox` 기존 그대로.
- 백엔드 — 변경 없음.
