# PlayBall

KBO 야구 앱 | Flutter + FastAPI + PostgreSQL

## 인프라
- 서버: Oracle Cloud Ubuntu 22.04 | 168.107.61.147:8000
- SSH 키: `C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key`
- DB: localhost:5432(서버)/5433(터널), db=playball, user=playball_user, pw=playball1234
- 레포: https://github.com/Aa26178787/playball

## 폴더 구조
- 로컬: `C:\Users\qq772\playball\` → `app\`(Flutter), `backend\`(FastAPI)
- 서버: `~/playball/backend/` ← WorkingDirectory (api/, database/, crawler/)

## 주요 명령어
```bash
ssh -i "C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key" ubuntu@168.107.61.147
cd ~/playball && git pull origin main --rebase && sudo systemctl restart playball
sudo journalctl -u playball -f
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
- baseUrl: http://168.107.61.147:8000
- 인증: JWT Bearer → SharedPreferences `access_token`

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
- database/connection.py — ThreadedConnectionPool(minconn=5, maxconn=20) + _PooledConn 래퍼
- crawler/naver_crawler.py (**절대 수정 금지**)
- crawler/scheduler.py
  - _get_scoring_play_detail: Naver 중계 API 실시간 득점 타자/투수/타구 파싱
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
GET /games/date/{date_str}   (home_starter, away_starter, weather, recent_5 포함) @cached(30)
GET /games/{id}              (innings, pitchers, batters) @cached(30)
GET /games/{id}/relay        실시간(진행중만)
GET /games/{id}/relay_all    ※ ThreadPoolExecutor 병렬 이닝 fetch
GET /games/{id}/roster
GET /games/{id}/preview      (선발투수, 상대전적)
GET /games/{id}/record_detail
GET /games/{id}/weather      (실내=indoor:true, 야외=temp/humidity/wind/pop)
GET /games/{id}/pitch-types  → {pitchers:{name:[{type,count,pct}]}}
GET /games/{id}/pitch-locations → {pitches:[{x,z,result,pitcher,top_sz,bot_sz}], pitchers:[...]}
  ※ ThreadPoolExecutor 병렬 이닝 fetch
  ※ x=횡위치(ft), z=높이(ft, 물리궤적 계산), result=ball/strike/swing/foul/hit/other
GET /games/{id}/highlights → {highlights:[{title,url,source,published_at}]}
  ※ DB 우선 조회, 없으면 Google News RSS 실시간 크롤
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
- 캐시: games/favorite-teams/rankings — stale-while-revalidate (games TTL=5분)

### game_detail_screen.dart
- 탭 7개 (isScrollable): 이닝/프리뷰/로스터/투수/타자/기록/하이라이트
- 투수 탭: 구종차트 + 투구위치 보기 → PitchLocationSheet
- 하이라이트 탭: url_launcher 외부 브라우저
- 공유 버튼: share_plus
- 자동새로고침: 30초 (진행중만)

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

### naver_crawler.py (**절대 수정 금지**)
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
- **DB 커넥션 풀**: ThreadedConnectionPool(5-20), _PooledConn 래퍼 (close()→putconn())
- **TTL 인메모리 캐시** (api/cache.py): @cached(30)/60/300/3600 데코레이터
  - /games/today, /games/date → 30초
  - /games/{id} → 30초
  - /teams/rankings → 60초
  - /players/rankings, /players/{id} → 300초
  - /teams/ → 3600초
- **GZipMiddleware**: minimum_size=500 (JSON ~65% 압축)
- **ThreadPoolExecutor 병렬 이닝 fetch**: relay_all + pitch-locations (직렬 ~1800ms → 병렬 ~200ms)
- **GET /players/rankings 단일 엔드포인트**: 14→1 API 호출 (랜덤 빈탭 버그 해결)

### 클라이언트사이드
- **cached_network_image** 전체 적용 (모든 NetworkImage 대체)
- **Shimmer 스켈레톤**: home/player/team 화면 로딩 시 (CircularProgressIndicator 제거)
- **LocalCache stale-while-revalidate**: 캐시→즉시표시 후 백그라운드 갱신
  - 재시작/재로그인 시 스피너 없이 즉시 데이터 표시
  - 로그아웃 시 clearUser() 자동 호출

## 주의사항
- 과거경기 수정: game_date < '2026-05-09' 조건 필수
- 동명이인: team_id 기준 조회
- 서버 백엔드 루트: ~/playball/backend/
- git push: --force 필수 (모노레포)
- git push/pull 원격 작업은 확인 없이 바로 실행
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
- naver_crawler.py **절대 수정 금지**
- firebase-service-account.json 서버 전용 (git push 금지)

