# PlayBall

KBO 야구 앱 | Flutter + FastAPI + PostgreSQL

## 인프라
- 서버: Oracle Cloud **A1.Flex (ARM aarch64, 4 OCPU/24GB)** Ubuntu 22.04 | 168.107.36.158:8000 (내부), HTTPS: playball.duckdns.org (2026-06-11 마이그레이션 — duckdns 자동갱신 cron 서버 등록)
- 구 x86 박스 168.107.61.147 = **DNS 릴레이 중** (nginx가 신 서버로 전체 프록시 — 폰/통신사 DNS 캐시가 구 IP 물고 502나던 사고 해결. 원본 conf 백업 = 구박스 /tmp/playball.nginx.pre-relay.bak). API/scheduler disabled, DB = 컷오버 스냅샷. **종료는 DNS 캐시 정리 후(1주+) — 끄면 캐시 잔존 유저 전원 접속 불가**
  - ⚠️ **06-12 502 사고 2건 (해결·스모크 감시 추가)**: ① **duckdns cron 핑퐁** — 구박스 root crontab(`/opt/duckdns/update.sh`)이 5분마다 DNS를 구 IP로 되돌림 → 전 트래픽 릴레이 경유 (제거 완료. user crontab만 보면 못 찾음 — **root crontab 확인**) ② **fail2ban 단일 IP 오인 밴** — 전 유저+봇스캔이 릴레이 한 IP로 와서 nginx-botsearch가 구박스 밴 → 릴레이 502. 해결 = `/etc/fail2ban/jail.local` `ignoreip = 127.0.0.1/8 ::1 168.107.61.147` (구박스 종료 시 ignoreip서 제거). 스모크 6·7항이 둘 다 감시
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
bash ~/playball/scripts/smoke.sh   # 배포 후 스모크 (ALL PASS 확인 — scheduler 미재시작/미pull 감지)
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
POST /games/{id}/predict [Bearer] {pick:home|away} — 팬 승부예측 (예정/라인업만, upsert) | GET /games/{id}/fan-predictions — 분포+my_pick (비캐시)
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
POST /user/points/attendance (KST 일1회 +5) | GET /user/points (total+rank+내역20) | GET /user/points/leaderboard TOP50 (공개, 수동캐시 300s)
GET /user/badges (lazy 평가 — 호출 시 신규 획득) | GET /user/missions (주간 진척+자동 보상) | GET /s/p/{id}·/s/g/{id} 공유 랜딩(HTML og)
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
- 양현종·이태양 = **실존 동명이인 확정**(2026-06-12 조사 — 오배정 아님): 양현종 KIA투수#343/키움 내야수#91, 이태양 KIA투수#325/키움 투수#8336 — naver_id 상이·양쪽 실데이터. ⚠️ 잔여 리스크 = **이름 조인**(plate_appearances·존히트맵)서 이태양 투수 2명 데이터 혼합(WPA는 HAVING count=1 스킵 가드 有). 근본해결 = PA에 naver_id 컬럼(보류)

### games
`id, naver_game_id, game_date, status(예정/진행/종료/취소), home/away_team_id, stadium_id, 스코어/이닝/안타/실책, start_time`

