# PlayBall 프로젝트

## 개요
KBO 야구 앱 | Flutter(모바일) + FastAPI(백엔드) + PostgreSQL(DB)

## 인프라
- 서버: Oracle Cloud Ubuntu 22.04 | IP: 168.107.61.147:8000
- SSH 키: C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key
- DB: host=localhost, port=5432(서버)/5433(터널), db=playball, user=playball_user, pw=playball1234
- 레포: https://github.com/Aa26178787/playball (모노레포)

## 폴더 구조
- 로컬: C:\Users\qq772\playball\ (모노레포 루트) → app\ (Flutter), backend\ (FastAPI)
- 서버: ~/playball/backend/ ← 백엔드 루트 (api/, database/, crawler/ 등이 여기 위치)
- ⚠️ 서버에서 백엔드 루트는 ~/playball/backend/ (서비스 WorkingDirectory)

## 자주 쓰는 명령어
- 서버 접속: `ssh -i "C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key" ubuntu@168.107.61.147`
- SSH 터널: `ssh -i "C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key" -L 5433:localhost:5432 ubuntu@168.107.61.147 -N`
- 백엔드 배포: `cd ~/playball && git pull origin main --rebase && sudo systemctl restart playball`
- 백엔드 로그: `sudo journalctl -u playball -f`
- DB 접속: `sudo -u postgres psql -d playball`
- 크롤러(서버): `cd ~/playball/backend && nohup python3 crawler/crawl_all_games.py > /tmp/crawl_all.log 2>&1 &`
- 크롤러(로컬): `cd C:\Users\qq772\playball\backend && python crawler\crawl_all_games.py`
- Flutter: `cd C:\Users\qq772\playball\app && flutter clean && flutter pub get && flutter run`
- git push(백엔드): `cd C:\Users\qq772\playball && git add . && git commit -m "메시지" && git push origin main --force`

## 서비스 파일
```
Description=PlayBall FastAPI Server
WorkingDirectory=/home/ubuntu/playball/backend
ExecStart=/home/ubuntu/.local/bin/uvicorn api.main:app --host 0.0.0.0 --port 8000
```

## 앱 설정
- 패키지명: com.playball.app
- namespace: com.playball.app
- MainActivity: app/android/app/src/main/kotlin/com/playball/app/MainActivity.kt

### Flutter 의존성 (pubspec.yaml)
- dio: ^5.4.0 (HTTP)
- provider: ^6.1.1 (상태관리)
- shared_preferences: ^2.2.2 (토큰저장)
- kakao_map_plugin: ^0.3.3 (카카오맵)
- firebase_core: ^2.27.0 (FCM)
- firebase_messaging: ^14.7.19 (FCM)
- intl: ^0.20.2 (날짜포맷)
- flutter_localizations (한국어)

## 주요 파일 경로

### 백엔드 (서버: ~/playball/backend/, 로컬: C:\Users\qq772\playball\backend)
- api/main.py - FastAPI 앱 진입점
- api/routers/games.py - 경기 API
- api/routers/players.py - 선수 API
- api/routers/teams.py - 팀 API
- api/routers/auth.py - 인증 API
- api/routers/user.py - 유저 API
- api/routers/stadiums.py - 경기장 API
- api/routers/widget.py - 위젯 API
- api/routers/community.py - 커뮤니티 API
- database/connection.py - DB 연결 (user=playball_user, pw=playball1234)
- crawler/naver_crawler.py - 실시간 크롤러 (절대 수정 금지)
- crawler/scheduler.py - 스케줄러
- crawler/crawl_all_games.py - 과거경기 이닝별중계 크롤링
- crawler/crawl_past_rosters.py - 과거경기 로스터 크롤링