## FCM 활성화 방법 (인프라 완료 — 수동 작업 필요)
1. Firebase 콘솔 → Android 앱 등록 (com.playball.app)
2. `google-services.json` → `app/android/app/google-services.json`
3. 서비스 계정 키 → 서버 `firebase-service-account.json` (이미 업로드됨)
4. `flutterfire configure` → `firebase_options.dart` 생성
5. Claude에게 "FCM 활성화 마무리해줘" 요청

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
- [x] 득점 알림: "팀명 득점!" 제목 + 타자/타구/상대투수 본문
- [x] 마이팀 등록말소 알림 (팀 팬 전체 — 선수팬 중복 방지)
- [x] 게임차 0 달성 알림 (동률 1위)
- [x] FCM 알림 인프라 (게임시작/종료/역전/연장/취소/순위변동/연승연패/홈런)

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
- [x] 이미지 공유 팀 로고 수정 (Image.memory 직접 로드로 RepaintBoundary 신뢰성)
- [x] 등록말소 배너 자정 자동 숨김 (60초 타이머 setState)
- [x] 직관승률 랭킹 API — GET /user/stadium-ranking (5회 이상 기준)

## 진행 예정 기능

### 즉시 (단순 수정 / 한 세션 내 완료 가능)
- [ ] 홈스크린 검색 입력 시 화이트모드 텍스트 흰색 버그 수정
- [ ] 게임카드 최근 5경기 결과에서 "홈"/"원정" 텍스트 삭제
- [ ] 홈스크린 날짜 스트립에 "오늘" 바로가기 버튼 추가
- [ ] 홈 스크린 마이팀 카드 + 순위탭 등수: "1위", "2위" 형태로 변경
- [ ] 등말소 탭 중복 표시 제거 (같은 날짜 동일 내용 중복, 웨이버→말소 중복 등)
- [ ] 부문별 순위 업데이트 안 되는 버그 확인/수정
- [ ] 타순별 탭: 선수 이미지 추가 + 클릭 시 선수 상세 이동
- [ ] 직관승률 랭킹 Flutter UI (API 완료 — /user/stadium-ranking)

### 중기 (기능 설계 필요 / 2~3 세션)
- [ ] 게임카드 다음 시리즈: 상대팀 팀 로고 표시 + 예정 경기에도 다음 시리즈 추가
- [ ] 게임카드 정렬: 팀로고 기준 일직선 (팀로고-등수/홈어웨이-선발투수-최근5경기-다음시리즈)
- [ ] 홈스크린/캘린더 스크롤 시 AppBar 색 변화 방지 (PLAYBALL + 아이콘 영역)
- [ ] 경기 상세 헤더: 팀명 위에 팀로고 배치
- [ ] 경기 상세 득점 요약 접기/펼치기 + 득점 내용 상세 (예: ㅇㅇㅇ 우중간 2루타 3타점)
- [ ] 경기 상세에서 미니 게임카드로 다른 경기 상세 바로 이동
- [ ] 투구위치 보기를 이닝별 중계 각 타자마다도 볼 수 있게 추가
- [ ] 선수탭 3열 카드 형태 (얼굴+등번호+이름 증명사진 스타일)
- [ ] 재계약 안 한 외인 선수 팀 명단에서 삭제 (과거 경기 기록 유지)
- [ ] 캘린더 탭 마이팀 일정만 표시
- [ ] 직관 기록 UI 개선: FAB → "일정 추가" / "직관 기록" 분리, 직관 기록에 이미지 첨부
- [ ] 순위 스크린 팀 기록 탭 추가 (팀타율/방어율/WHIP 등 부문별 전체 카테고리)
- [ ] 마이페이지 버튼 모든 스크린에 존재 (경기/순위/선수/캘린더/커뮤니티)
- [ ] 선수 상세 시즌 트렌드 스탯 변경 가능하게
- [ ] 커뮤니티 UI 인스타그램 형태 개선 (이미지 먼저 → 글쓰기)

### 장기 (설계/리소스/난이도 높음)
- [ ] 게임카드 배경: 당일 경기 구장 사진 삽입
- [ ] 게임카드 glow → neon sign 형태로 변경
- [ ] 실시간 중계 필드뷰 표시 (네이버처럼, 경기 종료 후에도 유지)
- [ ] 포스트시즌 진출 확률 (매직넘버/수학적 탈락 계산)
- [ ] 홈화면 위젯 (Android AppWidget — native kotlin 필요)
- [ ] 친구 신청/수락 — friend_requests 테이블, FCM 알림, 마이페이지 친구목록
- [ ] 1:1 채팅 — WebSocket + chat_rooms/chat_messages, 친구 관계 전제