### game_* 테이블
- game_innings / game_pitches(seqno, type, title — 투구+이벤트) / game_pitchers(result=승/패/세이브/홀드) / game_batters / game_rosters(roster_type, batting_order, position, pitching_style, is_starter) / game_highlights / game_relay_archive(payload JSONB) / game_predictions(user_id·game_id FK CASCADE, pick CHECK home|away, UNIQUE(user,game) — 팬 승부예측, 메가B)
- **point_ledger** (메가B 2026-06-12): user_id FK CASCADE, points, reason, ref_key, UNIQUE(user_id,reason,ref_key)=멱등 dedup. 적립 = `api/points.py award()` 경유만 (적중50/참여·무승부10/출석5/직관20). 정산 = scheduler 종료 후처리 (ref `pred:{gid}`). 잔여 메가B: 뱃지·주간미션·푸시GW·quiet hours·온보딩 모드
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
- 종료 감지: 팀순위 + 출전 선수 KBO 크롤 + game_summary(result 채워진 후 발송) + 마일스톤 + **전 이닝 1회 풀 재크롤**(`save_game_pitches` 1..max_inn)
  - ⚠️ **06-18 truncation 사고+수정**: 라이브 중 중간 이닝이 **타석 진행 시점(투구 스트리밍·투수판 이탈/일시정지)**에 부분 저장된 뒤 경기가 2이닝+ 진행하면, 종료 후처리가 `max_inn`/`max_inn-1`만 재크롤해 그 이닝이 영원히 미완성으로 stale(474 NC 서호철 4회말=2구만, Naver엔 3구+결과). 진단: 종료경기서 (game,inning)별 max-seqno 행 type∈(1,7) + 마지막 type-8 이후 결과(13/23)·주자아웃(14/24) 둘 다 없음 = 진짜 truncation. 스캔 결과 **2026 라이브 115이닝/29경기**(2021~25는 백필=아카이브 완전크롤/과거 풀재크롤로 ≈0). 수정 = 종료 시 **전 이닝 풀 재크롤**(종료당 1회) + 영향 30경기 일괄 수복.
  - ⚠️ **06-18b seqno offset 중복 사고+수정 (위 truncation heal이 노출/악화)**: `save_game_pitches`가 `seqno=opt['seqno']`(Naver 부여, **크롤마다 불안정** — 투수판 이탈/마운드 방문/투수교체/피치클락 등 사후삽입 이벤트가 뒤 seqno 시프트)를 ON CONFLICT 키 `(game_id,inning,inning_half,seqno,type)`에 포함 → 시프트된 동일 이벤트가 **새 행 INSERT, 옛 행 잔존**. 라이브 smart_update 30s 재크롤×이벤트多 이닝 → **이닝 통째 +offset 중복 누적**(325 6회=이탈4·방문2·교체2 → 전 타석 2벌). relay 읽기 `ORDER BY seqno` dedup 없음 → 중복+순서꼬임 노출. 규모 = **2026 라이브 63경기/661 결과중복**(백필 2021~23=이닝당 1회라 누적無 클린, 잔여 3~13/시즌=legit bat-around=타순일순 동일타자 2타석, seqno 멀어 무해). 수정 = **`save_game_pitches` 이닝 단위 replace**(DELETE (game,inning)→fresh INSERT, Naver relay 누적발행이라 안전) + **win_rate(결과행만 보유) DELETE 전 보존→NULL일 때만 재병합**. 정리 = 2026 flagged 63경기 재크롤(661→11=baseline). ⚠️종료 풀재크롤·backfill_*도 replace 경유라 idempotent 클린.
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
- ✅중간 3종 (2026-06-13 적용): **ETag/304**(`_ETagMiddleware` GET 200 바디 md5 + 클라 dio 인터셉터 If-None-Match/304→보관바디 — GZip보다 안쪽 add라 원본 기준 해시)·**서버 SWR**(`@cached(ttl, swr=True)` 기본 — 만료 시 stale 즉시 반환+백그라운드 스레드 갱신, stale 보관 = ttl×10, `_refreshing` 셋으로 갱신 dedup)·~~프로필 썸네일~~(미착수 잔여)
- ✅**`/home/bootstrap`** (2026-06-13): today+rankings(full)+이번달 calendar+app-config 1콜 (`api/routers/bootstrap.py` @cached(20), 조각별 try라 부분 실패 허용). 클라 = `_loadGames` isToday서 bootstrap 우선→실패 시 /games/today 폴백, `_applyBootstrapExtras`가 순위/캘린더/설정 주입(+`_skipNextRankingsFetch`로 개별 fetch 생략, initState서 `_loadGames().then(_loadRankings)` 체이닝 = race 방지). 잔여: compute() isolate 파싱·홈 위계 로딩·프로필 썸네일
- 장기: Cloudflare CDN(이미지 edge 캐시 — 도메인 계획과 묶음)·dio+http2_adapter(h2 멀티플렉싱 — bootstrap 도입 시 가치 하락하니 후순위)·uvicorn --workers(인메모리 캐시 워커별 중복 → Naver fetch 배수 트레이드오프, 부하 생기면 검토)

