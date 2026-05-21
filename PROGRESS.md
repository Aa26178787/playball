# PlayBall 개발 진행 현황

최종 업데이트: 2026-05-22

---

## 완료된 작업

### 버그 수정
- **batter_stats 데이터 오염 수정** (박성한 등 44명)
  - 원인: KBO Basic1 크롤러 ON CONFLICT에서 `EXCLUDED.home_runs` 직접 덮어쓰기 → NULL로 기존 데이터 삭제
  - 수정: `GREATEST(COALESCE(...), COALESCE(...))` 패턴으로 변경
  - 파일: `backend/crawler/kbo_daily_crawler.py`
  - 추가: `_sync_batter_stats_from_daily()` doubles/triples/hbp/cs/pa 동기화 확장
  - 추가: `run_season_crawl.py`에 daily sync 호출 추가

### UI 개선
- **전 화면 영문 지표 → 한글화**
  - `player_screen.dart`: OPS→출루장타율, WAR→대체승리기여, ERA→평균자책점, WHIP→이닝당출루
  - `team_screen.dart`: 동일
  - `game_detail_screen.dart`: ERA→평자, K→삼진, BB→볼넷
- **한글/영어 토글 버튼** (`player_detail_screen.dart` AppBar)
  - 버튼: ENG / 한글 전환
  - `_l(kor, eng)` 헬퍼로 전체 지표 라벨 토글

### 경기 상세 (`game_detail_screen.dart`)
- **자동 새로고침 표시**: 30초 자동 새로고침 상태바 (진행중 녹색 / 종료 회색)
- **수동 새로고침 버튼**: 우측 새로고침 아이콘 + 스피너
- **승리확률 그래프**: fl_chart LineChart
  - relay_all 데이터 기반, 최대 80포인트 다운샘플
  - 50% 기준선, 터치 툴팁, 그라디언트 채우기
  - 현재 홈/원정 확률 하단 표시
- **경기흐름 그래프**: fl_chart BarChart
  - 이닝별 홈(남색)/원정(빨강) 득점 막대

### 선수 화면 (`player_screen.dart`)
- **순위 하이라이트**: 1위=금색, 2위=은색, 3위=동색 원형 뱃지
- **타이틀 뱃지**: 1위에게 "홈런왕" 등 금색 뱃지 표시

### 선수 상세 (`player_detail_screen.dart`)
- **시즌 트렌드 그래프**: fl_chart LineChart
  - 타자: avg 꺾은선 (남색), 투수: ERA 꺾은선 (빨강)
  - 최근 20게임, x축 MM/DD, 터치 툴팁

### 캘린더 (신규)
- **백엔드**: `GET /calendar/{year}/{month}` 엔드포인트
  - 파일: `backend/api/routers/calendar.py`
  - `backend/api/main.py`에 라우터 등록
  - 응답: `{"year": 2026, "month": 5, "games": {"2026-05-01": [...]}}`
- **프론트**: `app/lib/screens/calendar/calendar_screen.dart`
  - 월별 달력 그리드 (팀 컬러 점으로 경기 표시)
  - 날짜 선택 시 하단에 경기 목록
  - 경기 카드 탭 → GameDetailScreen 이동
- **탭 추가**: home_screen.dart 5번째 탭 (캘린더 아이콘)

### FCM 인프라 (백엔드 완료, 프론트 코드 완료 — 활성화 대기 중)
- **백엔드 FCM 서비스**: `backend/api/fcm_service.py`
  - `notify_game_start()`, `notify_score_change()`, `notify_game_end()`
  - Firebase Admin SDK 사용 (firebase-admin 패키지)
  - 마이팀 등록 유저 필터링 (push_tokens + user_favorite_teams JOIN)
- **스케줄러 훅**: `backend/crawler/scheduler.py`
  - 경기 시작(예정→진행), 득점, 경기 종료 감지 → FCM 발송
- **프론트 코드**: `app/lib/main.dart`에 Firebase init + 토큰 등록 완성
  - 토큰 → `POST /user/push-token` 자동 전송
  - try-catch로 감싸서 Firebase 미설정 시 앱 크래시 없음
- **API**: `ApiService.registerFcmToken()` 추가

---

