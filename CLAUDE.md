# PlayBall

KBO 야구 앱 | Flutter + FastAPI + PostgreSQL

## 인프라
- 서버: Oracle Cloud Ubuntu 22.04 | 168.107.61.147:8000 (내부), HTTPS: playball.duckdns.org
- SSH 키: `C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key`
- DB: localhost:5432(서버)/5433(터널), db=playball, user=playball_user, pw=<env DB_PASSWORD> (회전 2026-06-09, 평문 보관 금지)
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
Environment="EMAIL_PASS=****"   # Gmail 앱비번 — 실값 서버 env만 (회전 2026-06-09)
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
- 마이페이지/구장(KakaoMap: 네이티브키=AndroidManifest, JS키=stadium_screen, REST키=env KAKAO_REST_KEY — 회전 2026-06-09)/알림(Material 아이콘 칩, 스와이프 삭제)
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
- ⚠️ **reconcile_starter_positions(cur, game_id)** = 대주자/대타가 선발로 표기되고 실포지션 선수가 backup으로 빠지는 경우 교정(promote/demote) — **save_game_roster + save_preview_roster + save_entry_roster 3곳 모두 끝에서 호출 필수** (한 곳만 하면 backup 나중 삽입 시 stale → 필드뷰 야수 누락, 06-08 롯데-한화 1루수 실종 사고)

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
- **nginx 배포 = `/etc/nginx/sites-enabled/playball`이 symlink 아닌 독립 실파일** (repo `nginx_playball.conf` → sites-available **아니라** sites-enabled로 cp해야 적용). ⚠️ 백업파일은 절대 sites-enabled 안에 두지 말 것(nginx가 `sites-enabled/*` 전부 로드 → `limit_req_zone` 중복 `emerg`). 백업은 /tmp. 적용 = cp→`nginx -t`→`systemctl reload nginx` (reload graceful이라 직후 수초 old/new worker 혼재 정상)
- **DB 비번 회전 = 3곳 동기화**: ① `ALTER USER playball_user PASSWORD` ② `/etc/pgbouncer/pgbouncer.ini` `[databases]` 줄 `password=`(auth_type=trust라 pgbouncer→postgres 실자격증명 = 여기, userlist.txt 아님) ③ systemd `Environment=DB_PASSWORD`(2 drop-in: playball=email.conf, scheduler=env.conf). ② 빠뜨리면 "pgbouncer cannot connect to server". 순서: ALTER→ini 교체→pgbouncer restart→서비스 restart
- 새 알림 = notification_log dedup 패턴 필수
- 테마 splashFactory = **NoSplash** + highlight/splash 투명 (탭 반짝임 전부 제거 — 06-08, 되돌리지 말 것). TabBarTheme overlayColor도 투명
- 프로필 크롭 = `PhotoCropScreen`(crop_your_image, Flutter 인앱). 네이티브 image_cropper(uCrop)는 Android15 edge-to-edge status bar 겹침으로 폐기 — 프로필엔 다시 쓰지 말 것. photo_manager 권한 = 기존 READ_MEDIA_IMAGES 재사용
- KT 팀컬러 = 0xFF3D424B 다크슬레이트 (원래 0xFF1A1A1A 검정 → 라이트모드 검은텍스트와 구분 안 됨). 팔레트 빨강(SSG/KIA/롯데)·네이비(NC/두산) 多 → 충돌 주의
- 팀상세/홈 메인탭 = PageView(`NeverScrollableScrollPhysics`)+`_KeepAlive` — 콘텐츠 가로 칩스크롤 hijack 방지 위해 PageView 스와이프 끔, 탭 전환은 `animateToPage`만
- **showDatePicker/showTimePicker 직접 호출 금지** — 전역 `MediaQuery.withClampedTextScaling(min 0.85)`과 picker 내부 clamp 충돌 → `'maxScale > minScale'` assert 크래시. 반드시 `builder:`로 linear scaler 재설정 (cal_event_add_screen `_pickerBuilder` 패턴 복사)
- **버튼 색 하드코딩 금지** — `SemColor.panelDark(0xFF111113)==scaffoldDark` → 다크모드 윤곽소실. 글로벌 `elevatedButtonTheme`(isDark 반전) 상속(bg/fg override 제거). SnackBar/배지의 panelDark는 의도라 예외
- **rate limit/IP = X-Real-IP** — nginx 뒤 `request.client.host`는 항상 127.0.0.1(전역버킷 무력화) → `_client_ip()`. 8000은 127.0.0.1만 ACCEPT라 헤더 신뢰 가능
- **users 참조 FK = ON DELETE CASCADE(개인데이터)/SET NULL(공유데이터)** — NO ACTION이면 회원탈퇴 FK위반으로 깨짐 + 개인정보 잔존
- **시크릿은 env**(DB_PASSWORD/ADMIN_KEY/JWT_SECRET_KEY/EMAIL_*) — 코드 하드코딩 금지. `backend/.env.example` 참조
- **DB 백업/파이프 성공판정 = PIPESTATUS+산출물 크기** — `pg_dump|gzip`의 `$?`는 gzip 것 → 실패해도 20B 빈파일을 SUCCESS로 오기록 사고. cron: db_backup.sh(3AM)·watchdog.py(*/10)
- **admin 엔드포인트 = X-Admin-Key 헤더 + ADMIN_KEY env + log_admin_access** (URL pw 파라미터 금지)