### 앱 (C:\Users\qq772\playball\app\lib)
- main.dart - 앱 진입점 + 스플래시
- screens/home/home_screen.dart
- screens/game/game_detail_screen.dart
- screens/player/player_screen.dart
- screens/team/team_screen.dart
- screens/team/team_detail_screen.dart - 팀 상세 (선수목록, 최근경기, 홈/원정전적)
- screens/auth/login_screen.dart
- models/game.dart
- api/api_service.dart
- providers/auth_provider.dart
- providers/game_provider.dart
- providers/team_provider.dart
- utils/team_theme.dart - 팀 컬러맵(kTeamColors), TeamLogo 위젯

## 백엔드 라우터 구조 (api/main.py)
- /auth - 인증 (로그인/회원가입/내정보/중복확인)
- /games - 경기
- /players - 선수
- /teams - 팀
- /user - 유저 (즐겨찾기/설정)
- /stadiums - 경기장
- /widget - 위젯
- /community - 커뮤니티

## 전체 API 목록

### 인증
- POST /auth/register - 회원가입 (email, password, nickname)
- POST /auth/login - 로그인 (email, password) → access_token 반환
- GET /auth/me - 내 정보 (Bearer 토큰 필요)
- GET /auth/check-email?email= - 이메일 중복확인
- GET /auth/check-nickname?nickname= - 닉네임 중복확인

### 경기
- GET /games/today - 오늘 경기
- GET /games/date/{date_str} - 날짜별 경기 목록 (home_starter, away_starter 포함)
- GET /games/{game_id} - 경기 상세 (innings, pitchers, batters)
- GET /games/{game_id}/relay - 실시간 중계 (진행중만)
- GET /games/{game_id}/relay_all - 전체 이닝 중계
- GET /games/{game_id}/roster - 경기 로스터
- GET /games/{game_id}/preview - 프리뷰 (선발투수, 상대전적)
- GET /games/{game_id}/record_detail - 상세 기록

### 선수
- GET /players/search?q=&player_type= - 선수 검색
- GET /players/hitters?season=&sort_by=&team_id=&limit= - 타자 목록 (sort: avg/home_runs/rbis/hits/ops/war)
- GET /players/pitchers?season=&sort_by=&team_id=&limit= - 투수 목록 (sort: era/wins/strikeouts/whip/saves/holds/war)
- GET /players/{player_id} - 선수 상세 (프로필 + 시즌별 성적)
- GET /players/{player_id}/daily?season= - 일자별 기록

### 팀
- GET /teams/ - 팀 목록
- GET /teams/rankings - 팀 순위 (wins/losses/draws/rank/win_rate/games_behind/streak/recent_5/home_record/away_record)
- GET /teams/{team_id}/players - 팀 선수 목록
- GET /teams/{team_id}/games - 팀 경기 목록

### 유저 (Bearer 토큰 필요)
- GET /user/favorite-teams - 즐겨찾는 팀
- POST /user/favorite-teams - 즐겨찾는 팀 추가 (team_id)
- DELETE /user/favorite-teams/{team_id} - 즐겨찾는 팀 삭제
- GET /user/favorite-players - 즐겨찾는 선수
- POST /user/favorite-players - 즐겨찾는 선수 추가 (player_id)
- DELETE /user/favorite-players/{player_id} - 즐겨찾는 선수 삭제
- GET /user/settings - 설정 조회
- PUT /user/settings - 설정 변경

### 커뮤니티
- GET /community/posts?team_id=&category=&page= - 게시글 목록
- GET /community/posts/{post_id} - 게시글 상세
- POST /community/posts - 게시글 작성 (title, content, category, team_id)
- POST /community/posts/{post_id}/like - 좋아요
- POST /community/posts/{post_id}/comments - 댓글 작성
- DELETE /community/comments/{comment_id} - 댓글 삭제

### 경기장
- GET /stadiums/ - 경기장 목록
- GET /stadiums/{stadium_id} - 경기장 상세

### 위젯
- GET /widget/live-scores - 실시간 스코어
- GET /widget/my-team-scores/{team_id} - 마이팀 스코어

