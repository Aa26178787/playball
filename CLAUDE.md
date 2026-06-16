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
- ✅중간 3종 (2026-06-13 적용): **ETag/304**(`_ETagMiddleware` GET 200 바디 md5 + 클라 dio 인터셉터 If-None-Match/304→보관바디 — GZip보다 안쪽 add라 원본 기준 해시)·**서버 SWR**(`@cached(ttl, swr=True)` 기본 — 만료 시 stale 즉시 반환+백그라운드 스레드 갱신, stale 보관 = ttl×10, `_refreshing` 셋으로 갱신 dedup)·~~프로필 썸네일~~(미착수 잔여)
- ✅**`/home/bootstrap`** (2026-06-13): today+rankings(full)+이번달 calendar+app-config 1콜 (`api/routers/bootstrap.py` @cached(20), 조각별 try라 부분 실패 허용). 클라 = `_loadGames` isToday서 bootstrap 우선→실패 시 /games/today 폴백, `_applyBootstrapExtras`가 순위/캘린더/설정 주입(+`_skipNextRankingsFetch`로 개별 fetch 생략, initState서 `_loadGames().then(_loadRankings)` 체이닝 = race 방지). 잔여: compute() isolate 파싱·홈 위계 로딩·프로필 썸네일
- 장기: Cloudflare CDN(이미지 edge 캐시 — 도메인 계획과 묶음)·dio+http2_adapter(h2 멀티플렉싱 — bootstrap 도입 시 가치 하락하니 후순위)·uvicorn --workers(인메모리 캐시 워커별 중복 → Naver fetch 배수 트레이드오프, 부하 생기면 검토)

## 주의사항
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
- **06-12 메가B 1차 (포인트 원장)**: point_ledger+game_predictions 테이블 → `api/points.py award()`(UNIQUE 멱등) → 예측 API(POST predict/GET fan-predictions) → scheduler 종료 정산(적중50/참여10) → 출석(+5 일1회)/직관(+20) 훅 → 리더보드 TOP50 → 게임카드 `_PredictionBar` 팬투표 섹션(픽 버튼→분포바+✓내픽, 'AI 승리 예측' 바 아래)+홈 출석 사일런트+마이페이지 points_screen(내 포인트/랭킹/적립내역). **mojibake 사고 복구**: api_service.dart·games.py 워킹카피 전체 오염(과거 PS append) → HEAD 복원+Edit 재적용, predictGame류 authHeaders 누락도 교정
- **06-12d UI 정리+킬스위치**: **포인트 기능 토글**(관리자 콘솔 '기능 토글' 탭 — GET/POST `/admin/feature-flags`(points/prediction/community), kill_switches JSONB 갱신+`/app-config` 캐시 즉시 무효화. 앱 = `AppConfig.enabled('points')` 가드: 게임카드 팬투표·출석 호출·마이페이지 포인트 진입. **현재 points=false 시드** — 콘솔서 켜기 전까지 앱/웹 숨김) + 연월 컨트롤 중앙정렬 + **팬투표 리디자인**(고스트 버튼+팀컬러 dot / 투표 후 라벨행+8px 얇은바 — ML 바와 위계 차등) + **마이페이지 재편**(글/좋아요/댓글 인라인 3섹션→'커뮤니티 활동' 허브 3행+바텀시트 전체목록, 포인트/차단/초기화 단독카드→'기타' 통합) + **알림 설정 4카테고리**(올스타→선수 흡수, 커뮤니티+방해금지→일반, 접힘 헤더 켜짐 n/m) + **scheduler 30분 heartbeat**(무경기 새벽 무로그 → 스모크 오인 방지, smoke 기준 35분)
- **06-13 안정화+관리자 대확장**: (앱/웹/iOS 다수 픽스) iOS 사파리 주배포 대응(웹 OS뒤로가기=JS 트랩 유일경로·extension type this 바인딩·webBottomGuard 탭바·헤더 상태바 단차 5탭+서브6·**기준폭 412 전역 스케일**(좁은기기=갤럭시 동일비율, Transform.scale+MediaQuery override)·textScale 1.1·헤더 노치 여백 headerTopGap·필드뷰 잔여500px 보장+FittedBox 비율유지) / 구장 카카오맵 웹 폴백(inappwebview 스텁→외부링크) / 루트 302→/app/ / **버그8**(탭바여백·작성칸 커서·트렌드 era소멸→안내문·공유 타점 rbi→rbis·인증문구·사전알림 GRANT누락·댓글알림 중복=POST재시도 GET한정+더블탭가드) / **성능3종**(SWR @cached(ttl,swr)·ETag/304 미들웨어+클라 If-None-Match·`/home/bootstrap` 1콜) / createImageBitmap premultiplyAlpha='premultiply'(전역스케일후 투명PNG 어두움 방지). ※다크모드 이미지 어두움은 이 옵션 아님 = **Chrome Auto Dark Theme** — index.html `<meta name=color-scheme content="light dark">`로 해결(06-14, 미선언 시 강제 darkening이 이미지만 dim) / 스코어보드+득점요약 통합카드(균등분배 스크롤제거·토글헤더제거·타점배지 높이24) / **마일스톤 정리**(개인최다 최소임계·등록말소 알림 0건=공백불일치+dedup·결정적순간/아침브리핑 전용토글) / 팀순위 시즌하한(전반기 216승=3시즌합산 — 홈원정·피타고리안·1점차도 동일 픽스)·PS확률 자체정렬+바아래 항목%
  - ⚠️ **502 사고 2건**(상단 인프라 기록): duckdns 구박스 cron 핑퐁 + fail2ban 릴레이 IP 오인밴. 스모크 6·7항이 감시
  - **관리자 콘솔 대확장**: 로그인 게이트(키 검증 후 진입) + **DAU 인프라**(`api/dau.py` 미들웨어 JWT sub 추출→daily_active_users 60s flush) + 탭4 신설(통계 DAU/WAU/MAU+가입추이 / 설정·공지 배너·버전·시즌단계+전체 푸시 broadcast / 시스템 하트비트·재크롤큐(admin_commands, scheduler 30s 소비)·백업·알림내역·보안로그 / 댓글 검색삭제) + 회원 정지(users.suspended_until, 로그인 403)·포인트 수동지급(reason=admin). 신규테이블 daily_active_users·admin_commands GRANT 완료
