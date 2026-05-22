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
Environment=EMAIL_PASS=lwsc sxbs mmxg uoba
```

## 앱 설정
- 패키지명: com.playball.app
- baseUrl: http://168.107.61.147:8000
- 인증: JWT Bearer → SharedPreferences `access_token`

## 주요 파일

### 백엔드 (~/playball/backend/)
- api/main.py
- api/routers/{games,players,teams,auth,user,stadiums,widget,community,calendar,phone,email_verify}.py
- api/weather_service.py (OpenWeatherMap 5분 캐시)
- api/email_service.py (Gmail SMTP, noreply.playball@gmail.com 발신)
- api/sms_service.py (미사용 — email로 교체됨)
- api/fcm_service.py (Firebase Admin SDK — 활성화 대기)
- database/connection.py
- crawler/naver_crawler.py (**절대 수정 금지**)
- crawler/scheduler.py, crawl_all_games.py, crawl_past_rosters.py
- crawler/kbo_roster_crawler.py

### 앱 (app/lib/)
- main.dart, api/api_service.dart
- screens/home/home_screen.dart
- screens/game/game_detail_screen.dart
- screens/player/{player_screen,player_detail_screen,player_compare_screen}.dart
- screens/team/{team_screen,team_detail_screen}.dart
- screens/calendar/calendar_screen.dart
- screens/auth/{login_screen,register_screen}.dart
- screens/mypage/{my_page_screen,phone_verify_screen}.dart  ← 이메일 인증 UI
- models/game.dart, utils/team_theme.dart
- providers/{auth,game,team}_provider.dart

## API 목록

### 인증
```
POST /auth/register          (email, password, nickname)
POST /auth/login             → access_token
GET  /auth/me                [Bearer] → id,email,nickname,phone_verified,phone_number,settings
GET  /auth/check-email?email=
GET  /auth/check-nickname?nickname=
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
```

### 선수
```
GET /players/search?q=&player_type=
GET /players/hitters?season=&sort_by=&team_id=&limit=
GET /players/pitchers?season=&sort_by=&team_id=&limit=
GET /players/{id}            (프로필 + 시즌별 성적 + roster_status)
GET /players/{id}/daily?season=
```

### 팀
```
GET /teams/
GET /teams/rankings
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
```

### 커뮤니티
```
GET    /community/posts?team_id=&category=&page=
GET    /community/posts/{id}
POST   /community/posts      [Bearer + phone_verified 필수] → 미인증 시 403 phone_not_verified
POST   /community/posts/{id}/like    [Bearer]
POST   /community/posts/{id}/comments [Bearer]
DELETE /community/comments/{id}      [Bearer]
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

### batter_stats
`player_id, season, games, at_bats, runs, hits, doubles, triples, home_runs, rbis, walks, strikeouts, stolen_bases, avg, obp, slg, ops, woba, wrc_plus, babip, iso, war, pa, tb, cs, sac, sf, ibb, hbp, gdp, errors, sb_pct, mh, risp, ph_ba`
※ sb_pct: 0~100 퍼센트 단위 (×100 금지)

### pitcher_stats
`player_id, season, games, wins, losses, saves, holds, innings_pitched, hits_allowed, runs_allowed, earned_runs, walks, strikeouts, home_runs_allowed, era, whip, fip, k_per_9, bb_per_9, babip, war, blown_saves, cg, sho, wpct, tbf, np, doubles_allowed, triples_allowed, sac, sf, ibb, hbp, wp, bk, qs, avg_against`

### player_daily_stats / player_roster_changes
(기존 스키마 유지)

## Flutter 앱 구조

### 탭 구성
0: 경기, 1: 순위, 2: 선수, 3: 캘린더, 4: 커뮤니티
- AppBar 우측: 마이페이지 아이콘(person_outline) → MyPageScreen

### home_screen.dart (TodayGamesTab)
- 날짜 이동 + 날짜 선택기
- 당일 등록말소 배너 (접기/펼치기)
- ★ 마이팀 필터 토글 (즐겨찾기 팀 있을 때만 표시)
- GameCard: 날씨 칩(이모지+기온+강수확률) + 팀별 최근5경기 W/L/D 뱃지

