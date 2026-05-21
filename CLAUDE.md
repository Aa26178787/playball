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
# 서버 접속
ssh -i "C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key" ubuntu@168.107.61.147
# SSH 터널
ssh -i "...key" -L 5433:localhost:5432 ubuntu@168.107.61.147 -N
# 배포
cd ~/playball && git pull origin main --rebase && sudo systemctl restart playball
# 로그
sudo journalctl -u playball -f
# DB
sudo -u postgres psql -d playball
# 크롤러(서버)
cd ~/playball/backend && nohup python3 crawler/crawl_all_games.py > /tmp/crawl_all.log 2>&1 &
# Flutter
cd C:\Users\qq772\playball\app && flutter run
# git push
cd C:\Users\qq772\playball && git add . && git commit -m "메시지" && git push origin main --force
```

## 서비스
```
WorkingDirectory=/home/ubuntu/playball/backend
ExecStart=/home/ubuntu/.local/bin/uvicorn api.main:app --host 0.0.0.0 --port 8000
Environment=OPENWEATHER_API_KEY=2e970a21c74205304e13657423b1625b
```

## 앱 설정
- 패키지명: com.playball.app
- baseUrl: http://168.107.61.147:8000
- 인증: JWT Bearer → SharedPreferences `access_token`

## 주요 파일

### 백엔드 (~/playball/backend/)
- api/main.py, api/routers/{games,players,teams,auth,user,stadiums,widget,community,calendar}.py
- api/weather_service.py (OpenWeatherMap 5분 캐시)
- api/fcm_service.py (Firebase Admin SDK — 활성화 대기)
- database/connection.py (user=playball_user, pw=playball1234)
- crawler/naver_crawler.py (**절대 수정 금지**)
- crawler/scheduler.py, crawl_all_games.py, crawl_past_rosters.py
- crawler/kbo_roster_crawler.py (KBO 공식 등록말소/선수이동 셀레니움)

### 앱 (app/lib/)
- main.dart (Firebase init 코드 포함 — 활성화 대기), api/api_service.dart
- screens/home/home_screen.dart, screens/game/game_detail_screen.dart
- screens/player/player_screen.dart, screens/player/player_detail_screen.dart
- screens/team/team_screen.dart, screens/team/team_detail_screen.dart
- screens/calendar/calendar_screen.dart (월별 달력)
- screens/auth/login_screen.dart
- models/game.dart, utils/team_theme.dart (kTeamColors, TeamLogo 위젯)
- providers/{auth,game,team}_provider.dart

## API 목록

### 인증
```
POST /auth/register          (email, password, nickname)
POST /auth/login             → access_token
GET  /auth/me                [Bearer]
GET  /auth/check-email?email=
GET  /auth/check-nickname?nickname=
```

### 경기
```
GET /games/today             (weather 포함)
GET /games/date/{date_str}   (home_starter, away_starter, weather 포함 — 오늘만)
GET /games/{id}              (innings, pitchers, batters)
GET /games/{id}/relay        실시간(진행중만)
GET /games/{id}/relay_all
GET /games/{id}/roster
GET /games/{id}/preview      (선발투수, 상대전적)
GET /games/{id}/record_detail
GET /games/{id}/weather      (구장 날씨 — 실내=indoor:true, 야외=temp/humidity/wind 등)
```

### 선수
```
GET /players/search?q=&player_type=
GET /players/hitters?season=&sort_by=&team_id=&limit=   (sort: avg/home_runs/rbis/hits/ops/war)
GET /players/pitchers?season=&sort_by=&team_id=&limit=  (sort: era/wins/strikeouts/whip/saves/holds/war)
GET /players/{id}            (프로필 + 시즌별 성적 + roster_status)
GET /players/{id}/daily?season=
```

### 팀
```
GET /teams/
GET /teams/rankings          (wins/losses/draws/rank/win_rate/games_behind/streak/recent_5/home_record/away_record)
GET /teams/{id}/players
GET /teams/{id}/games
GET /teams/{id}/roster-changes?days=30   (등록말소/부상/이동 현황)
GET /teams/roster-changes/today          (전 팀 당일 변경)
```

### 캘린더
```
GET /calendar/{year}/{month}   → {"year","month","games":{"2026-05-01":[...]}}
```

### 유저 [Bearer]
```
GET/POST   /user/favorite-teams
DELETE     /user/favorite-teams/{team_id}
GET/POST   /user/favorite-players
DELETE     /user/favorite-players/{player_id}
GET/PUT    /user/settings
POST       /user/push-token    (FCM 토큰 등록 — 활성화 대기)
```

### 커뮤니티
```
GET    /community/posts?team_id=&category=&page=
GET    /community/posts/{id}
POST   /community/posts                          (title, content, category, team_id) [Bearer]
POST   /community/posts/{id}/like               [Bearer]
POST   /community/posts/{id}/comments           [Bearer]
DELETE /community/comments/{id}                 [Bearer]
```

### 기타
```
GET /stadiums/, /stadiums/{id}
GET /widget/live-scores, /widget/my-team-scores/{team_id}
```

## DB 스키마

### teams
`id, name, short_name`
short_name: LG, KT, SK(SSG), NC, OB(두산), HT(KIA), LT(롯데), SS(삼성), HH(한화), WO(키움)

### stadiums
`id, name` | 1=서울(LG/두산), 2=고척(키움), 3=수원(KT), 4=인천(SSG), 5=대전(한화), 6=광주(KIA), 7=대구(삼성), 8=창원(NC), 9=사직(롯데)

### players
`id, name, team_id, player_type(투수/타자), number, profile_image, naver_player_id, position, pitching_style, throws, bats, height, weight, birth_date`

### games
`id, naver_game_id, game_date, status(예정/진행/종료/취소), home_team_id, away_team_id, stadium_id, home_score, away_score, current_inning, inning_half, home_hits, away_hits, home_errors, away_errors, start_time`

### game_innings
`id, game_id, inning, home_runs, away_runs`

### game_pitches
`id, game_id, inning, inning_half(0=초/1=말), seqno, batter_name, pitcher_name, pitch_num, pitch_result, stuff, speed, strike, ball, out, base1-3, home_score, away_score, title, text, type, home_win_rate, away_win_rate`
UNIQUE: (game_id, inning, inning_half, seqno, type) WHERE seqno IS NOT NULL
type: 1=투구, 2=교체, 7=마운드방문, 8=타자등장, 13=타석결과, 14=주자이동, 22=비디오판독, 24=수비변경
pitch_result: B=볼, T=스트라이크, S=헛스윙, F=파울, H=타격, V=번트헛스윙, W=번트파울

### game_pitchers
`id, game_id, player_id, team_side(home/away), pitching_order, role, result(승/패/세이브/홀드), innings_pitched, strikeouts, earned_runs, walks, hits_allowed, runs_allowed, home_runs_allowed, pitch_count`

### game_batters
`id, game_id, player_id, team_side, batting_order, position, at_bats, hits, rbis, home_runs, avg, walks`
UNIQUE: (game_id, player_id, team_side, batting_order)

### game_rosters
`id, game_id, player_id, team_side, roster_type(batter/pitcher), batting_order, position, pitching_style, is_starter`
UNIQUE: (game_id, player_id, team_side)

### batter_stats
`player_id, season, games, at_bats, runs, hits, doubles, triples, home_runs, rbis, walks, strikeouts, stolen_bases, avg, obp, slg, ops, woba, wrc_plus, babip, iso, war, pa, tb, cs, sac, sf, ibb, hbp, gdp, errors, sb_pct, mh, risp, ph_ba`
※ sb_pct: 0~100 퍼센트 단위 (곱하기 100 금지)

### pitcher_stats
`player_id, season, games, wins, losses, saves, holds, innings_pitched, hits_allowed, runs_allowed, earned_runs, walks, strikeouts, home_runs_allowed, era, whip, fip, k_per_9, bb_per_9, babip, war, blown_saves, cg, sho, wpct, tbf, np, doubles_allowed, triples_allowed, sac, sf, ibb, hbp, wp, bk, qs, avg_against`

### player_daily_stats
`player_id, game_date, opponent, result, stat_type, avg, pa, ab, runs, hits, doubles, triples, home_runs, rbi, sb, cs, walks, hbp, strikeouts, gdp, era, ip, h, hr, bb, so, r, er`

### player_roster_changes
`id, player_name, team_id, player_id, change_type, reason, change_date`
UNIQUE: (player_name, team_id, change_type, change_date)
change_type: 1군등록, 등록말소, 부상자명단, 임의탈퇴, 자유계약, 군입대, 트레이드, 웨이버, 방출, 복귀, 육성선수

## 네이버 API
NAVER_TEAM_CODE: HT=KIA, OB=두산, LT=롯데, SS=삼성, HH=한화, SK=SSG, KT=KT, NC=NC, WO=키움, LG=LG
Headers: `User-Agent: Mozilla/5.0 ...` / `Referer: https://sports.naver.com/`