## 주의사항
- ⚠️ **DB 커넥션 누수 — 3중 방어 완비(06-25), 신규코드는 그래도 try/finally 권장**: `conn=get_connection(); cur.execute(...); conn.close()`에서 execute/fetch가 던지면 close 스킵 → 영구 leak(idle in tx, 락 보유)였음. 06-25 사고=컬럼 오타로 매일 에러나던 일배치가 일 1개씩 누수 → `games` 락으로 마이그레이션 차단. **방어 3층**: ① `_PooledConn.__del__`이 스코프 이탈 시 close() 자동 호출(CPython refcount, **322개 사용처 전역 retrofit** — 명시 close 누락해도 자동 회수) ② `close()`가 putconn 전 rollback(tx 정리) ③ DB `idle_in_transaction_session_timeout=5min`(auto.conf, **재구축 시 재적용**). 누수는 이제 자동 회수되나 **신규 코드는 try/finally로 즉시 반납이 정석**(루프 내 다량 획득 시 특히). 핫테이블 ALTER 전 `pg_stat_activity` idle-in-tx 점검
- **baseUrl HTTPS 고정** / git push --force / 커밋·배포·로그·APK는 묻지 않고 실행
- **배포 시 playball + playball-scheduler 둘 다 재시작**
- **한글 파일 PowerShell -replace/Add-Content/Set-Content 전부 금지** (인코딩 깨짐 → crash loop). Edit/Write 도구만. 06-12 사고: api_service.dart·games.py 전체 mojibake → HEAD 복원+Edit 재적용으로 복구. 의심 시 `git diff`에 무관 한글줄 대량 변경 = 오염 신호
- **ARM(A1) selenium = snap chromium — 반드시 `crawler/driver_util.arm_or_wdm_chrome` 경유** (직접 webdriver.Chrome 생성 금지 — 신규 크롤러 포함). 규칙: ① binary_location 지정 금지(즉사) ② 프로필 = `~/snap/chromium/common/` 하위 **mkdtemp 인스턴스별 고유**(PID 기반이면 PID 재활용 × 크래시 잔존 SingletonLock → "Chrome instance exited" 간헐 즉사 — 1h 잔존물 자동청소 내장) ③ webdriver_manager는 ARM chromedriver 미제공 ④ scheduler 유닛 MemoryMax=2G(chromium 자식 — 512M이면 OOM 위험, drop-in memory.conf) ⑤ 진단 = env `SELENIUM_DRIVER_LOG=경로`로 verbose 채집
- PS5.1: here-string 안 큰따옴표 → git -m 인자 깨짐 (**커밋 메시지에 `"` 절대 금지** — pathspec 에러로 커밋 자체 실패, 2회 사고) / Invoke-RestMethod 한글 mojibake(수동 UTF-8 디코드) / `$h`·`$H` 대소문자 동일 변수
- **웹 이미지 3대 규칙 (06-11~12 크래시·미표시 전쟁 최종결론 — 변경 금지)**: ① **CanvasKit-only** — `webHtmlElementStrategy.prefer`(<img> 플랫폼뷰) 절대 금지 (iOS Safari 26 탭/standalone 불문 "문제 반복 발생" 크래시, A/B 5회) ② **네트워크 이미지 = `web_image.dart`의 `_FetchImage`(fetch 바이트→`createImageBitmap`→`ui_web.createImageFromImageBitmap` 주입) 필수** — Safari 26은 `<img>` 네트워크 로더가 200 응답에도 error 이벤트를 내고(WebKit 버그), 엔진 바이트 디코더도 내부 blob+img라 동일 실패. 실기기 단계별 진단(`/static/imgtest.html` — 보존됨)으로 PASS 조각만 조립한 파이프라인. OneFrame이라 GIF 애니는 미지원(업로드는 jpg/png만이라 무관) ③ **netImageProvider/CircleAvatar.backgroundImage/DecorationImage를 웹 도달 위젯에 신규 사용 금지** → netCircleAvatar/netImage 사용. 부가: standalone PWA 비활성(홈 아이콘=Safari로 열림), index.html에 ImageDecoder 숨김+detached decode 심 = 방어층으로 유지, **back-trap pushState는 `history.state` 보존 재푸시**(null이면 엔진 serialCount 깨짐), 캐시 오염 시 처방=`webSafeImageUrl` `_cb` 범프. ⚠️ **웹 조건 import = `dart.library.js_interop`만** — `dart.library.html`은 wasm(dart2wasm)서 false라 **스텁이 로드돼 기능 무음 사망** (06-12 발견: back-trap/theme-color/reload 전부 wasm 본판서 죽어 있었음 — 뒤로가기=앱종료·작업표시줄 색 미적용 원인). 웹 전용 코드 신규 작성 = dart:js_interop @JS 바인딩 (web_back_web.dart 패턴). ⚠️**js_interop 함정 2**: `@JS('window.history.pushState')` 직접 함수 바인딩 = JS this 깨져 Illegal invocation **무음 실패** — 반드시 extension type 멤버 호출. ⚠️**OS 뒤로가기**: Navigator 1.0이라 엔진이 브라우저 히스토리 안 쌓음 → didPopRoute 호출 기회 없음 — **JS 트랩(installWebBackHandler)이 유일 경로**, 제거 금지. **iOS 사파리 탭 사용자 = 주 배포 경로**: env(safe-area-inset-bottom)=0이라 하단 고정 UI가 사파리 탭바에 깔림 → `web_safe_area.dart webBottomGuard(context)`(iOS웹+env0=+20) 하단 고정 위젯에 필수. 필드뷰 = 화면 50% 캡 목표기반 축소(_fieldShrink)
- ABS 존 상수 plateHalfW=8.5/12, absHalfW=9.95/12, ballR=1.45/12 — 변경 금지
- TeamLogo 파라미터 `teamCode` / TeamDetailScreen `team`(Map) / NetworkImage 금지 → CachedNetworkImage
- ~~share_plus 10 고정~~ → **06-12 firebase 메이저 업** (core ^4.10/messaging ^16.3/crashlytics ^5.2 — 구버전이 Xcode 16 non-modular header 비호환으로 iOS 빌드 불가): share_plus ^12 동반, image_cropper 제거(미사용+web 충돌). 메이저 업 후 안드 빌드 깨지면 **flutter clean 먼저**(stale 캐시가 Unresolved reference 둔갑) / 소셜 로그인 안 함(결정) / 동명이인 team_id 기준
- 과거경기 수정 game_date < '2026-05-09' 조건 / 삼성 홈 stadium_id=7 보정 SQL
- 서버 pull 전 충돌 파일 rm (insta CSV 등 untracked 주의) / firebase-service-account.json push 금지
- **서버 git 인증 = PAT-in-URL(현재) / 보안강화 = SSH deploy key 권장**: 현재 remote = `https://<PAT>@github.com/...`(토큰 평문 `.git/config`). 최강 = **SSH deploy key** — `ssh-keygen -t ed25519 -f ~/.ssh/playball_deploy -N ''` → 공개키를 GitHub 레포 Settings→Deploy keys 등록(read-only 체크 가능) → `git remote set-url origin git@github.com:Aa26178787/playball.git`. 토큰 자체 제거·레포단위 폐기·노출0. 중간책 = env+credential helper(토큰 `.git/config`서 빼나 같은 유저면 `/proc/PID/environ`로 여전히 읽힘 = 어중간). PAT 만료/노출 시 GitHub서 회전 → 서버 `git remote set-url` 재실행 1회. (⚠️07-17 구토큰 `ghp_T5Gpq..` 만료 → 새 PAT로 재인증·`reset --hard origin/main` reconcile 완료, 현재 정상 pull)
- PgBouncer 6432 유지 / 커뮤니티 조회수 _view_cache 재시작 초기화(의도)
- **nginx 배포 = `/etc/nginx/sites-enabled/playball`이 symlink 아닌 독립 실파일** (repo `nginx_playball.conf` → sites-available **아니라** sites-enabled로 cp해야 적용). ⚠️ 백업파일은 절대 sites-enabled 안에 두지 말 것(nginx가 `sites-enabled/*` 전부 로드 → `limit_req_zone` 중복 `emerg`). 백업은 /tmp. 적용 = cp→`nginx -t`→`systemctl reload nginx` (reload graceful이라 직후 수초 old/new worker 혼재 정상)
- ⚠️⚠️ **repo nginx_playball.conf가 프로덕션 직접튜닝보다 뒤처질 수 있음** — 06-09 사고: CSP 배포가 sites-enabled를 repo로 덮으며 **API rate limit 300r/m→30r/m·burst 100→20 revert → 앱 홈 버스트(1초 20+요청) 전부 503 = 전 데이터 로딩 실패**. **cp 배포 전 반드시 `sudo diff /etc/nginx/sites-enabled/playball ~/playball/nginx_playball.conf`**. 현 튜닝 = api **300r/m+burst100** / auth 10r/m+burst5 (repo 동기화 완료). 진단법: nginx error.log `limiting requests, excess` + access.log `Dart/3.11`+503
- **DB 비번 회전 = 3곳 동기화**: ① `ALTER USER playball_user PASSWORD` ② `/etc/pgbouncer/pgbouncer.ini` `[databases]` 줄 `password=`(auth_type=trust라 pgbouncer→postgres 실자격증명 = 여기, userlist.txt 아님) ③ systemd `Environment=DB_PASSWORD`(2 drop-in: playball=email.conf, scheduler=env.conf). ② 빠뜨리면 "pgbouncer cannot connect to server". 순서: ALTER→ini 교체→pgbouncer restart→서비스 restart
- 새 알림 = notification_log dedup 패턴 필수
- **FCM 무-game_id 알림 = data에 엔티티ID로 collapse 분리 필수** (06-30 버그): `_send`의 collapse_key가 game_id 無면 bare 상수(`"roster_change"` 등) → Android `tag`+APNs `collapse-id` 동일 → 같은 타입 다발 알림(등말소·마일스톤·rank·streak·team_record)이 **트레이 한 슬롯에 합쳐져 최신이 이전 덮음**(발송·인앱함은 정상, 트레이만 드롭). `_collapse_key(ntype,game_id,data)`가 game_id 無면 data의 player_id/team_id로 분리 → **신규 무-game_id 알림 추가 시 data에 player_id/team_id 넣을 것**
- ⚠️ **`game_event_stream` 컬럼 = `event_type`** (`type` 아님). 06-18 사고: `_send_game_summary`가 `SELECT type FROM game_event_stream`로 매 종료마다 예외→return → **한줄평/MVP/game_summary push가 narrative 배포(06-15)~06-18 전부 죽음**(game_reviews 0행). 교훈 = ① dedup 마킹(`_mark_notified('game_end')`)을 **발송 성공 후**가 아닌 호출 전 하면 실패 시 영구 누락 ② 부가쿼리(event_flags 등)는 개별 try 격리 — 본체 발송 안 죽게. 수정+event_type+격리, 478 검증("삼성 끝내기, 구자욱")
- 테마 splashFactory = **NoSplash** + highlight/splash 투명 (탭 반짝임 전부 제거 — 06-08, 되돌리지 말 것). TabBarTheme overlayColor도 투명
- 프로필 크롭 = `PhotoCropScreen`(crop_your_image, Flutter 인앱). 네이티브 image_cropper(uCrop)는 Android15 edge-to-edge status bar 겹침으로 폐기 — 프로필엔 다시 쓰지 말 것. photo_manager 권한 = 기존 READ_MEDIA_IMAGES 재사용
- KT 팀컬러 = 0xFF3D424B 다크슬레이트 (원래 0xFF1A1A1A 검정 → 라이트모드 검은텍스트와 구분 안 됨). 팔레트 빨강(SSG/KIA/롯데)·네이비(NC/두산) 多 → 충돌 주의
- 팀상세/홈 메인탭 = PageView(`NeverScrollableScrollPhysics`)+`_KeepAlive` — 콘텐츠 가로 칩스크롤 hijack 방지 위해 PageView 스와이프 끔, 탭 전환은 `animateToPage`만
- **전역 글자크기 = OS 미반영 + 고정 0.85배** (06-25 1.0고정 → **06-27 0.85로 조정**): main.dart 텍스트 스케일 = `TextScaler.linear(0.85)` 고정(구 `MediaQuery.withNoTextScaling`=1.0, 더 구 `withClampedTextScaling 0.85~1.1`). OS '텍스트 크기' 설정 무영향(앱 지배 못 함). ⚠️**06-27 실측 진단으로 발견**: `withNoTextScaling`(1.0 강제)이 **폰 글자크기를 작게(0.8) 쓰는 유저**의 설정을 무시 → 앱 텍스트가 사용자 기대보다 ~25% 커 보임(진단 오버레이로 `osTS=0.8` 확인). → 1.0 대신 **0.85 고정**(OS 독립성 유지하되 축소). 앱 zoom 1.05(레이아웃+폰트 비례, **요소 크기**)는 별도 유지 → 텍스트는 요소 대비 0.85 비율. **크기 재조정 = 이 0.85 값만 변경**(웹·앱 동시 반영). ⚠️ 진단 시 "APK가 웹보다 큼" 신고 = 대개 **화면폭 차이**(웹을 넓은화면서 봄, w=549 vs 폰 w=411 → scale 둘 다 1.05 동일·버그 아님) + 위 텍스트 문제. ⚠️ a11y 큰글자 의도 포기(사용자 결정). picker clamp assert(`'maxScale > minScale'`)는 linear scaler도 min/max 없어 무관 — `_pickerBuilder` linear scaler 패턴 잔존(무해, 제거 불요). showDatePicker/showTimePicker는 builder로 scaler 명시 권장
- **버튼 색 하드코딩 금지** — `SemColor.panelDark(0xFF111113)==scaffoldDark` → 다크모드 윤곽소실. 글로벌 `elevatedButtonTheme`(isDark 반전) 상속(bg/fg override 제거). SnackBar/배지의 panelDark는 의도라 예외
- **rate limit/IP = X-Real-IP** — nginx 뒤 `request.client.host`는 항상 127.0.0.1(전역버킷 무력화) → `_client_ip()`. 8000은 127.0.0.1만 ACCEPT라 헤더 신뢰 가능
- **users 참조 FK = ON DELETE CASCADE(개인데이터)/SET NULL(공유데이터)** — NO ACTION이면 회원탈퇴 FK위반으로 깨짐 + 개인정보 잔존
- **시크릿은 env**(DB_PASSWORD/ADMIN_KEY/JWT_SECRET_KEY/EMAIL_*) — 코드 하드코딩 금지. `backend/.env.example` 참조
- **DB 백업/파이프 성공판정 = PIPESTATUS+산출물 크기** — `pg_dump|gzip`의 `$?`는 gzip 것 → 실패해도 20B 빈파일을 SUCCESS로 오기록 사고. cron: db_backup.sh(3AM)·watchdog.py(*/10)
- **admin 엔드포인트 = X-Admin-Key 헤더 + ADMIN_KEY env + log_admin_access** (URL pw 파라미터 금지)

