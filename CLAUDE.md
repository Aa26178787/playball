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
# 폰: 개발자 옵션 → 무선 디버깅 → 페어링 코드로 기기 페어링
adb pair [IP]:[포트]   # 6자리 코드 입력
adb connect [IP]:5555
flutter run
```
- 노트북-폰 다른 네트워크(집/일터)일 경우: 폰 핫스팟 켜고 노트북 연결

### APK 빌드 후 전송 (원격 배포)
```bash
flutter build apk --debug   # 또는 --release
# build/app/outputs/flutter-apk/app-release.apk → 카카오톡/구글드라이브로 전송
```

## 주요 파일

### 백엔드 (~/playball/backend/)
- api/main.py
- api/routers/{games,players,teams,auth,user,stadiums,widget,community,calendar,phone,email_verify,search}.py
- api/weather_service.py (OpenWeatherMap 5분 캐시)
- api/email_service.py (Gmail SMTP, noreply.playball@gmail.com 발신)
- api/sms_service.py (미사용 — email로 교체됨)
- api/fcm_service.py (Firebase Admin SDK — 활성화 대기)
- database/connection.py
- crawler/naver_crawler.py (**절대 수정 금지**)
- crawler/scheduler.py, crawl_all_games.py, crawl_past_rosters.py
- crawler/kbo_roster_crawler.py
- static/profiles/ (프로필 이미지 저장 디렉토리)

### 앱 (app/lib/)
- main.dart, api/api_service.dart
- screens/home/home_screen.dart
- screens/game/game_detail_screen.dart
- screens/game/pitch_location_chart.dart  ← 투구 위치 시각화 (스트라이크존)
- screens/player/{player_screen,player_detail_screen,player_compare_screen}.dart
- screens/team/{team_screen,team_detail_screen}.dart
- screens/calendar/calendar_screen.dart
- screens/auth/{login_screen,register_screen,forgot_password_screen}.dart
- screens/mypage/{my_page_screen,phone_verify_screen}.dart
- screens/community/{community_screen,post_detail_screen,create_post_screen}.dart
- screens/search/search_screen.dart  ← 통합 선수/팀 검색
- models/game.dart, utils/team_theme.dart
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
GET /games/today             (weather, home/away_recent_5, home/away_team_id 포함)
GET /games/date/{date_str}   (home_starter, away_starter, weather, recent_5 포함)
GET /games/{id}              (innings, pitchers, batters)
GET /games/{id}/relay        실시간(진행중만)
GET /games/{id}/relay_all
GET /games/{id}/roster
GET /games/{id}/preview      (선발투수, 상대전적)
GET /games/{id}/record_detail
GET /games/{id}/weather      (실내=indoor:true, 야외=temp/humidity/wind/pop)
GET /games/{id}/pitch-types  → {pitchers:{name:[{type,count,pct}]}}
GET /games/{id}/pitch-locations → {pitches:[{x,z,result,pitcher,top_sz,bot_sz}], pitchers:[...]}
  ※ x=횡위치(ft), z=높이(ft, 물리궤적 계산), result=ball/strike/swing/foul/hit/other
  ※ 진행중 경기: GREATEST(MAX(gi.inning), g.current_inning)으로 현재이닝 포함
GET /games/{id}/highlights → {highlights:[{title,url,source,published_at}]}
  ※ DB 우선 조회, 없으면 Google News RSS 실시간 크롤
```

### 선수
```
GET /players/search?q=&player_type=
GET /players/hitters?season=&sort_by=&team_id=&limit=
GET /players/pitchers?season=&sort_by=&team_id=&limit=
GET /players/{id}            (프로필 + 시즌별 성적 + roster_status)
GET /players/{id}/daily?season=
GET /players/{id}/pitch-stats?season=  → {total, pitch_types:[{type,count,pct}]}
  ※ game_pitch_locations 집계, 투수 전용
```

### 팀
```
GET /teams/
GET /teams/rankings  → 각 팀에 last_series:{wins,losses,games,label,opponent_id} 포함
  ※ label: 스윕 승/위닝 시리즈/스플릿/루징 시리즈/스윕 패
GET /teams/{id}/players
GET /teams/{id}/games
GET /teams/{id}/roster-changes?days=30
GET /teams/roster-changes/today
```

