# 1군 등록현황 diff — 부상/이탈 선수 자동 표기 (설계)

작성일: 2026-06-15
상태: 승인됨 (구현 대기)

## 목표
부상·강등으로 1군서 빠졌으나 앱에 정상 active로 남는 선수(예: 문동주 — 방카르트 수술)를
자동 표기. KBO 1군 등록현황(전체 명단)과 DB를 diff해 1군 미등록자에 '등록말소' roster_status
부여 → 앱 배지 노출. 복귀 시 자동 해제.

## 현재 상태 (확인됨)
- KBO에 **부상자명단 전용 페이지 없음**(probe: Register.aspx '부상' 부재). 대신
  `Player/Register.aspx` '구단별 등록현황' = 팀별 **현재 1군 전체 등록명단**(투수/포수/내야/외야 테이블).
- `players.roster_status` 컬럼 **없음**. 앱 roster_status = `get_player_detail`가 player_roster_changes
  최신행(LIMIT 1)서 파생 (players.py:1172). 문동주 = roster_changes 0건 → 배지 없음.
- 기존 부상 캡처(crawl_player_events.crawl_injury_list)는 말소 reason 기반인데 등록말소 reason=포지션 +
  윈도우 미스로 사실상 미작동(부상자명단 8건뿐).
- ⚠️ 새 roster_change insert는 알림 경로(crawl_player_events notify_*) 통해 **푸시 스팸 위험**.

## 범위
1. 1군 등록현황 크롤 (10팀 순회)
2. DB diff → 1군 이탈자 '등록말소' / 복귀자 '1군등록' (player_roster_changes)
3. 알림 스팸 방지 (자동 생성분 푸시 제외)
4. 스케줄러 일일 실행 + 1회 백필
### 범위 외
순수 '부상' vs '2군 강등' 구분(KBO 공개 소스에 부상 라벨 없음 — '1군 미등록' 표기가 최선). is_active
변경(이탈≠방출이라 active 유지, 배지만). 앱 UI 변경(기존 roster_status 배지 재사용).

## 컴포넌트

### 1. 크롤: `crawl_active_rosters() -> dict[int, set[str]]`  (kbo_roster_crawler.py)
- ARM 규칙: **driver = `driver_util.arm_or_wdm_chrome` 경유**(기존 _get_driver가 이를 쓰는지 확인,
  아니면 교체). binary_location 미지정·mkdtemp 프로필.
- Register.aspx 로드 → '구단별 등록현황' 탭 → **팀 선택 UI 순회**(드롭다운/팀 링크 — 셀렉터는 impl서
  probe로 확정). 각 팀: 투수/포수/내야수/외야수 테이블(헤더에 해당 포지션)서 선수명 수집.
  (감독/코치 테이블 제외 — 헤더 '감독'/'코치')
- 반환: {team_id: {선수명, ...}} 현재 1군 등록 집합. 팀명→team_id = 기존 _TEAM_NAME_MAP/_get_team_id_map.
- **실패 가드**: 한 팀이라도 0명이면 그 팀 스킵(diff 제외) — 부분 크롤로 멀쩡한 선수 오말소 방지.

### 2. diff + 동기화: `sync_active_roster()`
- 입력: crawl 결과(team_id → 등록 집합). 성공 팀만 처리.
- 각 성공 팀에 대해:
  - **이탈 감지**: DB players(team_id=팀, is_active=TRUE, **2026 1군 출전기록 있음** = game_batters/pitchers)
    중 이름이 현 등록 집합에 **없고**, 최신 roster_change가 '등록말소' 아니면 →
    `INSERT player_roster_changes(change_type='등록말소', reason='1군 미등록(자동)', change_date=today)`.
    - ⚠️ 2026 1군 출전 가드 = 순수 2군/미debut 선수 오말소 방지(문동주류 = 출전 후 이탈만 대상).
  - **복귀 감지**: 이름이 현 등록 집합에 **있고**, 최신 roster_change가 '등록말소'면 →
    `INSERT(change_type='1군등록', reason='복귀(자동)', change_date=today)`.
- dedup: UNIQUE(player_name, team_id, change_type, change_date) — 같은 날 재실행 안전.
- player_id 매칭 = 기존 `_find_player_id(name, team_id)`.

### 3. 알림 스팸 방지 ⚠️ (필수)
- 자동 생성 roster_change는 reason에 '(자동)' 마커. crawl_player_events의 알림 발송 경로
  (notify_player_transaction/notify_injury_list 등)가 **reason LIKE '%(자동)%' 행을 스킵**하도록 가드 추가.
- (impl 선행: 알림 경로가 player_roster_changes를 어떻게 읽어 발송하는지 확인 후 정확한 스킵 지점 결정)

### 4. 스케줄러
- 기존 roster 크롤 잡(`_update_roster_changes`, UTC 00:30) 뒤에 `sync_active_roster` 추가, 또는
  별도 일일 잡. ARM chromium MemoryMax 고려(기존 스케줄러 유닛).

### 5. 1회 백필
- 배포 후 `sync_active_roster` 1회 수동 실행 → 문동주 등 현 이탈자 일괄 '등록말소' 표기.

## 데이터 흐름
```
[일일] scheduler → crawl_active_rosters(10팀 1군 등록명단) →
  sync_active_roster: DB 1군활동선수 ∖ 등록명단 = 이탈 → '등록말소'(자동) insert
                      등록명단 ∩ 말소표기 = 복귀 → '1군등록'(자동) insert
[앱] get_player_detail roster_status = 최신 roster_change → 배지 노출 (변경 없음)
[알림] notify 경로가 reason '(자동)' 스킵 → 푸시 스팸 없음
```

## 에러 처리
- 크롤 팀 0명 → 해당 팀 diff 스킵(전팀 실패 시 전체 no-op).
- _find_player_id 실패(동명이인/미매칭) → 스킵(해당 선수 미표기, 무해).
- 알림 가드 누락 시 스팸 → impl서 notify 경로 확인 필수(스팸=사고).

## 테스트
- `test_active_roster_diff`(순수 단위): diff 로직 — 등록집합 + DB선수 + 최신상태 입력 → 말소/복귀/무변경
  판정 함수 분리해 테스트(크롤·DB 없이). 오늘 pytest 패턴.
- 서버 1회 실행 → 문동주 roster_status='등록말소' 확인 + 알림 미발송 로그 확인.

## 구현 순서 (writing-plans서 상세)
1. crawl_active_rosters (팀 순회 probe로 셀렉터 확정 → 수집)
2. diff 순수 판정 함수 + test
3. sync_active_roster (insert + dedup)
4. 알림 경로 '(자동)' 스킵 가드
5. 스케줄러 등록 + 1회 백필
6. 배포 + 검증(문동주 배지·알림 무발송)