## FCM (활성화 완료)
google-services.json(앱) / firebase_options.dart / firebase-service-account.json(서버) / firebase-admin 7.4.0 / push_tokens·user_settings notify 컬럼 — 전부 ✅. AndroidConfig high priority + channel playball_default.

## 변경 이력 (기능 상세 = git log · 재발방지 규칙 = 주의사항)
세션별 한 줄 요약. 사고 원인/교훈은 전부 ↑주의사항에 규칙화됨. 상세 브레인스톰/구프로젝트 로그 = `CLAUDE.md.diet-bak.*` 백업 참조.
- **~06-08**: 필드뷰 CustomPainter(ABS)·알림체계·이닝중계 개편·Option A 전면이식·인앱크롭·다중사진·피칭디자인/존히트맵·인스타 핸들
- **06-08b~10**: 출시준비(시크릿env·admin키·rate limit·FK CASCADE·유저차단·백업가드·Crashlytics) / 선수상세 개편(커스텀피커·비교말풍선·ⓘ용어) / 보안점검(EXIF·pg listen·인증제한)
- **06-11**: A1.Flex 이전 + 성능(orjson·uvicorn[std]) + app-config 풀스택 + 아침브리핑 + **메가A**(game_event_stream·plate_appearances·인게임 승률모델 AUC.85·승률그래프·클러치푸시·불펜피로도) + 3시즌화(PA type23 픽스·24/25 시즌스탯)
- **06-12**: **메가B**(point_ledger·예측·정산·리더보드·뱃지·미션·푸시GW quiet hours·온보딩모드) + **메가C**(공유카드·랜딩·인앱리뷰) + **메가D 코드측**(smoke.sh·CI·release APK) + 킬스위치(admin feature-flags)
- **06-13**: iOS 사파리 대응(웹 JS백트랩·전역스케일·webBottomGuard) + 성능3종(SWR·ETag/304·/home/bootstrap) + **관리자 콘솔 대확장**(로그인게이트·DAU·통계/설정/시스템 탭) + 502 사고2건(duckdns cron·fail2ban)
- **06-14**: game_start 미발송 진범=pregame이 user_notifications type='game_start' 기록→dedup 충돌(→'game_soon' 분리) / QS·starter 식별(pitching_order MIN) / 웹 다크이미지=color-scheme meta / 관리자 토글9종·maintenance
- **06-15~16**: **메가E**(내러티브·game_reviews) + **메가F**(points ON·예측결과푸시) + **메가G**(시즌phase·Wrapped) + 팀상세 대수술·디자인토큰 전면화(Typo/Pal/Radii/Space) + 데드코드·refresh_token bloat·로스터 자동화(2군·부상 diff)
- **06-17~19**: 역대데이터 프로젝트(↓완료섹션) + AI한줄평 LLM화 + 투구 truncation·seqno 중복 픽스(↑주의사항) + 역대 게임단위 백필(2010~23)
- **06-23~27**: 우천중단(games.suspended) + DB 커넥션 누수 근본수정(↑주의사항 3중방어) + "알림 죽음" 3분해(시간버그 parseServerTime·FCM stale토큰·글자크기 0.85 고정)
- **06-29~30**: 역대 C2(2군 시즌스탯/box/스플릿) 적재+UI + **퓨처스 홈 토글**(`[KBO｜퓨처스]` 세그먼트) + **FCM collapse 버그**(등말소 다발 알림 트레이 합쳐짐 → `_collapse_key` 엔티티 분리, ↑주의사항)
- **07-01~03**: 퓨처스 경기상세 풀스크린·배치픽스(포지션 한글·상무/울산/소뱅 로고·2군 일일잡 `_update_futures_games`·우천취소 0:0 픽스) + **마일스톤 대확장**(끝내기/사이클/다홈런/20-20/통산100단위/역대순위/팀기록6종) + **알림 지연 개선**(한줄평 즉시 boxscore 재크롤·게임데이터 마일스톤 early 분리 = 7~30분→1~5분)
- **07-04~05**: **투구 궤적 시각화**(game_pitch_locations 9 물리컬럼(PITCHf/x)·`pitch_trajectory.dart`·[위치/궤적] 토글·2D 측면상단·3D 원근회전 뷰) — ⚠️physics 백필 부분완료(live-guard 창밖 `backfill_pitch_physics` 재실행 잔여)·3D 존폭=absHalfW 정렬
- **07-07**: 마일스톤 stale 신고=**오진**(득점≠타점 혼동, 코드 무변경) — 교훈 "N타점인데 M 알림"=스탯종류 먼저 대조
- **07-17**: 경기요약 한줄평 팀 오귀속 버그 수정(key_play 승팀 필터·MVP wpa inning_half '0'/'1' 인코딩, 17건 재생성) + 투구위치 3D 횡회전 고정 + 서버 git 재인증·reconcile(origin/main)

