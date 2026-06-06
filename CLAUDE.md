# PlayBall

KBO 야구 앱 | Flutter + FastAPI + PostgreSQL

## 인프라
- 서버: Oracle Cloud Ubuntu 22.04 | 168.107.61.147:8000 (내부), HTTPS: playball.duckdns.org
- SSH 키: `C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key`
- DB: localhost:5432(서버)/5433(터널), db=playball, user=playball_user, pw=playball1234
- 레포: https://github.com/Aa26178787/playball
- HTTPS: nginx + Let's Encrypt, playball.duckdns.org → 168.107.61.147:8000 리버스프록시
  - Android 9+ HTTP 평문 차단 → 앱은 반드시 HTTPS 사용 (`usesCleartextTraffic` 미설정)

## 폴더 구조
- 로컬: `C:\Users\qq772\playball\` → `app\`(Flutter), `backend\`(FastAPI)
- 서버: `~/playball/backend/` ← WorkingDirectory (api/, database/, crawler/)

## 주요 명령어
```bash
ssh -i "C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key" ubuntu@168.107.61.147
# ⚠️ scheduler는 별도 서비스 — 백엔드 배포 시 반드시 둘 다 재시작 (06-06 발견: 미재시작으로 패치 미적용 사고)
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
- 인증: JWT Bearer → FlutterSecureStorage `access_token` / `refresh_token`
  - access token: 24시간, refresh token: 365일
  - checkLoginStatus(): 토큰 없으면 refresh 시도 → 실패 시 로그인 화면 (토큰은 401/403만 삭제)

## 앱 실행 / 배포

### 유선 flutter run
```bash
flutter run
```

### 무선 ADB (Android 11+ / 같은 네트워크 필수)
```bash
adb pair [IP]:[포트]   # 6자리 코드 입력
adb connect [IP]:5555
flutter run
```
- 노트북-폰 다른 네트워크: 폰 핫스팟 켜고 노트북 연결

### APK 빌드 후 전송
```bash
flutter build apk --debug   # 또는 --release
# build/app/outputs/flutter-apk/app-release.apk → 카카오톡/구글드라이브
```

## 주요 파일

### 백엔드 (~/playball/backend/)
- api/main.py — GZipMiddleware(500) + CORSMiddleware
- api/cache.py — TTL 인메모리 캐시 (`@cached(seconds)` 데코레이터, threading.Lock)
- api/routers/{games,players,teams,auth,user,stadiums,widget,community,calendar,phone,email_verify,search,news}.py
  - auth.py: `get_current_user` (필수), `get_optional_user` (선택, 비로그인 시 None 반환)
- api/weather_service.py (OpenWeatherMap 5분 캐시)
- api/email_service.py (Gmail SMTP, noreply.playball@gmail.com)
- api/fcm_service.py (Firebase Admin SDK — 파이어베이스 키 등록 대기)
  - notify_score_change: 팀명+득점 제목, 타자/타구/상대투수 본문
  - notify_team_roster_change: 마이팀 등록말소 팀팬 알림 (선수팬 중복 방지)
  - notify_gb_zero: 게임차 0 달성 시 알림
- database/connection.py — ThreadedConnectionPool(minconn=3, maxconn=20) + _PooledConn 래퍼 + _reset_pool() (pool exhausted 자동 복구)
- crawler/naver_crawler.py (수정 가능 — 2026-06-04부터)
- crawler/scheduler.py
  - _get_scoring_play_detail: Naver 중계 API 실시간 득점 타자/투수/타구 파싱
    - textRelays **reversed() 순회** (Naver 최신순 반환 → chronological 정렬 필요)
    - type 13(홈팀) + 23(원정팀) 타석 결과 양쪽 처리
  - _already_notified(game_id, ntype, sub_id) / _mark_notified — notification_log DB 영속 dedup
  - 홈인 정규식: `r'([가-힣]{2,4})(?:이|가)?\s*홈인'` + 조사 어미(로/서/에/으/며/면/도/만/나) reject
  - _recover_missed_daily_stats: 서버 재시작 시 누락 daily_stats 복구 (최근 2일)
- crawler/kbo_daily_crawler.py — games=0 행 건너뜀(중복방지) + wins/losses GREATEST 보호
- crawler/crawl_all_games.py, crawl_past_rosters.py, kbo_roster_crawler.py
- crawler/crawl_highlights.py (Google News RSS)
- static/profiles/, static/posts/

### 앱 (app/lib/)
- main.dart, api/api_service.dart
- utils/team_theme.dart — TeamLogo(CachedNetworkImage), teamColor, teamDisplayName
- utils/local_cache.dart — SharedPreferences JSON 캐시 (TTL, stale-while-revalidate)
- screens/home/home_screen.dart
- screens/game/game_detail_screen.dart
- screens/game/pitch_location_chart.dart
- screens/player/{player_screen,player_detail_screen,player_compare_screen}.dart
- screens/team/{team_screen,team_detail_screen}.dart
- screens/calendar/calendar_screen.dart
- screens/auth/{login_screen,register_screen,forgot_password_screen}.dart
- screens/mypage/{my_page_screen,phone_verify_screen}.dart
- screens/community/{community_screen,post_detail_screen,create_post_screen}.dart
- screens/notifications/notifications_screen.dart
- screens/stadium/stadium_screen.dart
- screens/search/search_screen.dart
- widgets/mention_text.dart
- models/game.dart
- providers/{auth,game,team,theme}_provider.dart

## API 목록

### 인증
```
POST /auth/register          (email, password, nickname)
POST /auth/login             → access_token
GET  /auth/me                [Bearer] → id,email,nickname,phone_verified,phone_number,settings
GET  /auth/check-email?email=
GET  /auth/check-nickname?nickname=
POST /auth/password/send-code  (email) → 비밀번호 재설정 코드 발송
POST /auth/password/reset      (email, code, new_password)
DELETE /auth/me              [Bearer] → 회원탈퇴
```

### 경기
```
GET /games/today             (weather, home/away_recent_5, home/away_team_id 포함) @cached(30)
GET /games/date/{date_str}   (home_starter, away_starter, weather, recent_5 포함) 커스텀 캐시(과거=86400/오늘=30/미래=3600)
GET /games/{id}              (innings, pitchers, batters) @cached(30)
GET /games/{id}/relay        실시간(진행중만) @cached(10)
GET /games/{id}/relay_all    커스텀 캐시(진행=30/종료=3600) ※ ThreadPoolExecutor 병렬 이닝 fetch (max_workers=4)
GET /games/{id}/roster       @cached(60)
GET /games/{id}/preview      (선발투수, 상대전적) @cached(300)
GET /games/{id}/record_detail @cached(60)
GET /games/{id}/weather      (실내=indoor:true, 야외=temp/humidity/wind/pop) @cached(300)
GET /games/{id}/pitch-types  → {pitchers:{name:[{type,count,pct}]}} @cached(60)
GET /games/{id}/pitch-locations → {pitches:[{x,z,result,pitcher,top_sz,bot_sz}], pitchers:[...]} @cached(60)
  ※ ThreadPoolExecutor 병렬 이닝 fetch (max_workers=4)
  ※ x=횡위치(ft), z=높이(ft, 물리궤적 계산), result=ball/strike/swing/foul/hit/other
GET /games/{id}/highlights → {highlights:[{title,url,source,published_at}]} @cached(1800)
  ※ DB 우선 조회, 없으면 Google News RSS 실시간 크롤
※ Naver API requests timeout=5초 (워커 점유 시간 제한)
```

### 선수
```
GET /players/search?q=&player_type=
GET /players/hitters?season=&sort_by=&team_id=&limit=
GET /players/pitchers?season=&sort_by=&team_id=&limit=
GET /players/rankings?season=  @cached(300)
  → {hitters:{avg:[...],home_runs:[...],rbis,hits,stolen_bases,ops,war},
     pitchers:{era:[...],wins,strikeouts,saves,holds,whip,war}}
  ※ 부문별 TOP10 한번에 반환 — 14개 병렬 호출 대체
GET /players/{id}            (프로필 + 시즌별 성적 + roster_status) @cached(300)
GET /players/{id}/daily?season=
GET /players/{id}/pitch-stats?season=  → {total, pitch_types:[{type,count,pct}]}
GET /players/popularity?limit=  → {players:[{id,name,player_type,position,profile_image,team_name,team_code,vote_count,voted}]}
  ※ HAVING vote_count > 0, voted=false(비로그인)
POST /players/{id}/vote      [Bearer] → {voted, vote_count} (토글)
```

### 팀
```
GET /teams/                  @cached(3600)
GET /teams/rankings          → 각 팀에 last_series:{wins,losses,games,label,opponent_id} 포함 @cached(60)
  ※ label: 스윕 승/위닝 시리즈/스플릿/루징 시리즈/스윕 패
GET /teams/{id}/players
GET /teams/{id}/games
GET /teams/{id}/roster-changes?days=30
GET /teams/roster-changes/today
GET /teams/{id}/season-stats?season=  → {record,batting,pitching} @cached(300)
GET /teams/popularity  → {teams:[{id,name,short_name,logo_url,vote_count,voted}]}
POST /teams/{id}/vote  [Bearer] → {voted, vote_count} (토글)
```