- **06-14 game_start 미발송 사고+수정**: 6/13 459 키움-한화 game_start 알림 누락(타 경기 460~463 정상). 원인 = **status 갱신 경로 2개 race** — `_update_today_games`(스케줄 크롤, curr_details 반영) vs `_update_live_games_realtime`(relay)가 `curr_details` 캡처 **이후** status를 '진행'으로 바꿈(relay 우선 감지). game_start 루프는 stale curr('예정')만 봐 전환 누락 → 다음 cycle prev='진행'이라 영구 스킵. ⚠️같은 시간대 selenium(snap chromium) 크래시 있었으나 **무관**(크래시는 전 경기 '예정' 시점, game_start은 그 후 — 시점 다름. 헷갈리지 말 것). 수정 2중방어: ① **알림 비교 직전 `curr_details`/`curr_statuses` 재캡처**(`_update_*` 갱신분 다 반영 후 비교 — game_start뿐 아니라 종료/취소 등 모든 state 알림이 relay 우선갱신 race서 보호) ② **game_start catch-up**: 전환(예정/라인업→진행) 외 `진행 & 초반(current_inning≤2) & 미발송`도 발송(재시작/예외/race 자가복구, >2회 진행 경기 제외=늦은 '경기 시작' 오발송 방지, notification_log 영속 dedup이라 중복 X). 459는 이미 종료라 소급 미발송. **교훈**: 전환(prev→curr) 기반 알림은 curr 캡처 시점·다중 갱신경로 race에 취약 → 비교 직전 재캡처 + state-based catch-up 병행
- **⚠️ 06-14 game_start 진짜 원인 정정** (위 recapture/catch-up은 **오진** — 무해해서 유지하나 원인 아니었음): **경기전 알림(pregame, "경기 N분 전")이 `user_notifications`에 type='game_start' 기록**(9d08207, 5/24) + **`_already_notified`에 user_notifications(game_id,type) 전역 체크 추가**(f2237a2, 6/3) → 충돌. pregame이 경기 2시간 전 game_start row를 남기면 실제 시작 시 '이미 보냄' 판정해 억제. ⚠️**체크가 game당 전역**이라 **한 명만 pregame 받아도 그 경기 game_start가 전원 누락**. 6/5 정상이던 건 그 경기에 pregame 미발화(설정/토큰), 6월 중순부터 발화하며 억제 시작. 459(키움-한화)만 누락·460~463 정상이던 것도 동일 사용자 pregame 차이로 설명됨. **수정**: pregame `user_notifications.type` 'game_start'→**'game_soon'**(FCM data.type은 game_start 유지=탭 라우팅), 앱 알림화면 game_soon=alarm 아이콘. ⚠️**경기 관련 user_notifications에 'game_start' type 재사용 금지** — `_already_notified`가 전역 game당 dedup하므로 pregame류는 별도 type 필수
- **06-14d 웹/UI 픽스 묶음**: ① **다크모드 웹 이미지 어두움** = **Chrome Auto Dark Theme**(color-scheme 미선언 시 콘텐츠 강제 darkening — 앱 UI는 이미 다크라 밝은 이미지만 dim). `app/web/index.html`에 `<meta name="color-scheme" content="light dark">` = opt-out. ⚠️premultiplyAlpha 가설은 오진(되돌림, 'premultiply' 유지). ② **핵심스탯 1회성 점선힌트** = 2x2 전체 wrap 아닌 **각 기록(숫자)에만** marching-ants(`_MarchingAntsBox`/`_DashedBorderPainter`), 비교말풍선 트리거 길게누르기→**클릭(onTapUp)**. **비규정(규정타석/이닝 미달)도 값+용어설명 팝업**(`_showCompareBubble` c==null early return 제거, c null-safe). ③ **갤럭시 스와이프 뒤로가기가 이전 사이트로 탈출** = web back trap popstate서 sentinel **재푸시를 onBack보다 먼저**(동기) — 빠른 연속 스와이프 레이스 창 제거(`web_back_web.dart`). ④ **인스타 링크 앱 연결** = `utils/insta_launch.dart`(`instagram://user?username=` 딥링크 우선+https 폴백), 선수/팀 상세 적용, AndroidManifest `<queries>` instagram scheme/package + iOS `LSApplicationQueriesSchemes`. 웹은 https 폴백(kIsWeb). ⑤ **PS확률 범례 풀네임** = PO/준PO/WC홈/WC원정 → 플레이오프/준플레이오프/와일드카드 홈/와일드카드 원정(team_screen `_psPctLabel`, Wrap이라 줄바꿈 안전). ⑥ **온보딩 모드 픽커 서버 영속** = `user_settings.app_mode`(TEXT) + `/auth/me` 포함 + `POST /user/app-mode`. 앱 픽커가 로그인 유저면 보기 전 서버 app_mode 확인(있으면 스킵+로컬 flag 복원), 선택 시 서버 저장 → 웹 localStorage(사파리 ITP/캐시삭제)로 로컬 flag 증발해도 **재로그인 시 재노출 안 됨**. ⚠️**웹 로그아웃/온보딩 재출현 원인 = 사파리 ITP가 미설치 웹앱 localStorage를 ~7일 evict**(토큰+flag 증발) or 사이트데이터 수동삭제 — 코드버그 아님. 토큰까지 영구화는 PWA 설치 필요(standalone 크래시로 보류). ⚠️웹 변경 다수 = 재빌드+배포 완료, **네이티브 APK는 미반영(재빌드 필요)**
- **06-14b QS/완투/완봉 0 누락 + starter 식별 버그**: 한화 박준영(#68) 6/13 6.1IP 2ER 퀄스인데 선수상세 QS 0. 원인 2중 ① `pitcher_stats.qs/cg/sho`는 **KBO 공식(규정충족자만 노출)**에서만 채워짐 → 비규정 선발 영원히 0 (2026 32명 영향) ② ⚠️**`game_pitchers.pitching_order` 베이스 불일치** — boxscore writer(naver_crawler `enumerate`)는 **0-base**(starter=0), 라이브 relay/entry writer(`enumerate(...,start=1)`)는 **1-base**(starter=1). 즉 라이브 중 starter=1, 최종 종료 후 starter=0. starter를 `pitching_order=1` 고정으로 찾던 곳(마일스톤 QS/완투, games.py 선발 fallback)이 종료 후 2번째 투수를 선발로 오인. **수정**: starter = `(game,team_side)별 MIN(pitching_order)`로 통일(convention-agnostic, 0/1 양쪽 안전) — 절대값 `=1` 금지. `_sync_pitcher_counting_from_games()`가 game_pitchers(starter min-order, ip≥6 & er≤3)서 QS/CG/SHO 계산해 GREATEST 보완(KBO값 유지), 경기 종료 후처리에 추가 + 3시즌 백필(99행). ※`innings_pitched`는 numeric(6.1=6⅓)이라 `>=6` 직접 비교 OK. ⚠️동명이인 박준영 한화 2명(313/8405) — QS는 player_id 귀속이라 무관
- **06-14c 핵심스탯 점선힌트 + 관리자 토글확장/서비스복구**: ① 선수상세 핵심스탯 길게누르기 안내 = 설명글→**marching-ants 점선박스 애니 1회성**(`_MarchingAntsBox`/`_DashedBorderPainter`, LocalCache flag `hint_core_longpress` — 처음만 표시+즉시 set, 길게누르면 해제) ② **관리자 기능토글 9종 확장**: FEATURES += win_prob/bullpen/pitch_zone/highlights/weather/share, 앱 `AppConfig.enabled(key)` 가드(OFF=섹션 graceful 숨김 — 승률그래프·불펜신호등·피칭디자인/존히트맵·하이라이트·날씨·공유카드). 기본 ON(kill_switches 미기재=enabled) ③ **`POST /admin/maintenance`**(clear_cache·reset_db_pool·rewarm_weather·all) — API 프로세스 직접실행(큐는 scheduler 프로세스라 캐시/풀 복구 불가), 콘솔 시스템탭 '서비스 복구' 버튼. **새 기능토글 추가 시 = backend FEATURES + 클라 AppConfig.enabled 가드 1:1 필수**
- **06-12c 메가D (출시 게이트 코드측)**: `scripts/smoke.sh`(서비스 활성+scheduler 30분 심장박동(새벽 무로그 정상이라 3분 기준은 오탐)+git 동기화+엔드포인트 9종+HTTPS 2종 — 배포 후 `bash ~/playball/scripts/smoke.sh` 1커맨드, ALL PASS 검증 완료) + **GitHub Actions CI 녹색**(`.github/workflows/ci.yml` — flutter analyze는 **`lib test` 범위 한정**(vendored local_packages가 CI fresh 환경서 미해석 에러)+test(@Tags(golden) 제외: 골든 PNG=Windows 렌더라 Linux 러너 불일치)+backend compileall) + **골든 확대**(VisitShareCard/PlayerShareCard — cached_network_image의 path_provider mock 채널 필수 패턴) + **release APK 빌드 복구**: google-services 4.3.10→4.4.2 (crashlytics gradle 3.x가 4.4.1+ 요구 — release minify의 mapping 업로드 태스크만 터져서 debug론 잠복, 65.5MB 빌드 성공). 잔여 메가D = 외부작업(Play 내부테스트·keystore)
- **06-12b 메가B 완결+메가C**: **푸시GW**(fcm_service._send = 단일 게이트웨이 — KST 23:30~07:30 quiet hours 억제(user_settings.notify_quiet 기본 ON, 인앱 알림함은 전원 저장) + ntype→Android 채널 3종 라우팅(playball_live/myteam/community — main.dart 생성, 설정 '방해금지' 토글)) → **뱃지**(api/badges.py 11종 + user_badges 테이블, GET /user/badges lazy 평가) → **주간미션**(GET /user/missions — 예측3/출석5/직관1, KST 월요일 주차, 완료 시 자동 보상 reason=mission_weekly) → points_screen에 미션 진척바+뱃지 그리드 → **온보딩 모드**(홈 첫실행 프로/캐주얼 픽커 — 캐주얼=compact+notify_my_team_only) → **push_tokens 다수 검증**(가짜 토큰 시뮬: 멀티발송/quiet 억제·opt-out/채널/무효토큰 자동삭제 전부 라이브 통과 — InvalidArgumentError 매칭 보강이 픽스). **메가C**: showShareCardDialog(RepaintBoundary→png→share_plus, 웹=버튼 숨김)+VisitShareCard/PlayerShareCard → 직관 저장 직후 공유 제안+승리 시 인앱리뷰(in_app_review ^2.0.9) → 선수상세 FAB 시트 '카드 공유'(랜딩 링크 동봉) → **공유 랜딩** `/s/p/{id}`·`/s/g/{id}`(api/routers/share.py — og 메타+웹앱 유도 버튼). 딥링크 스킴 = 출시 시 App Links로 (메가D)
- **06-15 버그픽스+시스템+메가E/F/G**: 팀상세·시스템 수정 후 메가셋 3개 연속 구현(spec/plan = `docs/superpowers/`).
  - **버그 5**: ① 팀상세 승률 '-' = 미니멀 진입점(홈 로고탭 등) widget.team에 win_rate 없음 → `_loadStandings`가 team_rankings서 빠진 헤더필드 백필 ② PS확률 정렬 뒤죽박죽 = 5개 직행확률 **합**으로 정렬→상위팀 ~100% 수렴 동점 → **시드 가중**(KS×5>PO×4>준PO×3>WC홈×2>WC원정)+rank tiebreak ③ 등록말소 행 = `reason` 컬럼이 약어 포지션("내"/"투") 저장 → 오른쪽 풀포지션 제거+이름 옆 풀포지션 ④ 선수목록 타자/투수 열 행높이 불일치 = 투수만 칩(Container padding) → 타자도 동일 칩 ⑤ 최근경기 시리즈 끝 1경기 orphan = getTeamGames limit 10이 3경기 시리즈 경계 자름(10=3+3+3+1) → fetch 18+잘린 가장오래된 불완전시리즈 숨김
  - **시스템 (다기기 간헐 로그아웃 진범)**: `create_refresh_token` 활성토큰 캡 쿼리 **`ORDER BY created_at ASC OFFSET 4` = 정렬 역전** → 오래된 4개 보존하고 방금 활동한 최신 토큰 삭제 → 다기기(삼성브라우저+사파리+APK) 사용자 활성세션 잘려 401. **DESC로 수정**. + revoked/만료 토큰 영구 누적(248행 중 92% dead) → create 시 per-user 정리 + scheduler 일일 전역 purge(UTC 18:00). + `flutter analyze lib` 18→**0**(미사용 import/메서드 제거, deprecated Share→SharePlus.instance)
  - **테스트 인프라**: `backend/tests/` pytest + CI `backend-test` job(postgres 서비스, 타깃 deps, `pytest.ini` pythonpath). 순수=DB불요/통합=`TEST_DATABASE_URL` skipif. **25개**(narrative/auth rotation/points/badges/season=순수+DB). 검증 = 서버 scratch DB(`playball_test` 생성→drop). auth 캡 버그를 이제 자동으로 잡음
  - **메가E 내러티브 엔진**: `api/narrative.py`(순수 dict→str, LLM 교체가능: `game_review`/`live_caption`/`mvp_line`) + **`game_reviews` 테이블**(game_id PK, review/mvp). 종료 후처리서 WPA(plate_appearances) 기반 **오늘의 MVP**(rbis 폴백)+game_event_stream 끝내기/연장 → 한줄평 생성 → `notify_game_summary(review_text=)`로 **game_summary 푸시 본문 교체**(신규 푸시 0). relay `current_state.situation_caption`=라이브 "지금 무슨 상황?". game detail `review` join → 경기상세 중계탭 상단 배너+MVP칩. 킬스위치 `narrative`(FEATURES+AppConfig). 한줄평/MVP=다음 종료경기부터
  - **메가F 리텐션 점화**: **points 킬스위치 OFF→ON**(admin POST /feature-flags, kill_switches={} 라이브) → 팬투표·출석·포인트·뱃지·미션·리더보드 전 유저 활성. **예측 결과 푸시**(`notify_prediction_result` 적중/참여/무, 토큰없는 웹유저는 인앱만) — 정산 루프서 예측자별, `notification_log (game_id,'prediction_result',uid)` dedup(⚠️**sub_id 비어있어야 user_notifications 전역체크 회피** = game_start 버그 패턴이라 sub_id=uid 필수). **예측 마감 카운트다운**(`_PredictionBar` deadline=경기시작, 1분 Timer, 마감 후 투표잠금). badges/mission 회귀테스트 추가
  - **메가G 시즌/오프시즌**: `api/season.py::compute_phase`(순수: preseason/regular/offseason, **postseason=admin 핀 전용** 자동판별X) + scheduler 일일 자동갱신(UTC 18:30, 일정서 first/last/recent → season_phase, postseason이면 미덮음, 캐시 무효화). **연말결산 Wrapped**(`GET /user/season-wrapped?year` 직관W/L/구장·예측적중·포인트·출석·최애 / `screens/wrapped/season_wrapped_screen` 그라디언트 카드+공유 / 마이페이지 진입). **오프시즌 홈**(season_phase=offseason+무경기 → 결산 진입 뷰). E/G 소비자 대부분 시즌 이벤트성(11월 phase전환 시 자동노출, 지금 Wrapped는 마이페이지 미리보기)
  - ⚠️ **네이티브 APK 전부 미반영** — E 배너·F 카운트다운·G Wrapped/오프시즌홈·버그픽스 클라분 = 웹·서버만 라이브. IPA=Codemagic main 빌드 자동포함, APK 재빌드 필요
- **06-15b 데드코드+팀상세 대수술+로스터자동화**: 메가E/F/G 후 정리·UI·데이터 위생 묶음(전부 웹+서버 라이브, 네이티브 미반영).
  - **데드코드 제거**: backend 미사용 import3·함수6(log_auth_fail·cache_delete·notify_allstar_vote_player_in·_notify_fav_player_lineup·_get_game_statuses·get_game_lineup)·StadiumRecord / dart 미사용 메서드 9 + cascade(헬퍼·_rosterStatusBadge·_playerRosterStatus fetch) = ~1100줄. `flutter analyze lib=0`. ⚠️elo 미사용 **파라미터**는 시그니처 위험으로 제외. ⚠️`git add -A`가 insta 스크래치 대량 오스테이징 → 코드파일만 선별 add (스크래치 untracked 유지)
  - **다크 팀컬러 가시성**: `utils/team_theme.dart`에 `adjustTeamColor`/`teamColorOn` 중앙화(HSL lightness<0.45 → +0.30 부스트). **전경(텍스트·배지·아이콘)만** 적용(로고·그라디언트 배경=raw). NC/두산/KT/키움 네이비 가독. + 다크 `sub` 회색 0xFF71717A→**0xFF8E8E98**(대비 AA, 전 화면 33곳). home `_adjustTeamColor` 중복 제거→공용
  - **시리즈카드 재설계**(팀상세 최근경기): 3섹션 → **헤더없이 경기별 3칸**(날짜/상대로고/스코어/승패, 승패색). 취소경기 포함(`getTeamGames` status IN 종료·취소, 셀='취소'), 전부취소 그룹 제외, 3-cap은 종료경기만(rainout 유지). **N월 M주차 구분선**(진출선 스타일). 폰트 스코어20/날짜12/승패13
  - **팀상세 6종**: ①월별성적+상대전적 **통합 재설계**(단일스크롤·시즌종합요약카드·통일 win%바·약세📉/강세📈 하이라이트, 구 차트/원형게이지/_RingPainter/_SummaryChip/_LegendDot 제거) ②**타순별 선수 중복** 수정(각 선수 주타순 1배정 — backend slot_pick CTE, 김도영 3·4번 동시표기 버그) ③커뮤→커뮤니티 ④플로팅탭 홈 형태 통일(height58·radius30·Icon22·active=ink) ⑦다크 sub 회색(상동)
  - **미계약 외인 자동화(A)**: `kbo_roster_crawler._save_changes`서 방출/웨이버/임의탈퇴 roster_change → `is_active=FALSE`(1군등록/복귀=재활성 self-heal). 앱 is_active 필터로 자동숨김. 치리노스(LG)·쿠싱(HH) 수동 off. ⚠️매닝(SS)=신규영입 부상이라 오탐(웹검증으로 회피). 기존 방출분 backlog는 자동신호 없음(이벤트無+외인플래그無)
  - **1군 등록현황 diff = 부상/이탈 자동표기**(문동주=방카르트 수술): `crawl_active_rosters`(Register.aspx **fnSearchChange('CODE')** 링크클릭 10팀 1군명단 — execute_script 직접호출은 strict-mode 에러) + `sync_active_roster`(diff→`roster_status` 배지). ⚠️**판정 = 1군 등록부재 AND 2026 1군출전 AND 14일+ 미출전**(staleness 가드 — 등록부재 단독은 크롤누락/휴식/당일말소로 현역 강민호 오말소. 1차 백필 201건 중 현역 오탐 발견→revert→가드 추가). roster_diff.py 순수판정+test. ⚠️**KBO 부상자명단 페이지 없음** → 1군 diff가 최선(부상≠2군 구분 불가). 스케줄러 `_update_roster_changes` 일일
  - ⚠️⚠️ **자동 생성 roster_change는 reason `(자동)` 마커 + 모든 뉴스 surface서 제외 필수**: 알림(`_notify_roster_for_fans`)·홈 등록말소 배너(`get_today_roster_changes`)·팀상세 최근등록말소(`get_roster_changes`) 전부 `reason NOT LIKE '%(자동)%'`. **선수상세 roster_status 배지(`get_player_detail` 최신행 파생)만 노출**=의도 surface. 교훈: 자동데이터를 기존 뉴스 테이블에 넣으면 **전 소비처 노출정책 일괄 점검**(홈 172 도배 사고 — 알림가드만 하고 배너 2곳 놓침)
  - **backend pytest 확장**: roster_diff·narrative·season·auth rotation·points·badges·pa = scratch DB(`playball_test`) 검증, CI backend-test(postgres) job
  - **refresh_tokens bloat**: revoked 토큰 영구누적(92% dead) → create 시 per-user 정리 + scheduler 일일 전역 purge
- **06-16 팀상세 UI + 디자인토큰 전면화**: (전부 웹+서버 라이브, **네이티브 APK 미반영**)
  - **팀상세/경기탭 재구성**: ① 상대전적 강세/약세 재설계(승/패/무 분리 + **승률**(구 "2-4" 폐기) + 상대 로고, 강세→약세 순, 이모지 제거·데이터 가운데정렬·카드높이 축소) ② **타순별 서브탭 → 팀 리더**(`GET /teams/{id}/leaders` @cached(300), 부문별 TOP3 — 타자 avg/hr/rbi/sb/ops·투수 era/w/k/sv/hld, 규정 게이트 qual_pa/ip / 앱 = 타자·투수 **2열** 한화면) ③ 선수카드에 best_stat/best_rank(최고순위 부문) 표기·hr→홈런. `getTeamBattingOrder` 제거
  - **타이포 스케일 토큰화** (`utils/design_tokens.dart` `Typo`): micro9/mini10/caption11/small12/body13/subtitle14/title16/lg18/h220/h124/display34. off-scale 매핑(8→micro·15→subtitle·17→title·19→lg·22→h2·26→h1). 전 화면 `fontSize` 정수리터럴 → `Typo.*`(12커밋). 소수(X.5)·초대형(28/32/150)은 raw 유지(의도)
  - **디자인토큰 4종 전면화** (5커밋, sed 바이트안전 일괄 + git diff 한글오염 매단계 감시 0):
    - `design_tokens` 확장: **`Typo.thin/semibold/black`**(w300/500/900) + **`Pal` 신설**(중성팔레트 ink/ink2/ink3/sub/paper/paper2/line/line2/track 9단계 다크/라이트 정준쌍 중앙화, `Pal.x(isDark)` bool 인자 — Theme 재조회 회피)
    - **fontWeight** `FontWeight.wN/bold/normal` → `Typo.*` (~370, 1:1 무손실)
    - **중성색** 화면별 `_C`헬퍼·인라인 삼항식 → `Pal.*` (278). 조건식 2형태(로컬 `isDark*` + 인라인 `Theme.of().brightness==dark`) 대응. ⚠️**정준 쌍만 매칭**(값 불일치·비정준쌍은 미변환 = 오변환 0). `_isDark` 밑줄 getter 엣지케이스 교정(`_Pal` 고아 4건)
    - **Radii** `circular(4/8/12/16/20/999)` → `Radii.xs/sm/md/lg/xl/pill` (110). off-scale(10/14/5/3/2/6/13/22)는 raw(스냅=모서리 시각변경 회피)
    - **Space** `EdgeInsets.all`·단일축 `SizedBox(width|height)` 스케일값 → `Space.*` (279). ⚠️`width:`/`height:`는 간격↔크기(로고/스피너)·Positioned 오프셋 구문구분 불가 → **명확한 간격 idiom만**(symmetric/only/fromLTRB·이중축 SizedBox·off-scale 6/10/14/18/20 = raw)
  - ⚠️ **신규 코드 = 토큰 우선**: `Typo`(폰트·weight)·`Pal`(중성색)·`SemColor`(시맨틱/브랜드)·`Radii`·`Space`. 인라인 hex/리터럴 지양
  - **제외(의도)**: `widgets/share_cards.dart`(골든 PNG 보호)·`utils/`(테마/토큰 정의층) = 전 토큰작업서 제외. 시맨틱/팀/결과칩/그라디언트 색 = 도메인색(중성팔레트 아님, 유지)
  - **검증**: analyze lib 0(매 단계) · 골든 4종 통과(VisitShare/PlayerShare/AppErrorView 라·다 — 값 1:1이라 PNG 불변) · 웹 wasm 재빌드 → `/app/` 200

## 역대 데이터 수집 프로젝트 (KBO 1982~) — ✅ 핵심 완료 (2026-06-15 착수 ~ 06-16 A/C1/B/꼬리/검증 완료, C2만 장기보류)

### ⚡ 트리거 (재개 프로토콜)
- ✅ **이 섹션(역대수집 핵심)은 완료** (A/C1/B/꼬리/검증). `역대수집 진행`은 이제 C2(장기 큐)만 남음 → 사실상 **아래 두 후속 트리거로 분기**:
  - **`역대UI 진행`** → 역대 데이터 앱/API 노출 (실사용자 가치, 데이터 준비됨) — 별도 섹션 「역대 데이터 UI 노출」
  - **`역대C2 진행`** → 퓨처스 경기단위·스플릿 세밀축 (장기·니치·무거움) — 별도 섹션 「역대 C2」
- **공통 동작 프로토콜**(세 트리거 동일): ① 해당 섹션 **진행 체크리스트** 읽기 → ② 첫 `[ ]` 실행 → ③ `[x]`+**진행로그** 한 줄 → ④ **연속**: 다음 `[ ]` → ⑤ `⏸️ 게이트` 만나면 멈추고 질문 / 막히면 정직 보고. 게이트 없으면 소진까지 자율.
- **각 단계 끝 = CLAUDE.md 해당 섹션 갱신**(체크박스+진행로그) → 세션 끊겨도 이어받음.
- 멈춤: "<트리거> 중단" / 게이트 / 미완료 0개.
- `역대수집 진행`(구 트리거) = C2 장기 큐 가리킴 (아래 「역대 C2」 = `역대C2 진행`과 동일 취급).

### 목적
- KBO 역대(1982~) 선수·팀 데이터로 **① 상세페이지 깊이(콘텐츠) ② 승리예측 정확도(모델)** 강화. 비시즌 DAU 방어·올드팬 자산.

### ⚠️ 소스 정책 (확정)
- **statiz(스탯티즈) 크롤 = 불법(ToS/저작권) → 전면 금지.** 절대 재도입 금지.
- 합법 소스만: **KBO 공식(koreabaseball.com, 가장 방어가능) + Naver 통계 API(기존 `statiz_crawler.py`가 실제로 쓰는 `api-gw.sports.naver.com/statistics` — 이름만 statiz, 도메인은 naver)**.
- ⚠️ `backend/crawler/statiz_crawler.py` = 오명. 실체는 Naver API. statiz.co.kr 안 건드림.

### 확인된 소스맵 (2026-06-15 스파이크 결과)
| 데이터 | 소스 | 깊이 | 방식 | 상태 |
|---|---|---|---|---|
| 1군 시즌스탯(타/투) | KBO `record/player/...basic1.aspx` | **1982~2026 44시즌** | ASP.NET `__doPostBack`+5단위페이저 | ✅확인 |
| 퓨처스 스탯 | KBO `futures/player/hitter.aspx` | **2010~2026** | postback+팀필터 | ✅확인 |
| 세이버(WAR/wOBA/wRC+/FIP) | — KBO 미제공 | — | 기존 `recompute_*_derived`로 자체계산 | ✅보유 |
| 은퇴선수 bio(생일/키/체중) | KBO `Record/Player/{Hitter,Pitcher}Detail/Basic.aspx?playerId=` | **은퇴선수 포함** | detail 헤더(생년월일/신장체중/투타/포지션/경력출신교) | ✅확인(양준혁 검증 — 1969생·188/95·좌투좌타·외야수·남도초~LG) |
| 수상경력 | KBO `History/Etc/{PlayerPrize,GoldenGlove}.aspx` + `Player/Awards/{playerprize,GoldenGlove,SeriesPrize}.aspx` | 역대 | ASP.NET(WebFetch는 list/history 에러 → selenium 필요) | ✅URL확인(구조 selenium서) |
| 드래프트 | **`draft.koreabaseball.com`** (별도 subdomain) | ❓ | ❓ | ✅URL확인(구조 미확인) |
| 연봉 | KBO 미제공 가능(공시/언론뿐) | ❓ | 합법성 회색 | ⬜보류후보 |
- 퓨처스 팀 = 한화/LG/고양/SSG/두산/상무/롯데/KIA/NC/삼성/KT/울산 (독립·군팀 고양/상무/울산 포함 → C2 팀매핑 소스).
- KBO = postback 무겁지만 레포 **이미 KBO postback 크롤 중**(`kbo_roster_crawler` fnSearchChange, `kbo_daily_crawler`) → 패턴 존재. selenium = ARM snap chromium `driver_util.arm_or_wdm_chrome` 경유 필수.

### 트랙 구성 (목적별 분리 — 섞지 말 것)
- **트랙 A 콘텐츠**(상세 깊이): 구단계보·선수신상·통산스탯·수상·PS·(꼬리)드래프트/연봉. ⚠️ statiz 빠져 신상/수상/연봉 소스 불확실 = bio 스파이크가 생사 결정.
- **트랙 B 모델**(예측): 박스역대(~2015+ 실효, 분포이동 주의)·스플릿 기본축. ⚠️ 야구 본질 고분산 = 데이터로 안 깨지는 천장(per-PA AUC~.52, ingame .854). 무한정 정확해지지 않음.
- **트랙 C1 근**(roster 시너지): 콜업/말소+2군 시즌스탯 → 기존 roster_diff "부상≠2군 구분 불가" 한계 해결. 가벼움.
- **트랙 C2 장기**(보류): 퓨처스 경기단위·일정·박스 = 사실상 2군 리그 풀 파이프라인. 니치·무거움 → 장기 큐.

### 견적 (statiz 드롭·꼬리 제거 후)
- 저장: 코어 ~400MB / 스플릿세밀·C2 포함 ~2GB. 크롤: ~5~12시간 1회배치. **$0**.
- 개발: 근기(A코어+C1+B+A꼬리) ~7~9세션. C2/스플릿세밀 = 장기.
- **불변 병목**: ① 동명이인(44년치 이름중복, statiz_id 못 쓰니 KBO/Naver player_id 키 설계) ② 구단계보(삼미/청보/태평양/빙그레/쌍방울/해태/현대/OB 등 없어진 구단 team_id 확장).

### ✅ 의사결정 (2026-06-15 게이트 통과 — 확정)
1. ~~스키마~~ → **별도 역대테이블 확정**: `historical_players`+`historical_season_stats`. 현 players/현역 파이프 무손상(신규생성금지 가드 유지). 앱 = active(players) ∪ historical 병합조회.
2. ~~동명이인 키~~ → **`kbo_player_id` UNIQUE 정규키 확정**: players + historical_players 둘 다 보유, 사람 1=id 1. naver_player_id=라이브 보조 브릿지. **이름조인 전면폐기**(PA naver_id 숙제와 연결 — 양현종/이태양 혼합 근본해결 경로).
3. ~~기회비용~~ → **단계적 착수 확정**: 구단계보 1단계만 먼저 → 재평가(전체 7~9세션 몰빵 아님).
4. ~~**bio/수상 소스**~~ → **✅해소(2026-06-15 스파이크2/3)**: KBO 은퇴선수 detail 페이지에 bio 풀세트(생년월일/신장체중/투타/포지션/경력) + 수상/드래프트 URL 확인. 트랙A 콘텐츠 축소 불요, 위키 대체소스 불요. statiz 드롭해도 트랙A 생존.

### 진행 체크리스트 (트리거가 여기 따라 진행)
- [x] 브레인스톰: 트랙/단계/견적 합의
- [x] 스파이크: KBO 1군기록(1982~) + 퓨처스(2010~) 구조 확인, statiz 불법 판정·드롭
- [x] **스파이크2**: KBO detail 페이지 은퇴선수 bio ✅존재(양준혁 검증) — 트랙A 생존, #4 해소
- [x] **스파이크3**: 수상(History/Etc·Player/Awards) + 드래프트(draft.koreabaseball.com) URL ✅확인 (구조 selenium서)
- [x] **스파이크4 (실측 종결 2026-06-15d)**: 서버 curl 실측 → naver stat api = **2007~만**(2006=count0, 2007부터 데이터). 역대 1982~2006은 naver 불가 → **KBO 단일 spine 확정**(id space 하나=kbo_player_id, 브릿지 불요). naver는 라이브/현역 파이프 전용 유지
- [x] ⏸️ **설계 게이트** (2026-06-15 사용자 결정): **#1 스키마=별도 역대테이블**(`historical_players`+`historical_season_stats`, 현 players 무손상, 앱 active∪historical 병합조회) / **#2 동명이인키=`kbo_player_id` UNIQUE 정규키**(naver_player_id=라이브보조, 이름조인 전면폐기) / **#3=단계적 착수**(구단계보 1단계만 하고 재평가)
- [x] 구단계보/팀역사 테이블 설계+시드 (2026-06-15): `team_franchises` 22행 시드, 프로덕션 적용·검증 완료
- [x] 트랙A코어 크롤러 (2026-06-15~16) **완료**: 통산/bio/수상/franchise/PS/세이버FIP 전부 빌드+검증. 정합: 이승엽467HR·MVP×44·2005KS 삼성vs두산·선동열 1993 FIP0.52(전체최저). FIP=1003행(avg3.57). PS 배치 백그라운드 완주중(`/tmp/hist_ps.log`). WAR/wOBA/wRC+=infeasible(미계산).
- [x] ~~트랙A코어 (구 상세)~~: **통산스탯 ✅**(`historical_crawler.py` Basic1+Basic2, **1982~2025 배치 실행중** nohup `/tmp/hist_crawl.log`) · **신상bio ✅**(`enrich_bio` detail div.player_info, 손민한 검증) · **franchise링크 ✅**(`link_franchises` 919/919, 백인천→LG) · **수상 ✅**(`enrich_awards` detail `Award.aspx` — ⚠️per-player Award는 서버 도달 OK(aggregation History만 차단), 손민한 2005 MVP+골글 검증). **⚠️배치 완료 후 runbook**: `python3 -m crawler.historical_crawler link` → `bio` → `awards`(전부 재실행안전). 잔여: **PS**(✅소스확정 = Basic1 `ddlSeries` 드롭다운 0정규/4와일드카드/3준PO/5PO/7한국시리즈 → **같은 크롤러+series param**, 스키마에 series_type 컬럼+UNIQUE 추가 필요, 배치후 빌드) · **세이버**(war=infeasible / fip=시즌집계로 계산가능, woba/wrc+=리그가중치 근사 필요 / babip·iso 등은 현 스키마에 컬럼 없음) · 비규정선수 완전성(KBO=규정자만, `ddlTeam` 팀필터가 우회 가능성). ※**trackB 스플릿 소스도 발견**: Basic1 `ddlSituation`(월별/구장별/홈방문/상대팀별/주야/전후반)
- [x] 트랙C1 (2026-06-16): **2군(부상≠강등) 구분 완료·배포**. `crawl_active_futures`(futures/player/register.aspx, 1군과 동일구조 `_crawl_register_page` 공유, 255명/10팀) + `classify_roster_diff` futures_registered 인자(2군 등록=positive→'2군' 즉시판정, 어느군도 없음=등록말소 stale가드, 2군크롤실패=폴백) + sync 통합('2군 강등(자동)' reason). roster_diff 테스트 10종 PASS, sync 라이브 123건(KT 이채호 등 2군 정합), scheduler 배포+smoke ALL PASS. ⚠️새 change_type='2군'도 reason '(자동)'이라 news surface 제외·선수상세 배지만 노출(도배방지 정책 준수). 2군 시즌스탯(historical)은 C2.
- [x] 트랙B (2026-06-16, 스플릿만): **박스역대→모델 = 저ROI 스킵**(야구 천장 .854/.52, CLAUDE.md 명시 — 9시즌 크롤 대비 AUC 거의 안 움직임). **스플릿 기본축 v1 완료**: `historical_splits`(타자 홈원정/상대팀/월별, ddlSituation+Detail 이중드롭 동적순회) — 2025 적재(2250행)+2023~2024 배치, slg=구성요소 계산(양의지 홈 .336/.512 검증). ⚠️v1 한계: 분할값당 ~80% 커버(KBO 분할뷰 표시필터/페이지 — 일부 스타 한 분할 누락), 투수/OPS·OBP(BB 미수집)·역대전체=후속(세밀축 장기). UI(선수상세 스플릿 테이블)=별도 기능작업.
- [x] 트랙A꼬리 (2026-06-16): **드래프트 ✅** = detail '지명순위'(예 손민한 '97 롯데 1차') → `draft_info` 컬럼, bio enrich 통합, 전체 재크롤중(`/tmp/hist_draft.log`, ~30min). **연봉 = 보류**(합법성 회색, 공시/언론뿐). draft.koreabaseball.com 별도크롤 불요(detail에 있음).
- [x] 검증 (2026-06-16): 라이브 스팟체크(이승엽 467HR·MVP×44·선동열 FIP0.52·백인천.412·양의지/김도영 스플릿·손민한 draft) + pytest 15종(test_historical_parse 5: _parse_ip/_parse_bio/draft + test_roster_diff 10: C1 2군구분). 전부 PASS.
- [ ] (장기 큐) 트랙C2 퓨처스 경기단위 / 스플릿 세밀축

### 진행로그
- 2026-06-15: 착수. 브레인스톰 완료(3트랙+C1/C2 분할). 스파이크1 완료 — statiz 서버렌더지만 **크롤 불법 판정→드롭**. KBO 1군 1982~2026·퓨처스 2010~2026 postback 확인. 트리거 프로토콜·이 섹션 신설. 다음=스파이크2(KBO bio).
- 2026-06-16g: **역대수집 핵심 완료**. 트랙A꼬리 드래프트(`draft_info`='지명순위', detail서 추출, 연봉=보류) + 검증(pytest 15 PASS: 파서+roster_diff, 라이브 스팟체크). 체크리스트 A/C1/B/꼬리/검증 전부 [x], 남은 건 C2(퓨처스 경기단위/스플릿 세밀축)=장기 큐 보류(설계대로). draft bio 재크롤 ~30min 완주중(`/tmp/hist_draft.log`). **데이터 깊이 적재 종료** — 다음 가치=UI 노출(앱/API, 별도 기능작업).
- 2026-06-16f: **트랙B 스플릿 v1 완료**(모델=저ROI 스킵 결정). `historical_splits` 스키마+`crawl_splits_season`(ddlSituation 축 + ddlSituationDetail 값 동적순회, 타자 Basic1 코어). FK 위반(스플릿엔 비규정선수 등장)→INSERT전 `_upsert_player` 픽스. slg는 분할뷰에 TB컬럼 없어 구성요소(H+2B+2*3B+3*HR)/AB 계산+백필(4496행). 2025 검증(양의지 홈 .336/.512), 2023~2024 배치(PID 246262, `/tmp/hist_splits.log`). ⚠️분할값당 첫값 150/나머지 120 = ~80% 커버(KBO 표시필터 추정, 일부 누락) — v1 수용, 정밀화 후속. 2023~2025 배치 완료(6750행, ~235선수/시즌) + slg 백필 완료(~99.9% AB>0, 김도영2024 홈 .339/.591 검증). **역대수집 주요트랙(A/C1/B) 전부 일단락**. 남은=PS완성(low-pri)·세밀축/투수스플릿/트랙A꼬리draft(장기)·**UI노출(앱/API — 별도 기능작업)**.
- 2026-06-16e: PS 배치 종료(부분) + trackB 스플릿 제약 발견. **PS**: 최적화본도 sleep-bound(~9s/page-sweep×8/season)라 glacial(kill 시 1984에 머묾) → kill. 현재 PS 적재=부분(한국시리즈 13시즌/PO 10/준PO 7, 주로 ~2005, 2006~ 결손). **low-priority라 부분 수용**, crawler 유휴 시 재개 가능(`ps 2006 2025`). **trackB 스플릿 제약**: ddlSituation은 situation1(축)+situation2(값) 이중드롭(홈/방문 등), split당 1크롤 → 전체 역대 스플릿(7축×값×44시즌×타투) = **비현실적(수일)**. 기본축=바운드 필수(현/최근시즌·홈원정/상대팀/월별). 좌우투 핸디드니스는 ddlSituation에 없음(별도). 스키마는 스코프 확정 후. 다음=스플릿 스코프 결정.
- 2026-06-16d: **트랙C1 완료·배포** (부상≠2군 구분). 기존 roster_diff 한계(1군 부재=무조건 '등록말소'라 강등·부상 혼동) 해결 = 2군 등록현황(`futures/player/register.aspx`, 1군과 구조동일) 크롤해 positive 증거로 '2군' 판정. classify_roster_diff에 futures_registered(2군 등록=즉시 '2군', 부재+stale=등록말소, 크롤실패=종전폴백) — 테스트 10 PASS. sync_active_roster 통합('2군 강등(자동)'), 라이브 123건 동기화(KT 이채호/문상철 등 2군 정합), scheduler 배포+smoke ALL PASS. ⚠️'2군' change_type도 '(자동)'이라 news surface 제외, 선수상세 배지만. historical 2군 시즌스탯=C2(장기). 다음 트랙=B(모델) 미착수. PS 배치 계속.
- 2026-06-16c: PS 크롤 드라이버 재사용 최적화(시즌당 8→1 startup, crawl_*_season에 driver 주입). 구 PS배치 kill→최적화 재가동(`/tmp/hist_ps2.log`, ps 1982~2025, ON CONFLICT 재개). ⚠️실 병목=per-page sleep(~64s/season)이라 ~2.6배만 빨라짐(~40min). ⚠️다음트리거=`/tmp/hist_ps2.log`(ps2). PS는 low-priority tail — trackA 핵심은 이미 완료.
- 2026-06-16b: 세이버 FIP 완료 → **트랙A코어 100% 종료**. `recompute_fip()`(시즌 리그상수 cFIP + per-pitcher, IP 6.1=6⅓변환, 정규만) → 1003행, avg3.57 범위0.52~6.20. 검증=선동열 1993 ERA0.78/FIP0.52(전체최저)·1986 0.99/0.91. WAR/wOBA/wRC+=infeasible(데이터/모델 한계, 미계산). 다음 트랙(C1 2군 / B 모델)은 미정=사용자 선택 대기(트랙 경계). PS 배치 계속 완주중.
- 2026-06-16: 트랙A코어 완료(데이터 적재+검증) + PS 빌드. **enrichment 완료**: bio 838/838(크래시fix 후 재실행 성공)·awards 541건/208명(MVP 정확히 44=44시즌×1, 골글 포지션별 44 정합)·franchise링크 919→전체. **정합검증**: career HR 이승엽467(정확)·최정432·최형우419 / W 송진우185·양현종168·선동열133 / debut·final 정확 / bio NULL 0(throws만 24결손). ⚠️career 합이 일부 실제보다 약간 낮음=KBO 규정자만 노출 한계(이승엽은 항상규정→정확). **PS 빌드**: series_type 컬럼(정규/와일드카드/준PO/PO/한국시리즈), ddlSeries param, 2005KS 검증(삼성vs두산 4G 정합), 1982~2025 PS 배치 실행중(PID 219812, `/tmp/hist_ps.log`, ~2hr, 단명드라이버라 crash내성). 다음=세이버 FIP(선택) or 트랙C1(콜업/2군). ⚠️다음트리거=`/tmp/hist_ps.log` 확인.
- 2026-06-15i: 시즌배치 완료(44시즌/838선수/2815행) + link 완료(1961행). **bio 드라이버 크래시 발견·수정**: 단일 드라이버가 ~327명서 chromium 사망(Connection refused) → bio 327/838 중단. `enrich_bio`/`enrich_awards`에 **70명마다 드라이버 재생성 + 예외 시 respawn 1회 재시도** 추가 → 재실행 검증(327→389/100s, 오류0). **재실행 오케스트레이터 가동**(bio→awards, `/tmp/hist_post2.sh`→`/tmp/hist_post2.log`, ~35min). ⚠️**다음 트리거 = `/tmp/hist_post2.log` "ALL DONE" 확인** → 완료면 정합검증+**PS 빌드(ddlSeries)**+**saber FIP**. ⚠️pkill -f "crawler..." 금지(자기 ssh 셸 매칭 자살, 255) — kill -0 PID로 체크.
- 2026-06-15h: 배치후 enrichment **자동 오케스트레이터 가동**(detached PID, `/tmp/hist_post.sh`→`/tmp/hist_post.log`): 시즌배치(`1982 2025`) 종료 대기 후 link→bio→awards 순차 자동실행(동시크롤 회피).
- 2026-06-15g: PS 소스 확정 + trackB 스플릿 소스 발견(recon). KBO Basic1에 `ddlSeries`(0정규/1시범/4와일드카드/3준PO/5PO/7한국시리즈) → **PS=같은 크롤러+series param**(detail 탭엔 PS 없었으나 리스트 series 드롭이 답). `ddlSituation`(월별/요일별/구장별/홈방문/상대팀별/주야/전후반)=trackB 스플릿축. `ddlTeam`(팀필터)=비규정 완전성 우회 후보. PS 빌드=배치후(series_type 컬럼+UNIQUE 변경 + 크롤). 배치 34/44 진행중.
- 2026-06-15f: 수상(awards) 서버사이드 해결. **핵심 발견**: aggregation History/Award 페이지는 서버 IP 차단이나 **per-player detail `{Hitter,Pitcher}Detail/Award.aspx?playerId=`는 도달 OK** → 로컬PC 불요. `historical_awards` 테이블 + `enrich_awards`(table 연도|수상 파싱) → 손민한 2005 MVP+골든글러브 검증. 배치후 runbook = link→bio→awards. PS는 detail 탭에 없어 소스 미확인(별도 조사). 배치 23/44 진행중.
- 2026-06-15e: 트랙A코어 bio+franchise링크 완료. **bio enrichment**(`enrich_bio`): detail `div.player_info ul li` 파싱(생년월일/신장체중/투타분해 '외야수(좌투좌타)'/경력) → 손민한 검증(1975-01-02·180/85·우우·대연초~NC). **franchise 링크**(`link_franchises` 순수SQL, 재실행안전): 시즌행 team_name(MBC/OB/현대..)→team_franchises era매칭(시즌범위 구분)+debut/final+대표팀(최다출전 현존구단). 919/919 링크·0 미연결·백인천1982 MBC청룡→LG 검증. ⚠️세이버/수상/PS 잔여(수상·PS=서버IP aggregation 차단→로컬). 배치완료 후 link·bio 재실행 runbook 기록.
- 2026-06-15d: 트랙A코어 통산스탯 크롤러 완료(배치 진행중). **스파이크4 실측 종결**: naver stat api = **2007~만**(2006=0, 2007✅) → 역대는 KBO 단일 spine 확정. **스키마 적용**: historical_players+historical_season_stats 프로덕션 생성. **크롤러**: `historical_crawler.py` — KBO `{Hitter,Pitcher}Basic/Basic1·Basic2.aspx`(⚠️ `Basic.aspx`(no"1")는 에러페이지 — `Basic1`/`Basic2`가 실 리스트, repo kbo_daily_crawler 패턴), ddlSeason 1982~9999, 선수명 앵커 `/Record/Retire/...playerId=` 추출=kbo_player_id. ⚠️**서버 IP는 detail+list("Basic1")만 도달, Main/search/History/PlayerPrize 등 aggregation은 에러**(WebFetch도 동일 — JS세션 필요. 단 우리 용도엔 Basic1으로 충분). ⚠️KBO 리스트=**규정충족자만**(2005 타43/투15, 비규정은 미노출 — 완전성은 후속 과제). **버그수정**: 1페이지 시즌서 `//a[.="2"]` 스트레이 클릭→18열 이종테이블 로드→ON CONFLICT 정상행 덮어씀(손민한 W18→0) → headers 열수 가드+(선수,팀)dedup+새행0종료. 검증=이병규2005(.337/9HR/.843)·손민한2005(18W/168.1IP)·백인천1982(.412)·박철순1982(24W/1.84). 1982~2025 배치 nohup 실행중(PID 185718). 다음=bio/수상/PS enrichment.
- 2026-06-15c: 구단계보 단계 완료. `team_franchises`(current_team_id NULL=단절, team_name/code/start_year/end_year/is_continuous/note, UNIQUE(team_name,start_year)) 마이그레이션+22행 시드 → 프로덕션 적용·검증(17 mapped/5 defunct). 개명·인수=현구단 연속, 현대(삼미→청보→태평양→현대)·쌍방울=KBO 관례대로 단절. 다음=트랙A코어 크롤러(#3 재평가 지점, GO 확인 후).
- 2026-06-15b: 스파이크2/3/4 일괄. **스파이크2 ✅**: KBO `Record/Player/HitterDetail/Basic.aspx?playerId=` 은퇴선수(양준혁) detail에 bio 풀세트(생년월일/신장체중/투타/포지션/경력출신교) 렌더 확인 → 트랙A 콘텐츠 생존, #4 해소. **스파이크3 ✅**: 수상=`History/Etc/PlayerPrize·GoldenGlove.aspx`+`Player/Awards/*`, 드래프트=`draft.koreabaseball.com`(별 subdomain) URL 확인(WebFetch는 KBO list/history 에러라 구조 검증은 selenium impl서). **스파이크4 [~]**: naver api `{season}` free-form 확인하나 실측 깊이는 이 환경서 미측정(WebFetch api-gw 차단) → impl서 curl 1줄. 다음=⏸️ 설계 게이트(스키마#1·동명이인키#2·우선순위#3 사용자 결정).

### 📦 현재 데이터 스냅샷 (2026-06-16 — UI/C2 세션 참조용)
적재 완료 (프로덕션 DB, 크롤러=`backend/crawler/historical_crawler.py` 서브커맨드 `<시즌범위>`/`bio`/`awards`/`link`/`fip`/`ps`/`splits`):
- `team_franchises` 22행 — 구단계보 (current_team_id NULL=해체구단 삼미/청보/태평양/현대/쌍방울)
- `historical_players` ~1100명 — **kbo_player_id 정규키** + bio/throws/bats/position/career/draft_info/debut_year/final_year/primary_team_id + naver_player_id·player_id 브릿지 (838 규정 + ~262 스플릿추가분 bio 보강중)
- `historical_season_stats` ~2880 정규행 + PS 부분 — series_type(정규/와일드카드/준PO/PO/한국시리즈), UNIQUE(kbo_player_id,season,team_name,series_type), FIP 1003행
- `historical_awards` 541건/208명 — MVP/골글/타이틀 (연도|수상)
- `historical_splits` 6750행 — 2023~2025 타자 기본축(홈원정/상대팀/월별), avg/slg
- 앱 노출 정책(설계 확정): **active(players) ∪ historical_players 병합조회, kbo_player_id 정규키, 이름조인 폐기**
- ⚠️ 잔여: PS 2006~ 결손(low-pri, `ps 2006 2025` 재개) / 스플릿 분할값당 ~80%커버 / 투수스플릿·OPS·세밀축 미수집 / WAR·wOBA·wRC+ infeasible

## 역대 데이터 UI 노출 (앱/API) — ✅ 완료 (2026-06-16, P1~P4 배포·live검증)
### ⚡ 트리거: 사용자가 **`역대UI 진행`** 입력 시 = 이 섹션 재개.
- **동작**: 역대수집과 동일 프로토콜 — 첫 `[ ]` 실행 → `[x]`+진행로그 → 연속, ⏸️게이트서 멈춤/질문. 각 단계 끝 CLAUDE.md 갱신.
- **목적**: 적재된 역대 데이터(위 스냅샷)를 앱/웹서 노출 = 올드팬 자산·비시즌 DAU. **데이터 준비됨 → 크롤 불요, 순수 백엔드+프론트라 PS/크롤 충돌 없음**(역대수집/C2와 독립 진행 가능).
### 진행 체크리스트
- [x] 브레인스톰/스파이크: 노출 범위·진입점 + 구조 파악 (2026-06-16) — players.py(검색/상세=players만, 역대 API 없음=그린필드)·player_screen(검색 탭2)·player_detail_screen(시즌칩=stats 기반) 파악. historical_* 스키마 4종 확인(series_type DEFAULT '정규', player_id 현역 브릿지, draft_info TEXT)
- [x] ⏸️ 설계 게이트 통과 (2026-06-16 사용자 결정): **범위=풀**(현역통산+은퇴검색/상세+스플릿+역대탭) / **검색=통합**(/players/search가 현역+은퇴 반환) / **은퇴상세=신규화면**(historical_player_detail_screen) / **검색키=kbo_player_id**(수집게이트 기확정) / 동명이인=primary_team+debut~final 구분. 스펙=`docs/superpowers/specs/2026-06-16-historical-data-ui-design.md`
- [x] API (2026-06-16, P1 배포+live검증): 신규 `api/routers/historical.py` — `GET /historical/{kbo_player_id}`(bio/통산집계/시즌별/PS/수상/스플릿/franchise, @cached 600) + `GET /historical/leaders`(통산 명예의전당, /{id}보다 먼저 선언, @cached 3600). 기존 `/players/search` UNION(historical_players 브릿지없는 은퇴만, key_type/is_historical/years 부여) + `/players/{id}` 머지(현역 브릿지 시 series_type='정규' AND season<2024 역대시즌+수상, 키매핑 walks_allowed→walks). 헬퍼 `_aggregate_career`/`_ip_to_outs`(순수테스트 3종 local PASS). **live: 이승엽 career HR 467·시즌15·수상15, leaders HR=467 top, search key_type=historical 정합**. ⚠️ local py(3.14)는 backend deps 없음 → 모듈테스트는 서버/CI
- [x] 앱 (2026-06-16, P2~P4, analyze lib=0): `api_service` getHistoricalPlayer/getHistoricalLeaders · `player_screen` 통합검색 '역대' 배지+활동연도+라우팅분기(is_historical→은퇴상세)+_numAvatar 이름폴백+헤더 '역대 기록실' 진입 · 신규 `historical_player_detail_screen`(bio/통산/시즌별표/PS/수상/스플릿/franchise, 라이브섹션 없음=이미지 미사용이라 웹규칙 무관) · 신규 `historical_leaders_screen`(명예의전당 카테고리칩+TOP25) · 현역 `player_detail_screen` 수상 섹션 머지. 토큰 교정(Pal.paper·BorderRadius.circular(Radii)·Typo.regular)
- [x] 웹 동반 빌드+배포 (2026-06-16): wasm 재빌드 → rsync `/var/www/playball_web/`, `/app/` 200. live검증 = 이승엽 career HR 467·선동열 search historical 1985~1993·leaders 승 송진우 185 정합. 골든 회귀 통과.
### 진행로그
- 2026-06-16: 착수. 브레인스톰+구조파악 완료(players.py/player_screen/player_detail_screen + historical_* 4스키마). 설계 게이트 통과(범위=풀·검색통합·은퇴상세신규·kbo_player_id키). 설계 스펙 작성+셀프리뷰(series_type='정규' 머지필터·컬럼키매핑 정정) → `docs/superpowers/specs/2026-06-16-historical-data-ui-design.md`. **유저 스펙 승인** → 구현플랜 작성+셀프리뷰 완료 → `docs/superpowers/plans/2026-06-16-historical-data-ui.md`(Task1~10, P1 backend TDD → P2 현역통산 → P3 은퇴상세 → P4 역대탭). 플랜 실행(인라인) → **P1~P4 전부 완료·배포**.
- 2026-06-16b: **역대UI 전체 완료**. P1 백엔드(historical.py 상세+leaders·/search UNION·/{id} 머지, series_type='정규'·키매핑, 헬퍼 순수테스트 local PASS) 배포+live(이승엽 467HR·leaders·search 정합). P2~P4 앱(통합검색 '역대'배지+라우팅·신규 historical_player_detail_screen·신규 historical_leaders_screen 명예의전당·현역상세 수상섹션, analyze lib=0). 웹 wasm 재빌드+rsync(`/app/` 200), 골든 4 PASS. ⚠️**네이티브 APK 미반영**(웹+서버만 — 기존 관행). 잔여=역대선수 인기투표/비교/공유=비목표(추후), PS 2006~ 결손(데이터).
- 2026-06-16c (후속 — 유저 피드백 3건): ① **현역상세 24시즌까지만 버그 = player_id 브릿지=0** (크롤러가 미설정). (이름+생일) 매칭으로 **277명 브릿지 복구**(동명이인 생일로 분리 — 양현종 KIA투수 1988 vs 키움내야수 2006) + `link_franchises`에 영속화. 양현종 상세 2024→**2009~2026 전체+수상(MVP·골글)** 라이브. ② **역대 기록실 = 선수스크린 헤더버튼 → 팀스크린 탭으로 이동**: 탭 재배치 팀순위/팀기록/부문별순위/**역대기록실**(length4, isScrollable), **`PlayerRankingsTab(historical:true)` 동일위젯 재사용**(포디엄/칩/순위행 UI 동일)+신규 `/historical/rankings` 번들. historical_leaders_screen.dart 삭제. 웹 재빌드+배포. ③ **데이터 한계 규명+해결**: KBO 기록=규정충족자만(시즌~60~70명) → 마무리(오승환 0행)·비규정·루키 누락, leaders 현역 과소(최정 432). **ddlTeam 팀필터가 비규정 노출 확정**(KIA필터=30명 전원 비규정포함). `allteams` 크롤(시즌×10팀) 빌드+검증(2024: 76→483행). **1982~2025 전체배치 가동중**(`/tmp/hist_allteams.log`, ~3hr, nohup PID 275699). ⚠️**배치 완료 후 runbook**: `link`(신규 비규정 현역 브릿지) → `fip`(recompute) → leaders/career 정확도↑. ⚠️해체구단(삼미/현대/쌍방울) 비규정은 ddlTeam 부재라 미수집(규정자는 기존 적재분 有). ⚠️현역 current시즌(2024~26)은 batter_stats에 있고 historical leaders엔 미합산 = 잔여(별도).
- 2026-06-17 (비규정 배치 완료 + 정확도 마감): **비규정 전체배치 완료** — 1985~2025 40/41시즌 확장(풀 로스터), `historical_season_stats` 정규행 ~2880 → **14566** (~5배). **현역 current 합산**(`_leader_query` = historical + batter/pitcher_stats UNION, NOT EXISTS 멱등) → leaders 활성선수 보정. **runbook 수동**(워처 `pgrep -f allteams_batch.sh`가 **자기 명령줄 자매칭**해 무한대기 버그 → 수동): `link`(franchise 13143·debut/final·브릿지277) + `fip`(5029행). ⚠️**player_type 오염 발견·수정**: KBO 타자 팀필터 페이지에 투수도 등장 → hitter crawl '타자' 선INSERT + ON CONFLICT player_type 미갱신 → 투수 시즌행 1570개 '타자' 오염(오승환 세이브 161 누락). **historical_players 권위값 정규화 UPDATE**(라이브 1570행 + `link_franchises`에 영속화 step5). **최종검증 라이브: 최정 통산 HR 534 #1(historical 20시즌495+현역39)·오승환 세이브 427 #1·송진우 승201**. ⚠️신규 비규정 선수 bio(birth_date) 미적재 → 그들 현역브릿지/검색은 `bio` enrich 필요(미실행, 별도 — 단 기존 현역스타 통산은 kbo_id 귀속이라 무관). ⚠️해체구단 비규정 여전 미수집(ddlTeam 부재).

## 역대 C2 (퓨처스 경기단위 · 스플릿 세밀축) — 장기 큐, 트리거 대기 (미착수)
### ⚡ 트리거: 사용자가 **`역대C2 진행`** 입력 시 = 이 섹션 재개.
- **동작**: 동일 프로토콜.
- **목적/스코프**: ① 퓨처스(2군) 경기단위·일정·박스 = 사실상 2군 리그 풀 파이프라인 ② 스플릿 세밀축(7축 전체×역대시즌·투수스플릿·OPS/OBP)
- ⚠️ **무거움·니치·일부 비현실**: KBO 크롤 sleep-bound(~9s/page-sweep) → 역대 전체 스플릿/2군 경기단위 = **수일~**. 착수 전 스코프 강하게 바운드 필수. 니치(2군 게임데이터=좁은 수요). **UI 노출보다 후순위 권장.**
### 진행 체크리스트
- [ ] 스파이크: 퓨처스 경기일정/박스 소스(`futures/schedule/FuturesList.aspx`, futures relay 유무) + 비용 산정
- [ ] ⏸️ 게이트: 스코프 결정(2군 시즌스탯 역대화? 경기단위? 스플릿 어느 축/시즌?) — 비현실 구간 배제
- [ ] (스코프 확정분) 크롤러+스키마+적재
- [ ] 스플릿 세밀축(투수/추가축/OPS, 바운드 내)
- [ ] 검증
### 진행로그
- (미착수 — `역대C2 진행`으로 시작)

## 선수/팀 상세 콘텐츠 확장 — 트리거 대기 (미착수, 2026-06-17 브레인스톰)
### ⚡ 트리거: 사용자가 **`상세확장 진행`** 입력 시 = 이 섹션 재개.
- **동작**: 역대UI와 동일 프로토콜 — 첫 `[ ]` 실행 → `[x]`+진행로그 → 연속, ⏸️게이트서 멈춤/질문. 각 단계 끝 CLAUDE.md 갱신.
- **목적**: 적재된 데이터로 선수/팀 상세 깊이 강화(올드팬 자산). **대부분 크롤 불요 = 보유 데이터 계산/노출**(역대 14566행·수상·스플릿·franchise·plate_appearances).
- **기존 화면**: `player_detail_screen`(현역, 히어로/핵심/그리드/트렌드/구종/존/시즌칩/수상) · `historical_player_detail_screen`(은퇴, bio/통산/시즌별/PS/수상/스플릿/franchise) · `team_detail_screen`(최근경기/월별·상대전적/팀리더/선수목록/로스터변경/PS확률). API = `api/routers/{players,teams,historical}.py`.
### 후보 (⭐=크롤0·즉시, 데이터 보유)
**선수 상세**:
- ⭐ **타이틀 이력**(홈런왕/타격왕/다승왕/평자책왕 등 시즌 부문1위 횟수) — `historical_season_stats`서 계산. "홈런왕 3회" 배지. 高가성비.
- ⭐ **통산 타임라인 / 팀 변천** — 시즌별 team_name 有 → "SK→SSG" 이적사·데뷔~은퇴 연표.
- ⭐ **마일스톤** — 통산 500홈런·2000안타·300승 달성 표시 + 다음 마일스톤 ETA(시즌페이스).
- **홈원정·상대팀 스플릿** — `historical_splits` 有(단 2023~25 타자만 → 투수/역대 확장 필요).
- **포스트시즌 통산** — 현역상세 추가(은퇴상세엔 有, PS데이터 부분 2006~결손).
- **클러치/WPA** — `plate_appearances` win_rate 有(현역 3시즌 한정).
**팀 상세**:
- ⭐ **구단 약사/계보 카드** — `team_franchises` 有(옛구단명·개명/인수/해체 note). "OB베어스 1982→두산 1999~".
- ⭐ **구단 역대 레전드** — franchise 소속 역대 선수 통산 리더(historical + 계보 매핑).
- ⭐ **역대 팀 시즌기록** — 14566행 팀별 집계(역대 최다승 시즌 등).
- **시즌별 순위 추이** — games 승패서 도출.
**크롤/소스 필요(별도, 비목표 후보)**: ❌우승이력(한국시리즈 — KBO/정적JSON) ❌연봉 ❌부상이력 ❌올스타/월간MVP ❌타이틀 중 비스탯(수비상 등)
### 진행 체크리스트
- [ ] 브레인스톰/스파이크: 후보 우선순위 확정 + 진입점·표시방식 (기존 3화면 구조 파악)
- [ ] ⏸️ 설계 게이트: 어느 항목 넣을지·UI 배치 (사용자 확인)
- [ ] API: 선정 항목 엔드포인트 (타이틀=계산·팀변천·마일스톤·구단약사·역대레전드 등, @cached)
- [ ] 앱: 선수상세 + 팀상세 섹션 추가 — ⚠️웹이미지 3규칙·netImage·토큰(Typo/Pal/Radii/Space) 준수
- [ ] 웹 동반 빌드+배포 + 검증·analyze lib=0
### 1차 추천 (크롤0)
선수 = 타이틀이력 + 팀변천 타임라인 · 팀 = 구단약사 + 역대레전드. 전부 보유 데이터.
### 진행로그
- (미착수 — `상세확장 진행`으로 시작)

## 해야할 것
### AI 경기 한줄평 알림 (2026-06-14 요청) — ✅ 구현완료 (06-15 메가E, 아래는 원 요청 기록)
- 구현: 템플릿 기반(`api/narrative.py`), game_summary 본문 교체(별도 푸시·토글 신설 안 함), game_reviews 영속. LLM 업그레이드는 엔진 인터페이스만 교체하면 됨. 잔여 = 추후 LLM/3줄요약/다이제스트(메가E2)
- **목표**: 경기 종료 시 경기 상황·결과를 분석해 **AI 한줄평**을 생성, 알림으로 전송 (마이팀/관심경기 대상)
- **트리거**: scheduler 종료 후처리(`post_finished_done` 블록, game_summary 발송 지점과 동일) — game_summary 보강 형태
- **입력 데이터(전부 보유)**: 최종 스코어·이닝별 득점, 승/패/세이브 투수, 결정적 타석(WPA 최대 — plate_appearances.win_rate_before/after), 역전/끝내기 여부(game_event_stream walkoff/extra_innings), 최다 안타·홈런·타점 선수(game_batters), 선발 QS 여부, 클러치 순간(clutch_moment)
- **생성 방식 2안**: ① **템플릿 기반**(LLM 없이 — WPA 최대 타석+스코어로 규칙 조립, 비용 0, 아침브리핑 패턴 재사용) ② **Claude API**(claude-haiku-4-5 등 저비용 — 자연스러움↑, 매일 5경기 소액). 1차 템플릿 → 추후 LLM 업그레이드 (브리핑/3줄요약과 콘텐츠 파이프 공유 — 변경이력 시너지번들 9)
- **전송**: 푸시GW(`fcm_service._send`) 경유 — quiet hours/채널 라우팅 자동. ntype = `ai_review`(또는 game_summary 흡수). 알림 설정 토글 1개 신설(daily_briefing 류) + notification_log dedup(`game_id, 'ai_review'`)
- **표시**: 인앱 알림함 저장 + (옵션)경기 상세 상단 한줄평 배지. 라이트팬 진입장벽↓ 자산(경기 3줄 요약·다이제스트와 연결)

### 관리자 콘솔 확장 백로그 (2026-06-13 추천)
- **1순위 묶음 (app_config 편집 — 한 세션감)**: ① 공지 배너 작성/해제 UI ② min_version/latest_version 강제업데이트 설정 ③ 공지 푸시 발송(전체/팀별, 확인 다이얼로그)
- **사용자 추이**: DAU/WAU/MAU — 측정 인프라부터 필요: API 미들웨어서 인증 유저 (user_id, date) 일별 upsert(daily_active_users 테이블, 메모리 set+주기 flush로 경량) + 가입 추이(users.created_at 기존) + 콘솔 그래프 탭
- 운영: 서버 상태 패널(스케줄러 하트비트·최근 에러·크롤 성공여부 — 등록말소 크롤 사고 류 콘솔 인지)·포인트 수동 지급(reason=admin)·댓글 검색/삭제·인스타 핸들 즉석 수정·시즌 단계 전환(season_phase)·알림 발송 내역 뷰어(CS 디버깅)
- 분석: 기능 사용률(예측 참여/직관기록 수)·인기 게시글·팀별 팬 분포·알림 발송량 추이
- 도구: 유저 상세(활동 이력+포인트+기기)·계정 정지(현재 삭제만)·크롤 수동 재실행 버튼·경기 데이터 무결성 체크·admin 접근로그 뷰어(security_log 기보유)·백업 최근 시각 표시

### UI/UX 추천 백로그 (2026-06-13 큐레이션 — 구현비용 대비 체감순)
- **강추 3**: ① 첫 실행 마이팀 선택 플로우(개인화 뿌리 — 홈 풀카드·푸시·캘린더 즉시 개인화) ② 홈 직관 미니 배너("이번 시즌 직관 5승 3패" — 차별 자산 노출, 데이터 보유) ③ 새 중계 항목 amber 페이드인(30s 폴링이 살아있는 중계로 체감)
- 가성비: 선수 초성검색(ㄱㄷㅇ→김도영)·경기 없는 날 마이팀 D-day 카드·필드뷰 풀스크린 토글(작은폰 보완)·예측 마감 카운트다운(포인트 ON 시)·오프라인 배너(connectivity)
- 완성도(출시 직전): AppEmptyView 공용 빈상태·목록→상세 Hero 전환·스낵바 톤 통일

### 즉시 (코드측)
- [ ] **다크모드 육안검증** (⏸️ 사용자 지시로 보류 — 직접 요청 전까지 패스, 2026-06-12): 다크 ~15커밋+메가B/C 신규 UI 헤드리스만 검증된 상태. 골든이 회귀는 방어
- 메가B/C/D 코드측 = ✅ 전부 완료 (06-12 변경이력). 잔여 = 외부작업(아래)과 메가D Play 내부테스트
- [x] **키 회전** (2026-06-09 완료): Gmail·Kakao(JS/네이티브/REST)·DB pw 회전+라이브검증, 옛 Gmail 폐기 확인 (출시 APK는 새 키 재빌드)
### 중기 (코드 품질) — ✅ 2026-06-09 전부 완료 (상세 기록 보존)
- [x] ~~empty catch debugPrint~~(✅ 2026-06-09 빈 `catch(_){}` 52개 → `catch(e){debugPrint('<file>: $e')}` 17파일, game_detail:435 finally형만 제외) / ~~non-null `!` audit~~(✅ 2026-06-09 검토결과 안전·수정불요: `['key']!` 23개=로컬 const map·초기화보장·null체크 storage / `x!.` 94개=`_gameData!` 등 가드 후 idiomatic. crash 버그 없음) / ~~AppErrorView 전면~~(✅ 2026-06-09 6화면 ad-hoc 에러UI→`AppErrorView`(테마인식): team×2·notifications·search·player_stats·pitch_chart·post_detail. 잔여=home(레이아웃 얽힘,brand 적용됨)·team_detail 인라인 retry) / ~~서버 print→logging~~(✅ 2026-06-09 런타임서비스 fcm/weather/email/sms → `api/log_setup.py` 중앙설정+모듈 logger. prediction CLI·scheduler 운영 print는 유지)
- [~] **SemColor.panelDark 감사**(2026-06-09): 80개 분류 — A(라이트잉크 `isDark?light:panelDark` ~40)·A2/A3·B(SnackBar/헤더그라디언트/온보딩 의도)는 **유지**. **Pattern-C 버그**(무조건 panelDark를 fg/fill/border에 → 다크 안 보임) ~22개. 수정완료 6: home OutlinedButton×2·login/register checkbox·phone icon → `SemColor.brand(context)`(다크0xFFE5E5E7/라이트panelDark). **C-fg 수정완료**: home버튼·auth체크박스·phone아이콘 + game_detail TabBar label/indicator(×2)·OutlinedButton → `brand(context)`(analyze clean). **C-fg defer → ✅해소 확인(2026-06-12)**: player_stats 토글=brand+반전 적용됨, player_compare 280=isDark 분기 적용됨, 200=다크 헤더 의도(B). panelDark 감사 전체 종결. **C-bg 결정**(다크 surface=기존 `AppColors.surfaceDark 0xFF18181C/surface2Dark` 재사용, 새 토큰 불요): player_screen 선수/구단 토글(818·836 bg + 825·843 텍스트반전)=✅`brand(context)`+invert. **gd C-bg defer→홀리스틱 다크패스**(헤더3301·avatar3364/3770·TableRow3863/3889): StatelessWidget 헬퍼는 context 없음 + 테이블 border(`0xFFE0E0E4`)·셀 비테마라 단독 fix 불일치. **홀리스틱 착수**: player_compare 테이블/검색카드 테마화 ✅(2026-06-09, State라 `context` 가용·AppColors.surfaceDark/surface2Dark 사용, 헤더는 의도 다크밴드 유지). player_stats ✅(2026-06-09 헤딩/섹션라벨 color 제거→테마 텍스트색 상속, 토글 brand+반전, _buildContent에 context 스레딩). game_detail ✅(2026-06-09 통계테이블 border/헤더row + 로스터헤더(3301) + 타순배지(3364·3770) → 인라인 다크 hex 0xFF1F1F24/26262C, `_tableCell` 데이터셀은 color:null이라 이미 테마구동). **홀리스틱 다크패스 3화면(player_compare·player_stats·game_detail) 완료**. ⚠️**전체 육안검증 미완**(헤드리스 컴파일만) → `flutter run` 다크모드 점검 필수. ⚠️무차별 치환 금지(A/B 다수). / **Radii**: magic `circular(999)`→`Radii.pill` 33곳 ✅(2026-06-09, 5파일). 수치 스케일(4/8/12/16/20)은 off-scale 값(10/13/14 등) 多 혼재 → 부분 토큰화=일관성↓라 점진 보류
- [~] ~~Golden test(다크+라이트)~~(✅ 2026-06-09 인프라 구축: `app/test/golden/` built-in `matchesGoldenFile`, AppErrorView 라이트/다크 PNG 기준 커밋. 갱신=`flutter test --update-goldens test/golden`, 확장=테마인식 위젯 동일 패턴 추가. ※폰트 미로드로 텍스트=tofu box지만 색/레이아웃 회귀엔 충분. 잔여=주요화면 골든 확대) / ~~pre-commit grep hook~~(✅ 2026-06-09 `.githooks/pre-commit`: 음수 letterSpacing WARN + `baseUrl http://` BLOCK. 클론마다 활성화 `git config core.hooksPath .githooks`) / ~~nginx 보안헤더~~(✅ 2026-06-09 HSTS+CSP+Permissions-Policy 등 7종 적용·검증)
- [x] 이닝중계 진행이닝 TTL 30→10s 검토 → **유지 결정**(클라 폴링 30s 고정이라 하향=Naver 부하 3배·UX 이득 0)
### 보안 점검 — ✅ 2026-06-10 전부 완료 (감사: ufw deny-default·fail2ban·SSH 키온리·unattended-upgrades·pip-audit 주간·bcrypt·refresh rotation 확인)
- [x] **업로드 EXIF 제거**: `api/image_utils.py` strip_metadata(Pillow 재인코딩, exif_transpose 선적용=회전보존) — 프로필+게시글 적용
- [x] postgres listen_addresses → localhost (`ALTER SYSTEM` — 범인은 auto.conf의 과거 ALTER SYSTEM '*') / rpcbind disable / 이메일 인증 5회 실패 시 코드 무효화(`phone_verifications.attempts`)
- [x] 백업 오프사이트: `backup_pull.ps1` + schtasks PlayballBackupPull(매일 12:00 트리거, 6일 스로틀=주1 pull, `~/playball_backups/` 4개 보관, 1MB 미만=실패 간주)

### 베타/출시 배포 경로 (2026-06-11 결정)
- **Android 베타 = Firebase App Distribution** (이미 Firebase 연동·Crashlytics 동일 콘솔·완전 무료·Play Console $25 불요·자동 업데이트 알림). release keystore 생성+안전백업 선행(분실=업뎃 불가). 지인 이메일 등록→링크 설치
- **iOS = $99 회피 불가** (Apple 서명 인증서가 Developer Program에 묶임 — TestFlight·App Distribution·Scarlet 모두 그 위. Mac은 Codemagic 무료티어로 회피 가능하나 $99는 별개). 지인 소수 = **웹 PWA 맛보기**(무료·안전), 정식 iOS = $99+Codemagic→TestFlight
- ⭐⭐ **웹 동반 수정 원칙 (2026-06-11, 사용자 지시)**: 앱(Flutter) 수정 시 **웹도 반드시 같이 반영**. 같은 코드베이스라 대부분 자동 동반되나, **재빌드+배포 필요**(`MSYS_NO_PATHCONV=1 flutter build web --wasm --release --base-href "/app/" --no-web-resources-cdn --pwa-strategy=none` → tar→rsync `/var/www/playball_web/`. **06-12 wasm(skwasm) 본판 승격** — nginx /app/에 COOP/COEP 필수, dart:html 플러그인 2종은 local_packages 스텁 override, 미지원 브라우저 자동 JS 폴백. /app2/=실험트랙 잔존). 배포 스크립트화 권장. ⚠️**앱엔 되는데 웹엔 안 되는 변경이면 사용자에게 먼저 고지**. 웹 미지원 영역(`kIsWeb` 분기 필요): 푸시·카카오지도(inappwebview)·갤러리(photo_manager)·이미지공유·캘린더내보내기·secure_storage(→_SafeStore 폴백 완료)·dio IO어댑터(→kIsWeb 가드 완료)·외부이미지(→webSafeImageUrl 프록시 완료). 새 기능이 이 영역 건드리면 웹 폴백 동시 구현 or 고지
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

<!-- FABLIZE:BEGIN — run Opus like Fable (always-on router). Verified procedures only. Install/update: fablize setup.sh -->
## Operating mode (always on — auto-route by task signal)

Apply what the task signals; with no signal, baseline only. Read each pack only when needed. Routing: smallest matching discipline only, overlap only when genuinely multi-category, mimic observable behavior only.

- **[always]** Lead with the outcome · stay within the requested scope (no incidental refactors) · ground completion claims in this session's tool results · confirm before destructive or hard-to-reverse actions.
- **[2+ sequential stories]** Run `python3 C:/Users/qq772/.claude/plugins/cache/fablize/fablize/2.0.0/scripts/goals.py`: create → next → checkpoint (with evidence) → final verification gate (no completion without `--verify-cmd` and `--verify-evidence`). Run from the repo root; state in `./.fablize/` (resume with `status`). Skip for single-step tasks.
- **[debugging / test failure / unknown cause / review]** Follow `C:/Users/qq772/.claude/plugins/cache/fablize/fablize/2.0.0/packs/investigation-protocol.txt`: reproduce first → 3+ competing hypotheses → evidence per hypothesis → full causal chain → verify before/after → report rejected hypotheses.
- **[render/executable artifact: HTML, SVG, game, UI, chart]** Follow `C:/Users/qq772/.claude/plugins/cache/fablize/fablize/2.0.0/packs/verification-grounding-pack.txt` grounding loop: run it in the real renderer → observe the output → fix what you see → re-run. A static check is not observation.
- **[hard or ambiguous task]** Adaptive thinking scales with difficulty automatically. To go higher, recommend `/effort xhigh` to the user. Depth (capability) cannot be raised: if stuck 2+ times or out-of-spec discovery is needed, report the limit honestly and escalate.
<!-- FABLIZE:END -->