## 인증 방식
- JWT Bearer 토큰
- 저장: SharedPreferences에 access_token 키로 저장
- 사용: Authorization: Bearer {token} 헤더

## DB 스키마

### teams
id, name, short_name
short_name: NC, HT(KIA), SS(삼성), OB(두산), LT(롯데), HH(한화), SK(SSG), KT, WO(키움), LG

### stadiums
id, name
1=서울(LG/두산), 2=고척(키움), 3=수원(KT), 4=인천(SSG), 5=대전(한화), 6=광주(KIA), 7=대구(삼성), 8=창원(NC), 9=사직(롯데)

### players
id, name, team_id, player_type(투수/타자), number, profile_image, naver_player_id, position, pitching_style, throws, bats, height, weight, birth_date

### games
id, naver_game_id, game_date, status(예정/진행/종료/취소), home_team_id, away_team_id, stadium_id, home_score, away_score, current_inning, inning_half, home_hits, away_hits, home_errors, away_errors, start_time

### game_innings
id, game_id, inning, home_runs, away_runs

### game_pitches
id, game_id, inning, inning_half(0=초/1=말), seqno, batter_name, pitcher_name, pitch_num, pitch_result(B/T/S/F/H/V/W), stuff, speed, strike, ball, out, base1, base2, base3, home_score, away_score, title, text, type, home_win_rate, away_win_rate
UNIQUE INDEX: (game_id, inning, inning_half, seqno, type) WHERE seqno IS NOT NULL

### game_pitchers
id, game_id, player_id, team_side(home/away), pitching_order, role, result(승/패/세이브/홀드), innings_pitched, strikeouts, earned_runs, walks, hits_allowed, runs_allowed, home_runs_allowed, pitch_count

### game_batters
id, game_id, player_id, team_side, batting_order, position, at_bats, hits, rbis, home_runs, avg, walks
UNIQUE: (game_id, player_id, team_side, batting_order)

### game_rosters
id, game_id, player_id, team_side, roster_type(batter/pitcher), batting_order, position, pitching_style, is_starter
UNIQUE: (game_id, player_id, team_side)

### batter_stats
player_id, season, games, at_bats, runs, hits, doubles, triples, home_runs, rbis, walks, strikeouts, stolen_bases, avg, obp, slg, ops, woba, wrc_plus, babip, iso, war, pa, tb, cs, sac, sf, ibb, hbp, gdp, errors, sb_pct, mh, risp, ph_ba

### pitcher_stats
player_id, season, games, wins, losses, saves, holds, innings_pitched, hits_allowed, runs_allowed, earned_runs, walks, strikeouts, home_runs_allowed, era, whip, fip, k_per_9, bb_per_9, babip, war, blown_saves, cg, sho, wpct, tbf, np, doubles_allowed, triples_allowed, sac, sf, ibb, hbp, wp, bk, qs, avg_against

### player_daily_stats
player_id, game_date, opponent, result, stat_type, avg, pa, ab, runs, hits, doubles, triples, home_runs, rbi, sb, cs, walks, hbp, strikeouts, gdp, era, ip, h, hr, bb, so, r, er

## 네이버 API
NAVER_TEAM_CODE_MAP: HT=KIA, OB=두산, LT=롯데, SS=삼성, HH=한화, SK=SSG, KT=KT, NC=NC, WO=키움, LG=LG

NAVER_HEADERS: User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 / Referer: https://sports.naver.com/

엔드포인트:
- https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/relay?inning={n}
- https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/lineup
- https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/preview
- https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/record
- https://m.sports.naver.com/game/{naver_game_id}/relay (셀레니움용)
- https://m.sports.naver.com/game/{naver_game_id}/lineup (셀레니움용)