## 역대 데이터 프로젝트 (KBO 1982~) — ✅ 전부 완료
목적: 역대 선수·팀 데이터로 상세 깊이·올드팬 자산·비시즌 DAU. 소스 = **KBO 공식 + Naver 통계 API만** (⚠️statiz 크롤=불법 ToS, 절대 금지 — `statiz_crawler.py`는 오명, 실체는 Naver API). 크롤러 = `backend/crawler/historical_crawler.py` 서브커맨드(`<시즌범위>`/bio/awards/link/fip/ps/splits/futures/detsplits/naver).
- ⚠️ **kbo_player_id = 역대 정규키**(players + historical_players 공유, 사람1=id1, 이름조인 폐기). naver_player_id=라이브 브릿지.
- ⚠️ **KBO 리스트=규정충족자만** → 비규정은 `ddlTeam` 팀필터로 우회. 해체구단(삼미/현대/쌍방울) 비규정은 미수집.
- ⚠️ **Naver stat API = 2007~만**(pre-2007=KBO 단일 spine). woba~2008+·war/wrc+~2014+ = **시즌별 표시용**(통산집계 부정확).

### 적재 스냅샷 (프로덕션 DB)
- `team_franchises` 22행 — 구단계보(current_team_id NULL=해체구단)
- `historical_players` ~1100명 — bio/career/draft_info/debut·final/primary_team + naver·player_id 브릿지(현역 277명)
- `historical_season_stats` ~14566행 — 규정+비규정, series_type(정규/PS), FIP/woba/war/wrc+/babip/iso 등
- `historical_awards` 541건 — MVP/골글/타이틀
- `historical_splits` — 타자 11130행(23~26)+투수 5459행(24~25): 홈원정/상대팀/월별/플래툰/구장
- `historical_futures_season_stats` 12967행/17시즌 — 2군 시즌스탯 / `futures_games`+`futures_game_box`(JSONB) 952경기 — 2군 box(playerId 없이 이름만)
- **게임단위 백필 = game_pitches/PA 2010~2023 확장**(11317경기·885120타석, 갭0) → matchup 진짜통산·역대 WPA/클러치·리플레이·존히트맵
- ⚠️ 미수집/잔여: PS 2006~ 부분결손 · 2군 pitch-by-pitch=infeasible(소스부재) · WAR/wOBA 통산집계 부정확(시즌표시만)