## FCM (활성화 완료)
google-services.json(앱) / firebase_options.dart / firebase-service-account.json(서버) / firebase-admin 7.4.0 / push_tokens·user_settings notify 컬럼 — 전부 ✅. AndroidConfig high priority + channel playball_default.

## 변경 이력 (기능 상세 = git log / 재발방지 규칙 = 주의사항)
- **~06-08 누적**: 필드뷰 CustomPainter(ABS)·알림체계(notification_log dedup/마일스톤/game_summary)·이닝중계 개편(textRelays 지연 → 직전이닝 재fetch)·Option A 전면이식(헤더5탭/마이페이지/팀상세/선수/캘린더/커뮤니티)·인앱크롭(PhotoCropScreen)·다중사진(image_urls)·피칭디자인&존히트맵·인스타339명·플로팅탭 슬라이드
- **06-08b 출시준비(보안·안정화)**: 시크릿 env화·admin X-Admin-Key·rate limit 강화(X-Real-IP)·업로드 magic-byte·회원탈퇴 FK CASCADE·유저차단(user_blocks)·DB백업 가드·watchdog·Crashlytics·보안감사(auth/IDOR 견고)·auth 버튼 다크 가시성

## 해야할 것
### 출시 전 필수 (네 권한 / 외부 작업)
- [x] **키 회전** (2026-06-09 완료): Gmail 앱비번·Kakao(JS/네이티브/REST)·DB pw 전부 회전+라이브검증. ⚠️ 서버 `.bak.*`(옛 시크릿) 잔존 — 안정 확인 후 삭제 / 옛 Gmail 앱비번 콘솔 폐기 확인 / 출시 APK는 새 키로 재빌드
- [ ] **도메인 + Cloudflare**: 웹사이트 Free 플랜 + Tunnel(IP은닉, duckdns/certbot 제거). ⚠️ Bot Fight Mode OFF(앱 API 차단), 동적 JSON 캐시 bypass
- [ ] **Play Console**($25) + keystore 안전백업(분실=업데이트 불가) + Data Safety + targetSdk 확인
- [~] **법무**: 정책 페이지 배포 완료 → `https://playball.duckdns.org/privacy` · `/terms` (HTML=`backend/static/legal/`, nginx exact-match). 잔여 = ① 문의메일 placeholder(`playball.support@gmail.com`) 실계정 교체 ② 출시 전 법률 검토 ③ (옵션)앱 마이페이지 약관 링크 ④ KBO/Naver 저작권 최종 판단
### 중기 (코드 품질)
- [ ] empty catch~41 debugPrint / non-null `!` audit / AppErrorView 전면 / ~~서버 print→logging~~(✅ 2026-06-09 런타임서비스 fcm/weather/email/sms → `api/log_setup.py` 중앙설정+모듈 logger. prediction CLI·scheduler 운영 print는 유지)
- [~] **SemColor.panelDark 감사**(2026-06-09): 80개 분류 — A(라이트잉크 `isDark?light:panelDark` ~40)·A2/A3·B(SnackBar/헤더그라디언트/온보딩 의도)는 **유지**. **Pattern-C 버그**(무조건 panelDark를 fg/fill/border에 → 다크 안 보임) ~22개. 수정완료 6: home OutlinedButton×2·login/register checkbox·phone icon → `SemColor.brand(context)`(다크0xFFE5E5E7/라이트panelDark). **C-fg 수정완료**: home버튼·auth체크박스·phone아이콘 + game_detail TabBar label/indicator(×2)·OutlinedButton → `brand(context)`(analyze clean). **C-fg defer**: player_stats(65·314)·player_compare(285) = 위젯이 다크 미대응(context 파라미터 없음 + grey200/black87 혼재) → 단독 swap 불가, AppErrorView/홀리스틱 다크패스와 묶을 것. player_compare 203 = 다크 헤더 의도(B 재분류). **잔여 C-bg**(brand 아님, surface색 필요): player_screen 칩(818·836)·gd TableRow(3863·3889)·CircleAvatar(3364·3770)·BoxDecoration(3301). ⚠️무차별 치환 금지(A/B 다수). / Radii 토큰 잔여
- [ ] Golden test(다크+라이트) / ~~pre-commit grep hook~~(✅ 2026-06-09 `.githooks/pre-commit`: 음수 letterSpacing WARN + `baseUrl http://` BLOCK. 클론마다 활성화 `git config core.hooksPath .githooks`) / ~~nginx 보안헤더~~(✅ 2026-06-09 HSTS+CSP+Permissions-Policy 등 7종 적용·검증)
- [x] 이닝중계 진행이닝 TTL 30→10s 검토 → **유지 결정**(클라 폴링 30s 고정이라 하향=Naver 부하 3배·UX 이득 0)
### 장기
- [ ] 홈화면 위젯(Android AppWidget native kotlin) / state restoration / i18n은 skip 확정

## 알려진 이슈
- push_tokens 사용자 1명 — 다수 유저 알림 시나리오 미검증
- 라이브 pitch-locations cold 첫 호출 ~2초 (Naver fetch 의존)
- scheduler 30초 사이클 — 연속 이벤트 1개 알림 통합 (의도된 dedup)
- 타자 존 타율 = 인플레이 기준 (삼진 제외 → 시즌 타율보다 소폭 높음, BABIP 성격)
- 동일 이닝 타순 일순 시 존 타율 매칭 근사 (발생순 zip — 오차 미미)