```
https://api-gw.sports.naver.com/schedule/games/{id}/relay?inning={n}
https://api-gw.sports.naver.com/schedule/games/{id}/lineup
https://api-gw.sports.naver.com/schedule/games/{id}/preview
https://api-gw.sports.naver.com/schedule/games/{id}/record
https://m.sports.naver.com/game/{id}/relay   (셀레니움)
https://m.sports.naver.com/game/{id}/lineup  (셀레니움)
```

## 크롤러 핵심 로직

### crawl_all_games.py (과거경기 이닝별중계)
- 셀레니움 네이버 모바일 중계 (역순 표시 → 역순파싱 후 정순변환)
- pitcher_idx 경기 전체 유지 (이닝간 초기화 금지)
- inter_changes(타자사이 교체) vs intra_changes(타석내 교체) 구분
- 셀레니움 옵션: --headless --no-sandbox --disable-dev-shm-usage --disable-gpu
- 대상: game_date < '2026-05-09' 종료경기

### crawl_past_rosters.py
- _parse_naver_lineup(): 네이버 라인업 = 1군 전체(~190명, 정상)
- find_player(name, team_id): 팀ID 우선으로 동명이인 구분
- 대상: game_date < '2026-05-09' 종료경기

### kbo_roster_crawler.py (등록말소/선수이동)
- 셀레니움, KBO 공식 사이트 (JS 렌더링)
- `crawl_daily_register()`: Register.aspx → '전체 등록 현황' 탭 → table[-2](1군등록) / table[-1](등록말소)
- `crawl_trade(days)`: Trade.aspx → 단일 테이블, 날짜/항목/팀/선수/비고
- `run_today()`: 당일 등록말소만 / `run_trade(days)`: 선수이동 현황
- 스케줄러: 경기 2시간 전~30분 전 5분마다 run_today() 호출