### 유저 [Bearer]
```
GET/POST   /user/favorite-teams
DELETE     /user/favorite-teams/{team_id}
GET/POST   /user/favorite-players
DELETE     /user/favorite-players/{player_id}
GET/PUT    /user/settings
PUT        /user/nickname
POST       /user/email/send-code
POST       /user/email/verify                   ({code}) → phone_verified=TRUE
POST       /user/push-token                     (FCM — 활성화 대기)
POST       /user/profile-image                  → {profile_image: url}
GET        /user/calendar-events?year=&month=
POST       /user/calendar-events
DELETE     /user/calendar-events/{event_id}
GET        /user/notifications?limit=50         → {notifications:[...], unread_count}
POST       /user/notifications/read-all
PATCH      /user/notifications/{id}/read
GET        /user/stadium-ranking?limit=30       → {ranking:[{rank,nickname,total,wins,losses,draws,win_rate}]}
  ※ 5회 이상 직관 기록 있는 유저만 (HAVING COUNT(*) >= 5), 비로그인 가능
```

### 커뮤니티
```
GET    /community/posts?team_id=&category=&sort=&q=&page=
GET    /community/posts/{id}
POST   /community/posts      [Bearer + phone_verified 필수]
PUT    /community/posts/{id} [Bearer, 작성자만]
DELETE /community/posts/{id} [Bearer, 작성자만]
POST   /community/posts/{id}/like    [Bearer]
POST   /community/posts/{id}/report  [Bearer]
POST   /community/posts/{id}/comments [Bearer]
DELETE /community/comments/{id}      [Bearer, 작성자만]
GET    /community/my-posts?page=     [Bearer]
GET    /community/my-comments?page=  [Bearer]
GET    /community/my-likes?page=     [Bearer]
POST   /community/posts/upload-image [Bearer, multipart] → {image_url}
```

### 검색
```
GET /search?q=  → {players:[{id,name,player_type,position,profile_image,team,team_code}], teams:[{id,name,short_name}]}
```

### 구장 / 맛집
```
GET  /stadiums/, /stadiums/{id}
GET  /stadiums/{stadium_id}/food-places/search?q=
GET  /stadiums/{stadium_id}/food-places/community
POST /stadiums/{stadium_id}/food-places [Bearer]
POST /stadiums/food-places/{id}/vote [Bearer]
PUT  /stadiums/food-places/{id}/admin?action=approve|reject&pw=playball1234
GET  /stadiums/food-places/pending?pw=playball1234
```
※ 상태 흐름: pending_vote → (5표) → pending_admin → approved

### 기타
```
GET /widget/live-scores, /widget/my-team-scores/{team_id}
GET /calendar/{year}/{month}
```

## DB 스키마

### users
`id, email, password_hash, nickname, profile_image, created_at, phone_number, phone_verified(bool)`

### phone_verifications
`id, user_id, phone_number(실제론 email), code, expires_at, used, created_at`

### teams
`id, name, short_name`
short_name: LG, KT, SK(SSG), NC, OB(두산), HT(KIA), LT(롯데), SS(삼성), HH(한화), WO(키움)

### stadiums
`id, name` | 1=서울(LG/두산), 2=고척(키움), 3=수원(KT), 4=인천(SSG), 5=대전(한화), 6=광주(KIA), 7=대구(삼성), 8=창원(NC), 9=사직(롯데)

### players
`id, name, team_id, player_type(투수/타자), number, profile_image, naver_player_id, position, pitching_style, throws, bats, height, weight, birth_date`

### games
`id, naver_game_id, game_date, status(예정/진행/종료/취소), home_team_id, away_team_id, stadium_id, home_score, away_score, current_inning, inning_half, home_hits, away_hits, home_errors, away_errors, start_time`

### game_innings / game_pitches / game_pitchers / game_batters / game_rosters / game_highlights
- game_highlights: `id, game_id, title, url(UNIQUE), thumbnail, source, published_at, crawled_at`

### batter_stats
`player_id, season, games, at_bats, runs, hits, doubles, triples, home_runs, rbis, walks, strikeouts, stolen_bases, avg, obp, slg, ops, woba, wrc_plus, babip, iso, war, pa, tb, cs, sac, sf, ibb, hbp, gdp, errors, sb_pct, mh, risp, ph_ba`
※ sb_pct: 0~100 퍼센트 단위 (×100 금지)

### pitcher_stats
`player_id, season, games, wins, losses, saves, holds, innings_pitched, hits_allowed, runs_allowed, earned_runs, walks, strikeouts, home_runs_allowed, era, whip, fip, k_per_9, bb_per_9, babip, war, blown_saves, cg, sho, wpct, tbf, np, doubles_allowed, triples_allowed, sac, sf, ibb, hbp, wp, bk, qs, avg_against`

### user_calendar_events
`id, user_id, event_date(DATE), title(VARCHAR200), description(TEXT), color(VARCHAR20, default='blue'), created_at`
- color: blue/red/green/orange/purple/gray

### user_notifications
`id, user_id, title, body, type(VARCHAR30), game_id, is_read(bool), created_at`
- type: game_start/score_change/comeback/game_end/extra_innings/cancelled/rank_change/winning_streak/losing_streak/roster_change/new_comment

### notification_log (영속 dedup)
`id, game_id(INT), type(VARCHAR60), sub_id(VARCHAR60 default=''), sent_at(TIMESTAMPTZ)`
UNIQUE(game_id, type, sub_id)
- scheduler.py _already_notified/_mark_notified가 사용
- targets=0 (push_token 없음)이어도 dedup 작동 (재시작 후 중복 알림 차단)
- sub_id 예시: `{home}_{away}` (score_change), `{player_id}_{hr_n}` (fav_hr), `{team_id}_{count}_{W/L}_{date}` (streak)
- GRANT 필수: `GRANT ALL ON notification_log, notification_log_id_seq TO playball_user;`

### stadium_food_places / stadium_food_votes
- food_places: `id, stadium_id, name, category, address, kakao_place_id, memo, status, vote_count, submitted_by, created_at`
- food_votes: `id, place_id, user_id, created_at` UNIQUE(place_id, user_id)

### player_daily_stats / player_roster_changes
(기존 스키마 유지)

### player_popularity_votes / team_popularity_votes
- player_popularity_votes: `id, user_id, player_id, created_at` UNIQUE(user_id, player_id)
- team_popularity_votes: `id, user_id, team_id, created_at` UNIQUE(user_id, team_id)
  ※ GRANT 필수: `GRANT ALL ON player_popularity_votes, team_popularity_votes TO playball_user;`

## Flutter 앱 구조

### 탭 구성
0: 경기, 1: 순위, 2: 선수, 3: 캘린더, 4: 커뮤니티
- AppBar 우측: 검색 → SearchScreen, 구장 아이콘 → StadiumScreen, 마이페이지 → MyPageScreen

### home_screen.dart (TodayGamesTab)
- 날짜 이동 + 날짜 선택기
- 당일 등록말소 배너 (접기/펼치기)
- 마이팀 필터 토글 (즐겨찾기 팀 있을 때만)
- AppBar 벨 아이콘: 읽지 않은 알림 수 빨간 뱃지 → NotificationsScreen
- GameCard: 날씨 칩 + 팀별 최근5경기 W/L/D 뱃지 + 팀 순위 표시 + 다음 시리즈 상대팀
  - 승리팀 로고 주변 후광 효과 (_winnerGlowLogo)
  - 하단 "다음 vs 상대팀" 한 줄 표시 (날짜/홈원정 없음)
- 로딩: Shimmer 게임카드 스켈레톤 4개
- 캐시: games/favorite-teams/rankings — stale-while-revalidate
  - 오늘 날짜: games TTL=300초, 과거 날짜: TTL=86400초 (1일)
- _loadGames race condition: _loadGen generation counter (날짜 전환 중복 호출 방지)
  - Dio retry interceptor: DioExceptionType.unknown 포함 (앱 시작 시 네트워크 미초기화 대응)
  - catch 시 2초 후 1회 자동 재시도 (isRetry 파라미터)
- _gamesDateMismatch: 선택 날짜와 _games 날짜 불일치 시 shimmer 표시

### game_detail_screen.dart
- 탭 4개 (isScrollable): 중계/라인업/기록/하이라이트
- 투수 탭: 구종차트 + 투구위치 보기 → PitchLocationSheet
- 하이라이트 탭: url_launcher 외부 브라우저
- 공유 버튼: share_plus
- 자동새로고침: 30초 (진행중만)
- **필드뷰 (_buildFieldSection)**:
  - 진행중 + relay 로드됨: BSO 카운트 + 실시간 수비/타자/주자 (_buildLiveStatus)
  - 종료/예정/라인업: 홈팀 수비 스타팅 라인업 정적 표시 (_rosterData 기반)
  - 조건: `_relayData != null || _rosterData != null`