### 유저 [Bearer]
```
GET/POST   /user/favorite-teams
DELETE     /user/favorite-teams/{team_id}
GET/POST   /user/favorite-players
DELETE     /user/favorite-players/{player_id}
GET/PUT    /user/settings
PUT        /user/nickname                        (닉네임 변경, 중복확인)
POST       /user/email/send-code                (가입 이메일로 인증번호 발송, rate limit 1분)
POST       /user/email/verify                   ({code}) → phone_verified=TRUE
POST       /user/push-token                     (FCM — 활성화 대기)
POST       /user/profile-image                  (multipart/form-data, file) → {profile_image: url}
GET        /user/calendar-events?year=&month=   → {events:[{id,date,title,description,color}]}
POST       /user/calendar-events                ({event_date,title,description?,color?}) → {id}
DELETE     /user/calendar-events/{event_id}
```

### 커뮤니티
```
GET    /community/posts?team_id=&category=&sort=&q=&page=
GET    /community/posts/{id}
POST   /community/posts      [Bearer + phone_verified 필수] → 미인증 시 403 phone_not_verified
PUT    /community/posts/{id} [Bearer, 작성자만]  (title, content)
DELETE /community/posts/{id} [Bearer, 작성자만]
POST   /community/posts/{id}/like    [Bearer]
POST   /community/posts/{id}/report  [Bearer]   (reason)
POST   /community/posts/{id}/comments [Bearer]
DELETE /community/comments/{id}      [Bearer, 작성자만]
GET    /community/my-posts?page=     [Bearer]
GET    /community/my-comments?page=  [Bearer] → {comments:[{id,content,created_at,post_id,post_title}]}
POST   /community/posts/upload-image [Bearer, multipart] → {image_url}
  ※ 이미지 먼저 업로드 후 image_url을 createPost 파라미터로 전달
```

### 검색
```
GET /search?q=  → {players:[{id,name,player_type,position,profile_image,team,team_code}], teams:[{id,name,short_name}]}
```

### 기타
```
GET /stadiums/, /stadiums/{id}
GET /widget/live-scores, /widget/my-team-scores/{team_id}
GET /calendar/{year}/{month}
```

## DB 스키마

### users
`id, email, password_hash, nickname, profile_image, created_at, phone_number, phone_verified(bool)`
- phone_verified: 이메일 인증 완료 여부 (커뮤니티 글쓰기 조건)

### phone_verifications (이메일 인증 코드 저장)
`id, user_id, phone_number(실제론 email저장), code, expires_at, used, created_at`
- 만료 레코드: 인증 성공/발송 시 자동 cleanup (1일 경과분 삭제)

### teams
`id, name, short_name`
short_name: LG, KT, SK(SSG), NC, OB(두산), HT(KIA), LT(롯데), SS(삼성), HH(한화), WO(키움)

### stadiums
`id, name` | 1=서울(LG/두산), 2=고척(키움), 3=수원(KT), 4=인천(SSG), 5=대전(한화), 6=광주(KIA), 7=대구(삼성), 8=창원(NC), 9=사직(롯데)

### players
`id, name, team_id, player_type(투수/타자), number, profile_image, naver_player_id, position, pitching_style, throws, bats, height, weight, birth_date`

### games
`id, naver_game_id, game_date, status(예정/진행/종료/취소), home_team_id, away_team_id, stadium_id, home_score, away_score, current_inning, inning_half, home_hits, away_hits, home_errors, away_errors, start_time`

### game_innings / game_pitches / game_pitchers / game_batters / game_rosters
(기존 스키마 유지 — 변경 없음)

### game_highlights
`id, game_id(FK→games), title, url(UNIQUE), thumbnail, source, published_at, crawled_at`
- url_launcher로 외부 브라우저 오픈

### posts
`id, user_id, team_id, title, content, category, views, likes, created_at, updated_at, image_url`
- image_url: /static/posts/ 경로 (커뮤니티 이미지 첨부)

