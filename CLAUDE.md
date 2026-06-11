# PlayBall

KBO 야구 앱 | Flutter + FastAPI + PostgreSQL

## 인프라
- 서버: Oracle Cloud **A1.Flex (ARM aarch64, 4 OCPU/24GB)** Ubuntu 22.04 | 168.107.36.158:8000 (내부), HTTPS: playball.duckdns.org (2026-06-11 마이그레이션 — duckdns 자동갱신 cron 서버 등록)
- 구 x86 박스 168.107.61.147 = **DNS 릴레이 중** (nginx가 신 서버로 전체 프록시 — 폰/통신사 DNS 캐시가 구 IP 물고 502나던 사고 해결. 원본 conf 백업 = 구박스 /tmp/playball.nginx.pre-relay.bak). API/scheduler disabled, DB = 컷오버 스냅샷. **종료는 DNS 캐시 정리 후(1주+) — 끄면 캐시 잔존 유저 전원 접속 불가**
- SSH 키: `C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key`
- DB: localhost:5432(서버)/5433(터널), db=playball, user=playball_user, pw=<env DB_PASSWORD> (회전 2026-06-09, 평문 보관 금지)
  - pg 튜닝(2026-06-11, 24G 박스): ALTER SYSTEM(auto.conf) — shared_buffers 4G·effective_cache_size 12G·work_mem 32M·maintenance 1G·max_wal 2G·random_page_cost 1.1·parallel 4/2. DB 재구축 시 auto.conf 보존/재적용
- 레포: https://github.com/Aa26178787/playball
- HTTPS: nginx + Let's Encrypt 리버스프록시 (Android 9+ HTTP 평문 차단 → 앱은 반드시 HTTPS)
- 서비스 2개: `playball`(API uvicorn) + `playball-scheduler`(크롤러/알림 — 별도 프로세스)

## 폴더 구조
- 로컬: `C:\Users\qq772\playball\` → `app\`(Flutter), `backend\`(FastAPI), `ui\`(mockup 원본 — 이식 완료분 보관)
- 서버: `~/playball/backend/` ← WorkingDirectory (api/, database/, crawler/, models/)

## 주요 명령어
```bash
ssh -i "C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key" ubuntu@168.107.36.158
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
GET /games/{id}/win-prob-series @30 — 타석별 홈 승률 시계열 (시즌초=naver 승률, 5/9~=인게임 모델 즉석계산, 저장 없음)
※ relay의 field_view: batter(bats 포함)/next_batter(타순+1)/runners/defense + current_state.home_win_prob(인게임 모델)
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
GET /teams/{id}/bullpen-status @1800 — 불펜 피로도 신호등 (최근7일·선발제외·KST. red=2연투+|3일45구+|어제35구+ / yellow=어제등판|3일25구+|3일2회. 응답=등판자만, 미포함=휴식충분)
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
- insta_handle: 358명 등록 (활성 기준, 미등록 140 중 외국인 ~31). **검증·도구·워크플로 = `backend/crawler/INSTA_VERIFY.md`** (⭐imginn 본인검증=gold, 가족계정·동명이인 색출, ⚠️Google AI개요 핸들 환각 절대금지). 신고 = `insta_handle_reports` + `POST /players/{id}/report-insta`
- ⚠️ 양현종·이태양 = KIA·키움 양쪽 중복(team_id 오배정 의심, 미해결)

### games
`id, naver_game_id, game_date, status(예정/진행/종료/취소), home/away_team_id, stadium_id, 스코어/이닝/안타/실책, start_time`

### game_* 테이블
- game_innings / game_pitches(seqno, type, title — 투구+이벤트) / game_pitchers(result=승/패/세이브/홀드) / game_batters / game_rosters(roster_type, batting_order, position, pitching_style, is_starter) / game_highlights / game_relay_archive(payload JSONB) / game_predictions(UNIQUE user,game)
- game_pitch_locations: `game_id, inning, inning_half, pitcher_name, batter_name, x, z, result(ball/strike/swing/foul/hit), top_sz, bot_sz, pitch_type, stance(R/L)` — 106k+ 행, 피칭디자인/타자존 소스
  - ※ result='hit'은 인플레이 (안타 아님). 안타 판정 = game_pitches 타석 결과 텍스트 ('1루타/2루타/3루타/홈런/내야안타' — '안타' 단독 표기 안 씀)

### batter_stats / pitcher_stats
(시즌 누적 — 컬럼 광범위. sb_pct는 이미 % 단위 ×100 금지)
- **24·25 과거 시즌 적재 완료** (2026-06-11): batter 293/343, pitcher 206/240행. 소스 = 네이버 통계 API(`statiz_crawler get_*_stats(season)` + `save_players_and_stats(update_players=False)` — **현존 선수 naver_id 매칭만, 신규생성/프로필갱신 금지**: 은퇴선수 오염+현역 team_id 과거팀 덮어쓰기 방지) + KBO 공식 보강(규정충족자만 노출됨) + SQL 파생. 재실행 = `crawler/backfill_season_stats.py 2024 2025`. war/woba/wrc+ 포함, 은퇴/이탈 선수 행 없음(의도)
- ⚠️ **KBO 기록 페이지 페이저**: '다음' 링크 = 페이지 아님, **5단위 블록 점프** — 숫자 링크 우선 클릭 (한때 1·6페이지만 수집 undercrawl)
⚠️ **statiz 미제공 파생지표 = crawler `recompute_pitcher_derived`/`recompute_batter_derived`(statiz_crawler.py)가 raw서 계산** — statiz INSERT/ON CONFLICT엔 없어 안 채우면 0. 투수: fip·k_per_9·bb_per_9·babip·k_bb·h_per_9·hr_per_9·wpct·k_pct·bb_pct·k_bb_pct / 타자: tb·xbh·bb_k·gpa·bb_pct·k_pct. 이닝 .1/.2=⅓⅔ 변환, FIP 리그상수(시즌집계), BABIP tbf>0 가드, K%/BB%는 % 단위(×100 저장). tbf(상대타자수)도 statiz 일부만 제공 → recompute가 추정(3*IP+피안타+볼넷+사구)으로 채움(K%/BB%/BABIP 분모). save_players_and_stats 끝서 호출. **신규 파생 추가 시 recompute에 넣을 것**. go/ao류는 statiz 미제공=계산불가
- ⚠️ **`idx_game_rosters_player_id`(game_rosters(player_id)) 인덱스 필수** — /hitters·get_player_detail의 상대포지션 `mode()` correlated subquery가 인덱스 없으면 seq scan(27k)×선수수=2.5~5s → 앱 8s receiveTimeout 초과 → 타자 리스트 빈화면 사고(06-09). +`get_hitters @cached(300)`. **DB 재구축 시 인덱스 재생성**
batter: avg,obp,slg,ops,woba,wrc_plus,babip,iso,war,risp,fpct,po,assists,dp,pb …
pitcher: era,whip,fip,k_per_9,bb_per_9,babip,war,qs,blown_saves,avg_against …