### naver_crawler.py (**절대 수정 금지**)
- 5분마다 실행, 진행중 경기 실시간 업데이트
- 종료 감지 시 15분 후 선수 스탯 업데이트
- 경기 2시간 전부터 로스터 크롤링

### scheduler.py 스케줄
- 5분마다: 진행중 경기 업데이트 (naver_crawler)
- 경기 2시간 전~30분 전 (5분 단위): 등록말소 크롤링
- UTC 00:30 (KST 09:30): 등록말소 + 7일치 선수이동 크롤링
- 경기 상태 변화 감지 → FCM 발송 (활성화 대기)

## Flutter 앱 구조

### 탭 구성 (home_screen.dart)
0: 경기 (TodayGamesTab), 1: 순위 (TeamScreen), 2: 선수 (PlayerScreen), 3: 캘린더 (CalendarScreen), 4: 커뮤니티 (CommunityScreen)

### game_detail_screen.dart
- 탭: 이닝/프리뷰/로스터/투수/타자/기록
- 스코어 헤더 하단: 날씨 정보 (이모지/기온/습도/풍속/강수확률)
- 승리확률 그래프: fl_chart LineChart (relay_all 기반, 80pt 다운샘플, 50% 기준선)
- 경기흐름 그래프: fl_chart BarChart (이닝별 홈/원정 득점)
- 자동새로고침: 30초 (진행중만), Timer → dispose()에서 cancel()
- 수동 새로고침 버튼: AppBar 우측

### player_detail_screen.dart
- 한글/영어 토글: AppBar 버튼, `_l(kor, eng)` 헬퍼
- 시즌 트렌드 그래프: fl_chart LineChart (타자=avg, 투수=ERA, 최근 20경기)
- 등록말소 뱃지: roster_status 있을 때 헤더에 색상 뱃지

### player_screen.dart
- 순위 1~3위 하이라이트: 금/은/동 원형 뱃지
- 타이틀 뱃지: 1위에게 "홈런왕" 등 표시