### batter_stats
`player_id, season, games, at_bats, runs, hits, doubles, triples, home_runs, rbis, walks, strikeouts, stolen_bases, avg, obp, slg, ops, woba, wrc_plus, babip, iso, war, pa, tb, cs, sac, sf, ibb, hbp, gdp, errors, sb_pct, mh, risp, ph_ba`
※ sb_pct: 0~100 퍼센트 단위 (×100 금지)

### pitcher_stats
`player_id, season, games, wins, losses, saves, holds, innings_pitched, hits_allowed, runs_allowed, earned_runs, walks, strikeouts, home_runs_allowed, era, whip, fip, k_per_9, bb_per_9, babip, war, blown_saves, cg, sho, wpct, tbf, np, doubles_allowed, triples_allowed, sac, sf, ibb, hbp, wp, bk, qs, avg_against`

### user_calendar_events
`id, user_id(FK→users), event_date(DATE), title(VARCHAR200), description(TEXT), color(VARCHAR20, default='blue'), created_at`
- color 옵션: blue/red/green/orange/purple/gray
- INDEX: (user_id, event_date)

### player_daily_stats / player_roster_changes
(기존 스키마 유지)

## Flutter 앱 구조

### 탭 구성
0: 경기, 1: 순위, 2: 선수, 3: 캘린더, 4: 커뮤니티
- AppBar 우측: 검색 아이콘 → SearchScreen, 마이페이지 아이콘(person_outline) → MyPageScreen

### home_screen.dart (TodayGamesTab)
- 날짜 이동 + 날짜 선택기
- 당일 등록말소 배너 (접기/펼치기)
- ★ 마이팀 필터 토글 (즐겨찾기 팀 있을 때만 표시)
- GameCard: 날씨 칩(이모지+기온+강수확률) + 팀별 최근5경기 W/L/D 뱃지

### game_detail_screen.dart
- 탭: 이닝/프리뷰/로스터/투수/타자/기록/하이라이트 (7개, isScrollable)
- 스코어 헤더: 날씨 정보 행 + 팀별 최근5경기 W/L/D 뱃지
- 승리확률 그래프: LineChart (80pt 다운샘플)
- 경기흐름 그래프: BarChart (이닝별 득점)
- 투수 탭: 구종차트 바 + 범례 + **투구 위치 보기** 버튼 → PitchLocationSheet(gameStatus 전달)
- 하이라이트 탭: GET /games/{id}/highlights → ListView + url_launcher 외부 브라우저
- AppBar 공유 버튼: share_plus → 경기 결과/예정 텍스트 OS 공유시트
- 자동새로고침: 30초 (진행중만)

### pitch_location_chart.dart (PitchLocationSheet)
- **3단계 필터**: ① 투수 선택(홈/원정 그룹) → ② 이닝 선택(해당 투수 이닝만) → ③ 타자 선택(해당 투수×이닝 타자만)
- 결과 필터 칩(전체/볼/스트라이크/헛스윙/파울/타격)
- 투수 변경 시 이닝·타자 리셋, 이닝 변경 시 타자 리셋
- CustomPainter ABS 스트라이크존:
  - plateHalfW = 8.5/12 ft (실제 플레이트 반폭)
  - absHalfW = 9.95/12 ft (ABS 판정 경계 = 플레이트 + 공반지름 1.45인치)
  - ballR = 1.45/12 ft; topAbs = topSz+ballR, botAbs = botSz-ballR
  - 3x3 구역선 + 플레이트 모양(±8.5인치)
- 진행중 경기 30초 자동새로고침 + LIVE 배지
- 색상: 볼=파랑, 스트라이크=빨강, 헛스윙=주황, 파울=노랑, 타격=초록

### search_screen.dart
- AppBar 인라인 TextField (자동포커스)
- /search?q= → 팀 섹션(TeamLogo) + 선수 섹션
- 탭: TeamDetailScreen / PlayerDetailScreen