## FCM 활성화 방법 (미완료 — 수동 작업 필요)

### 1단계: Firebase 프로젝트 생성 (브라우저)

1. [https://console.firebase.google.com](https://console.firebase.google.com) 접속
2. **프로젝트 추가** 클릭
3. 프로젝트 이름 입력 (예: `playball-kbo`)
4. Google Analytics 설정 → 완료

### 2단계: Android 앱 등록 (브라우저)

1. 프로젝트 홈 → **Android 아이콘** 클릭
2. Android 패키지 이름: **`com.playball.app`** 입력
3. 앱 닉네임: PlayBall
4. **앱 등록** 클릭
5. **`google-services.json` 다운로드**
6. 다운로드한 파일을 → `C:\Users\qq772\playball\app\android\app\google-services.json` 에 저장

### 3단계: 서비스 계정 키 생성 (브라우저)

1. Firebase 콘솔 → 프로젝트 설정(톱니바퀴) → **서비스 계정** 탭
2. **새 비공개 키 생성** 클릭 → JSON 다운로드
3. 다운로드한 파일 이름을 `firebase-service-account.json` 으로 변경
4. 서버에 업로드:
   ```bash
   scp -i "C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key" firebase-service-account.json ubuntu@168.107.61.147:~/playball/backend/
   ```

### 4단계: FlutterFire CLI 설정 (터미널 — Claude Code에서 `!` 붙여서 실행)

```bash
! dart pub global activate flutterfire_cli
! cd C:\Users\qq772\playball\app && flutterfire configure
```

- `flutterfire configure` 실행 시 브라우저 Firebase 로그인 → 프로젝트 선택 → Android 선택
- 완료 후 `app/lib/firebase_options.dart` 자동 생성됨

### 5단계: 코드 수정 (Claude에게 요청)

`firebase_options.dart` 생성 확인 후 Claude에게 다음 요청:
> "FCM 활성화 마무리해줘"

Claude가 처리할 내용:
- `main.dart` import 추가 + `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` 수정
- `build.gradle` google-services 플러그인 확인/추가
- 서버에 `pip install firebase-admin` 실행
- 서버 재시작

---

## 미구현 기능 (우선순위 순)

### 높음
- [ ] **FCM 활성화** (위 단계 완료 후 Claude가 마무리)
- [ ] **홈화면 위젯** (Android AppWidgetProvider + home_widget 패키지, 네이티브 코드 필요)

### 중간
- [ ] 경기카드 최근5경기 승/패/무 표기
- [ ] 투수 구종차트 (경기 상세)
- [ ] 선수 비교 화면
- [ ] 마이팀 개인화 홈

### 낮음
- [ ] 비밀번호 찾기/재설정
- [ ] 회원탈퇴, 닉네임 변경
- [ ] 다크모드
- [ ] 오프라인 캐싱
- [ ] 커뮤니티 이미지 첨부, 게시글 검색
- [ ] 날씨 정보 (야외 경기장)
- [ ] 피타고리안 승률
- [ ] 투구 히트맵, 스프레이 차트

---

## 주요 파일 위치

| 파일 | 설명 |
|------|------|
| `backend/api/routers/calendar.py` | 캘린더 API |
| `backend/api/fcm_service.py` | FCM 발송 서비스 |
| `backend/crawler/scheduler.py` | FCM 훅 포함 스케줄러 |
| `app/lib/screens/calendar/calendar_screen.dart` | 캘린더 화면 |
| `app/lib/screens/game/game_detail_screen.dart` | 승리확률/경기흐름 그래프 |
| `app/lib/screens/player/player_detail_screen.dart` | 트렌드 그래프 + 한글/영어 토글 |
| `app/lib/screens/player/player_screen.dart` | 순위 하이라이트 뱃지 |
| `app/lib/main.dart` | Firebase init (활성화 대기 중) |

---

## 서버 접속 / 배포 명령어

```bash
# 서버 접속
ssh -i "C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key" ubuntu@168.107.61.147

# 배포
cd ~/playball && git pull origin main --rebase && sudo systemctl restart playball

# 로그 확인
sudo journalctl -u playball -f

# firebase-admin 설치 (FCM 활성화 시)
pip install firebase-admin
```