## game_pitches type / pitch_result 코드
- type: 1=투구, 2=교체, 7=마운드방문/투수판이탈, 8=타자등장, 13=타석결과, 14=주자이동, 22=비디오판독, 24=수비위치변경/주자아웃
- pitch_result: B=볼, T=스트라이크, S=헛스윙, F=파울, H=타격, V=번트헛스윙, W=번트파울

## 크롤러 핵심 로직

### crawl_all_games.py (과거경기 이닝별중계)
- 셀레니움 네이버 모바일 중계 크롤링(역순 표시)
- pitcher_idx 경기 전체 유지 (이닝간 초기화 금지)
- 타자사이 교체(inter_changes) vs 타석내 교체(intra_changes) 구분
- 역순 파싱 후 정순 변환
- 셀레니움 옵션: --headless --no-sandbox --disable-dev-shm-usage --disable-gpu
- 대상: game_date < '2026-05-09' 종료 경기

### crawl_past_rosters.py (과거경기 로스터)
- _parse_naver_lineup() 함수 파싱
- 네이버 라인업 = 1군 전체 선수단(~190명, 정상)
- find_player(name, team_id): 팀ID 우선으로 동명이인 구분
- 대상: game_date < '2026-05-09' 종료 경기

### naver_crawler.py (실시간 - 절대 수정 금지)
- 5분마다 실행
- 진행중 경기 실시간 업데이트
- 경기 종료 감지 시 15분 후 선수 스탯 업데이트
- 경기 2시간 전부터 로스터 크롤링

## Flutter 앱 구조