### player_screen.dart
- 1~3위 포디엄 (2위 좌/1위 중/3위 우, 금은동)
- 타이틀 뱃지 (홈런왕 등)
- AppBar: 선수비교 아이콘 → PlayerCompareScreen

### player_detail_screen.dart
- 한글/영어 토글: 스탯 섹션 상단 (AppBar 아님)
- 최근 5경기 섹션 (최신순, 타자=AVG/HR/RBI, 투수=ERA/K/BB)
- 투수 전용: 구종분포 바차트 (_buildPitchStatsCard) — /players/{id}/pitch-stats 사용
- 시즌 트렌드 그래프 (최근 20경기)
- 등록말소 뱃지

### player_compare_screen.dart
- 두 선수 검색 → 스탯 테이블 (좋은 값 navy bold 강조)
- 타자 14행 / 투수 13행

### calendar_screen.dart
- 월별 달력, 날짜 선택 → KBO 경기 목록 + 개인 일정 목록
- 날짜 셀: 팀 컬러 점(경기) + 황색 점(개인 일정)
- 예정/라인업 경기: 📅 아이콘 → add_2_calendar 네이티브 캘린더 추가
- FAB(+): 선택 날짜에 개인 일정 추가 다이얼로그 (제목/메모/색상 6종)
- 개인 일정 카드: 색상 바 + 삭제 버튼 (확인 다이얼로그)
- API: GET/POST/DELETE /user/calendar-events

### team_screen.dart (순위 탭)
- 팀 카드: last_series 배지 표시 (스윕 승/위닝 시리즈/스플릿/루징 시리즈/스윕 패)
- 색상: 스윕 승=진파랑, 위닝=파랑, 스플릿=회색, 루징=빨강, 스윕 패=진빨강

### team_detail_screen.dart
- 탭 5개 (isScrollable): 선수명단 / 최근경기 / 등록말소 / 뉴스 / 커뮤니티
- 커뮤니티 탭: GET /community/posts?team_id= → 글 목록(제목/닉네임/날짜/조회·좋아요·댓글) → PostDetailScreen
- 최근경기: 시리즈별 그룹핑 + 시리즈 결과 배지

### my_page_screen.dart
- 프로필 이미지: GestureDetector → ImagePicker(갤러리) → 업로드 (카메라 뱃지 + 스피너)
- 닉네임 편집 아이콘
- 이메일 인증 상태 + 인증하기 버튼 → PhoneVerifyScreen
- 마이팀 목록 → TeamDetailScreen
- 즐겨찾기 선수 → PlayerDetailScreen
- 내 댓글 최근 5개 (post_title 포함) → PostDetailScreen
- 로그아웃 (AuthProvider.logout())

### phone_verify_screen.dart (이메일 인증 UI)
- 발송 버튼 → 가입 이메일로 6자리 코드 발송
- 코드 입력 → 인증 완료 → phone_verified=TRUE
- Rate limit 429 수신 시 에러 표시

### community_screen.dart
- 무한스크롤: ScrollController → 200px 여유 시 _loadMore() → page+1 append
- AutomaticKeepAliveClientMixin으로 탭 전환 시 상태 유지

### post_detail_screen.dart
- 본인 글: PopupMenu → 수정(인라인 다이얼로그)/삭제(확인 후 pop)
- 타인 글: PopupMenu → 신고
- 본인 댓글: 휴지통 아이콘 → 삭제

### create_post_screen.dart
- 403 phone_not_verified 수신 시 → 인증 유도 다이얼로그 → PhoneVerifyScreen

### game.dart 모델
`id, status, homeTeam, awayTeam, homeScore, awayScore, currentInning, inningHalf, stadium, startTime, isDraw, winPitcher, losePitcher, homeStarter, awayStarter, weather, homeRecent5, awayRecent5, homeTeamId, awayTeamId`

### team_theme.dart
`kTeamColors, kTeamLogoUrls, kTeamDisplayNames`
`TeamLogo(teamCode, size, logoUrl)`, `teamColor(code)`, `teamDisplayName(code)`