### 플랫폼 코어 (2026-06-11 — 메가A/B 토대)
- **game_event_stream**: 도메인 이벤트 (scheduler 8종 발행: game_start/score_change/game_end/cancelled/extra_innings/pitcher_change/walkoff/starter_announced). `api/event_stream.emit_event`, UNIQUE(game_id,type,dedup_key) dedup. ⚠️ 기존 `game_events`(naver_crawler 텍스트 적재)와 별개 테이블. 소비자(예정): 타임라인·WPA·리플레이·브리핑
- **plate_appearances**: PA 정규화 (`api/pa_parser.py` — game_pitches type 8/1/13 + **23(주요플레이) 파싱**). 컬럼: 타자/투수/result_class(single~hr/bb/hbp/so/sac/error/fc/reach_other/out)/is_hit/n_pitches/outs_before/주자/스코어/**win_rate_before·after(홈 기준 — WPA 재료)**/seq범위. 종료 후처리서 자동 적재 + `crawler/backfill_pa.py`(재실행 안전 upsert. 단 **pa_seq 시프트형 파서변경 시 DELETE 후 재실행**)
  - ⚠️ **type 23 필수** (2026-06-11 발견): 홈런·희생플라이 등 주요플레이는 type 13 없이 **23으로만** 발행되는 경기 다수 (24·25 아카이브 전체 + 2026 일부) — 23 무시하면 해당 타석이 다음 타자 대타로 오인돼 통째 증발 (2024 hr=0 사고). 가드 = 타자명 일치 + classify≠etc. 현재 **145,689 PA (24~26 3시즌, win_rate 98.7% 커버)**
- ~~데이터 기간 결손~~ → **win_rate 버그 해결**(2026-06-11): 원인 = metricOption이 textRelays **항목 레벨**인데 textOptions 내부서 조회(naver_crawler 레벨 착오). 수정+`backfill_winrate.py`로 5/9~ 재크롤 → 전 기간 WPA 가능. 잔여 결손 = 3/12~5/8 카운트/주자 스냅샷만(컨텍스트 NULL 유지). ※Naver metricOption에 **wpaByPlate**(타석 WPA 직접 제공)도 있음 — 필요 시 활용
- **과거 시즌(24·25) 수집 = GO 판정**(2025-06-11 파일럿): 일정·relay API 과거 시즌 완전 보존(구조 동일). 비용 0(대역 2-4GB·저장 ~70MB), 시즌당 야간 배치 8-9시간(1.5s 간격). 선행 = 과거 games 행 INSERT(일정 크롤). 이득 = matchup 진짜 통산 + per-PA 재평가(AUC 천장 ~0.55) + 2시즌 아카이브
- 안타판정: result_class 분기 순서 의존 ('땅볼로 출루'=reach_other, '삼진 아웃'=so). 대타 교체=동일 pa_seq 슬롯 대체, 무결과 타석(3아웃 주자사)=미적재
- **인게임 승률 모델** (`api/prediction/ingame_model.py`): PA 컨텍스트+승패 라벨 로지스틱, **계수 JSON**(`ingame_coef.json` — pickle 불요, 추론 순수 파이썬). v1 = 8,488타석 AUC .853/Brier .154. 재학습 = 서버서 `python3 -m api.prediction.ingame_model` → coef scp 회수 커밋. 소비: relay home_win_prob·win-prob-series·(예정)결정적순간 푸시/WPA. matchup도 PA 기반 교체 완료(/players/matchup — 직접대결 정밀, 필드뷰 좌하단 캡션)