### main.dart
- SplashScreen - 로딩중 네이비(#1A237E) 배경 + 야구공 아이콘 + PlayBall 텍스트
- AppEntryPoint - 로그인 상태에 따라 HomeScreen/LoginScreen 분기
- 페이드인 애니메이션 적용
- 상태관리: AuthProvider, GameProvider, TeamProvider

### game.dart 모델
id, status(예정/진행/종료/취소/라인업), homeTeam, awayTeam, homeScore, awayScore, currentInning, inningHalf, stadium, startTime, isDraw, winPitcher, losePitcher, homeStarter, awayStarter

### api_service.dart
- baseUrl: http://168.107.61.147:8000
- HTTP 클라이언트: Dio
- 토큰: SharedPreferences에 access_token 저장
- 인증헤더: Authorization: Bearer {token}

### game_detail_screen.dart
- 탭: 이닝/프리뷰/로스터/투수/타자/기록
- _getWinRate(): 진행중→relay win_rate, 종료→relayAll win_rate
- _buildLiveStatus(): 볼/스트라이크/아웃/베이스 표시
- 승리확률: 스코어보드 아래 표시 (진행중/종료 모두)
- 자동새로고침: 30초마다 _refreshLiveData() (진행중만)
- 이닝 탭 자동 스크롤: relayAll 업데이트 시 최하단으로 스크롤
- Timer는 dispose()에서 cancel()

## 주의사항
- naver_crawler.py 절대 수정 금지
- 과거경기 수정 시 반드시 game_date < '2026-05-09' 조건
- 동명이인 선수 처리 시 반드시 team_id 기준 조회
- 서버 백엔드 루트: ~/playball/backend/ (WorkingDirectory)
- 로컬 백엔드: C:\Users\qq772\playball\backend
- 삼성 홈경기 구장 없는 경우: UPDATE games SET stadium_id = 7 WHERE home_team_id = 11 AND stadium_id IS NULL
- git push 시 --force 옵션 필요 (모노레포 구조로 인해)

## 해결된 주요 이슈
- 동명이인 player_id 오류 → game_date < '2026-05-09' 팀ID 기준 수정 완료
- 투수 매핑 꼬임 → pitcher_idx 경기 전체 유지
- 무승부 표시 오류 → winPitcher/losePitcher 조건 추가
- 승리확률 위치 → 스코어보드 아래로 통일
- 삼성 홈경기 구장 없음 → stadium_id=7 업데이트
- database 모듈 오류 → connection.py user=playball_user로 수정
- 패키지명 불일치 → namespace/applicationId/MainActivity 모두 com.playball.app으로 통일
- 서버 경로 오류 → WorkingDirectory=/home/ubuntu/playball/backend로 수정
- force push 후 database/connection.py 유실 → 서버에서 직접 재생성

## 미구현 기능

### 완료
- [x] 경기 중 자동 새로고침 (30초)
- [x] 앱 패키지명 통일 (com.playball.app)
- [x] 스플래시 화면
- [x] 이메일/닉네임 중복확인 API + UI
- [x] 이닝 중계 자동 스크롤
- [x] 부문별 순위 (타자/투수 TOP 10)
- [x] 경기 예정 시 선발투수 표시 (홈화면)
- [x] 선수 포지션별 필터링
- [x] 취소 경기 UI 처리 개선
- [x] 팀 순위 페이지 개선 (로고, 최근5경기, 홈/원정전적, 팀 상세화면)
- [x] 팀 로고 전체 적용 (GameCard + 순위 + 부문별순위)

### 인증/계정
- [ ] 비밀번호 찾기/재설정
- [ ] 소셜 로그인 (카카오/구글)
- [ ] 회원탈퇴
- [ ] 닉네임 변경
- [ ] 프로필 이미지 업로드

### 홈/경기 목록
- [ ] 경기 카드 최근 5경기 승/패/무 표기 (팀별)
- [ ] 날씨 정보 표시 (야외 경기장)

### 경기 상세
- [ ] 이닝 중계 스크롤 자동화
- [ ] 승리확률 그래프
- [ ] 경기 흐름 그래프 (이닝별 득점 추이)
- [ ] 투수 구종 비율 차트
- [ ] 스트라이크/볼 비율 표시
- [ ] 상대 팀 최근 5경기 승/패/무 표기

### 팀 순위
- [ ] 팀별 부상자/등록말소 현황
- [ ] 피타고리안 승률 표시
- [ ] 직관 승률 입력 기능

### 부문별 순위
- [ ] 1~3위 상단 가로 배열 하이라이트
- [ ] 삼진왕/세이브왕 등 타이틀 표시

### 캘린더
- [ ] 캘린더 뷰 API (백엔드)
- [ ] 월별 캘린더 뷰 (프론트)
- [ ] 마이팀 일정 자동 등록
- [ ] 과거 경기 스코어 표시
- [ ] 날짜 클릭 → 경기 상세
- [ ] 홈/원정 구분 표시

### 선수
- [ ] 시즌 성적 트렌드 그래프
- [ ] 선수 비교 기능 (2명 나란히)
- [ ] 투구 히트맵 (스트라이크존 시각화)
- [ ] 타구 방향 차트 (스프레이 차트)
- [ ] 드래프트/FA 정보

### 마이팀/마이페이지
- [ ] 마이팀 경기 우선 표시 (개인화 홈)
- [ ] 내 게시글/댓글 목록
- [ ] 즐겨찾기 선수/팀 설정 UI 개선

### 커뮤니티
- [ ] 커뮤니티 카테고리 세분화 (자유/팀별/분석/질문)
- [ ] 게시글 이미지 첨부
- [ ] 게시글 검색
- [ ] 게시글/댓글 신고
- [ ] 인기글 탭

### 알림
- [ ] FCM 푸시알림 (Firebase 연동)
- [ ] 경기 시작/종료 알림
- [ ] 득점 알림
- [ ] 마이팀 알림만 받기 설정
- [ ] 알림 히스토리 페이지

### 경기장
- [ ] 카카오맵 연동 (경기장 위치)
- [ ] 경기장 주변 맛집/주차장 정보
- [ ] 선수 추천 맛집 등록 기능

### 기타
- [ ] 다크모드
- [ ] 홈 화면 위젯
- [ ] 오프라인 캐싱
- [ ] 상대전적 히스토리