- **득점 상세 (_buildScoringSection)**:
  - 타석 이벤트(type 13/23) + 후속 홈인 이벤트(type 14/24/31) 그룹화
  - RBI/홈런 타석 표시 → 홈인 주자 들여쓰기로 연결 표시
  - standalone 홈인 (폭투/보크 등): 타석 없이 독립 표시

### pitch_location_chart.dart (PitchLocationSheet)
- 3단계 필터: 투수 → 이닝 → 타자
- 결과 필터 칩(전체/볼/스트라이크/헛스윙/파울/타격)
- ABS 스트라이크존: plateHalfW=8.5/12, absHalfW=9.95/12, ballR=1.45/12 (ft) — **변경 금지**
- 진행중 30초 자동새로고침 + LIVE 배지

### player_screen.dart
- 타자/투수/인기투표 탭 (TabController length=3), 팀 필터, 정렬 칩
- 인기투표 탭: 선수/구단 토글, 하트 버튼(토글 투표), 1~3위 금/은/동 메달 배지
  - 선수: 득표 있는 선수만 표시 (HAVING > 0), 처음엔 빈 상태
  - 구단: 전체 10팀 항상 표시 (득표 0도 포함)
  - 비로그인: 하트 터치 시 "로그인 후 투표" 스낵바
- 로딩: Shimmer 선수행 스켈레톤 12개

### player_detail_screen.dart
- 한글/영어 토글, 최근 5경기, 투수 구종분포 바차트, 시즌 트렌드 그래프

### player_compare_screen.dart
- 두 선수 검색 → 스탯 테이블 (좋은 값 navy bold)

### team_screen.dart (순위 탭)
- 팀 순위: last_series 배지 + 최근5경기 뱃지
- 부문별 순위: GET /players/rankings 단일 호출 → 타자/투수 7카테고리
- 로딩: Shimmer 팀행/랭킹행 스켈레톤 10개
- 캐시: team_rankings/player_rankings — stale-while-revalidate

### team_detail_screen.dart
- 탭 5개: 선수명단 / 최근경기 / 등록말소 / 뉴스 / 커뮤니티

### my_page_screen.dart
- 프로필 이미지 업로드, 닉네임 편집, 이메일 인증
- 마이팀/즐겨찾기선수/내글/내댓글/좋아요글
- 캐시: me/favorite_teams/favorite_players/my_posts/my_comments/my_likes — stale-while-revalidate
- **재시작 후 즉시 데이터 표시 (닉네임 '-' 없음)**

### calendar_screen.dart
- 월별 달력, KBO경기 + 개인일정
- 예정경기 → add_2_calendar, FAB → 개인일정 추가 (색상 6종)

### community_screen.dart
- 무한스크롤, AutomaticKeepAliveClientMixin
- stale-while-revalidate (캐시 TTL 300초, 카테고리=전체+검색 없을 때만)

### stadium_screen.dart
- KakaoMap 9개 구장, 카드 탭 → 지도 포커스
- 네이티브 앱 키: f5b365c3d6aff5eb4640ab80783797ac

### team_theme.dart
`TeamLogo(teamCode, size, logoUrl)` — CachedNetworkImage 사용
`teamColor(code)`, `teamDisplayName(code)`

### local_cache.dart
```dart
LocalCache.set(key, value)           // JSON + timestamp 저장
LocalCache.get(key, maxAgeSeconds)   // TTL 초과 시 null 반환
LocalCache.clearUser()               // 로그아웃 시 전체 삭제
```
캐시 키: me / favorite_teams / favorite_players / my_posts / my_comments / my_likes /
         user_settings / team_rankings / player_rankings / games_{dateStr}

## 네이버 API
NAVER_TEAM_CODE: HT=KIA, OB=두산, LT=롯데, SS=삼성, HH=한화, SK=SSG, KT=KT, NC=NC, WO=키움, LG=LG
Headers: `User-Agent: Mozilla/5.0` / `Referer: https://sports.naver.com/`

### 투구 위치 데이터
- `crossPlateX`: 횡위치(ft) 직접 사용
- 높이: y=0 시점 t 이차방정식 → `z_plate = z0 + vz0*t + 0.5*az*t²`
- `topSz`/`bottomSz`: 타자별 ABS 존
- `textOptions type=1`: stuff=구종, text=결과

## 크롤러 핵심 로직

### naver_crawler.py (수정 가능)
- 5분마다 진행중 경기 실시간 업데이트
- 종료 감지 시 15분 후 선수 스탯 업데이트

### scheduler.py
- **30초마다**: smart_update (naver_crawler 래퍼, 메인 루프 10초 sleep)
- 경기 2시간 전~30분 전: 등록말소 크롤링
- UTC 00:30 (KST 09:30): 등록말소 + 7일치 선수이동
- 1시간마다: 하이라이트 크롤
- **경기 종료 감지 시**: 해당 경기 출전 선수만 KBO 크롤 (game_pitchers + game_batters 조회)
- **매주 월요일 KST 00:00** (UTC 15:00): DB 전체 선수 KBO 크롤
- **시작 시**: _recover_missed_daily_stats (최근 2일 player_daily_stats 누락 복구)
- **_save_player_daily_stats_today(target_date)**: target_date 파라미터로 과거 날짜 지정 가능

### crawl_all_games.py
- 셀레니움 네이버 모바일 중계 역순파싱
- pitcher_idx 경기 전체 유지 (이닝간 초기화 금지)
- 대상: game_date < '2026-05-09' 종료경기

### kbo_roster_crawler.py
- crawl_daily_register(): 1군등록/등록말소
- crawl_trade(days): 선수이동

### crawl_highlights.py
- Google News RSS (Naver 403 우회)
- 팀명→team_id: KT=1, KIA=2, 롯데=4, 한화=5, NC=6, 두산=7, 키움=8, LG=9, SSG=10, 삼성=11

## 성능 최적화 (구현 완료)

### 서버사이드
- **DB 커넥션 풀**: ThreadedConnectionPool(3-20), _PooledConn 래퍼 (close()→putconn())
  - _reset_pool(): PoolError 'exhausted' 감지 시 자동 재생성 (`closeall()` → 재시도)
- **TTL 인메모리 캐시** (api/cache.py): @cached(seconds) 데코레이터
  - /games/today → 30초
  - /games/{id} → 30초
  - /games/{id}/relay → 10초 (신규)
  - /games/{id}/roster, /record_detail, /pitch-types, /pitch-locations → 60초 (신규)
  - /games/{id}/preview, /weather → 300초 (weather 신규)
  - /games/{id}/highlights → 1800초 (신규)
  - /games/date/{date_str} → 커스텀 (과거=86400/오늘=30/미래=3600)
  - /games/{id}/relay_all → 커스텀 (진행=30/종료=3600)
  - /teams/rankings → 60초
  - /players/rankings, /players/{id} → 300초
  - /teams/ → 3600초
- **GZipMiddleware**: minimum_size=500 (JSON ~65% 압축)
- **ThreadPoolExecutor 병렬 이닝 fetch**: relay_all + pitch-locations (max_workers=4, 직렬 ~1800ms → 병렬 ~200ms)
- **Naver API timeout=5초** (워커 점유 시간 제한)
- **GET /players/rankings 단일 엔드포인트**: 14→1 API 호출 (랜덤 빈탭 버그 해결)
- **VPS swap 4G + swappiness 30**: OOM 방지 (RAM 956Mi 한계)

### 클라이언트사이드
- **cached_network_image** 전체 적용 (모든 NetworkImage 대체)
- **Shimmer 스켈레톤**: home/player/team 화면 로딩 시 (CircularProgressIndicator 제거)
- **LocalCache stale-while-revalidate**: 캐시→즉시표시 후 백그라운드 갱신
  - 재시작/재로그인 시 스피너 없이 즉시 데이터 표시
  - 로그아웃 시 clearUser() 자동 호출
- **ApiService._dedupGet**: 동일 GET URL 동시 호출 → 단일 in-flight Future 공유
  - 적용 엔드포인트: today/gameDetail/byDate/relay/relayAll/preview/recordDetail/pitchTypes/weather/roster/teams/rankings
  - 캐시 stampede 차단 (race condition 시 중복 호출 단일화)
- **GameDetailScreen _isLoadingInFlight**: _loadData 재진입 가드

