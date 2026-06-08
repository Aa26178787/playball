# PlayBall

KBO 야구 앱 | Flutter + FastAPI + PostgreSQL

## 인프라
- 서버: Oracle Cloud Ubuntu 22.04 | 168.107.61.147:8000 (내부), HTTPS: playball.duckdns.org
- SSH 키: `C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key`
- DB: localhost:5432(서버)/5433(터널), db=playball, user=playball_user, pw=playball1234
- 레포: https://github.com/Aa26178787/playball
- HTTPS: nginx + Let's Encrypt 리버스프록시 (Android 9+ HTTP 평문 차단 → 앱은 반드시 HTTPS)
- 서비스 2개: `playball`(API uvicorn) + `playball-scheduler`(크롤러/알림 — 별도 프로세스)

## 폴더 구조
- 로컬: `C:\Users\qq772\playball\` → `app\`(Flutter), `backend\`(FastAPI), `ui\`(mockup 원본 — 이식 완료분 보관)
- 서버: `~/playball/backend/` ← WorkingDirectory (api/, database/, crawler/, models/)

## 주요 명령어
```bash
ssh -i "C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key" ubuntu@168.107.61.147
# ⚠️ scheduler는 별도 서비스 — 백엔드 배포 시 반드시 둘 다 재시작 (미재시작 → 패치 미적용 사고 이력)
cd ~/playball && git pull origin main --rebase && sudo systemctl restart playball && sudo systemctl restart playball-scheduler
sudo journalctl -u playball -f          # API 로그
sudo journalctl -u playball-scheduler -f # 크롤러/알림 로그
sudo -u postgres psql -d playball
cd C:\Users\qq772\playball && git add . && git commit -m "msg" && git push origin main --force
```

## 서비스 환경변수
```
WorkingDirectory=/home/ubuntu/playball/backend
ExecStart=/home/ubuntu/.local/bin/uvicorn api.main:app --host 0.0.0.0 --port 8000
# /etc/systemd/system/playball.service.d/email.conf
Environment=OPENWEATHER_API_KEY=2e970a21c74205304e13657423b1625b
Environment=EMAIL_USER=noreply.playball@gmail.com
Environment=EMAIL_PASS=tsgi xehp bgvt nawo
```

## 앱 설정
- 패키지명: com.playball.app
- baseUrl: https://playball.duckdns.org  ← **HTTP로 변경 금지** (Android 9+ 차단)
- 인증: JWT Bearer → FlutterSecureStorage `access_token`(24h) / `refresh_token`(365d)
  - checkLoginStatus(): 토큰 없으면 refresh 시도 → 실패 시 로그인 화면 (토큰은 401/403만 삭제)
  - refresh 5xx/network 오류는 logout 안 함, `_refreshFuture` in-flight dedup

## 앱 실행 / 배포
```bash
flutter run                          # 유선
adb pair [IP]:[포트] && adb connect [IP]:5555 && flutter run   # 무선 (같은 네트워크)
flutter build apk --debug|--release  # → build/app/outputs/flutter-apk/
```
- 노트북-폰 다른 네트워크: 폰 핫스팟. screencap: `MSYS_NO_PATHCONV=1 adb pull` (Git Bash)

## 주요 파일

### 백엔드 (~/playball/backend/)
- api/main.py — GZipMiddleware(500) + CORSMiddleware
- api/cache.py — TTL 인메모리 캐시 (`@cached(seconds)`, threading.Lock)
- api/routers/{games,players,teams,auth,user,stadiums,widget,community,calendar,phone,email_verify,search,news,prediction}.py
  - auth.py: `get_current_user`(필수) / `get_optional_user`(비로그인 None)
  - user.py: ⚠️ `/notifications/read`가 `/notifications/{id}`보다 먼저 선언 필수 (FastAPI 선언 순)
- api/weather_service.py — OpenWeatherMap 5분 캐시 + **stale-while-revalidate + 4분 주기 백그라운드 워머** (전 구장 현재+예보 — cold 블로킹이 홈 5초 지연 원인이었음)
- api/prediction/ — ML 승리예측 (model/features/calibration/eval) + assignment/(과제용 1_train·2_evaluate·README — 로직 정리 문서)
- api/fcm_service.py — Firebase Admin. notify_milestone은 player_milestone_alerts로 dedup
- database/connection.py — ThreadedConnectionPool(3,20) + _PooledConn + _reset_pool()(exhausted 자동 복구)
- crawler/naver_crawler.py — save_game_roster(라인업 페이지) / **save_preview_roster**(preview 풀 로스터) / **save_entry_roster**(relay entry) / save_game_pitches
- crawler/scheduler.py — 30초 사이클, notification_log dedup(_already_notified/_mark_notified)
- crawler/crawl_insta_local.ps1 + verify_insta_local.ps1 — 인스타 핸들 나무위키 크롤 (로컬 PC 전용 — 서버 IP 403)
- crawler/kbo_daily_crawler.py, crawl_highlights.py(Google News RSS), kbo_roster_crawler.py
- static/profiles/, static/posts/

### 앱 (app/lib/)
- main.dart, api/api_service.dart
- utils/{team_theme,local_cache,app_theme,design_tokens}.dart
- screens/home/home_screen.dart — GameCard(풀/compact) + 날짜스트립 + _FloatingNavBar
- screens/game/{game_detail_screen,pitch_location_chart}.dart
- screens/player/{player_screen,player_detail_screen,player_compare_screen,player_stats_section}.dart
- screens/team/{team_screen,team_detail_screen}.dart
- screens/calendar/{calendar_screen,cal_event_add_screen,visit_record_screen}.dart
- screens/community/{community_screen,create_post_screen,post_detail_screen,food_add_screen}.dart
- screens/{auth,mypage,notifications,stadium,search}/...
- widgets/{mention_text,common_widgets,stadium_ranking_sheet,onboarding_helper}.dart
- providers/{auth,game,team,theme}_provider.dart

## API 목록

### 인증
```
POST /auth/register|login, GET /auth/me [Bearer], GET /auth/check-email|check-nickname
POST /auth/password/send-code|reset, DELETE /auth/me
```

### 경기
```
GET /games/today @cached(30) | /games/date/{d} 커스텀(과거86400/오늘30/미래3600)
GET /games/{id} @30 | /relay @10(진행만) | /relay_all 커스텀(진행30/종료3600, 병렬 4)
GET /games/{id}/roster @60 (선발+후보+불펜, pitching_style=COALESCE(gr,p.throws))
GET /games/{id}/preview @300 | /record_detail @60 | /weather @300
GET /games/{id}/pitch-types @60 | /pitch-locations @60 (x=횡ft, z=높이ft, 병렬 4)
GET /games/{id}/highlights @1800 (DB 우선, 없으면 RSS)
GET /games/{id}/predict | /predictions — ML 승리확률 + 팬 투표
※ relay의 field_view: batter(bats 포함)/next_batter(타순+1)/runners/defense
```

### 선수
```
GET /players/search | /hitters | /pitchers (sort_by, team_id, limit) — number 포함, hitters position=game_rosters 주포지션(mode) 세부값(1루수/유격수 등)
GET /players/rankings @300 — 부문별 TOP10 일괄 (14→1 호출)
GET /players/{id} @300 — 프로필+시즌별+roster_status+team_code+insta_handle
GET /players/{id}/daily | /pitch-stats
GET /players/{id}/pitch-design @3600 — 투수 구종별 5x5 존 분포 (stance R/L)
GET /players/{id}/batter-zones @3600 — 타자 피투구/헛스윙/존별타율 (throws R/L)
GET /players/{id}/pitcher-zones @3600 — 투수 존별 피투구분포/피안타율 (stance R/L, 구종합산, 인플레이↔타석결과 (game,inning,half,batter) zip)
GET /players/popularity | POST /players/{id}/vote [Bearer] | GET /players/{id}/vote-status (비캐시, voted/vote_count)
```

### 팀
```
GET /teams/ @3600 | /rankings @60 (last_series 라벨 포함)
GET /teams/{id}/players(throws 포함)|games(home/away_code 포함)|roster-changes|season-stats
GET /teams/postseason-odds @300 — Monte Carlo (odds 키 = id)
GET /teams/popularity | POST /teams/{id}/vote
```

### 유저 [Bearer]
```
GET/POST/DELETE /user/favorite-teams|favorite-players
GET/PUT /user/settings, PUT /user/nickname, POST /user/email/send-code|verify
POST /user/push-token, POST /user/profile-image
GET/POST/DELETE /user/calendar-events + PUT /{id} (수정) — start_time/end_time HH:MM (null=종일)
GET /user/notifications?limit= | POST read-all | PATCH {id}/read
DELETE /user/notifications/read (read보다 {id} 라우트 뒤!) | DELETE /user/notifications/{id} | DELETE /user/notifications
GET /user/stadium-ranking (5회 이상, 비로그인 가능) | /user/stadium-stats
```

### 커뮤니티 / 검색 / 구장 / 기타
```
/community/posts CRUD + like/report/comments + my-* + upload-image (작성 = phone_verified 필수) — posts.image_urls JSONB(다중사진, image_url=첫장 호환)
GET /search?q= → players+teams
/stadiums/* + food-places (pending_vote →5표→ pending_admin → approved, admin pw=playball1234)
GET /widget/live-scores | /calendar/{y}/{m} (games dict keyed by yyyy-mm-dd)
```

## DB 스키마

### users / phone_verifications
users: `id, email, password_hash, nickname, profile_image, phone_number, phone_verified`
phone_verifications: code 저장 (phone_number 컬럼에 실제론 email)

### teams / stadiums
teams `id, name, short_name` — LG,KT,SK(SSG),NC,OB(두산),HT(KIA),LT(롯데),SS(삼성),HH(한화),WO(키움)
stadiums 1=서울 2=고척 3=수원 4=인천 5=대전 6=광주 7=대구 8=창원 9=사직

### players
`id, name, team_id, player_type, number, profile_image, naver_player_id, position, throws, bats, height, weight, birth_date, insta_handle`
- ⚠️ pitching_style 컬럼 없음 (game_rosters.pitching_style 또는 throws 사용)
- insta_handle: 339명 등록 (나무위키 크롤+검수). 미수집은 수동 UPDATE

### games
`id, naver_game_id, game_date, status(예정/진행/종료/취소), home/away_team_id, stadium_id, 스코어/이닝/안타/실책, start_time`

### game_* 테이블
- game_innings / game_pitches(seqno, type, title — 투구+이벤트) / game_pitchers(result=승/패/세이브/홀드) / game_batters / game_rosters(roster_type, batting_order, position, pitching_style, is_starter) / game_highlights / game_relay_archive(payload JSONB) / game_predictions(UNIQUE user,game)
- game_pitch_locations: `game_id, inning, inning_half, pitcher_name, batter_name, x, z, result(ball/strike/swing/foul/hit), top_sz, bot_sz, pitch_type, stance(R/L)` — 106k+ 행, 피칭디자인/타자존 소스
  - ※ result='hit'은 인플레이 (안타 아님). 안타 판정 = game_pitches 타석 결과 텍스트 ('1루타/2루타/3루타/홈런/내야안타' — '안타' 단독 표기 안 씀)

### batter_stats / pitcher_stats
(시즌 누적 — 컬럼 광범위. sb_pct는 이미 % 단위 ×100 금지)
batter: avg,obp,slg,ops,woba,wrc_plus,babip,iso,war,risp,fpct,po,assists,dp,pb …
pitcher: era,whip,fip,k_per_9,bb_per_9,babip,war,qs,blown_saves,avg_against …

### 알림/투표/기타
- user_notifications: type = game_start/score_change/comeback/game_end/extra_innings/cancelled/rank_change/winning·losing_streak/roster_change/new_comment
- notification_log: UNIQUE(game_id,type,sub_id) — scheduler 영속 dedup. **새 알림 추가 시 동일 패턴 필수**
- player_milestone_alerts: 마일스톤 dedup (UNIQUE player,type,value,season,month)
- player/team_popularity_votes, stadium_food_places/votes, user_calendar_events(color 6종 + start_time/end_time TIME nullable), player_daily_stats, player_roster_changes
- 신규 테이블 생성 시 `GRANT ALL ... TO playball_user;` 필수

## Flutter 앱 구조 (2026-06-07 기준)

### 탭: 0경기 1순위 2선수 3캘린더 4커뮤니티
- 하단 _FloatingNavBar (마이팀 칩 포함) — **바에서 좌우 스와이프 = 탭 전환**

### 홈 (home_screen)
- 날짜 스트립: 경기 없는 날 비활성 (calendar API 월별 lazy, `_gameDates`), '오늘' 점프
- **게임카드 2형태**: 마이팀 = 풀(hero) / 일반 = compact (마이팀 미설정 시 전부 풀)
  - 풀: 로고46+팀명+`3위 · 홈` | 중앙 스코어(':'=ink3) + 회차 | 최근5 | 날씨·구장 plain text(지도 비활성) | 선발/승패투수 | 다음시리즈 | 예측투표(예정)
  - compact 3층: 양 사이드 로고44+홈/원정칩 | 중앙 [스코어·시간(18px)] [상태] [승패투수/선발]
  - status pill: 예정 → **선발 확정**(양팀 선발 발표, amber) → **라인업 확정** → ●LIVE(회차는 스코어 밑 단일) → 종료
  - 승팀 오버레이 로고: LayoutBuilder로 작은 로고 수직선 동적 정렬
- 등록말소 배너, 알림 벨 뱃지, compact 토글(view_compact)

### 경기 상세 (game_detail)
- **필드뷰 항상 상단 고정** (핀 토글 제거). 패널 498/428/408 + Spacer 바닥 정착 + 상시 AnimatedSize(전환 overflow 방지)
- 다른 구장 경기: **블라인드 핸들** (하단 중앙, 접힘 '다른 구장 경기 ▼') — LocalCache 영구, 셀 = 팀컬러 듀얼 띠 + 승팀 강조 + 라이브 보더 (mainAxisExtent 62 고정)
- 필드뷰: BSO(dots만) + 주자(베이스 정중앙 좌표) + 타자(bats로 좌/우 배터박스) + **다음타석 오버레이**(우하단 2층) + 베이스 탭 시트
- 탭 4 (중계/라인업/기록/하이라이트) + 플로팅 nav (스와이프 전환, 서브: 라인업=키플레이어/로스터, 기록=투수/타자/상대)
- **이닝별 중계 (디자인 B)**: 이닝 칩 네비(득점 amber dot·라이브 red) + 단일 이닝 + **좌우 스와이프**(방향성 슬라이드) — 타석 헤더 2행(1행 타자 vs 투수+우측끝 투구위치 / 2행 결과 chip 풀, 괄호 제거), 투구 dot tonal
- **득점요약**: 중앙 로고-선수-타구 + 사이드 홈=좌[이닝][타점]/원정=우 — 타점 = 홈인 이벤트 카운트+HR본인 (Naver에 타점 표기 없음), relay dedup(최근4 윈도우)
- 키플레이어: 선발 맞대결 + 중앙 VS 칩 / 로스터: 단일 카드 좌우 2열 — [선발]투수 최상단 → 타순 → 후보 → 불펜(좌완/우완/언더·사이드)
- 하이라이트: 히어로 카드 + 컴팩트 행 + 출처 칩/상대시간

### 선수 탭/상세 (mockup 디자인)
- 탭: 커스텀 헤더('선수' + 검색 오버레이(디바운스 350ms) + 다크 토글) / 타자·투수·인기투표
- 목록: 순위 리스트 행(이미지 아바타+등번호 배지, top3 팀컬러) ↔ 카드 2열 토글, 스탯 pill 칩, 팀컬러 tint 필터
- 상세: 히어로 헤더 216(팀컬러 그라디언트+워터마크+로고280 중앙+프로필88+기본정보 한줄+인스타 버튼) → 핵심 2x2 → 최근5 단일카드 → 세부/고급/수비 3열 그리드 → 트렌드 → 투수: 구종분포+**피칭 디자인**(구종별 5x5 히트맵, stance 토글) / 타자: **존 히트맵**(피투구/헛스윙률/타율, vs좌우투, 표본<5 회색, 3x3 굵은 외곽선)
- 비교 진입 = 상세 AppBar compare_arrows

### 순위 탭 (team_screen)
- 탭 3: 팀 순위(필터 칩에 **PS 확률** 토글 — 별도 리스트 뷰) / 부문별 / 팀 기록

### 캘린더 탭 (Option A 디자인, 06-07 이식)
- 커스텀 헤더(별=마이팀 필터, ＋=추가 메뉴 시트, 마이페이지) + 월 네비 + 직관승률 배너(통계/랭킹 pill) + 달력 그리드(선택=ink, 오늘=마이팀 tint, 직관 승/패 보더, 멀티데이 이벤트 바) + 선택일 상세(KBO 게임 타일 — 마이팀 tint+배지, LIVE/종료/취소 캡슐 / 개인 일정 타일 — 컬러 엣지+시간+X 삭제)
- **cal_event_add_screen**: 일정 추가/수정 풀스크린 — 날짜 헤더 카드(액센트=색상), 날짜 범위 픽커, **시간 설정 토글**(off=종일, on=TimePicker 18:30→21:30 기본), 색상 6종, 메모. `event` 파라미터 주면 수정 모드(프리필+PUT)
- **visit_record_screen**: 직관 기록 추가 풀스크린 — 경기 카드(로고 VS), 승리/패배/무승부 3버튼(액센트 연동), 메모, 사진. 기존 기록은 조회/삭제 다이얼로그 유지
- 일정 타일 탭=수정, 마이팀 색 = favorite_teams 첫 팀 short_name → teamColor

### 커뮤니티 탭 (Option A 디자인, 06-07 이식)
- 커스텀 헤더(랭킹/마이페이지 _Btn32) + 탭 4(전체/팀별/인기/맛집)
- 전체/인기: 검색 박스(paper2)+카테고리 칩(선택=ink)+게시글 카드(팀 태그=team_id→코드 팀컬러, 무한스크롤/캐시 유지)
- 팀별: 정적 팀 칩(로고+팀컬러, LG 기본 선택) → _PostListTab 재사용
- 맛집: 구장 칩 + 타일(인증=SemColor.live) + '맛집 제안' pill FAB(nav 위) → **food_add_screen** 풀스크린(구장 칩+카카오 검색→선택 카드→한줄 추천→제출, 자유입력 아님)
- **create_post_screen**: 글 작성 풀 restyle — 카테고리/팀 칩, 보더리스 제목(60자)+본문, 이미지 박스, 하단 툴바(이미지·@삽입·글자수), 멘션 도움말 유지

### 기타 화면
- 마이페이지/구장(KakaoMap 키 f5b365c3d6aff5eb4640ab80783797ac)/알림(Material 아이콘 칩, 스와이프 삭제)
- Option A `_C` 색상 헬퍼(bg/paper/paper2/ink~sub/line/track) — 화면별 private 클래스로 복제 사용 (calendar/community/선수 계열)

### local_cache.dart
`set/get(maxAgeSeconds)/getStale/remove/hasFlag/setFlag/clearUser`
주요 키: me, favorite_*, my_*, team/player_rankings, games_{date}, other_strip_expanded, 1회 힌트 flag들

## 네이버 API
TEAM_CODE: HT=KIA OB=두산 LT=롯데 SS=삼성 HH=한화 SK=SSG WO=키움 (KT/NC/LG 동일)
Headers: `User-Agent: Mozilla/5.0` / `Referer: https://sports.naver.com/`

### 엔드포인트별 데이터 (api-gw.sports.naver.com/schedule/games/{id}/...)
- `/preview` — **경기 ~2h 전부터**: previewData.{home,away}TeamLineUp = fullLineUp(선발투수)+pitcherBullpen(hitType)+batterCandidate / 선발 상세 / 상대전적
- `/relay?inning=N` — **경기 시작 후**: textRelays(최신순 → reversed 필수), currentGameState, homeEntry/awayEntry(pcode/pos/pitchingStyle)
  - ⚠️ textRelays는 타석 종료 후 일괄 발행 — 이닝 전환 직후 직전 이닝이 미완성일 수 있음 → **직전 이닝 항상 재fetch/재저장** (relay_all 캐시 컷오프 max-1, save_game_pitches max_inn-1 동반)
- 투구 위치: crossPlateX(횡ft), 높이 = 물리궤적 z0+vz0·t+0.5·az·t², topSz/bottomSz = 타자별 ABS존

## 크롤러 / 스케줄러

### 로스터 크롤 타임라인
- 경기 2h 전~ 10분 주기: save_game_roster(라인업 페이지 — 선발 타순) + save_preview_roster(preview — 선발투수 보강+후보/불펜)
- 경기 시작(game_start): save_entry_roster 1회 (entry 변동분)
- 진행 중 선발 타순 비면 재크롤. upsert: 기존 선발 행 is_starter 보존, style/position COALESCE 보충

### scheduler.py 주기 작업
- 30초: smart_update (라이브 이닝/선수/투구 저장 — 투구는 현재+직전 이닝)
- 경기 2h~30m 전: 등록말소 / UTC 00:30: 등록말소+선수이동 / 1시간: 하이라이트
- 종료 감지: 팀순위 + 출전 선수 KBO 크롤 + game_summary(result 채워진 후 발송) + 마일스톤
- 마일스톤: **이번 경기로 임계값 '통과'한 것만** (prev < t ≤ curr — stale 일괄 발송 방지)
- 라인업/등록말소 발생 시: 승리예측 재로깅 + 캐시 무효화
- 매주 월 KST 00:00: 전체 선수 KBO 크롤 / 시작 시: daily_stats 복구

### ML 승리예측 (api/prediction/ — 상세는 assignment/README.md)
- LR+RF 앙상블+saber 스태킹, feature 108개, 시간순 split, grid search 가중치. sklearn (딥러닝 아님)

## 성능 최적화 (구현 완료 요약)
- 서버: 커넥션 풀+자동복구, @cached TTL 전 엔드포인트, GZip, 병렬 이닝 fetch(4), Naver timeout 5s, swap 4G, **날씨 백그라운드 워머**
- 클라: cached_network_image 전면, Shimmer, LocalCache SWR, _dedupGet(stampede 차단), maxConnectionsPerHost=20, _loadGen race 가드

## 주의사항
- **baseUrl HTTPS 고정** / git push --force / 커밋·배포·로그·APK는 묻지 않고 실행
- **배포 시 playball + playball-scheduler 둘 다 재시작**
- **한글 파일 PowerShell -replace 금지** (인코딩 깨짐 → crash loop). Edit 도구 사용
- PS5.1: here-string 안 큰따옴표 → git -m 인자 깨짐 / Invoke-RestMethod 한글 mojibake(수동 UTF-8 디코드) / `$h`·`$H` 대소문자 동일 변수
- ABS 존 상수 plateHalfW=8.5/12, absHalfW=9.95/12, ballR=1.45/12 — 변경 금지
- TeamLogo 파라미터 `teamCode` / TeamDetailScreen `team`(Map) / NetworkImage 금지 → CachedNetworkImage
- share_plus ^10.0.0 고정 (10.1.4 = firebase 충돌) / 소셜 로그인 안 함(결정) / 동명이인 team_id 기준
- 과거경기 수정 game_date < '2026-05-09' 조건 / 삼성 홈 stadium_id=7 보정 SQL
- 서버 pull 전 충돌 파일 rm (insta CSV 등 untracked 주의) / firebase-service-account.json push 금지
- PgBouncer 6432 유지 / 커뮤니티 조회수 _view_cache 재시작 초기화(의도)
- 새 알림 = notification_log dedup 패턴 필수
- 테마 splashFactory = **NoSplash** + highlight/splash 투명 (탭 반짝임 전부 제거 — 06-08, 되돌리지 말 것). TabBarTheme overlayColor도 투명
- 프로필 크롭 = `PhotoCropScreen`(crop_your_image, Flutter 인앱). 네이티브 image_cropper(uCrop)는 Android15 edge-to-edge status bar 겹침으로 폐기 — 프로필엔 다시 쓰지 말 것. photo_manager 권한 = 기존 READ_MEDIA_IMAGES 재사용
- KT 팀컬러 = 0xFF3D424B 다크슬레이트 (원래 0xFF1A1A1A 검정 → 라이트모드 검은텍스트와 구분 안 됨). 팔레트 빨강(SSG/KIA/롯데)·네이비(NC/두산) 多 → 충돌 주의
- 팀상세/홈 메인탭 = PageView(`NeverScrollableScrollPhysics`)+`_KeepAlive` — 콘텐츠 가로 칩스크롤 hijack 방지 위해 PageView 스와이프 끔, 탭 전환은 `animateToPage`만
- **showDatePicker/showTimePicker 직접 호출 금지** — 전역 `MediaQuery.withClampedTextScaling(min 0.85)`과 picker 내부 clamp 충돌 → `'maxScale > minScale'` assert 크래시. 반드시 `builder:`로 linear scaler 재설정 (cal_event_add_screen `_pickerBuilder` 패턴 복사)

## FCM (활성화 완료)
google-services.json(앱) / firebase_options.dart / firebase-service-account.json(서버) / firebase-admin 7.4.0 / push_tokens·user_settings notify 컬럼 — 전부 ✅. AndroidConfig high priority + channel playball_default.

## 변경 이력 핵심 (세션 통합 요약, 상세는 git log)

### ~06-05: 기반 구축
필드뷰 CustomPainter(SVG 300x310 좌표계, ABS), 핀 패널, BSO 오버레이, 알림 체계(notification_log dedup, 마일스톤, game_summary), 인증 안정화, 프로필 크롭, analyzer 338→0, design_tokens 도입, 다크모드 일괄.

### 06-06: UX 다듬기 + 근본이슈
- 🔑 **scheduler 별도 서비스 미재시작 발견** — 배포 루틴에 양 서비스 재시작 명문화
- weather SWR(홈 5초 지연 해결), 읽은알림 라우트 순서, 마일스톤 통과 조건, 종료 필드뷰 stale relay
- tooltip 21곳/Hero/grey 대비/emoji→Material 등 접근성·디자인 일괄, compact 카드 도입

### 06-07: 대개편
- **이닝 race fix** (textRelays 발행 지연 → 직전 이닝 재fetch/재저장) + 429 백필
- 경기상세: 블라인드 핸들, 이닝 칩 네비+스와이프, 2행 타석 헤더, tonal dot, 득점요약(홈인 카운트 방식), 로스터 풀 명단(preview API 발견), 키플레이어/하이라이트/기록 개편, 플로팅바 스와이프
- 선수탭/상세 mockup 전면 이식 + 핵심/세부/고급/수비 그리드 + **피칭 디자인** + **타자 존 히트맵**(존별 타율 — 인플레이↔타석결과 zip 매칭)
- **인스타 339명** (나무위키 로컬 크롤 + 팀명 검증 — Instagram 직접 크롤 불가)
- 선발 확정 status, 스파클 제거, 등번호 배지, 날씨 워머, 과제 스크립트(1_train/2_evaluate)

### 06-07b~08: 캘린더·커뮤니티 Option A 이식 + 일정 기능 확장
- ui/ mockup 5개 이식: 캘린더 탭, 커뮤니티 탭(4탭 전부), 일정추가/글작성/맛집제안 풀스크린화 (cal_event_add·food_add 신규, 기존 다이얼로그/바텀시트 제거)
- **직관기록 풀스크린** (visit_record_screen — 결과 3버튼+메모+사진, 다이얼로그 대체)
- **일정 시간 선택** 풀스택: DB start_time/end_time TIME + API + 시간 토글 UI + 타일 시간 표시
- **일정 수정**: PUT /user/calendar-events/{id} + CalEventAddScreen 수정 모드(타일 탭 진입)
- 🔑 **DatePicker textScaler 크래시** 발견·수정 (전역 clamp min 0.85 충돌 → picker builder 가드, 주의사항 등재)
- 맛집 FAB nav 위 정렬, 일정 색 팔레트 Option A 교체(gray 키=틸 표시), adb 원격 조작으로 실기 검증 루틴 확립 (screencap+uiautomator dump+input tap)

### 06-08: 헤더 통일 + 선수/팀상세 Option A 전면 + 다중사진 + 인앱크롭 + 플로팅 슬라이드
- **헤더 5탭 통일**: 홈/팀/선수/캘린더/커뮤니티 = `[화면전용][다크토글][마이페이지]` 우측, 32×32 bordered 버튼, 타이틀 h2/ls-0.5, 하단 line. 홈/팀 Material AppBar → 커스텀 헤더(SafeArea)
- **마이페이지 Option A 전면**: 프로필/마이팀(전체 팀)/즐겨찾기(가로)/직관/글·댓글·좋아요/알림설정 접이식+커스텀토글/다크. `favoritePlayersChanged` 노티파이어 → 즐겨찾기 해제 실시간 반영
- **팀 상세 Option A 전면**: 팀컬러 헤더(흰 _Btn32)·선수 2열(타자|투수 + 포지션/구위 필터)·경기 3+타순 서브탭(시리즈카드 3등분/월별 막대차트/상대전적 원형게이지+2열). fl_chart 제거
- **선수 화면 다수**: 백넘버 `#-` 수정(getHitters/pitchers에 `p.number`), 상세 이미지 stretch(PlayerAvatar memCacheHeight 제거), 다크 검은텍스트(섹션라벨 등), 등록말소 백넘버 옆, **인기투표=상세 하트**(GET vote-status 비캐시), **피칭 존 히트맵(피안타율)**(GET pitcher-zones), 카드 3열, **세부 포지션 필터**(game_rosters mode → getHitters detail_pos), top3 스탯색 제거
- **인스타식 인앱 크롭**: `PhotoCropScreen`(crop_your_image+photo_manager) — 1:1 고정틀+갤러리그리드, 네이티브 uCrop 폐기(Android15 status bar 겹침 해결), initialRectBuilder로 crop⊆image(밖 이동 방지). 프로필만 적용
- **다중 이미지 게시글**: posts.image_urls JSONB, pickMultiImage(10)+썸네일스트립, 상세 다중표시
- **플로팅탭 슬라이드**: 홈/팀상세 메인탭 PageView(NeverScrollable)+animateToPage+`_KeepAlive`(콘텐츠 가로스크롤 비충돌), 선택 하이라이트 LayoutBuilder+AnimatedPositioned 슬라이드(경기상세 pill 포함)
- **모든 좌우스크롤 칩 페이드**(ShaderMask dstIn) + 고정높이 strip 칩 `alignment center`(세로 쏠림)
- **가시성**: 전역 splash 제거(NoSplash), KT 팀컬러 0xFF1A1A1A→0xFF3D424B, 투구위치 시트 theme-aware(존 다크대응·히트맵토글 제거·범례 상단), 단상 금/은 텍스트 대비, 게임카드 최근5 패/무 색+최근선, 팀상세 경기 승=팀컬러/패무=무채색
- **팀카드**: 홈구장 전체명+지도 진입(StadiumScreen), 승패무|경기|승률 정렬·폰트↑
- 인스타 오배정 12건(225studio.official·team_futures) NULL, 미수집 605명 목록 추출
- 백엔드: getTeamPlayers `throws`, getTeamGames home/away_code, 맛집 구장 '서울'→'잠실'
- deps 추가: crop_your_image ^2.0.0, photo_manager ^3.6.4

## 진행 예정 / 백로그

### 검증 도구 (권장)
- [ ] Golden tests (GameCard 등 다크+라이트) / device_preview / accessibility_tools / DevTools 성능 측정
- [ ] pre-commit grep hook (letterSpacing typo류)

### 중기
- [ ] empty catch ~41건 debugPrint / non-null `!` audit / AppErrorView 전면 적용
- [ ] Radii 토큰 점진 적용 (반경 혼재) / SemColor.panelDark 잔여 hardcoded 점진 치환
- [ ] 다크모드 잔여: forgot_password, my_page 일부, phone_verify, register
- [ ] 이닝별 중계 진행 이닝 TTL 30→10s 검토 (필드뷰와 지연차)

### 장기
- [ ] 홈화면 위젯 (Android AppWidget — native kotlin)
- [ ] state restoration 추가 화면 / 동적 시간 표시 / i18n은 skip 확정

## 실기 확인 대기 (최신)
- ✅ 확인됨(06-07): 캘린더 새 디자인, 일정추가 화면+날짜/시간 픽커, 직관기록 풀스크린 렌더
- 일정 시간 포함 저장→타일 표시, 일정 수정 저장 플로우, 맛집 제안 풀스크린 제출, 글작성 새 디자인 제출, 커뮤니티 다크모드
- compact/hero 혼합 + 3층 compact + 선발 확정 pill (경기 2h 전)
- 이닝 칩 네비+스와이프(라이브 추적), 타석 2행 헤더, tonal dot, 득점요약 중앙 정렬
- 블라인드 핸들 애니메이션 + 좁은 화면 overflow
- 선수탭 리스트/카드+검색 오버레이+다크 토글, 상세 그리드/피칭디자인/존 히트맵(3x3 외곽선)
- 인스타 버튼, 로스터 후보/불펜, 다음타석 오버레이, 알림 스와이프/아이콘 칩
- ※ 06-07 검증 중단 잔여물: 6/7에 'test' 일정 생성됐을 수 있음 — 보이면 삭제

## 알려진 이슈
- push_tokens 사용자 1명 — 다수 유저 알림 시나리오 미검증
- 라이브 pitch-locations cold 첫 호출 ~2초 (Naver fetch 의존)
- scheduler 30초 사이클 — 연속 이벤트 1개 알림 통합 (의도된 dedup)
- 타자 존 타율 = 인플레이 기준 (삼진 제외 → 시즌 타율보다 소폭 높음, BABIP 성격)
- 동일 이닝 타순 일순 시 존 타율 매칭 근사 (발생순 zip — 오차 미미)