### 알림/투표/기타
- user_notifications: type = game_start/score_change/comeback/game_end/extra_innings/cancelled/rank_change/winning·losing_streak/roster_change/new_comment/daily_briefing/**clutch_moment**(승률 ±20%p 급변·5회+·평균 0.81건/경기 — notify_score_change 설정 준용)
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

### 성능 백로그 (2026-06-10 — 측정 먼저: TimingMiddleware+nginx $request_time 로그+DevTools 타임라인으로 병목 확정 후 착수)
- ✅즉효 3종(2026-06-10 적용): orjson(default_response_class — FastAPI 0.135가 deprecation 경고 1회 출력하나 동작·성능 정상, 향후 fastapi 업그레이드 시 반환타입 어노테이션 방식 검토)·uvicorn[standard](uvloop+httptools)·nginx TLS1.3/session_cache/stapling(06-09 기적용 확인)
- 중간: **ETag/304**(30s 폴링이 매번 풀바디 재전송 중 — 해시 ETag+If-None-Match면 변화 없을 때 헤더만, 서버+클라 _dedupGet 양쪽 수정)·**서버측 캐시 SWR**(@cached 만료 시 stale 반환+백그라운드 갱신 — cold 시 Naver 5s 블로킹이 p99 원인, 날씨 워머 패턴 일반화)·**프로필 이미지 썸네일**(크롤 시 88px/리스트용 사전 리사이즈 — 목록 스크롤 대역폭/디코드)
- 큰 체감(반나절+): **`/home/bootstrap` 집계 엔드포인트**(홈 진입 burst 20+요청→1요청 — RTT 왕복 절감, LTE서 최대 체감. rate limit 버스트 사고 원인도 제거)·대형 JSON `compute()` isolate 파싱(메인스레드 jank)·홈 위계 로딩(첫 프레임=오늘경기만, 나머지 후순위)
- 장기: Cloudflare CDN(이미지 edge 캐시 — 도메인 계획과 묶음)·dio+http2_adapter(h2 멀티플렉싱 — bootstrap 도입 시 가치 하락하니 후순위)·uvicorn --workers(인메모리 캐시 워커별 중복 → Naver fetch 배수 트레이드오프, 부하 생기면 검토)

## 주의사항
- **baseUrl HTTPS 고정** / git push --force / 커밋·배포·로그·APK는 묻지 않고 실행
- **배포 시 playball + playball-scheduler 둘 다 재시작**
- **한글 파일 PowerShell -replace 금지** (인코딩 깨짐 → crash loop). Edit 도구 사용
- **ARM(A1) selenium = snap chromium — 반드시 `crawler/driver_util.arm_or_wdm_chrome` 경유** (직접 webdriver.Chrome 생성 금지 — 신규 크롤러 포함). 규칙: ① binary_location 지정 금지(즉사) ② 프로필 = `~/snap/chromium/common/` 하위 **mkdtemp 인스턴스별 고유**(PID 기반이면 PID 재활용 × 크래시 잔존 SingletonLock → "Chrome instance exited" 간헐 즉사 — 1h 잔존물 자동청소 내장) ③ webdriver_manager는 ARM chromedriver 미제공 ④ scheduler 유닛 MemoryMax=2G(chromium 자식 — 512M이면 OOM 위험, drop-in memory.conf) ⑤ 진단 = env `SELENIUM_DRIVER_LOG=경로`로 verbose 채집
- PS5.1: here-string 안 큰따옴표 → git -m 인자 깨짐 (**커밋 메시지에 `"` 절대 금지** — pathspec 에러로 커밋 자체 실패, 2회 사고) / Invoke-RestMethod 한글 mojibake(수동 UTF-8 디코드) / `$h`·`$H` 대소문자 동일 변수
- **웹 = CanvasKit-only 고정, `webHtmlElementStrategy.prefer`(<img> 플랫폼뷰) 절대 금지** — 06-11 A/B 5회 최종결론: iOS Safari 26에서 플랫폼뷰 포함 빌드 = 탭/standalone 불문 "문제 반복 발생" 크래시, CanvasKit-only만 안정. standalone PWA도 비활성 상태(index.html apple-capable 제거 — 홈 아이콘=Safari로 열림). **잔여 미해결 = iOS서 CanvasKit 이미지 미표시**(200 수신 후 디코드 실패 의심 — errorBuilder가 조용히 삼킴. 추적 카드: ① /ni/ 프록시 Pillow 재인코딩(plain RGB) ② canvasKitForceCpuOnly ③ --wasm(skwasm, COOP/COEP) /app2/ 실험. 관련 flutter#152709 누수도 미해결 오픈). netCircleAvatar는 유지(구조 무해) / **웹 back-trap pushState는 반드시 `history.state` 보존 재푸시** (null로 덮으면 엔진 serialCount 깨짐)
- ABS 존 상수 plateHalfW=8.5/12, absHalfW=9.95/12, ballR=1.45/12 — 변경 금지
- TeamLogo 파라미터 `teamCode` / TeamDetailScreen `team`(Map) / NetworkImage 금지 → CachedNetworkImage
- share_plus ^10.0.0 고정 (10.1.4 = firebase 충돌) / 소셜 로그인 안 함(결정) / 동명이인 team_id 기준
- 과거경기 수정 game_date < '2026-05-09' 조건 / 삼성 홈 stadium_id=7 보정 SQL
- 서버 pull 전 충돌 파일 rm (insta CSV 등 untracked 주의) / firebase-service-account.json push 금지
- PgBouncer 6432 유지 / 커뮤니티 조회수 _view_cache 재시작 초기화(의도)
- **nginx 배포 = `/etc/nginx/sites-enabled/playball`이 symlink 아닌 독립 실파일** (repo `nginx_playball.conf` → sites-available **아니라** sites-enabled로 cp해야 적용). ⚠️ 백업파일은 절대 sites-enabled 안에 두지 말 것(nginx가 `sites-enabled/*` 전부 로드 → `limit_req_zone` 중복 `emerg`). 백업은 /tmp. 적용 = cp→`nginx -t`→`systemctl reload nginx` (reload graceful이라 직후 수초 old/new worker 혼재 정상)
- ⚠️⚠️ **repo nginx_playball.conf가 프로덕션 직접튜닝보다 뒤처질 수 있음** — 06-09 사고: CSP 배포가 sites-enabled를 repo로 덮으며 **API rate limit 300r/m→30r/m·burst 100→20 revert → 앱 홈 버스트(1초 20+요청) 전부 503 = 전 데이터 로딩 실패**. **cp 배포 전 반드시 `sudo diff /etc/nginx/sites-enabled/playball ~/playball/nginx_playball.conf`**. 현 튜닝 = api **300r/m+burst100** / auth 10r/m+burst5 (repo 동기화 완료). 진단법: nginx error.log `limiting requests, excess` + access.log `Dart/3.11`+503
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
- **06-11 즉시묶음**: 보안5(EXIF Pillow 재인코딩·pg listen localhost·rpcbind off·백업 오프사이트 pull·인증 5회 제한) + 성능(orjson·uvicorn[standard]) + **app-config 풀스택**(서버 `/app-config`+`app_config` 테이블 / 클라 `AppConfig` 강제업데이트 다이얼로그·홈 서버배너·`enabled()` 킬스위치 API — 위젯 적용 점진) + **아침 브리핑**(KST 09:00 팀별 1통, 라이브 검증 완료) + UI소품(햅틱·이닝칩 자동스크롤·댓글 이탈경고). 잔여: 다크 육안검증
- **06-11b 메가A 착수**: 플랫폼 코어(game_event_stream 8종 발행 + plate_appearances 24,584타석 백필 — 분포 리그 정합 검증) → **matchup 직접대결**(서버+선수상세+필드뷰 좌하단 라이브 캡션) → **인게임 승률 모델 v1**(AUC .853)+win-prob-series+relay home_win_prob → **승률 그래프 UI**(중계탭 상단 `_WinProbChart` — 타석별 라인·50%점선·이닝라벨·터치툴팁·라이브30s) → **결정적순간 푸시**(`_check_clutch_moment` — game_pitches 최신행→모델, ±20%p·5회+, 시뮬 평균 0.81건/경기). **per-PA 안타확률 = 검증 후 보류**(AUC 0.50 — 1시즌 표본으론 타자 간 분산이 타석 노이즈에 묻힘, 출루 라벨도 동일. `pa_hit_model.py` 보존, 2시즌+ 재평가. 데일리픽 등 의존 기능 동반 보류) → **불펜 피로도**(bullpen-status + 경기상세 로스터 불펜 색상뱃지·범례 — 라이브 검증: 조동욱 red 2연투 정합). **메가A 전체 완료** (per-PA만 데이터 사유 보류). ⚠️**서버 pull 충돌 주의 확장: 학습 coef json도 untracked 충돌원** (ingame_coef.json 사고 — pull 실패로 직전 배포 누락됐었음. 산출물 커밋 전 서버 측 rm) ⚠️5/9~ Naver win_rate 미수신 건 라이브 시간대 확인 대기
- **06-11c A1이전+3시즌화**: A1.Flex 마이그레이션(상단 인프라) → **PA type23 파서버그 발견·수정**(홈런/SF 타석 증발 — 전체 재구축 132,949→145,689 PA, 김도영 2024 HR 38 정합 확인) → 모델 재학습(ingame AUC .8541@14.5만 / **per-PA .5226 — 0.497서 개선됐지만 표면노출 계속 보류**, matchup 통산은 3시즌 자동 수혜) → **24·25 시즌스탯 적재**(네이버 통계 match-only + KBO 보강 + statiz 타자파생 미실행 오타픽스) → **선수상세 시즌칩**(2026/2025/2024/통산 — 통산=클라 집계(카운팅 합·비율 재계산·불가시 표본가중), 리그비교/규정뱃지는 최신시즌 뷰만) → **홈 날짜스트립 2024-03~ 확장**(연도 픽커 추가, 월칩 = 보는 연도 기준, 오프시즌 날짜 = 경기없음 비활성). 존히트맵/피칭디자인은 자연히 3시즌 합산됨(표본↑, 의도)
- **06-10 선수상세 개편**: 핵심스탯 커스텀피커(선수별 슬롯)+리그순위/규정미달/방향인식 비교말풍선(길게누르기,단어줄바꿈 word-joiner)·스탯 ⓘ용어설명·세부그리드=전체−핵심·팀상세 SNS링크(YT/IG/굿즈)·최근본선수칩·인스타 신고버튼. **인스타 다중검증(상세=INSTA_VERIFY.md): 339→358, imginn으로 가족계정9·동명이인 박멸**. 선발투수 게임카드 조기표시(`_update_probable_starters` 오늘+내일). 홀드 GREATEST고정버그(올러294)→자가치유

## 해야할 것
### 즉시 (코드측)
- [ ] **다크모드 육안검증** ⚠️: 2026-06-09 세션 다크 ~15커밋이 헤드리스 컴파일만 검증됨 → `flutter run` 다크 점검(경기상세 통계테이블·라인업 타순배지·로스터헤더 / 선수비교 / 선수상세 통계 / 인기투표 토글 / 각 화면 에러상태 AppErrorView) 후 발견분 수정. 골든이 향후 회귀는 방어
- [x] **키 회전** (2026-06-09 완료): Gmail·Kakao(JS/네이티브/REST)·DB pw 회전+라이브검증, 옛 Gmail 폐기 확인 (출시 APK는 새 키 재빌드)
### 중기 (코드 품질) — ✅ 2026-06-09 전부 완료 (상세 기록 보존)
- [x] ~~empty catch debugPrint~~(✅ 2026-06-09 빈 `catch(_){}` 52개 → `catch(e){debugPrint('<file>: $e')}` 17파일, game_detail:435 finally형만 제외) / ~~non-null `!` audit~~(✅ 2026-06-09 검토결과 안전·수정불요: `['key']!` 23개=로컬 const map·초기화보장·null체크 storage / `x!.` 94개=`_gameData!` 등 가드 후 idiomatic. crash 버그 없음) / ~~AppErrorView 전면~~(✅ 2026-06-09 6화면 ad-hoc 에러UI→`AppErrorView`(테마인식): team×2·notifications·search·player_stats·pitch_chart·post_detail. 잔여=home(레이아웃 얽힘,brand 적용됨)·team_detail 인라인 retry) / ~~서버 print→logging~~(✅ 2026-06-09 런타임서비스 fcm/weather/email/sms → `api/log_setup.py` 중앙설정+모듈 logger. prediction CLI·scheduler 운영 print는 유지)
- [~] **SemColor.panelDark 감사**(2026-06-09): 80개 분류 — A(라이트잉크 `isDark?light:panelDark` ~40)·A2/A3·B(SnackBar/헤더그라디언트/온보딩 의도)는 **유지**. **Pattern-C 버그**(무조건 panelDark를 fg/fill/border에 → 다크 안 보임) ~22개. 수정완료 6: home OutlinedButton×2·login/register checkbox·phone icon → `SemColor.brand(context)`(다크0xFFE5E5E7/라이트panelDark). **C-fg 수정완료**: home버튼·auth체크박스·phone아이콘 + game_detail TabBar label/indicator(×2)·OutlinedButton → `brand(context)`(analyze clean). **C-fg defer**: player_stats(65·314)·player_compare(285) = 위젯이 다크 미대응(context 파라미터 없음 + grey200/black87 혼재) → 단독 swap 불가, AppErrorView/홀리스틱 다크패스와 묶을 것. player_compare 203 = 다크 헤더 의도(B 재분류). **C-bg 결정**(다크 surface=기존 `AppColors.surfaceDark 0xFF18181C/surface2Dark` 재사용, 새 토큰 불요): player_screen 선수/구단 토글(818·836 bg + 825·843 텍스트반전)=✅`brand(context)`+invert. **gd C-bg defer→홀리스틱 다크패스**(헤더3301·avatar3364/3770·TableRow3863/3889): StatelessWidget 헬퍼는 context 없음 + 테이블 border(`0xFFE0E0E4`)·셀 비테마라 단독 fix 불일치. **홀리스틱 착수**: player_compare 테이블/검색카드 테마화 ✅(2026-06-09, State라 `context` 가용·AppColors.surfaceDark/surface2Dark 사용, 헤더는 의도 다크밴드 유지). player_stats ✅(2026-06-09 헤딩/섹션라벨 color 제거→테마 텍스트색 상속, 토글 brand+반전, _buildContent에 context 스레딩). game_detail ✅(2026-06-09 통계테이블 border/헤더row + 로스터헤더(3301) + 타순배지(3364·3770) → 인라인 다크 hex 0xFF1F1F24/26262C, `_tableCell` 데이터셀은 color:null이라 이미 테마구동). **홀리스틱 다크패스 3화면(player_compare·player_stats·game_detail) 완료**. ⚠️**전체 육안검증 미완**(헤드리스 컴파일만) → `flutter run` 다크모드 점검 필수. ⚠️무차별 치환 금지(A/B 다수). / **Radii**: magic `circular(999)`→`Radii.pill` 33곳 ✅(2026-06-09, 5파일). 수치 스케일(4/8/12/16/20)은 off-scale 값(10/13/14 등) 多 혼재 → 부분 토큰화=일관성↓라 점진 보류
- [~] ~~Golden test(다크+라이트)~~(✅ 2026-06-09 인프라 구축: `app/test/golden/` built-in `matchesGoldenFile`, AppErrorView 라이트/다크 PNG 기준 커밋. 갱신=`flutter test --update-goldens test/golden`, 확장=테마인식 위젯 동일 패턴 추가. ※폰트 미로드로 텍스트=tofu box지만 색/레이아웃 회귀엔 충분. 잔여=주요화면 골든 확대) / ~~pre-commit grep hook~~(✅ 2026-06-09 `.githooks/pre-commit`: 음수 letterSpacing WARN + `baseUrl http://` BLOCK. 클론마다 활성화 `git config core.hooksPath .githooks`) / ~~nginx 보안헤더~~(✅ 2026-06-09 HSTS+CSP+Permissions-Policy 등 7종 적용·검증)
- [x] 이닝중계 진행이닝 TTL 30→10s 검토 → **유지 결정**(클라 폴링 30s 고정이라 하향=Naver 부하 3배·UX 이득 0)
### 보안 점검 — ✅ 2026-06-10 전부 완료 (감사: ufw deny-default·fail2ban·SSH 키온리·unattended-upgrades·pip-audit 주간·bcrypt·refresh rotation 확인)
- [x] **업로드 EXIF 제거**: `api/image_utils.py` strip_metadata(Pillow 재인코딩, exif_transpose 선적용=회전보존) — 프로필+게시글 적용
- [x] postgres listen_addresses → localhost (`ALTER SYSTEM` — 범인은 auto.conf의 과거 ALTER SYSTEM '*') / rpcbind disable / 이메일 인증 5회 실패 시 코드 무효화(`phone_verifications.attempts`)
- [x] 백업 오프사이트: `backup_pull.ps1` + schtasks PlayballBackupPull(매일 12:00 트리거, 6일 스로틀=주1 pull, `~/playball_backups/` 4개 보관, 1MB 미만=실패 간주)

### 베타/출시 배포 경로 (2026-06-11 결정)
- **Android 베타 = Firebase App Distribution** (이미 Firebase 연동·Crashlytics 동일 콘솔·완전 무료·Play Console $25 불요·자동 업데이트 알림). release keystore 생성+안전백업 선행(분실=업뎃 불가). 지인 이메일 등록→링크 설치
- **iOS = $99 회피 불가** (Apple 서명 인증서가 Developer Program에 묶임 — TestFlight·App Distribution·Scarlet 모두 그 위. Mac은 Codemagic 무료티어로 회피 가능하나 $99는 별개). 지인 소수 = **웹 PWA 맛보기**(무료·안전), 정식 iOS = $99+Codemagic→TestFlight
- ⭐⭐ **웹 동반 수정 원칙 (2026-06-11, 사용자 지시)**: 앱(Flutter) 수정 시 **웹도 반드시 같이 반영**. 같은 코드베이스라 대부분 자동 동반되나, **재빌드+배포 필요**(`MSYS_NO_PATHCONV=1 flutter build web --release --base-href "/app/" --no-web-resources-cdn` → tar→rsync `/var/www/playball_web/`). 배포 스크립트화 권장. ⚠️**앱엔 되는데 웹엔 안 되는 변경이면 사용자에게 먼저 고지**. 웹 미지원 영역(`kIsWeb` 분기 필요): 푸시·카카오지도(inappwebview)·갤러리(photo_manager)·이미지공유·캘린더내보내기·secure_storage(→_SafeStore 폴백 완료)·dio IO어댑터(→kIsWeb 가드 완료)·외부이미지(→webSafeImageUrl 프록시 완료). 새 기능이 이 영역 건드리면 웹 폴백 동시 구현 or 고지
- **웹 PWA 배포 완료** (2026-06-11): `https://playball.duckdns.org/app/` — 지인 iOS 사파리서 '홈 화면에 추가' = 설치. 빌드 = `MSYS_NO_PATHCONV=1 flutter build web --release --base-href "/app/"`(Git Bash 경로변환 회피 필수) → `build/web` tar→ `/var/www/playball_web/` rsync. nginx `location /app/` alias+SPA try_files + **CSP 재선언**(server의 `script-src 'none'`이 location add_header로 덮여야 Flutter JS 작동 — script 'self'+unsafe-inline+wasm-unsafe-eval, img https:). 갱신 = 재빌드→rsync (nginx 불변). ⚠️재빌드 시 base-href·MSYS 플래그 누락 주의
- **웹 PWA 빌드 시 불가 기능**: 푸시(firebase_messaging/local_notifications)·구장지도(flutter_inappwebview)·갤러리(photo_manager)·이미지공유(path_provider+share_plus 파일)·캘린더내보내기(add_2_calendar). 크롭·secure_storage·Crashlytics=반쪽. ✅정상=홈/경기상세(필드뷰·중계·승률그래프·맞대결·불펜)·선수(피칭디자인·존히트맵)·순위·커뮤니티텍스트·검색·인증

### 장기 / 출시 외부작업 (네 권한·비용 — **물어보면 안내**)
- [ ] **도메인 + Cloudflare**: 웹사이트 Free 플랜 + Tunnel(IP은닉, duckdns/certbot 제거). ⚠️ Bot Fight Mode OFF(앱 API 차단), 동적 JSON 캐시 bypass
- [ ] **Play Console**($25) + keystore 안전백업(분실=업데이트 불가) + Data Safety + targetSdk 확인
- [ ] **법무 잔여**: 정책 페이지(`/privacy`·`/terms`)·HTML(`backend/static/legal/`) 배포 완료. 남음 = ① 문의메일 placeholder(`playball.support@gmail.com`) 실계정 교체 ② 출시 전 법률 검토 ③ (옵션)앱 마이페이지 약관 링크 ④ KBO/Naver 저작권 최종 판단
- [ ] 홈화면 위젯(Android AppWidget native kotlin) / state restoration / i18n=skip 확정 / 골든 테스트 확대 / Radii 수치 스케일 토큰화

## 기능 백로그 (2026-06-10 브레인스톰 — 우선순위 미정, 착수 전 상의)

### 신규 기능
- 라이브: 실시간 승리확률 그래프(ML 재사용)·현재타석 matchup 통산기록(game_pitches로 계산)·결정적순간 푸시(확률 급변 ±20%p)·불펜 피로도 보드(game_pitchers 최근 등판일/투구수)·우천취소 확률(weather 재사용)
- 기록: 마일스톤 트래커 화면(알림 백엔드 보유)·신인왕/MVP 레이스(WAR)·순위변동 타임라인·오늘의 MVP(종료 시 자동선정)·매직넘버(PS odds 재사용)·선수 스플릿(홈원정/주야/vs팀)·팀 H2H 매트릭스
- 참여: 승부예측 포인트/랭킹(game_predictions 보유 — 리텐션 1순위)·데일리픽·직관뱃지(전구장 정복 등 visit_record)·이상형월드컵·선수카드/직관기록 공유이미지(RepaintBoundary+share_plus)·경기별 응원톡(모더레이션 비용 고려)
- 유틸: 선수 팔로우 알림(선발등판/타순 포함 — favorite_players 보유)·아침 브리핑 푸시(어제결과+오늘 선발 1통)·중계채널 안내(정적 매핑)·티켓오픈 알림·ICS 캘린더 내보내기

### UI/UX 개선 (✅=2026-06-11 완료: 햅틱(탭/투표/새로고침)·이닝칩 자동스크롤·댓글 이탈경고 / 펄스dot·히트맵범례 = 기구현 확인)
- 전역: Hero 전환(목록 아바타→상세)·오프라인 배너(connectivity+SWR 표시)·빈상태 공용 AppEmptyView(AppErrorView 패턴)·당겨새로고침 통일·긴 리스트 위로가기 FAB·스낵바 톤 통일·하단바 스와이프 힌트(1회 flag)
- 홈: 경기없는날 마이팀 다음경기 D-day 카드·날짜스트립 길게누르기 픽커(_pickerBuilder 필수)·compact 토글 첫실행 툴팁
- 경기상세: 새 중계 항목 amber 페이드인·필드뷰 풀스크린 오버레이(작은폰 비좁음)
- 선수: 초성검색(ㄱㄷㅇ→김도영)·목록 길게누르기 2명 비교선택·투표 결과 바 애니메이션
- 캘린더/커뮤: 직관기록 다중사진(image_urls 인프라 재사용)·이미지 핀치줌 갤러리 뷰어·달력 월 스와이프

### 운영/출시 인프라
- ⭐강제 업데이트 게이트(`/app-config` min_version — **출시 전 필수**, 나중엔 못 넣음)·킬스위치(Firebase Remote Config 기능별 off)·공지배너(app-config에 banner 필드)
- admin 콘솔 웹(insta/게시글 신고·맛집 승인 — 현재 psql 수동, X-Admin-Key 재사용)·배포후 스모크 curl 스크립트(scheduler 미재시작류 사고 감지)
- 알림: quiet hours(22~08 보류 — 심야 푸시=삭제 1순위)·Android 채널 분리(라이브/마이팀/커뮤 — OS 선택 차단 가능)
- 성장: 딥링크(게시글/경기/선수 공유→앱)·인앱리뷰(직관 '승리' 기록 직후)·Play 내부테스트 트랙(push_tokens 다수 검증 겸용)
- 품질: 외국인 한글↔영문 이름매핑 테이블(인스타 검증도 필요)·pitch_locations 시즌 아카이빙 계획(106k+/시즌)·GitHub Actions CI(analyze+골든)·앱 백그라운드 시 폴링 중단 확인(배터리/서버)

### 팬 세그먼트별 (올드팬=기록 깊이 / 라이트팬=쉬움·재미. 현재 앱=올드팬 강·라이트팬 funnel 약)
- 올드팬 분석계(보유 데이터로 즉시 가능): 볼배합 시퀀스 분석(game_pitches 구종순서·초구 성향)·**과거경기 필드뷰 리플레이(game_relay_archive JSONB 보유 — 타앱 없는 유니크 자산)**·보더라인 판정 분석(ABS존 px)·클러치 WPA/LI 리더보드(승률모델 재사용)·파크팩터(구장별 타고/투고 보정)·페이스 프로젝션(시즌 환산+마일스톤 ETA)·좌우 스플릿 수치 테이블(존히트맵 데이터 표화)·박스스코어 기록지 뷰(전통 스코어카드+이미지 저장)·등록말소/부상 타임라인(roster_changes 보유)·PS 확률 분포 그래프(odds 확장)·**타석 안타확률 모델(per-PA, 아래 별도)**
- 올드팬 확장계(크롤/콘텐츠 추가 필요): 통산 커리어 합산 뷰·2군 기록/콜업 워치(퓨처스 크롤)·연봉 대비 WAR 가성비(연봉 공시 크롤)·KBO 오늘의 역사(정적 JSON)·역대 기록실·조건 알림 빌더("X가 OPS 1.0 도달 시" — 마일스톤 인프라 연장)·기록 CSV 내보내기·커스텀 스탯 대시보드 확장(핵심스탯 피커 연장)·라인업 시뮬레이터(타순 기대득점)
- 라이트팬 진입장벽: 응원팀 찾기 테스트(온보딩 취향 퀴즈→팀 추천, 결과 공유=바이럴)·쉬운 스탯 모드(OPS→S~C 등급, 리그 백분위)·**"지금 무슨 상황?" 라이브 캡션(relay→"2사 만루, 한 방이면 역전" 자연어 한줄)**·야구 입문 코스(기존 ⓘ 용어 모아 단계별)·룰 일러스트 사전(인필드플라이 등)·첫 직관 가이드(체크리스트+구장별)·용어 팝업 퀴즈
- 라이트팬 재미/콘텐츠: 경기 3줄 요약(game_summary 자연어 강화)·하이라이트 몰아보기 피드·"오늘의 한 장"(종료 시 사진1+한줄 자동)·최애 포토카드 꾸미기(프로필+스탯 커스텀→공유)·선수 생일/데뷔 기념일 알림·응원가 가사 링크집(저작권→링크만)·야구퀴즈/밸런스게임·시즌 연말결산 카드(Wrapped式 — 직관/예측/투표 데이터)·다이제스트 모드(푸시 대신 하루 1통 요약)
- 소셜/게이미피케이션(공통): 팬 레벨(출석+예측+커뮤니티+직관 포인트 통합)·1:1 예측 대결(친구 초대)·오늘의 승리 MVP 팬투표(인기투표 인프라 재사용)·주간 미션(시즌패스式 무료)·출석 스탬프
- 모드 컨셉: 온보딩 "야구 얼마나 보세요?" → 프로/캐주얼 모드(스탯 밀도·푸시 빈도·홈 구성 프리셋 — compact 토글·커스텀 피커가 씨앗)
### 추가 영역 (2차 브레인스톰)
- ML 확장(모델/데이터 보유): 투수 교체 타이밍 예측(불펜 패턴)·경기 소요시간 예측(직관러 귀가용)·익일 선발라인업 예측·선수 시즌 최종성적 프로젝션 밴드·LLM 자동 경기 프리뷰/리뷰 기사(Claude API — 매일 5경기, 비용 소액)·기록 질문 챗봇(RAG over own DB — 차별화 크나 API 비용 검토)
- 커뮤니티 심화: 경기별 라이브 스레드 자동 개설/종료시 아카이브·투표(poll) 첨부 게시글·직관샷/팬아트 갤러리 탭(이미지 그리드 뷰)·월간 베스트글 명예의전당. ⚠️지역 직관모임 매칭=모더레이션/안전 부담 커서 비추
- **오프시즌 모드(비시즌 DAU 방어 — 야구앱 최대 갭)**: 스토브리그 FA 트래커·연말결산 카드·명장면 리플레이 큐레이션·올타임 팀 뽑기·퀴즈 시즌제·개막 D-day
- 시즌 이벤트: 포스트시즌 브라켓 예측(10월 참여 폭발)·골든글러브/올스타 예측 이벤트
- 수익화(출시 후): AdMob 네이티브(게임카드 사이 1개 수준)·프리미엄 구독(광고제거+심화 분석+위젯 커스텀)·티켓/굿즈 어필리에이트
- 플랫폼: Flutter web 커뮤니티(SEO 유입)·태블릿 2컬럼 레이아웃. TV/WearOS=비추(니치)
- 접근성: 스크린리더 시맨틱·색각보조(팀컬러에 패턴/라벨 병기)·시니어 모드(큰글씨+단순화 — 고령 올드팬 실수요)
- 신뢰: 기록 갱신시각 표시("5초 전")·오류신고 일반화(인스타 신고 패턴→전 기록)·데이터 출처 고지 페이지·오픈소스 라이선스 화면
- **타석 안타확률(per-PA) 모델**: 라벨=game_pitches 타석결과(1루타/2루타/3루타/홈런/내야안타 — '안타' 단독표기 없음 규칙 재사용), ~5.5만 타석/시즌. 피처=타자 시즌누적(시점까지만 — leakage 금지, player_daily_stats rolling)+최근폼+플래툰(bats×throws)+투수 피성적+**존 겹침점수(타자 핫존5x5 × 투수 투구분포5x5 내적 — 양쪽 보유, 차별화 피처)**+매치업 통산(표본少→empirical Bayes shrinkage)+구장 파크팩터+홈원정. 모델=LR/GBM+기존 calibration 모듈, 시간순 split(승리예측 관행). 기대성능 정직하게: base ~27%, AUC ~0.58-0.62(야구 per-PA 본질 한계) — 절대값보다 "오늘 매치업 21% vs 33%" 상대 비교 가치. 확장=멀티클래스(아웃/볼넷/단타/장타)→xwOBA식 기대치, 볼카운트 반영 실시간 업데이트(pitch별 재계산). 서빙=relay 응답에 batter 확률 필드 or /games/{id}/pa-prob @10s

### 시너지 번들 (2026-06-10 — 같이 만들면 배수 효과. ⭐=신규 발굴 항목)
1. **라이브 승률 엔진** = ⭐**win_prob 시계열 적재**(scheduler 30s 사이클서 이닝/타석별 승률 재계산→테이블 저장 — 신규) 하나로 4기능: 승리확률 그래프(시계열 그대로)+결정적순간 푸시(델타±20%p 감지)+클러치 WPA 리더보드(타석 전후 차 적분)+오늘의 MVP(경기 WPA 합산). **엔진 1 : 기능 4**
2. **게이미피케이션 공통 기반** = ⭐**통합 포인트 원장+뱃지 엔진**(point_ledger+badges+user_badges, 적립사유 UNIQUE dedup=notification_log 패턴 — 신규) 위에: 승부예측 랭킹·데일리픽·출석스탬프·직관뱃지·주간미션·팬레벨 6개가 전부 얹힘. 원장 없이 개별 구현하면 나중에 통합 지옥
3. **per-PA 모델 1 : 기능 3**: 타석 안타확률 모델 → matchup 확률 표시(필드뷰)+데일리픽 후보 제공+쉬운스탯 기대등급. 번들2 원장이 데일리픽 정산 받쳐줌
4. **app-config 묶음**: `/app-config` 엔드포인트 하나에 min_version(강제업데이트)+feature_flags(킬스위치)+banner(공지) 3기능 — 1세션, 출시 전 필수
5. **홈 성능 3종 동시**: /home/bootstrap 집계 만들 때 ETag/304+서버측 SWR 같은 코드경로에 함께 — 따로 하면 3번 손대는 곳을 1번에
6. **공유 성장 루프**: 공유이미지(포토카드/직관기록)+딥링크+인앱리뷰+⭐**공유 랜딩 페이지**(서버 정적 HTML og:image 프리뷰 — 미설치자 유입용, 신규) = 생성→공유→유입→리뷰 루프 완성
7. **온보딩 리뉴얼 1플로우**: 응원팀 찾기 테스트→프로/캐주얼 모드 선택→푸시 프리셋 — 첫실행 한 플로우로 묶어야 자연스러움
8. **불펜 데이터 계보**: 불펜 피로도 보드(집계)→투수교체 예측·익일 선발라인업 예측(같은 피처 재사용) — 보드 먼저
9. **콘텐츠 발송 파이프**: 아침 브리핑+3줄 요약+다이제스트 모드 = scheduler 일일 batch 1개(템플릿 기반, LLM은 추후 업그레이드만)
10. **admin 콘솔 = 신고 통합**: ⭐**통합 신고 큐**(insta/게시글/기록오류 reports 일반화 테이블 — 신규)+맛집 승인 한 화면. 오류신고 일반화 항목과 동시 설계
11. **직관러 니치 패키지** (사업성 전략① 정렬): 직관뱃지+직관통계 심화+우천취소 확률+경기 소요시간 예측+첫직관 가이드+티켓오픈 알림+기존 구장/맛집 — 묶어서 "직관 탭" 강화로 출시 차별점
12. **품질 3종 순서**: 다크모드 육안검증→발견 화면 골든 추가→GitHub Actions CI — 검증이 골든 소재 공급, CI가 회귀 방어

### 로드맵 최종 (2026-06-10 — 번들 단위 즉시/중기/장기 + 4트랙 수렴)
**4트랙 수렴**: 전 백로그가 ①라이브 임팩트(경기 보는 맛) ②리텐션 루프(돌아올 이유) ③성장 루프(퍼지는 경로) ④출시·운영 게이트(안 죽는 기반)로 정리됨
- **즉시(1세션 단위)**: 보안5종 일괄(EXIF·pg listen·rpcbind·백업pull·이메일5회) / 번들4 app-config(강제업뎃+킬스위치+배너) / 즉효성능 3종(orjson·uvicorn[std]·TLS1.3) / 다크모드 육안검증(번들12 1단계) / 아침 브리핑 템플릿판(번들9 시작) / UI소품 묶음(햅틱·펄스dot·자동포커스·범례ⓘ·이탈경고 등)
- **중기(3~4세션 단위)**: ⭐메가A 라이브 임팩트 / ⭐메가B 리텐션 루프 / 메가C 성장 루프 / 메가D 출시 게이트 / 번들5 홈성능3종 / 번들10 admin+신고큐 / 번들11 직관러 패키지 / 잔여 분석 단품(마일스톤트래커·순위타임라인·스플릿·H2H·파크팩터·박스스코어)
- **장기(그 이상/유료/외부)**: 외부작업(도메인·Play·법무·KBO라이선스) / 리플레이·홈위젯·iOS·web·오프시즌모드·브라켓예측 / 크롤신규(2군·연봉·역사) / LLM(자동기사·챗봇)·수익화 / 접근성 확장·state restoration

**2차 메가번들 (번들의 번들 — ⭐=신규 부품)**
- **메가A 라이브 임팩트** = 번들1(승률엔진→4기능)+번들3(per-PA→3기능)+번들8 1단계(불펜피로도). 공통 토대 = ⭐**PA(타석) 정규화 모듈**(game_pitches 타석경계·안타라벨 파싱 공통화 — per-PA 라벨·WPA 적분·matchup 집계 셋 다 이걸 씀, 신규). 순서: PA모듈→승률엔진→per-PA→피로도
- **메가B 리텐션 루프** = 번들2(원장+6기능)+번들7(온보딩 모드)+quiet hours+채널분리+다이제스트. 공통 토대 = ⭐**푸시 발송 게이트웨이 단일화**(발송부 한 곳: quiet hours·채널 라우팅·다이제스트 적립·dedup 일괄 — 흩어진 채로 quiet hours 넣으면 곳곳 수정, 신규). 유저 라이프사이클 1축 관리
- **메가C 성장 루프** = 번들6(공유+랜딩+딥링크+리뷰)+번들11 교차(직관기록 카드=공유 1순위 소재) — 직관 탭 강화가 곧 공유 소재 공장
- **메가D 출시 게이트** = 번들4(app-config)+스모크 스크립트+번들12(골든+CI)+Play 내부테스트 — 배포 안전망 일괄, 출시 직전 1묶음
- **연결 명시**: 번들1 산출(오늘의 MVP·WPA)이 번들9 콘텐츠(브리핑/3줄요약) 소재로 흐름 — 승률엔진 먼저면 브리핑 품질 공짜 상승 / 검색 패키지(초성+최근검색+외국인 이름매핑) 소묶음 추가

**3차: 플랫폼 코어 발견 (트랙 횡단 공통층)**
- 코어 4 = PA모듈(데이터)·포인트원장(상태)·푸시GW(전달)·app-config(제어) + ⭐**game_events 도메인 이벤트 스트림**(신규 — scheduler가 감지하는 모든 사건(득점/교체/마일스톤/승률델타)을 이벤트 테이블로 발행, 푸시GW·원장적립·브리핑·WPA가 같은 스트림 구독). **이벤트 스트림 = 과거경기 리플레이의 토대이기도** (relay_archive+events 재생) → **리플레이 장기→중기 강등(쉬워짐)**
- 트랙 의존: A(콘텐츠 생산)→B(소비·정산)→C(공유·확산), D 횡단. A 먼저가 정석

**4차: 시즌 캘린더 시간축 매핑**
- 6~7월 즉시묶음+메가D+**출시**(10월 모멘텀 타려면 여름 출시 필수) → 7~8월 메가A(시즌 중 가치 최대) → 8~9월 메가B·C → **10월 브라켓 예측 이벤트**(원장 위 1세션급 — 장기→중기 강등)+마케팅 → 11~3월 오프시즌모드(연말결산=원장·직관 데이터 소비)+리플레이+크롤신규(2군/연봉)
- ⭐**시즌 상태머신**(신규 — 서버/앱이 개막전·정규·PS·비시즌 단계 인지, 홈 구성·푸시·기능 자동 전환. app-config feature_flags 확장으로 구현, 오프시즌 모드의 토대)

**5차: 차단기(blocker) 역방향 분석 — 트랙별 선행 게이트**
- 메가B 전 **push_tokens 다수 검증**(내부테스트 트랙과 동시) / 커뮤니티 심화 전 **admin콘솔+신고큐** / 수익화 전 **KBO 라이선스** / 모든 신규 UI 전 **다크 육안검증** / 킬스위치 = 데이터 종속 리스크 완충재(네이버 차단 시 라이브만 끄고 생존 — app-config 출시 전 필수 근거)
- ⭐**합성 부하테스트**(신규 — k6/locust 가상유저 100~1000으로 bootstrap+폴링 부하 1회 실측, free tier 한계 수치화 = 서버비용 리스크 실측. 출시 전 1세션)

### 사업성 메모 (2026-06-10 평가)
- 순풍: KBO 1000만 관중 시대(2030·여성 신규팬 급증)+티빙 모바일 중계 유료화 → **무료 텍스트/시각화 라이브 수요 공백** = 필드뷰가 정조준. 경쟁(네이버=범용 문자중계, KBO공식앱=품질낮음, 팀앱=단일팀)에 비해 분석깊이+직관기록+커뮤니티 통합이 차별점
- ⭐최대 리스크 = **데이터 종속**: 네이버 비공식 API+statiz 크롤 — 상업화 시 약관/저작권 노출 급증, 차단=서비스 사망. **수익화 마케팅 전 KBO 데이터 제휴/라이선스 검토 필수** (법무 잔여항목과 연결). 하이라이트=링크만(영상 호스팅 금지) 유지
- 기타 리스크: 1인 운영(모더레이션/CS)·서버비용(현 무료티어, 캐시로 버팀)·비시즌 DAU 폭락(오프시즌 모드로 방어)
- 수익 현실치: DAU 1만 가정 — 네이티브광고 월 ~100-200만원, 구독(전환 1-3%) 월 ~50-100만원. 1년차 현실 목표 MAU 1~5만 = 사이드수익 구간. 단독 스타트업 스케일은 데이터 라이선스 해결+니치 장악 후 판단
- 전략: ①니치 1개 집중(직관러 도구 or 라이브 필드뷰) ②무료+가벼운 광고로 시작 ③데이터 리스크 해결 전 공격적 마케팅 자제 ④포스트시즌(10월) 모멘텀 활용

## 알려진 이슈
- push_tokens 사용자 1명 — 다수 유저 알림 시나리오 미검증
- 라이브 pitch-locations cold 첫 호출 ~2초 (Naver fetch 의존)
- scheduler 30초 사이클 — 연속 이벤트 1개 알림 통합 (의도된 dedup)
- 타자 존 타율 = 인플레이 기준 (삼진 제외 → 시즌 타율보다 소폭 높음, BABIP 성격)
- 동일 이닝 타순 일순 시 존 타율 매칭 근사 (발생순 zip — 오차 미미)