### UI 노출 (✅ 완료 — 웹+서버 라이브, APK 미반영)
- 통합검색(현역∪은퇴 '역대'배지) · 은퇴상세 `historical_player_detail_screen` · 순위탭 '역대기록실' 탭(`PlayerRankingsTab(historical:true)`) · 현역상세 수상+career-extras(타이틀이력·팀변천·마일스톤·스플릿) · 팀상세 구단역사/레전드
- **퓨처스(2군)**: 홈 탭 `[KBO｜퓨처스]` 토글(같은 날짜스트립+카드 셸을 2군 데이터로, `widgets/futures_game_card.dart`, 재시작=KBO) + 퓨처스 경기상세 풀스크린(`screens/futures/futures_game_detail_screen.dart`, 타자/투수 탭·박스). box API=`api/routers/futures.py`(games/box/leaders), 2군 일일잡 `scheduler._update_futures_games`(KST 04:00 idempotent). ⚠️box 선수=이름만(kbo_player_id 미연결)
- ⚠️ 육안 렌더는 사용자 디바이스/웹 스팟체크 권장(Flutter canvas 헤드리스 미관찰)
- 재개 트리거(전부 완료, 재작업 시만): `역대UI 진행` `역대C2 진행` `상세확장 진행` — 동작 = 위 이력·git log 참고 후 진행