## 네이버 API
NAVER_TEAM_CODE: HT=KIA, OB=두산, LT=롯데, SS=삼성, HH=한화, SK=SSG, KT=KT, NC=NC, WO=키움, LG=LG
Headers: `User-Agent: Mozilla/5.0` / `Referer: https://sports.naver.com/`

### 투구 위치 데이터 (relay API)
- `ptsOptions`: 물리궤적 파라미터 (y0,vy0,ay,z0,vz0,az,x0,vx0,ax)
- `crossPlateX`: 홈플레이트 통과 횡위치(ft) — 직접 사용
- `crossPlateY`: 0.7083ft 고정 = 플레이트 절반 너비(8.5인치) — 높이 아님, 사용 안 함
- 높이 계산: y=0 시점 t 이차방정식 풀기 → `z_plate = z0 + vz0*t + 0.5*az*t²`
- `topSz`/`bottomSz`: 타자별 ABS 스트라이크존 (신장 기반으로 변동)
- `textOptions type=1`: 투구 이벤트, `stuff`=구종, `text`=결과(볼/스트라이크/헛스윙/파울/타격)

## 크롤러 핵심 로직

### naver_crawler.py (**절대 수정 금지**)
- 5분마다 진행중 경기 실시간 업데이트
- 종료 감지 시 15분 후 선수 스탯 업데이트

### crawl_all_games.py
- 셀레니움 네이버 모바일 중계 역순파싱
- pitcher_idx 경기 전체 유지 (이닝간 초기화 금지)
- 대상: game_date < '2026-05-09' 종료경기

### kbo_roster_crawler.py
- crawl_daily_register(): 1군등록/등록말소
- crawl_trade(days): 선수이동

### crawl_highlights.py
- Google News RSS로 KBO 하이라이트 크롤 (Naver 403 우회)
- `crawl_highlights()`: 3개 쿼리 hourly 크롤
- `crawl_highlights_for_game(game_id)`: 경기 종료 시 트리거
- `game_highlights` 테이블에 저장 (url UNIQUE)
- 팀명→team_id 매핑: KT=1, KIA=2, 롯데=4, 한화=5, NC=6, 두산=7, 키움=8, LG=9, SSG=10, 삼성=11

### scheduler.py
- 5분마다: naver_crawler
- 경기 2시간 전~30분 전: 등록말소 크롤링
- UTC 00:30: 등록말소 + 7일치 선수이동
- 1시간마다: 하이라이트 크롤 (crawl_highlights)
- 경기 종료 감지 시: crawl_highlights_for_game(game_id) 호출

## 주의사항
- **naver_crawler.py 절대 수정 금지**
- 과거경기 수정: game_date < '2026-05-09' 조건 필수
- 동명이인: team_id 기준 조회
- 서버 백엔드 루트: ~/playball/backend/
- git push: --force 필수 (모노레포)
- git push/pull 원격 작업은 확인 없이 바로 실행
- 삼성 홈경기 구장 누락: `UPDATE games SET stadium_id=7 WHERE home_team_id=11 AND stadium_id IS NULL`
- sb_pct는 이미 퍼센트 단위 (×100 금지)
- 소셜 로그인 구현 안 함 (결정)
- TeamLogo 파라미터: `teamCode` (not `code`)
- TeamDetailScreen 파라미터: `team` (Map, not teamId)
- 서버 직접 수정 후 git push 시: 로컬 scp로 동기화 먼저, 그 다음 push
- 서버 pull 전: `git stash` 필수 (직접 수정 파일 있을 경우)
- 커뮤니티 조회수 쓰로틀: community.py `_view_cache` in-memory dict (재시작 시 초기화됨, 의도적)
- ABS 존 상수: plateHalfW=8.5/12, absHalfW=9.95/12, ballR=1.45/12 (ft 단위) — 변경 금지
- share_plus 버전: ^10.0.0 (^10.1.4는 firebase_messaging 충돌)

## FCM 활성화 방법 (인프라 완료 — 수동 작업 필요)

1. Firebase 콘솔 → 프로젝트 추가 → Android 앱 등록 (com.playball.app)
2. `google-services.json` → `app/android/app/google-services.json`
3. 서비스 계정 키 → `firebase-service-account.json` → 서버 업로드
4. `flutterfire configure` → `firebase_options.dart` 생성
5. Claude에게 "FCM 활성화 마무리해줘" 요청