## 주의사항
- **baseUrl 반드시 `https://playball.duckdns.org`** — HTTP로 변경 시 Android 9+ 전체 API 차단
- 과거경기 수정: game_date < '2026-05-09' 조건 필수
- 동명이인: team_id 기준 조회
- 서버 백엔드 루트: ~/playball/backend/
- git push: --force 필수 (모노레포)
- git push/pull 원격 작업은 확인 없이 바로 실행
- 커밋 / 서버 배포(ssh pull+restart) / 서버 로그 확인 / APK 빌드 → yes/no 묻지 않고 바로 실행
- 삼성 홈경기 구장: `UPDATE games SET stadium_id=7 WHERE home_team_id=11 AND stadium_id IS NULL`
- sb_pct: 이미 퍼센트 단위 (×100 금지)
- 소셜 로그인 구현 안 함 (결정)
- TeamLogo 파라미터: `teamCode` (not `code`)
- TeamDetailScreen 파라미터: `team` (Map, not teamId)
- 서버 pull 전: `git stash` 필수 (직접 수정 파일 있을 경우)
- 커뮤니티 조회수 쓰로틀: `_view_cache` in-memory dict (재시작 시 초기화, 의도적)
- ABS 존 상수: plateHalfW=8.5/12, absHalfW=9.95/12, ballR=1.45/12 (ft) — **변경 금지**
- share_plus 버전: ^10.0.0 (^10.1.4는 firebase_messaging 충돌)
- NetworkImage / Image.network 사용 금지 → CachedNetworkImage/CachedNetworkImageProvider
- naver_crawler.py 수정 가능 (2026-06-04부터)
- firebase-service-account.json 서버 전용 (git push 금지)
- **한글 파일 PowerShell `-replace` 금지**: UTF-8 인코딩 깨짐 → SyntaxError crash loop 유발. Edit 도구 사용
- PgBouncer port 6432 → 5432 변경 금지 (동시접속 폭증 시 pool 고갈)
- **scheduler 재시작 후 알림 누락 방지**: notification_log 테이블 + _already_notified/_mark_notified 사용 필수. 새 알림 추가 시 동일 패턴 적용

## FCM (활성화 완료)
- google-services.json: app/android/app/google-services.json ✅
- firebase_options.dart: app/lib/firebase_options.dart ✅
- firebase-service-account.json: 서버 ~/playball/backend/ ✅ (git push 금지)
- firebase-admin==7.4.0: 서버 pip 설치 + requirements.txt ✅
- push_tokens / user_settings notify 컬럼: DB ✅
- _get_app() 초기화: FCM OK: True 확인 ✅

## 세션 변경사항 요약 (2026-06-04 ~ 06-05)