## 해야할 것

### AI 경기 한줄평 — ✅ 구현완료 (Gemini LLM)
- `api/narrative.py game_review` = Gemini 무료 API(`gemini-2.5-flash`) 우선 → 실패/무키/타임아웃(12s) 시 `_template_review` 폴백(절대 안 죽음). env = scheduler `gemini.conf` `GEMINI_API_KEY`/`GEMINI_MODEL`(키 회전 시 교체+scheduler restart). 검증 facts만 프롬프트(환각가드), `thinking_budget=0`, **1문장 60자**. game_summary 본문 교체, game_reviews 영속, 발송=종료 후처리.
- ⚠️ **결정장면(key_play)·MVP = 반드시 승팀 타석만**(07-17 팀 오귀속 버그 수정): key_play=win_rate 부호정렬(홈승 DESC/원정승 ASC)로 승팀 기여만, MVP wpa=`inning_half` **'0'(초/원정)·'1'(말/홈) 인코딩**('초'/'말' 아님). 거짓결정타 3가드(안타/희생타만·margin≤5·초반거대swing 글리치배제). 무승부도 발송(is_draw면 result 대기 스킵).

### 백로그 (착수 전 상의)
- **관리자 콘솔**: app-config 편집(공지배너·강제업데이트·푸시발송) · 서버상태 패널 · 유저상세/정지 · 크롤 수동재실행 · 기능 사용률 분석
- **UI/UX 강추**: 첫실행 마이팀 선택 플로우 · 홈 직관 미니배너 · 새 중계 amber 페이드인 · 선수 초성검색 · 필드뷰 풀스크린 · AppEmptyView 공용
- **베타/출시**: Android=Firebase App Distribution(keystore 백업 선행) / iOS=$99+Codemagic→TestFlight or 웹 PWA(배포중 `/app/`)
- **외부작업**(물어보면 안내): 도메인+Cloudflare Tunnel(IP은닉) · Play Console $25 · 법무(문의메일 실계정·법률검토·KBO/Naver 저작권) · 홈위젯(native kotlin)
- ⏸️ **다크모드 육안검증 = 영구 패스**(사용자 지시, 골든이 회귀방어)