### game_detail_screen.dart
- 탭: 이닝/프리뷰/로스터/투수/타자/기록
- 스코어 헤더: 날씨 정보 행
- 승리확률 그래프: LineChart (80pt 다운샘플)
- 경기흐름 그래프: BarChart (이닝별 득점)
- 투수 타일: 구종차트 바 + 범례
- 자동새로고침: 30초 (진행중만)

### player_screen.dart
- 1~3위 포디엄 (2위 좌/1위 중/3위 우, 금은동)
- 타이틀 뱃지 (홈런왕 등)
- AppBar: 선수비교 아이콘 → PlayerCompareScreen

### player_detail_screen.dart
- 한글/영어 토글: 스탯 섹션 상단 (AppBar 아님)
- 시즌 트렌드 그래프 (최근 20경기)
- 등록말소 뱃지

### player_compare_screen.dart
- 두 선수 검색 → 스탯 테이블 (좋은 값 navy bold 강조)
- 타자 14행 / 투수 13행

### calendar_screen.dart
- 월별 달력, 날짜 선택 → GameCard 형태 경기 목록

### team_detail_screen.dart
- 탭 3개: 선수명단 / 경기일정 / 등록말소

### my_page_screen.dart (신규)
- 프로필 (닉네임 편집 아이콘)
- 이메일 인증 상태 + 인증하기 버튼 → PhoneVerifyScreen
- 마이팀 목록 → TeamDetailScreen
- 즐겨찾기 선수 → PlayerDetailScreen
- 로그아웃 (AuthProvider.logout())

### phone_verify_screen.dart (이메일 인증 UI)
- 발송 버튼 → 가입 이메일로 6자리 코드 발송
- 코드 입력 → 인증 완료 → phone_verified=TRUE
- Rate limit 429 수신 시 에러 표시

### community/create_post_screen.dart
- 403 phone_not_verified 수신 시 → 인증 유도 다이얼로그 → PhoneVerifyScreen

### game.dart 모델
`id, status, homeTeam, awayTeam, homeScore, awayScore, currentInning, inningHalf, stadium, startTime, isDraw, winPitcher, losePitcher, homeStarter, awayStarter, weather, homeRecent5, awayRecent5, homeTeamId, awayTeamId`

### team_theme.dart
`kTeamColors, kTeamLogoUrls, kTeamDisplayNames`
`TeamLogo(teamCode, size, logoUrl)`, `teamColor(code)`, `teamDisplayName(code)`

## 네이버 API
NAVER_TEAM_CODE: HT=KIA, OB=두산, LT=롯데, SS=삼성, HH=한화, SK=SSG, KT=KT, NC=NC, WO=키움, LG=LG
Headers: `User-Agent: Mozilla/5.0` / `Referer: https://sports.naver.com/`

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

### scheduler.py
- 5분마다: naver_crawler
- 경기 2시간 전~30분 전: 등록말소 크롤링
- UTC 00:30: 등록말소 + 7일치 선수이동

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

## FCM 활성화 방법 (인프라 완료 — 수동 작업 필요)

1. Firebase 콘솔 → 프로젝트 추가 → Android 앱 등록 (com.playball.app)
2. `google-services.json` → `app/android/app/google-services.json`
3. 서비스 계정 키 → `firebase-service-account.json` → 서버 업로드
4. `flutterfire configure` → `firebase_options.dart` 생성
5. Claude에게 "FCM 활성화 마무리해줘" 요청

## 미구현 기능
- [ ] 비밀번호 찾기/재설정, 회원탈퇴, 프로필 이미지 업로드
- [ ] FCM 활성화 (인프라 완료)
- [ ] 마이팀 개인화 홈, 내 게시글/댓글
- [ ] 커뮤니티: 이미지 첨부, 검색, 신고, 인기글 탭
- [ ] 투구 히트맵, 스프레이 차트, 드래프트/FA 정보
- [ ] 피타고리안 승률, 직관 승률
- [ ] 다크모드, 홈화면 위젯, 카카오맵 연동