### 필드뷰 (mockup SVG 300x310 좌표계)
- `_FieldBgPainter` 전면 재작성 — `canvas.scale(size.width / 300)` 후 SVG 좌표로 그림
- BoxFit.contain — visible content (y=66~296, 230 height) fit + 가로 center
- 부채꼴 dirt sector 90도 (-45° ~ +45°), radius `_R_DIRT=132`
- 외야 mowing stripe 9개 (교대 #54944A/#4C8A42, sweep 10° each)
- 부채꼴 외야 잔디 배경 (#356030 → #264821 radial gradient)
- 내야 정사각 잔디 다이아몬드 + 베이스패스 stroke (페어 clip)
- 1B/3B/2B dirt 컷아웃 + 마운드 + 홈 dirt + 홈플레이트 5각형
- 베이스: 회전 정사각 (`_rot45` matrix), 점거 시 #FCD34D + orange aura
- 배터박스 2개 (RRect rx 1.5)
- 파울라인: 진짜 -135°/-45° 방향
- 슬롯 크기: outer `(screen_w - 36) x 345`, inner field area `(screen_w - 68) x 290`
- field SizedBox 230 → 290, Padding(16, 35, 16, 20), 패널 height 530/435 → 505/410

### 선수 위치 (SVG 좌표 — placed() painter transform 적용)
- 수비: P(150,208) C(150,283) 1B(220,186) 2B(183,153) SS(117,153) 3B(80,186) LF(64,118) CF(150,84) RF(236,118)
- DH(30,280) 벤치
- 베이스/주자: base1(222,200) base2(162,148) base3(78,200) batter(132,262)

### 핀 (필드뷰 + 다른경기 strip 상단 고정)
- `bool _fieldPinned` state + AppBar IconButton 제거 → BSO overlay 오른쪽 별도 토글 "고정"
- `_buildPinnedPanel(game)`: mini-scoreboard (홈로고+스코어+원정로고) + 필드뷰 + 다른경기 strip
- panel height 강제 (Container) + spacer Column 동일 → scaffold body 노출 fix
- 핀 시 gameHeader skip → 본문 직접 TabBarView (Column[spacer, Expanded(TabBarView)])
- 하단 rounded `BorderRadius.vertical(bottom: 16)`

### BSO overlay (필드뷰 상단 가운데)
- 필드뷰 Stack 안 `Positioned(top:8, center)` 검은 반투명 캡슐
- LIVE badge (진행중 빨강 / 비라이브 회색) + BSO dots + refresh
- 항상 표시 (비라이브 시 0/0/0 fallback, null-safe `?.`)
- 핀 토글 별도 `Positioned(top:8, right:12)` (BSO와 분리)

### 다른 경기 strip (1x4)
- 위치: gameHeader 내부 필드뷰 ↓ 승투패투 위
- 2-col grid → 4-col (`crossAxisCount: 4, childAspectRatio: 1.4`)
- 셀 축소: TeamLogo 16, fontSize 9~11, padding 4

### 게임카드
- 폰트 +2pt (`_centerPitcherCell`/`_centerNextSeriesCell` 11→13)
- 마이팀 외곽선 팀컬러 + width 2
- weather/status chip 외곽선 추가 (지도 chip 통일)
- 헤더 chip만 opaque, 빈공간 transparent (overlay 자연 노출)
- 선발/다음시리즈 Container Padding 양끝 확장 (negative margin assertion 회피 → Padding vertical 15 + 자체 horizontal 15)
- 오버레이 팀로고: wikipedia 500px PNG (size>=200, kTeamOverlayLogoUrls map), `ImageFiltered blur sigma 1.2`
- 일반 로고: Naver f92_88 (size<80) + f400_400 (size>=80)
- 진행중 카드도 winner 강조 (homeWon/awayWon에 `isLive` 포함)
- footer Container `color: cardBg` opaque

### 승투/패투
- `_pitcherBadge` 이미지 제거, 라벨박스(승/패) + 이름 + 그날 기록 (`이닝/실점/K`)
- `_pitcherDayStats(name)` helper — `pitchers` list lookup → runs_allowed 사용 (자책 → 실점)
- MatchupHeader 각 팀 column 안 `_buildRecentBar` 직후 위치 (좌우 대칭)
- 홈팀 col: home 승 시 승 라벨 / 진 시 패 라벨, 원정 col: 반대

### 날짜/월 스트립
- 외곽선 `Border.all` → `boxShadow(black 0.08, blur 4, offset (0,1))`
- color transparent → paper

### 프로필 이미지
- `image_cropper: ^7.1.0` 추가 (pubspec.yaml)
- `image_cropper_for_web 5.1.0` + `image_cropper_platform_interface 6.1.0`
- 1:1 강제 crop, JPG 90, max 512
- AndroidManifest.xml UCropActivity 등록 (Theme.AppCompat.Light.NoActionBar)
- AndroidUiSettings.statusBarColor 추가 → 상단 status bar 침범 fix
- `MultipartFile filename: 'profile.jpg'` 명시 — 서버 ext check 통과
- ⚠️ image_cropper 7.1.0에 `cropStyle` named param 없음 → 원형 가이드 미지원 (정사각 grid만)

### nginx /static 권한
- `/home/ubuntu` 디렉토리 `o+x` 없어 nginx www-data 접근 불가 → 403 Forbidden
- `chmod o+x /home/ubuntu /home/ubuntu/playball /home/ubuntu/playball/backend` + `chmod -R o+rX static`
- 모든 기존 프로필 이미지 즉시 표시

### 인증 안정성
- `_RefreshResult` enum (success / authFailed / networkError)
- refresh 응답 401/403만 logout → 5xx/network 유지
- `_refreshFuture` in-flight dedup (동시 401 race 차단)
- retry fetch 실패 시 logout 안 함 (다음 요청에서 재시도)

### naver_crawler 보정 로직
- `update_live_game_players`: batter `posName or pos` fallback — homeLineup 은 posName, homeEntry 는 pos 키 → 벤치 선수도 position 정확
- `save_game_roster` 끝부분 starter fixup SQL — 같은 batting_order 의 대타 starter + 실제 포지션 sub 시 sub 를 starter 로 promote, 대타 강등
- scheduler `_fixup_starter_positions()` 안전망 sweep (`_inProgressNoStarterBatter` cycle 후 호출)

### relay_all 빈 archive 차단
- 종료 직후 game_pitches 비어있을 때 relay_list=[] archive 영속 → 이후 빈 결과 영구
- relay_list 비어있으면 archive 저장 skip + 캐시 60s 만 (재조회 유도)
- 419/420/422 기존 빈 archive DELETE

### game_summary 발송 지연
- `game_pitchers.result IN ('승','패','세이브','홀드')` 1건 이상 확인 후 발송
- 미달 시 다음 사이클로 미룸 (대타→대타 본문 X, 정상 승투/패투/홀드/세이브 본문)

### crawl_transactions FA 옛 뉴스 차단
- Google News RSS 결과 중 `published_at < today - 7일` skip
- event_date도 `published_at` 우선 (발행일 영속)
- 강백호 FA 같은 옛 시즌 뉴스 재알림 차단

### 경기 상세 UI
- 핀 토글 BSO overlay 우측 별도 (검은 반투명 캡슐 + push_pin + "고정")
- BSO overlay LIVE badge: 진행중 빨강 / 비라이브 회색 (#9A9AA3)
- BSO overlay refresh `SizedBox(16,16)` wrap → spinner/icon shift 방지
- 날씨/온도 row 위치: ScoreBoardDark ↓ MatchupHeader ↑ 사이
- floatHeaderSlivers: true (스크롤 reveal)
- NestedScrollView 제거 → SingleChildScrollView + Column(gameHeader + SizedBox(TabBarView fixed-height)) (단일 스크롤)
- 다른 경기 strip 새 위치: 필드뷰 ↓ 승투패투 ↑
- 종료 승투/패투 → MatchupHeader 안 각 팀 column 안 (좌우 대칭)
- 득점 요약 어웨이 row `mainAxisAlignment.end` (오른쪽 cluster)

### 빌드/배포
- adb wireless reconnect 필요 시 폰에서 무선 디버깅 재시작
- flutter run -d adb-R3CX90J1HJK... (specific device id)
- screencap: MSYS_NO_PATHCONV=1 adb pull (Git Bash path translation 회피)

## 구현 완료

### 경기/투구
- [x] 경기 상세 7탭 (이닝/프리뷰/로스터/투수/타자/기록/하이라이트)
- [x] 투구 위치 보기: 3단계 필터 + ABS존 + LIVE 배지
- [x] 경기 상세 공유 버튼 (share_plus)
- [x] 피타고리안 승률 (팀 순위 탭 카드에 표시)
- [x] 경기 상세 로스터 선수 클릭 → PlayerDetailScreen 이동
- [x] 중계 탭 로딩 실패: shimmer + 4초 간격 자동 재시도 (최대 3회, 오류 UI 없음)

### 선수
- [x] 선수 상세: 최근5경기 + 구종분포 바차트
- [x] /players/{id}/pitch-stats
- [x] 부문별 순위 단일 엔드포인트 (/players/rankings)
- [x] KBO 시즌 크롤러 games=0 중복행 방지 + wins/losses GREATEST 보호
- [x] 선수/구단 인기투표 (하트) — player_screen 인기투표 탭 (선수/구단 토글, 금/은/동 메달)

### 팀
- [x] 팀 순위 시리즈 결과 배지
- [x] 팀 상세 8탭 (선수명단/최근경기/등록말소/뉴스/커뮤니티/월별성적/상대전적/타순별)
- [x] 팀 순위 탭 피타고리안 승률 표시
- [x] 팀 시즌 기록 바 (팀타율/방어율/WHIP/득점/실점/홈런) — GET /teams/{id}/season-stats
  ※ game_batters에 doubles/triples 없음 → batter_stats 조인으로 집계 (season-stats 500 수정)
- [x] 이닝별 중계 득점 요약 섹션 (누가 어떻게 득점, 스코어보드 아래)
- [x] 팀 상세 뉴스 썸네일 (Google News RSS media:content/thumbnail/img 파싱)

### 캘린더
- [x] KBO경기 → 네이티브 캘린더 추가
- [x] 개인 일정 CRUD (색상 6종)
- [x] 직관 기록 + 직관 승률 표시

### 커뮤니티
- [x] 이미지 첨부, 검색, 인기글, 팀 커뮤니티 탭
- [x] 댓글 좋아요, 내가 좋아요한 글
- [x] stale-while-revalidate 캐시

### 알림
- [x] 득점 알림: "팀명 스코어:스코어 팀명 [N회 초/말]" 제목 + "[득점팀] 타자 vs 투수 — 타구결과 (N타점)" + 구종/속도 + 홈인 본문
- [x] 마이팀 등록말소 알림 (팀 팬 전체 — 선수팬 중복 방지)
- [x] 게임차 0 달성 알림 (동률 1위)
- [x] FCM 알림 인프라 (게임시작/종료/역전/연장/취소/순위변동/연승연패/홈런)
- [x] **경기 종료 알림 game_summary 즉시 발송** (이전 game_end 단순 스코어 → 승투/패투/홀드/세이브/MVP 포함)
- [x] **알림 트리거 전면 idempotent화** — notification_log DB + _already_notified/_mark_notified
  - 적용: game_start/cancelled/starter_announced/score_change/extra_innings/walkoff/game_summary/streak/rank_change/gb_zero/pennant_race/pitcher_change/fav_hr/fav_lineup
  - scheduler 재시작 시 누락/중복 모두 해소
- [x] **연승/연패 임계값 5→3**: 3연승부터 알림 (sub_id에 count 포함, 매 경기 증가마다)
- [x] textRelays reversed 순회 (Naver 최신순 반환) + type 23(원정팀) 추가 → 알림 본문 타구결과/구종/홈인 정상 표시
- [x] 홈인 정규식 개선: 조사 어미(로/서/에/으/며/면/도/만/나) reject → "실책으로 홈인" 같은 오추출 차단

### 인증/유저
- [x] 비밀번호 찾기/재설정, 이메일 인증, 프로필 이미지

### UX/성능
- [x] 다크모드, 마이팀 개인화 홈, 통합 검색
- [x] Shimmer 스켈레톤 (home/player/team)
- [x] cached_network_image 전체 적용 (fadeIn 없음)
- [x] LocalCache stale-while-revalidate (home/mypage/team/community)
- [x] DB 커넥션 풀, TTL 캐시, GZip, ThreadPoolExecutor
- [x] 카카오맵 구장 화면
- [x] 투구 위치 히트맵, 타자vs투수 상대전적
- [x] 검색 최근 기록 (SharedPreferences, 최대 10개)
- [x] GameCard 승리팀 후광 효과, 팀 순위 표시, 다음 시리즈 상대팀
- [x] 서버 재시작 시 daily_stats 누락 자동 복구 (_recover_missed_daily_stats)
- [x] 이미지 공유 팀 로고 + 승투/패투 얼굴 수정 (precacheImage + CachedNetworkImageProvider, Naver CDN 403 우회)
- [x] 등록말소 배너 자정 자동 숨김 (60초 타이머 setState)
- [x] 직관승률 랭킹 API — GET /user/stadium-ranking (5회 이상 기준)
- [x] 홈화면 게임카드 날짜 race condition 근본 해결 (_loadGen generation counter + DioExceptionType.unknown 재시도)
- [x] 게임카드 스코어 정중앙 배치 (CrossAxisAlignment.center)
- [x] 게임카드 다음 시리즈 텍스트 overflow 수정 (Row mainAxisSize.min 제거 + ellipsis)
- [x] 실시간 필드뷰 (야구장 다이아몬드 CustomPainter + BSO 카운트, _buildLiveStatus 교체)
- [x] 필드뷰 비라이브 표시 — 종료/예정 경기에서 홈팀 수비 라인업 정적 표시 (_buildFieldSection)
- [x] 득점 상세 홈인-타석 연결 — 홈인 이벤트를 preceding 타석 아래 들여쓰기 표시
- [x] 과거 날짜 로딩 속도 개선 — LocalCache TTL 86400초 + 서버 @cached(300)
- [x] 중계 타자별 헤더 Flexible 적용 (이름 overflow 방지)
- [x] pitch-locations batter 타순 접두사 제거 ("N번타자 이름" → "이름", DB+실시간 양쪽)
- [x] FCM 서비스 계정 키 복원 (서버에서 사라진 firebase-service-account.json 재업로드)
- [x] FCM 완전 활성화 (firebase-admin 7.4.0, push_tokens DB, _get_app() OK 확인)
- [x] **DB pool 자동 복구** — PoolError 'exhausted' 감지 시 _reset_pool() → closeall() → 재생성
- [x] **필드뷰 주자 표시 수정** — Naver currentGameState.base1/2/3가 타순번호(1-9) 반환 → game_batters.batting_order 조회 추가 (team_side = 공격팀)
- [x] **API 캐시 5개 엔드포인트 추가** — pitch-types(60s) / pitch-locations(60s) / weather(300s) / highlights(1800s) / relay(10s)
- [x] **relay_all/pitch-locations max_workers 9→4 + Naver timeout 10→5초** — 동시 부하 + 워커 점유 축소
- [x] **ApiService._dedupGet** — 동일 GET URL in-flight Future 공유 (캐시 stampede 차단)
- [x] **GameDetailScreen _isLoadingInFlight 가드** — _loadData 재진입 방지
- [x] **VPS swap 1G→4G 확장** + swappiness 60→30 (OOM 방지)

## 세션 변경사항 요약 (2026-06-05 ~ 06-06) — UI/UX 정리 + 다크모드 시인성

### Analyzer cleanup (338 → 24, app/lib=0)
- `dart fix --apply`: curly_braces 39 + null_aware 9 + 기타 (14 파일)
- `withOpacity` → `withValues(alpha:)` 90개 (7 파일)
- 미사용 import/method/field/local var 일괄 제거 (~1400 lines)
- `__/___` → `_` wildcard (Dart 3.7+)
- `Matrix4.translate` → `translateByDouble` (deprecated)
- `surfaceVariant` → `surfaceContainerHighest`
- `DropdownButtonFormField.value` → `initialValue`
- `print` → `debugPrint`
- `letterSpacing` 음수(-0.6/-0.3/-0.2/-0.1/-0.4/-0.5) → 0 일괄 (한글 자간 정책 통일)
- **critical fix**: `letterSpacing: 05` typo (Dart parser = int 5, 한글 자간 5px 폭증 → GameCard overflow) — 5 곳 fix
- BuildContext async gap 가드 (mypage 로그아웃/탈퇴, post_detail 신고)
- SCREAMING_SNAKE → camelCase (_kR_OUT 등)

### Design tokens 도입 + migration
- `design_tokens.dart`: `Typo`/`SemColor`/`Space`/`Radii` 4 클래스
- `SemColor.panelDark` (#111113), `SemColor.brand(context)` 테마-aware helper
- 19 파일 inline `Color(0xFF111113)` → `SemColor.panelDark` migration
- `MaterialApp.builder` `MediaQuery.withClampedTextScaling 0.85~1.3` (a11y 큰글자 깨짐 방지)

### Theme (`AppTheme`) 강화
- `textTheme` 한글 가독성: body/title height 1.4/1.3, letterSpacing 0
- `AppColors.primaryDark` #F4F4F5 → **#E5E5E7** (Apple HIG 순백 회피)
- `AppColors.borderDark` #26262C → **#33333A** (다크 contrast AAA)
- `SnackBarTheme`: 다크는 surface2Dark + elevation 6 (scaffoldDark 동일 시인성 손실 차단)
- `BottomSheetTheme`: 반경 16 + showDragHandle false (manual handle과 중복 방지)
- `DialogTheme`: 16
- `TabBarTheme`: labelStyle w800, indicatorSize.label, unselected textTertiary
- `InkSparkle` splashFactory 활성 (다크 alpha 0.08/0.12 상향)

### UI 기능
- **GameCard compact mode**: AppBar 토글 (view_compact ↔ view_agenda), 1줄 카드 ~64px, LocalCache.setFlag 영구 저장
- **AppBar breadcrumb (game_detail)**: 2단 title "팀 vs 팀\n중계 · 키플레이어" (subTab 동적)
- **베이스 affordance**: 필드뷰 베이스 tap → bottom sheet (1·2·3루 + 주자 정보)
- **LIVE pulse dot**: AnimationController opacity 0.55~1.0 easeInOut 1.4s
- **AnimatedSwitcher 스코어**: fade → slide+fade 250ms easeOutCubic
- **패팀 점수 dim**: opacity 0.45 + fontSize 30pt (vs 승팀 34pt)
- **취소 status pill**: lineThrough + cancel icon + SemColor.danger
- **마이팀 badge**: solid fill → 반투명 + border + star icon
- **GameCard 외곽선**: borderDark AAA, 마이팀 width 2
- **드래그 핸들**: `SheetHandle` 공통 위젯
- **AppErrorView, PlayerAvatar, TapTarget**: common_widgets

### Restoration framework
- `RestorationMixin` + `RestorableInt × 3` (game_detail: tabIdx, lineupSub, statsSub)
- `MaterialApp.restorationScopeId: 'playball_root'`
- 프로세스 재시작 후 게임 상세 탭 복원

### Dio 네트워크
- `IOHttpClientAdapter.maxConnectionsPerHost = 20` (default 6 → WiFi 동시 호출 큐잉 완화)
- Debug interceptor `kDebugMode only`: in-flight 카운터 + per-request timing 로그

### 다크모드 시인성 (panelDark 검정 겹침 해결)
- **team_screen TabBar** indicator/labelColor → 분기 (다크모드 탭 라벨 안 보임 fix)
- **team_screen 부문별 카테고리 chip** 선택 white-on-white invisible → black 분기 + 비선택 t.ink2
- **team_screen 마이팀 외곽선/star icon** → favBorder 분기
- **team_screen _buildSegmentControl** → 분기
- **team_screen 포디움 bg** → 다크 #1F1F24
- **team_detail CircularProgressIndicator** × 6 → 분기
- **team_detail 서브탭 segment** 선택 색/텍스트 → 분기
- **login_screen** 'PlayBall' title + baseball icon → brand 분기
- **calendar_screen** AppBar title + star icon + 직관 승률 카드 + 랭킹 시트 + FAB + 그리드 선택 셀 → brand
- **community_screen** FAB + 카테고리 ChoiceChip + 팀 칩 + _tagChip + 인기 activeColor + 맛집 시트 → brand
- **create_post_screen** 인증/이미지 첨부/@ 링크 chip/icon/text → brand
- **game_detail** CircularProgressIndicator 다수 → brand

### 백엔드
- `crawl_pitch_locations.py` insert 전 `re.sub('^\d+번타자 ', '', batter)` (재발 방지)
- DB: `game_pitch_locations` 101,809 행 batter_name prefix strip 마이그레이션
- `highlights` endpoint: 진행/예정/취소 게임 슬로우 YouTube 크롤 skip
- `relay_all` 빈 archive payload fallthrough + ON CONFLICT DO UPDATE
- `scheduler 30초 사이클` 의도된 dedup 결론 (Naver API rate limit + DB load)

### 오버플로우 보강
- compact card teamSide Text → Flexible + maxLines 1 + ellipsis
- AppBar breadcrumb maxLines:1 + ellipsis
- GameCard stadium chip 외부 Flexible + 내부 Text Flexible + softWrap false

## 세션 변경사항 요약 (2026-06-06 오후) — UX 버그 + 디자인/발견성 (커밋 8a8974b~decb85f)

### UX 버그 수정
- notifications Dismissible: onDismissed 단독 → `confirmDismiss`에서 API 호출, 실패 시 false ("dismissed widget still in tree" 크래시 방지)
- notifications `_readAll` try/catch + 실패 스낵바
- post_detail `created_at.substring(0,10)` length 가드 (RangeError)
- search 오류 상태 분리 (`_error` flag) — 네트워크 실패가 "검색 결과가 없습니다"로 오인되던 것 해소 + 재시도 버튼

### 다크모드 가시성
- `CircularProgressIndicator(color: SemColor.panelDark)` → `SemColor.brand(context)` 4곳 (search/player/player_detail/mypage)
- notifications 미읽음 bg/dot isDark 분기
- post_detail 댓글바 border → `Theme.dividerColor`
- **theme ElevatedButton 다크 반전** (밝은 버튼+어두운 텍스트) — 검정 on 검정 윤곽 소실 fix
- focusedBorder 다크 primaryDark 분기
- 프로필 카메라 배지 흰 테두리 1.2

### 디자인 토큰/일관성
- `AppColors.live/win/lose` 삭제 (사용처 0, SemColor.live와 색 상충 #22C55E vs #E53935)
- `SemColor.info = success` alias 명시
- `circular(99)` → `999` 통일 (7곳)
- 극소 폰트 상향: 7→8 (필드뷰 라벨, W/L 뱃지), 8.5→9/9.5 (필드뷰 이름, 게임차)
- 메타텍스트 `grey[400]`(대비 1.95:1) → `grey[600]`(4.6:1) 12곳
- PS 확률 범례 `#E0E0E4`(1.1:1) → `#9A9AA2`
- 알림 emoji 아이콘 → Material icon + 타입색 원형 칩 36px (`_typeIcon` → `(IconData, Color)` record)
- Hero 전환: player_screen 카드 ↔ player_detail 아바타 (`tag: 'player_$id'`)

### 발견성 (affordance)
- IconButton tooltip 21곳 (TalkBack 겸용): 비밀번호 표시, 월 이동, 삭제, 지우기, 공유, 좋아요, 즐겨찾기/마이팀, 닫기 등
- 핀 캡슐 Tooltip "필드뷰를 화면 상단에 고정" 2곳
- 1회 힌트 (LocalCache flag 패턴, onboarding_helper 동일): `hint_notif_swipe` (알림 스와이프 삭제), `hint_base_tap` (필드뷰 베이스 탭)
- post_detail RefreshIndicator + `_loadPost` 첫 로드만 스피너 (refresh 깜빡임 방지)
- player_detail AppBar `compare_arrows` → PlayerCompareScreen 진입점
- **`widgets/stadium_ranking_sheet.dart` 신규** — 직관승률 랭킹 시트 공용 추출, 캘린더 + 커뮤니티 AppBar(emoji_events) 양쪽 진입

### 보류 (대량 치환 — 실기 검증 선행 필수, letterSpacing 사고 전례)
- fontSize 11→12 (239곳), `Colors.grey` 무지정 토큰화 (123곳), w800 정리 (81곳), 인라인 height 1.4 — 화면 단위 점진 권장

### 실기 확인 필요 (이번 세션분)
- 알림 아이콘 칩 시인성 + 스와이프 1회 힌트
- Hero 전환 (사각 카드 → 원형 아바타 morph 어색하면 롤백)
- ElevatedButton 다크 반전 전체 화면 영향
- post_detail 당겨새로고침 / 커뮤니티 랭킹 시트

## 세션 변경사항 요약 (2026-06-06 저녁) — 게임카드/필드뷰/득점요약 개편 + scheduler 근본이슈

### 🔑 근본 이슈: playball-scheduler 별도 서비스 미재시작
- scheduler = **별도 systemd 서비스** (`playball-scheduler.service`, `-u` python 직접 실행)
- 기존 배포 루틴이 `restart playball`(API)만 → **06-04~06 scheduler 패치 전부 메모리 미적용**
  - game_summary MVP-only 발송 (result 대기 gate 미적용 — 종료 9초 만에 발송 로그로 확인)
  - 류현진 "5승 달성" 오보 (stale 임계값 일괄 발송)
- 주요 명령어의 배포 커맨드에 양 서비스 재시작 반영됨 — **백엔드 수정 시 반드시 둘 다 재시작**

### 백엔드
- **user.py 라우트 순서**: `DELETE /notifications/read`를 `/{notif_id}`보다 먼저 (read→int 파싱 422 → "삭제 실패" fix)
- **마일스톤 '통과' 조건**: `>= threshold` → `prev < t <= curr` (이번 경기 기여분 차감: 타자 gb 컬럼, 투수 result/K). 시즌+통산+young 전부. 첫 평가 시 지난 임계값 일괄 발송 차단
- **weather_service stale-while-revalidate**: cold/만료 시 요청 스레드 직렬 외부 API(구장 5곳×5s timeout) → **홈 당일 5초 지연 원인**. daemon 스레드 배경 갱신 + stale 즉시 반환 (`_spawn` + `_refreshing` set)
- **field_view.next_batter**: 현재 타자 batting_order+1 (대타 최신 row), `order` 포함
- **field_view.batter.bats** 추가 (좌/우/양)

### 게임카드 (home_screen)
- **마이팀만 풀(hero) 카드, 일반 = compact 행** (`compact: _compactMode || (_favoriteTeamIds.isNotEmpty && !isMyTeam)`)
- **compact 3층 구조**: 1층 로고+팀명+스코어(vs) / 2층 상태(종료·N회·시간) / 3층 승패투수·선발
- 날씨/구장: chip → **plain text 한 줄** (스코어 아래 중앙, `☀️ 24° · 잠실`), 지도 탭 기능 제거 (`_weatherText()` helper)
- 스코어 `:` 가시성: line2 → ink3 w600
- 라이브 회차 중복 제거: 헤더 pill `● LIVE`만, 회차는 스코어 밑 단일
- 승팀 오버레이 로고: 고정 left:-70 → LayoutBuilder 동적 — **작은 팀로고(46px) 수직선 정렬** (`로고중심 = 15 + side/2`)
- **경기 없는 날 날짜 스트립 비활성**: calendar API 월별 lazy 로드 (`_gameDates`/`_loadedMonths`), 없는 날 opacity 0.35 + 탭 차단

### 경기 상세 (game_detail)
- **필드뷰 항상 상단 고정**: `_fieldPinned = true` final, 고정 토글 캡슐 2곳 제거, 핀 힌트 SnackBar 제거 (베이스 탭 힌트만 유지 `base_hint_shown`)
- 핀 패널: 높이 505/410 → **482/408** (하단 빈 여백 제거, overflow 2.4px 보정 포함), rounded bottom 16 + 분리 그림자
- '다른 경기' 라벨 삭제, BSO `B1` → `B` (dots만)
- **다음타석 오버레이** (우하단 2층 텍스트): `다음타석 ↵ N번 타자 ○○○` (black α0.55, rounded 8)
- 필드뷰 주자 dot = painter 베이스 중심 좌표 일치 (base1 208,208 / base2 150,150 / base3 92,208)
- **좌/우타 배터박스**: bats 좌/양 → x=168 mirror (우타 132, 홈플레이트 150 대칭)

### 득점요약 전면 재설계 (한화-롯데 429 실데이터 검증)
- 발견 1: **Naver relay title에 (N타점) 표기 부재** → 텍스트 파서가 적시타 누락
- 발견 2: **relay archive 동일 이벤트 이중 저장** (비인접 [타석][홈인][타석][홈인] 패턴) → 행 중복
- **타점 산정 = 타석 뒤 홈인 이벤트 수 + (홈런 시 본인 1)** — 텍스트 표기 무관
- byHalf 구성 시 최근 4개 윈도우 동일 (type,title,text) dedup
- 표기: `[5말][로고] 김현수 우중간 적시 2루타 [2타점]` — 홈=좌 / 원정=우 미러, 이름 natural width, 타점 badge 48px (홈런 amber), desc 괄호 보조설명 제거
- standalone 홈인(폭투 등): `주자명 홈인 (타석 외)` + 득점 badge
- 누적 스코어(2:0) badge / 상세 play rows(playWidgets dead code ~120줄) 제거

### 순위 탭
- **PS 확률 = 팀 순위 탭 내 세부 카테고리 chip** (시즌/전반기/최근10 옆 토글, `_showPsView`) — 별도 탭/카드 내 bar 제거
- `_psChildren(isDark)` — 범례 + 팀별 stacked bar 리스트 (같은 ListView 영역 전환)
- **PS 0% 버그**: odds API 키 `team_id` 아님 → **`id`** (oddsById lookup miss)
- 순위 카드에서 PS bar/TOP2 라벨/범례 제거 (stages 계산 삭제)

### 진단 노트
- 서버 응답: warm 4ms / PC HTTPS 67ms (첫 요청만 DNS 0.7s) — 서버는 문제 아님
- 이닝별 중계 vs 필드뷰 속도차: relay TTL 10s vs relay_all 30s + Naver textRelays 타석 종료 후 일괄 발행 (소스 지연). 진행 이닝만 TTL 단축 옵션 보류
- 알림함 body는 user_notifications에 전체 저장 — MVP-only는 발송 시점 데이터 문제였음 (위 scheduler 이슈)

### 실기 확인 필요 (저녁 세션분)
- compact/hero 혼합 리스트 + compact 3층 (마이팀 미설정 = 전부 풀 카드 유지 확인)
- 날짜 스트립 월요일(06-08) 비활성 + 미래 월 lazy 로드
- 다음타석 오버레이 (라이브), 좌타자 배터박스 mirror
- 득점요약 — 다른 경기들 (밀어내기/실책 득점 케이스)
- PS 확률 chip 토글 + % 표시
- 핀 패널 478→482 후 overflow 재발 여부 (좁은 화면)

## 진행 예정 기능

### 즉시 (단순 수정 / 한 세션 내 완료 가능)
- [x] 홈스크린 검색 입력 시 화이트모드 텍스트 흰색 버그 수정
- [x] 게임카드 최근 5경기 결과에서 "홈"/"원정" 텍스트 삭제
- [x] 홈스크린 날짜 스트립에 "오늘" 바로가기 버튼 추가
- [x] 홈 스크린 마이팀 카드 + 순위탭 등수: "1위", "2위" 형태로 변경
- [x] 등말소 탭 중복 표시 제거 (ROW_NUMBER PARTITION BY player_name, change_type)
- [x] 부문별 순위 업데이트 안 되는 버그 — KeepAlive 제거로 탭 재진입 시 갱신
- [x] 타순별 탭: 선수 이미지 추가 + 클릭 시 선수 상세 이동
- [x] 직관승률 랭킹 Flutter UI (캘린더 배너 → 랭킹 버튼 → 하단 시트)

### 중기 (기능 설계 필요 / 2~3 세션)
- [x] 게임카드 다음 시리즈: 상대팀 팀 로고 표시 + 예정 경기에도 다음 시리즈 추가
- [x] 게임카드 정렬: 팀로고 기준 일직선 (팀로고-등수/홈어웨이-선발투수-최근5경기-다음시리즈)
- [x] 홈스크린/캘린더 스크롤 시 AppBar 색 변화 방지 (surfaceTintColor: transparent)
- [x] 경기 상세 헤더: 팀명 위에 팀로고 배치
- [x] 경기 상세 득점 요약 접기/펼치기
- [x] 경기 상세에서 미니 게임카드로 다른 경기 상세 바로 이동 (상단 가로 스크롤 스트립)
- [x] 투구위치 보기를 이닝별 중계 각 타자마다도 볼 수 있게 추가
- [x] 선수탭 3열 카드 형태 (얼굴+등번호+이름 증명사진 스타일)
- [x] 재계약 안 한 외인 선수 팀 명단에서 삭제 — team_id=NULL (쿠싱/아데를린/양가온솔/베니지아노/오러클린/로젠버그)
- [x] 캘린더 탭 마이팀 일정만 표시 (별 아이콘 토글)
- [x] 직관 기록 UI 개선: FAB → "일정 추가" / "직관 기록" 분리
- [x] 순위 스크린 팀 기록 탭 추가 (타격/투수 카테고리별 팀 랭킹)
- [x] 마이페이지 버튼 모든 스크린에 존재 (경기/순위/선수/캘린더/커뮤니티)
- [x] 선수 상세 시즌 트렌드 스탯 변경 가능하게 (타자: AVG/안타/홈런/타점/볼넷, 투수: ERA/이닝/탈삼진/볼넷/자책)
- [x] 커뮤니티 UI 인스타그램 형태 개선 (이미지 있는 글은 이미지 먼저 표시)

### 장기 (설계/리소스/난이도 높음)
- [x] 실시간 중계 필드뷰 표시 (BSO + 야구장 다이아몬드 CustomPainter, 진행중 경기)
- [x] 포스트시즌 진출 확률 — Monte Carlo 10,000회, GET /teams/postseason-odds @cached(300), 순위탭 하단 바차트
- [ ] 홈화면 위젯 (Android AppWidget — native kotlin 필요)

### 추가 기능 (완료)
- [x] 직관 통계 강화 — `/user/stadium-stats` (구장별/월별) + 캘린더 통계 버튼/바텀시트
- [x] 팬 승리예측 투표 — `/games/{id}/predict`, `/games/{id}/predictions` + GameCard 투표 UI (예정경기)
  ※ game_predictions 테이블: user_id, game_id, predicted_team_id, UNIQUE(user_id, game_id)

## 알려진 버그 / 성능 이슈

- push_tokens 등록 사용자 매우 적음 (현재 1명) — 다수 유저 알림 시나리오 검증 불가
- 라이브 경기 pitch-locations cold cache 첫 호출 Naver fetch 의존 (캐시 60s, 첫 진입 ~2초)
- scheduler 30초 사이클 → 빠른 연속 이벤트(스코어 + 즉시 회복) 일부 합쳐서 1개 알림으로 통합 (의도된 dedup, Naver API rate limit + DB load 고려)
- `SemColor.panelDark` 잔여 hardcoded 59건 — 대부분 `tk.ink` 토큰 할당 (이미 분기), TableRow header bg (테이블 border로 구분). minor impact, 점진 cleanup 가능

## 앞으로 해야할 것

### 즉시 가능 (low risk)
- [ ] 실기/에뮬레이터 verify — UI 변경 누적 다수 (compact mode, breadcrumb, base sheet, 다크모드 brand 분기, theme 일괄 적용)
- [ ] `letterSpacing` typo 류 방지: pre-commit grep hook (`-?\d*\.?\d+` 잘못 변환 감지)
- [ ] `SemColor.panelDark` 잔여 59건 점진 `SemColor.brand(context)` 치환
- [ ] AnimatedSwitcher 확장 (status pill, rank 변경, recent5 — 현재 정적)

### 검증 / 도구 도입 권장
- [ ] **Golden tests** 도입 — GameCard / TeamCard / PlayerCard 다크+라이트 4 골든 → CI 시각 회귀
- [ ] **device_preview** 패키지 — 개발 중 모든 사이즈 한눈 + textScaler 슬라이더
- [ ] **accessibility_tools** wrap — 다크 contrast / 터치 영역 / Semantics 자동 경고
- [ ] **DevTools Performance overlay** — `_LivePulseDot` ×5 등 jank 측정 (저사양 폰)
- [ ] CI pre-commit hook: `letterSpacing 0[1-9]` / `SemColor\.panelDark.*color:` hardcoded grep

### 중기 (1~2 세션)
- [ ] empty catch 41건 → debugPrint 추가 (silent fail 가시화)
- [ ] non-null `!` 53건 audit (대부분 setState 후 안전이지만 일부 guard 추가 권장)
- [ ] 빈 텍스트 상태 / 에러 상태 — `AppErrorView` 전체 화면 적용 (현재 일부만)
- [ ] 시즌 트렌드 차트 grid dash 외 chart 일관성 (다른 chart도 동일 스타일)
- [ ] 카드 모서리 반경 `Radii` 토큰 점진 적용 (현재 12/14/16/18 혼재)
- [ ] **GameCard hierarchy** #4 후속 — compact 외에 "최소" 모드 (스코어만)
- [ ] Spacer + Flexible 조합 audit (모든 Row layout)

### 장기
- [ ] 홈화면 위젯 (Android AppWidget — native kotlin)
- [ ] Flutter state restoration 추가 화면 (home/team/player)
- [ ] 베이스 affordance 확장: 수비수 tap 시 선수 정보, 타자 tap 시 detail
- [ ] 동적 시간 표시 ("18:30" → "1시간 후 시작" 주기 timer)
- [ ] 다국어 (i18n) — skip 확정 상태

### 다크모드 잔여 점진
- [ ] forgot_password_screen (213/218 hardcoded)
- [ ] notifications_screen panelDark icon/text
- [ ] my_page_screen 일부 hardcoded
- [ ] phone_verify_screen panelDark
- [ ] auth/register_screen panelDark
- [ ] game_detail TableRow header (visible via border, low priority)

## 검증 미완료 항목 (실기 테스트 필요)
다음 누적 변경은 정적 분석 통과했으나 시각/동작 확인 필요:
- compact 토글 hint SnackBar
- 베이스 affordance bottom sheet (1·2·3루 tap)
- LIVE pulse 애니메이션 (5경기 동시 시 GPU 부담)
- AppBar breadcrumb 2단 표시 + 긴 팀명 ellipsis
- 패팀 점수 dim opacity + 30pt
- Restoration 프로세스 재시작 시나리오
- Dio 동시 호출 20 한도
- 다크모드 모든 화면 가시성 (특히 다크 surface 위 brand 색 contrast)
- textScaler 1.3 시 모든 Row overflow
- SnackBar surface2Dark bg 분리감

### WiFi 환경 체감 로딩 느림 (2026-06-04 진단 중)
서버 측 최적화 적용했지만 사용자 체감 차이 존재. **모바일 직접 nslookup+curl 측정 시 WiFi vs 셀룰러 raw 동일** → 네트워크 자체 문제 아님.
**서버 측 적용 완료:**
- nginx HTTP/2 활성화 (`listen 443 ssl http2;`)
- ssl_session_tickets on (TLS resume 빠름)
- TCP BBR congestion control (`net.ipv4.tcp_congestion_control=bbr`)
- TCP fastopen 양방향 (`tcp_fastopen=3`)
- slow_start_after_idle=0 (keep-alive 약신호 회복)
- qdisc fq (BBR pair)
- tcp_notsent_lowat=16384
**잔여 의심 후보 (향후 진단):**
1. Dio/HttpClient maxConnectionsPerHost=6 → 게임 상세 10+ 동시 호출 시 큐잉
2. Naver CDN (sports-phinf.pstatic.net) 이미지 라우팅 WiFi unstable
3. WiFi 백그라운드 트래픽 (카카오톡/유튜브 등) 대역폭 점유
4. WiFi 2.4GHz 혼잡 (5GHz 대비)
5. 앱 콜드 스타트 첫 DNS+TLS (curl은 이미 캐시 hit 상태)
**진단 step (다음 세션):**
- A. 모바일에서 Naver CDN 이미지 직접 측정 (WiFi vs 데이터)
- B. Dio interceptor 로깅 (동시 호출 수 + per-request timing)
- C. maxConnectionsPerHost 6→20 변경 후 비교
- D. 폰 백그라운드 트래픽 비교

## 해결됨 (이전 알려진 이슈)

- ~~relay_all 서버사이드 캐시 없음~~ → 30초 캐시 + 완료 이닝 메모리 캐시
- ~~DB pool 고갈~~ → _reset_pool() 자동 복구
- ~~알림 본문 타구결과 빈값~~ → textRelays reversed + type 23 추가
- ~~scheduler 재시작 시 알림 누락/중복~~ → notification_log dedup
- ~~필드뷰 주자 이름/이미지 미표시~~ → batting_order 1-9 lookup 추가
- ~~동명이인(박준영/이승현) game_pitchers 합쳐짐~~ → _reinsert_dupe_name_rows + _fix_dupe_name_player_ids (Naver pcode 기반 자동 재INSERT)
- ~~game_summary 미발송~~ → outer dedup mark 먼저로 인한 내부 체크 즉시 return → 내부 체크 제거
- ~~한화 두산 11회 연장 알림 누락~~ → inning sub_id 적용 (회차별 dedup)
- ~~선수 상세 최근 5경기 미업데이트~~ → daily_stats dedup으로 매 사이클 호출 (newly_finished 의존 제거)
- ~~FCM 핸드폰 미수신~~ → AndroidConfig high priority + channel_id='playball_default'
- ~~예측 모델 vote UI~~ → ML 기반 win-prediction (LR+RF 앙상블, RF weight grid search, 70.1% acc)