### 기능 백로그 (아이디어 인덱스 — 착수 전 상의. 상세 = 백업 참조)
- **라이브**: 승률그래프✅·matchup✅·클러치푸시✅·불펜보드✅ / 우천취소 확률·투수교체 예측·경기 소요시간 예측
- **기록**: 마일스톤 트래커·MVP레이스·순위타임라인·H2H·파크팩터·박스스코어 / per-PA 안타확률(보류 AUC~.52 데이터한계)
- **참여**: 예측랭킹✅·뱃지✅·미션✅ / 데일리픽·직관뱃지·팬레벨·1:1 예측대결·이상형월드컵
- **콘텐츠/라이트팬**: 3줄요약·다이제스트·"지금 무슨상황" 캡션✅·쉬운스탯 등급·응원팀 찾기 테스트·연말결산 Wrapped✅
- **오프시즌**(비시즌 DAU): 스토브리그 FA·명장면 리플레이(game_relay_archive 자산)·올타임 팀뽑기·퀴즈·개막 D-day
- **시즌이벤트**: 포스트시즌 브라켓 예측·골든글러브/올스타 예측
- **올드팬 분석**(보유데이터): 볼배합 시퀀스·과거경기 필드뷰 리플레이·클러치 WPA 리더보드·좌우 스플릿 테이블·파크팩터
- **수익화**(출시후): AdMob 네이티브·프리미엄 구독 / ⚠️최대 리스크 = 네이버 데이터 종속(상업화 전 KBO 제휴/라이선스 검토 필수)

## 알려진 이슈
- ✅ ~~**DB 커넥션 누수 (idle in transaction 미커밋)**~~ — 06-25 **근본원인 규명·수정**(↓변경이력). 원인 = `crawl_player_events.daily_player_summary`/`hitting_streak_check` SELECT가 없는 컬럼 `pds.at_bats`(실제=`pds.ab`) 참조 → 매 실행 에러 + **try/finally 부재**로 `conn.close()` 스킵 → 커넥션 영구 leak(idle in tx aborted), 일 1개 누적 → `games` 락으로 마이그레이션 차단. 수정 = 컬럼 픽스 + try/finally + `_PooledConn.close()` rollback + `idle_in_transaction_session_timeout=5min`(auto.conf) + **`_PooledConn.__del__` 안전망(322개 사용처 전역 retrofit, 스코프 이탈 시 자동 close)**. ⚠️**재발방지 = ↓주의사항 "DB 커넥션 누수 3중 방어"**. 점검: `SELECT pid,state,now()-state_change,left(query,60) FROM pg_stat_activity WHERE state LIKE 'idle in transaction%'`
- push_tokens 사용자 1명 — 다수 유저 알림 시나리오 미검증
- 라이브 pitch-locations cold 첫 호출 ~2초 (Naver fetch 의존)
- scheduler 30초 사이클 — 연속 이벤트 1개 알림 통합 (의도된 dedup)
- 타자 존 타율 = 인플레이 기준 (삼진 제외 → 시즌 타율보다 소폭 높음, BABIP 성격)
- 동일 이닝 타순 일순 시 존 타율 매칭 근사 (발생순 zip — 오차 미미)

<!-- FABLIZE:BEGIN — run Opus like Fable (always-on router). Verified procedures only. Install/update: fablize setup.sh -->
## Operating mode (always on — auto-route by task signal)

Apply what the task signals; with no signal, baseline only. Read each pack only when needed. Routing: smallest matching discipline only, overlap only when genuinely multi-category, mimic observable behavior only.

- **[always]** Lead with the outcome · stay within the requested scope (no incidental refactors) · ground completion claims in this session's tool results · confirm before destructive or hard-to-reverse actions.
- **[2+ sequential stories]** Run `python3 C:/Users/qq772/.claude/plugins/cache/fablize/fablize/2.0.0/scripts/goals.py`: create → next → checkpoint (with evidence) → final verification gate (no completion without `--verify-cmd` and `--verify-evidence`). Run from the repo root; state in `./.fablize/` (resume with `status`). Skip for single-step tasks.
- **[debugging / test failure / unknown cause / review]** Follow `C:/Users/qq772/.claude/plugins/cache/fablize/fablize/2.0.0/packs/investigation-protocol.txt`: reproduce first → 3+ competing hypotheses → evidence per hypothesis → full causal chain → verify before/after → report rejected hypotheses.
- **[render/executable artifact: HTML, SVG, game, UI, chart]** Follow `C:/Users/qq772/.claude/plugins/cache/fablize/fablize/2.0.0/packs/verification-grounding-pack.txt` grounding loop: run it in the real renderer → observe the output → fix what you see → re-run. A static check is not observation.
- **[hard or ambiguous task]** Adaptive thinking scales with difficulty automatically. To go higher, recommend `/effort xhigh` to the user. Depth (capability) cannot be raised: if stuck 2+ times or out-of-spec discovery is needed, report the limit honestly and escalate.
<!-- FABLIZE:END -->