### team_detail_screen.dart
- 탭 3개: 선수명단 / 경기일정 / 등록말소
- 등록말소 탭: 날짜별 그룹, 종류별 아이콘 (↑파랑=등록, ↓주황=말소, 🏥빨강=부상, 👤회색=임의탈퇴)

### calendar_screen.dart
- 월별 달력 그리드, 팀 컬러 점으로 경기 표시
- 날짜 선택 → 하단 경기 목록 → 탭으로 GameDetailScreen 이동

### home_screen.dart
- 당일 등록말소 배너: 접기/펼치기, 등록N/말소N/부상N 칩
- GameCard 상단: 날씨 칩 (이모지 + 기온 + 강수확률)

### team_theme.dart
- kTeamColors, kTeamLogoUrls (Naver CDN), kTeamDisplayNames
- TeamLogo 위젯: logoUrl → kTeamLogoUrls[code] → 컬러 원형 fallback
- teamColor(code), teamDisplayName(code) 헬퍼

### game.dart 모델
`id, status(예정/진행/종료/취소/라인업), homeTeam, awayTeam, homeScore, awayScore, currentInning, inningHalf, stadium, startTime, isDraw, winPitcher, losePitcher, homeStarter, awayStarter, weather`

## 주의사항
- **naver_crawler.py 절대 수정 금지**
- 과거경기 수정: game_date < '2026-05-09' 조건 필수
- 동명이인: team_id 기준 조회
- 서버 백엔드 루트: ~/playball/backend/
- git push: --force 필수 (모노레포)
- git push/pull 등 원격 작업은 확인 없이 바로 실행
- 삼성 홈경기 구장 누락: `UPDATE games SET stadium_id=7 WHERE home_team_id=11 AND stadium_id IS NULL`
- sb_pct는 이미 퍼센트 단위 (×100 금지)
- 소셜 로그인(카카오/구글) 구현 안 함 (결정)

## FCM 활성화 방법 (인프라 완료 — 수동 작업 필요)

백엔드 코드(`fcm_service.py`), 스케줄러 훅, Flutter 코드(`main.dart`) 모두 완성.
Firebase 프로젝트 연결만 하면 즉시 동작.

### 1단계: Firebase 프로젝트 생성
1. console.firebase.google.com → 프로젝트 추가
2. Android 앱 등록: 패키지명 `com.playball.app`
3. `google-services.json` 다운로드 → `app/android/app/google-services.json` 저장

### 2단계: 서비스 계정 키 생성
1. Firebase 콘솔 → 프로젝트 설정 → 서비스 계정 → 새 비공개 키 생성
2. 파일명 `firebase-service-account.json` 으로 변경
3. 서버에 업로드:
   ```bash
   scp -i "C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key" firebase-service-account.json ubuntu@168.107.61.147:~/playball/backend/
   ```

### 3단계: FlutterFire CLI
```bash
! dart pub global activate flutterfire_cli
! cd C:\Users\qq772\playball\app && flutterfire configure
```
→ `app/lib/firebase_options.dart` 자동 생성됨

### 4단계: Claude에게 요청
`firebase_options.dart` 생성 확인 후:
> "FCM 활성화 마무리해줘"

Claude가 처리: main.dart import 수정, build.gradle 확인, 서버 `pip install firebase-admin`, 재시작

## 미구현 기능

### 인증/계정
- [ ] 비밀번호 찾기/재설정, 회원탈퇴, 닉네임 변경, 프로필 이미지 업로드

### 경기 상세
- [ ] 투수 구종차트, 스트라이크/볼 비율

### 알림
- [ ] FCM 활성화 (인프라 완료 — Firebase 프로젝트 연결만 필요)
- [ ] 알림 히스토리 화면

### 팀/순위
- [ ] 피타고리안 승률, 직관 승률 입력

### 선수
- [ ] 선수 비교 화면, 투구 히트맵, 스프레이 차트, 드래프트/FA 정보

### 홈/경기
- [ ] 경기카드 최근5경기 승/패/무 표기

### 마이팀/마이페이지
- [ ] 마이팀 개인화 홈, 내 게시글/댓글, 즐겨찾기 UI 개선

### 커뮤니티
- [ ] 카테고리 세분화, 이미지 첨부, 게시글 검색, 신고, 인기글 탭

### 경기장
- [ ] 카카오맵 연동, 주변 맛집/주차장

### 기타
- [ ] 다크모드, 홈화면 위젯, 오프라인 캐싱, 상대전적 히스토리