## 구현 완료

### 경기/투구
- [x] 경기 상세 7탭 (이닝/프리뷰/로스터/투수/타자/기록/하이라이트)
- [x] 하이라이트 탭 (Google News RSS 크롤, url_launcher)
- [x] 투구 위치 보기: 3단계 필터(투수→이닝→타자) + ABS존 정확 표시
  - plateHalfW=8.5/12, absHalfW=9.95/12, ballR=1.45/12
  - 진행중 30초 자동새로고침 + LIVE 배지
- [x] 경기 상세 공유 버튼 (share_plus)
- [x] 피타고리안 승률 (teams.py, 팀 카드 표시)

### 선수
- [x] 선수 상세: 최근 5경기 + 투수 구종분포 바차트
- [x] GET /players/{id}/pitch-stats (game_pitch_locations 집계)
- [x] 선수 기록 규정이닝/규정타석 조건 제거

### 팀
- [x] 팀 순위 최근 시리즈 결과 배지 (스윕 승/위닝/스플릿/루징/스윕 패)
- [x] 팀 상세 5탭: 선수/최근경기/등록말소/뉴스/커뮤니티

### 캘린더
- [x] KBO 경기 → 네이티브 캘린더 추가 (add_2_calendar)
- [x] 개인 일정 CRUD (user_calendar_events 테이블, FAB, 색상 6종)

### 커뮤니티
- [x] 조회수 IP 기반 10분 쓰로틀 (in-memory dict)
- [x] 이미지 첨부 (POST /community/posts/upload-image)
- [x] 검색 + 인기글 탭 (sort=hot)
- [x] 팀 커뮤니티 탭 (team_detail_screen)

### 인증/유저
- [x] 비밀번호 찾기/재설정 (이메일→코드→재설정)
- [x] 이메일 인증 (phone_verified 플래그, 커뮤니티 글쓰기 조건)
- [x] 프로필 이미지 업로드

### 기타
- [x] 다크모드 (ThemeProvider, SharedPreferences)
- [x] 마이팀 개인화 홈 (순위/연승/오늘경기)
- [x] 통합 검색 (선수/팀)
- [x] Google News RSS 하이라이트 크롤러

## 진행 예정 기능

### 즉시 착수 가능
- [ ] **카카오맵 구장 화면** — 구장 목록 + 지도 핀 (API 키 보유, kakao_map_plugin)
  - 9개 구장 좌표 하드코딩 (서울/고척/수원/인천/대전/광주/대구/창원/사직)
  - StadiumScreen: 구장 카드 리스트 + 지도 마커
- [ ] **FCM 알림 기준 구현** — user_settings 기반 조건부 발송
  - notify_game_start: 경기 시작 시 (naver_crawler 진행 감지)
  - notify_score_change: 득점 변경 시 (home_score/away_score 변화)
  - notify_game_end: 경기 종료 시
  - notify_my_team_only: 위 알림을 user_favorite_teams 경기만
  - push_tokens 테이블 활용, fcm_service.py send_to_tokens()

### 중기 작업
- [ ] **투구 위치 히트맵** — 현재 점 → 구역별 농도(색상) 오버레이
- [ ] **내가 좋아요한 글** — GET /community/my-likes + 마이페이지 섹션
- [ ] **타자 vs 투수 상대전적** — game_batters/game_pitchers 집계 쿼리
- [ ] **검색 최근 기록** — SharedPreferences 로컬 저장 (최대 10개)
- [ ] **댓글 좋아요** — comment_likes 테이블 + POST /community/comments/{id}/like

### 장기/보류
- [ ] 홈화면 위젯 (Android AppWidget — native kotlin 필요)
- [ ] 스프레이 차트 (타구방향 데이터 없음 — 네이버 텍스트만 제공)
- [ ] 드래프트/FA 정보 (데이터 소스 없음)
- [ ] 팀별 월별 승률 추이 그래프
