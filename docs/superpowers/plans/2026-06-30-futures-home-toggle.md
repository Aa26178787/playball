# 홈 화면 1군 ↔ 퓨처스 토글 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 홈(경기) 탭에 `[1군 | 퓨처스]` 세그먼트 토글을 추가해 같은 날짜스트립+카드 레이아웃을 퓨처스(2군) 데이터로 채워 보여준다.

**Architecture:** 기존 `/futures/games?season&month` 엔드포인트를 월 단위로 호출해 `game_date`로 그룹핑 → 홈 날짜 스트립의 활성일/리스트를 파생(1군 캘린더 lazy 패턴 미러). 백엔드 변경 없음. 퓨처스 카드는 `futures_screen`에서 공용 위젯으로 추출. 순위 탭의 중복 퓨처스 탭 제거.

**Tech Stack:** Flutter (Dart), 기존 `ApiService.getFuturesGames`, 디자인 토큰(`Typo`/`Pal`/`Radii`/`Space`), `showFuturesBoxSheet`.

## Global Constraints
- `flutter analyze lib` = 0 (매 태스크 끝 확인).
- 디자인 토큰 우선: `Typo`(폰트/weight)·`Pal`(중성색)·`SemColor`(시맨틱)·`Radii`·`Space`. 인라인 hex 지양.
- 웹 동반 원칙: 앱 수정 = 웹 재빌드+배포 (마지막 태스크). 빌드 명령 = `MSYS_NO_PATHCONV=1 flutter build web --wasm --release --base-href "/app/" --no-web-resources-cdn --pwa-strategy=none`.
- 한글 파일 편집 = Edit/Write 도구만 (PowerShell -replace/Set-Content 금지 — 인코딩 깨짐).
- 퓨처스 status ∈ {예정, 종료, 취소}만 (라이브 없음). LIVE pill/30초 폴링 미적용.
- 골든 테스트 회귀 통과 (`flutter test`).
- TeamLogo 파라미터 = `teamCode`. NetworkImage 금지(웹 도달 위젯) — 단 퓨처스 카드는 TeamLogo만 사용(개별 선수 이미지 없음).

---

### Task 1: 퓨처스 카드 공용 위젯 추출 + 날짜 그룹핑 헬퍼

`futures_screen.dart`의 `_gameCard`를 공용 위젯 `FuturesGameCard`로 추출하고, 월별 게임 리스트를 `yyyy-MM-dd`로 그룹핑하는 순수 함수를 같은 파일에 정의한다(테스트 대상).

**Files:**
- Create: `app/lib/widgets/futures_game_card.dart`
- Create: `app/test/futures_group_test.dart`

**Interfaces:**
- Produces:
  - `class FuturesGameCard extends StatelessWidget` — 생성자 `FuturesGameCard({Key? key, required Map game, required bool isDark, VoidCallback? onTap})`.
  - `Map<String, List> groupFuturesGamesByDate(List games)` — 게임 리스트를 `game_date`(앞 10자, `yyyy-MM-dd`)로 그룹. `game_date == null`이면 스킵.

- [ ] **Step 1: 그룹핑 헬퍼 실패 테스트 작성**

`app/test/futures_group_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:playball/widgets/futures_game_card.dart';

void main() {
  test('groups games by yyyy-MM-dd date prefix', () {
    final games = [
      {'game_id': 'a', 'game_date': '2026-06-01'},
      {'game_id': 'b', 'game_date': '2026-06-01'},
      {'game_id': 'c', 'game_date': '2026-06-02'},
    ];
    final m = groupFuturesGamesByDate(games);
    expect(m.keys.toSet(), {'2026-06-01', '2026-06-02'});
    expect(m['2026-06-01']!.length, 2);
    expect(m['2026-06-02']!.length, 1);
  });

  test('skips null game_date', () {
    final m = groupFuturesGamesByDate([
      {'game_id': 'a', 'game_date': null},
      {'game_id': 'b', 'game_date': '2026-06-02T00:00:00'},
    ]);
    expect(m.keys.toSet(), {'2026-06-02'});
  });

  test('empty input returns empty map', () {
    expect(groupFuturesGamesByDate([]), isEmpty);
  });
}
```

> 참고: 앱 pubspec `name`이 `playball`이 아니면 import 경로 패키지명을 실제 값으로 맞출 것 (`grep '^name:' app/pubspec.yaml`).

- [ ] **Step 2: 테스트 실행 → 실패 확인**

Run: `cd app && flutter test test/futures_group_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:playball/widgets/futures_game_card.dart'` (파일 없음).

- [ ] **Step 3: 위젯 + 헬퍼 구현**

`app/lib/widgets/futures_game_card.dart` (카드 본문은 현 `futures_screen.dart`의 `_gameCard`를 그대로 옮기고 `onTap`을 파라미터화):
```dart
import 'package:flutter/material.dart';
import '../utils/design_tokens.dart';
import '../utils/team_theme.dart'; // TeamLogo

/// 퓨처스(2군) 게임 카드 — 1군 compact 카드 미러: HOME-left / AWAY-right.
/// 라이브 없음(status ∈ 예정/종료/취소). 탭 = 박스스코어 시트(onTap 주입).
class FuturesGameCard extends StatelessWidget {
  final Map game;
  final bool isDark;
  final VoidCallback? onTap;
  const FuturesGameCard({super.key, required this.game, required this.isDark, this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = game;
    final aS = g['away_score'], hS = g['home_score'];
    final done = g['status'] == '종료';
    final cancelled = g['status'] == '취소';
    final homeWon = done && hS != null && aS != null && hS > aS;
    final awayWon = done && hS != null && aS != null && aS > hS;

    Widget side(String code, String label, bool won, bool isHome) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: (homeWon || awayWon) && !won ? 0.45 : 1.0,
              child: TeamLogo(teamCode: code, size: 44),
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                  color: Pal.paper2(isDark), borderRadius: BorderRadius.circular(3)),
              child: Text(isHome ? '홈' : '원정',
                  style: TextStyle(
                      fontSize: Typo.micro, fontWeight: Typo.bold, color: Pal.sub(isDark))),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: Typo.micro, color: Pal.ink3(isDark))),
          ],
        );

    Widget center() {
      if (cancelled) {
        return Text('취소',
            style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: Pal.ink3(isDark)));
      }
      if (done) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${hS ?? '-'}',
                style: TextStyle(
                    fontSize: Typo.lg, fontWeight: Typo.extra,
                    color: homeWon ? Pal.ink(isDark) : Pal.sub(isDark))),
            Text(' : ',
                style: TextStyle(
                    fontSize: Typo.subtitle, fontWeight: Typo.bold, color: Pal.ink3(isDark))),
            Text('${aS ?? '-'}',
                style: TextStyle(
                    fontSize: Typo.lg, fontWeight: Typo.extra,
                    color: awayWon ? Pal.ink(isDark) : Pal.sub(isDark))),
          ]),
          const SizedBox(height: 5),
          Text('종료',
              style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: Pal.ink3(isDark))),
        ]);
      }
      return Text('예정',
          style: TextStyle(fontSize: Typo.lg, fontWeight: Typo.extra, color: Pal.ink(isDark)));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: Space.sm),
      decoration: BoxDecoration(
        color: Pal.paper(isDark),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: Pal.line(isDark)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              side(g['home_code'] as String, g['home_label'] as String, homeWon, true),
              Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                center(),
                const SizedBox(height: 4),
                Text(g['stadium']?.toString() ?? '',
                    style: TextStyle(fontSize: Typo.micro, color: Pal.sub(isDark))),
                if (g['is_exhibition'] == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('교류전',
                        style: TextStyle(fontSize: Typo.micro, color: SemColor.warning)),
                  ),
              ])),
              side(g['away_code'] as String, g['away_label'] as String, awayWon, false),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 퓨처스 게임 리스트를 game_date(앞 10자, yyyy-MM-dd)로 그룹. null 날짜는 스킵.
Map<String, List> groupFuturesGamesByDate(List games) {
  final map = <String, List>{};
  for (final g in games) {
    final d = (g as Map)['game_date'];
    if (d == null) continue;
    final key = d.toString().substring(0, 10);
    (map[key] ??= []).add(g);
  }
  return map;
}
```

> `SemColor.warning`가 없으면 현 `futures_screen.dart`의 교류전 색 표기(`SemColor.warning`)를 그대로 사용 — 동일 import 출처. 확인: `grep -n "SemColor.warning" app/lib/screens/futures/futures_screen.dart` (원본에 있음).

- [ ] **Step 4: 테스트 실행 → 통과 확인**

Run: `cd app && flutter test test/futures_group_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: analyze 확인 + 커밋**

Run: `cd app && flutter analyze lib`
Expected: `No issues found!` (또는 0 issues)
```bash
git add app/lib/widgets/futures_game_card.dart app/test/futures_group_test.dart
git commit -m "feat(futures): extract FuturesGameCard widget + date grouping helper"
```

---

### Task 2: 홈 상태 + 퓨처스 로딩 계층

홈에 퓨처스 모드 상태와 월 단위 로딩/그룹핑, 라이브 타이머 가드를 추가한다. (UI 연결은 Task 3.)

**Files:**
- Modify: `app/lib/screens/home/home_screen.dart`

**Interfaces:**
- Consumes: `groupFuturesGamesByDate` (Task 1), `ApiService.getFuturesGames(int season, {int? month})`.
- Produces (홈 내부 상태/메서드):
  - `bool _futuresMode` (기본 false)
  - `final Map<String, List> _futuresByDate`, `final Set<String> _futuresActiveDates`, `final Set<String> _futuresLoadedMonths`
  - `Future<void> _loadFuturesMonth(DateTime d)`
  - `DateTime? _latestFuturesDate()`
  - `Future<void> _enterFuturesMode()`, `void _exitFuturesMode()`

- [ ] **Step 1: import 추가**

`home_screen.dart` 상단 import 블록에 추가 (기존 import 인근):
```dart
import '../../widgets/futures_game_card.dart';
import '../futures/futures_box_sheet.dart';
```

- [ ] **Step 2: 상태 필드 추가**

`_HomeScreenState`의 `final Set<String> _gameDates = {};` / `final Set<String> _loadedMonths = {};` (현 434-435) 바로 아래에 추가:
```dart
  // ── 퓨처스(2군) 모드 ──
  bool _futuresMode = false;
  final Map<String, List> _futuresByDate = {};
  final Set<String> _futuresActiveDates = {};
  final Set<String> _futuresLoadedMonths = {};
```

- [ ] **Step 3: 퓨처스 로딩/전환 메서드 추가**

`_loadMonthGameDates` 메서드(현 440-451) 바로 아래에 추가:
```dart
  Future<void> _loadFuturesMonth(DateTime d) async {
    final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
    if (_futuresLoadedMonths.contains(key)) return;
    _futuresLoadedMonths.add(key);
    try {
      final data = await ApiService.getFuturesGames(d.year, month: d.month);
      final grouped = groupFuturesGamesByDate((data['games'] as List?) ?? []);
      if (!mounted) return;
      setState(() {
        _futuresByDate.addAll(grouped);
        _futuresActiveDates.addAll(grouped.keys);
      });
    } catch (_) {
      _futuresLoadedMonths.remove(key); // 실패 시 재시도 허용
    }
  }

  DateTime? _latestFuturesDate() {
    if (_futuresActiveDates.isEmpty) return null;
    final sorted = _futuresActiveDates.toList()..sort();
    return DateTime.parse(sorted.last);
  }

  Future<void> _enterFuturesMode() async {
    setState(() => _futuresMode = true);
    await _loadFuturesMonth(_selectedDate);
    if (!mounted) return;
    // 선택일에 퓨처스 경기 없으면 로드된 최근 경기일로 점프
    if (!_futuresActiveDates.contains(_dateKey(_selectedDate))) {
      final latest = _latestFuturesDate();
      if (latest != null) setState(() => _selectedDate = latest);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  void _exitFuturesMode() {
    final today = DateTime.now();
    setState(() {
      _futuresMode = false;
      if (!_isSameDay(_selectedDate, today)) {
        _selectedDate = today;
        _isLoading = true;
        _games = [];
        _loadGen++;
      }
    });
    _loadGames();
    _loadTomorrowGames();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }
```

- [ ] **Step 4: `_loadGames` 퓨처스 가드 + 타이머 가드**

`_loadGames()` 본문 맨 앞(현 873 `final gen = ++_loadGen;` 직전)에 추가:
```dart
    if (_futuresMode) return; // 퓨처스 모드는 _loadFuturesMonth가 담당
```
`_startAutoRefresh`의 타이머 콜백(현 713-714 `if (!mounted) return;` 다음 줄)에 추가:
```dart
      if (_futuresMode) return; // 퓨처스 = 라이브 폴링 없음
```

- [ ] **Step 5: analyze 확인 + 커밋**

Run: `cd app && flutter analyze lib`
Expected: `No issues found!` (미사용 경고 없도록 — 이 시점엔 신규 메서드가 아직 호출 안 됨. analyze는 private 미사용 메서드에 `unused_element` 경고를 낼 수 있음 → Task 3에서 즉시 연결하므로 한 커밋으로 묶으려면 Task 3까지 진행 후 analyze. 경고가 나오면 Task 3 완료 후 커밋.)

> **주의:** Step 5에서 `unused_element`(미사용 private 메서드) 경고가 뜨면 **이 태스크 커밋을 보류하고 Task 3을 이어서 완료한 뒤** 한 번에 커밋한다(분리 커밋이 analyze=0을 깨면 합친다). 경고가 없으면:
```bash
git add app/lib/screens/home/home_screen.dart
git commit -m "feat(futures): home futures-mode state + monthly loading layer"
```

---

### Task 3: 홈 UI — 토글·날짜스트립 분기·리스트 분기·컨트롤 숨김

Task 2의 상태/메서드를 UI에 연결한다.

**Files:**
- Modify: `app/lib/screens/home/home_screen.dart`

**Interfaces:**
- Consumes: Task 2의 `_futuresMode`/`_enterFuturesMode`/`_exitFuturesMode`/`_loadFuturesMonth`/`_futuresByDate`/`_futuresActiveDates`/`_futuresLoadedMonths`, Task 1의 `FuturesGameCard`, `showFuturesBoxSheet`.
- Produces: `Widget _buildLeagueToggle(bool isDark)`, `Widget _buildFuturesList()`.

- [ ] **Step 1: 세그먼트 토글 위젯 추가**

`_buildMonthStrip()` 메서드(현 1063) 바로 위에 추가:
```dart
  Widget _buildLeagueToggle(bool isDark) {
    Widget seg(String label, bool active, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: active ? null : onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(vertical: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? Pal.ink(isDark) : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: Typo.small,
                      fontWeight: Typo.extra,
                      color: active ? Pal.paper(isDark) : Pal.sub(isDark))),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Pal.paper2(isDark),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(children: [
          seg('1군', !_futuresMode, () {
            HapticFeedback.selectionClick();
            _exitFuturesMode();
          }),
          seg('퓨처스', _futuresMode, () {
            HapticFeedback.selectionClick();
            _enterFuturesMode();
          }),
        ]),
      ),
    );
  }
```

- [ ] **Step 2: 토글을 월/날짜 스트립 컨테이너 최상단에 삽입**

현 1486-1491 Column children을 다음으로 수정:
```dart
            child: Column(
              children: [
                _buildLeagueToggle(isDark),
                _buildMonthStrip(),
                _buildDateStrip(),
              ],
            ),
```

- [ ] **Step 3: 날짜 스트립 — 퓨처스 활성일/lazy-load/onTap 분기**

`_buildDateStrip`의 itemBuilder 내부(현 1251-1276)를 퓨처스 분기로 교체:
```dart
          // 경기 없는 날 비활성 — 모드별 소스
          final monthKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';
          final loadedSet = _futuresMode ? _futuresLoadedMonths : _loadedMonths;
          if (!loadedSet.contains(monthKey)) {
            Future(() => _futuresMode ? _loadFuturesMonth(date) : _loadMonthGameDates(date));
          }
          final activeSet = _futuresMode ? _futuresActiveDates : _gameDates;
          final noGame = loadedSet.contains(monthKey) && !activeSet.contains(_dateKey(date));
```
그리고 onTap(현 1270-1277)을 모드 분기로 교체:
```dart
          return GestureDetector(
            onTap: noGame ? null : () {
              if (!isSelected) {
                setState(() => _selectedDate = date);
                if (_futuresMode) {
                  _loadFuturesMonth(date); // 같은 월이면 즉시 반환(이미 로드)
                } else {
                  _loadGames();
                  Future.delayed(const Duration(seconds: 3), () { if (mounted) _loadTomorrowGames(); });
                }
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
              }
            },
```
(`itemBuilder`의 나머지 — Opacity/AnimatedContainer 등 — 변경 없음.)

> '오늘' 점프 버튼(현 1326-1350): 퓨처스 모드에서도 today로 가되 today에 2군 경기 없으면 빈 리스트. v1 수용(스펙 명시). 변경 불필요.

- [ ] **Step 4: 1군 컨트롤(필터/간략 토글) 퓨처스 모드 숨김**

필터/간략 토글 줄(현 1496-1532, `Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 2), child: Row(...))`)을 조건부로 감싼다. 해당 `Padding(` 앞에 `if (!_futuresMode)` 추가:
```dart
          if (!_futuresMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
              child: Row(
                // ... 기존 내용 그대로 ...
              ),
            ),
```
(등록말소 배너 줄 1494-1495는 이미 `_isSameDay(_selectedDate, now)` 조건 — 퓨처스 모드에서도 today면 뜰 수 있으니 `if (!_futuresMode && _todayRosterChanges.isNotEmpty && ...)`로 `!_futuresMode &&` 추가.)

- [ ] **Step 5: 게임 리스트 — 퓨처스 분기 + `_buildFuturesList` 추가**

`_buildGameList()` 본문 맨 앞(현 1661 `List filtered;` 직전)에 추가:
```dart
    if (_futuresMode) return _buildFuturesList();
```
`_buildGameList()` 메서드 바로 위(또는 아래)에 신규 메서드 추가:
```dart
  Widget _buildFuturesList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final games = _futuresByDate[_dateKey(_selectedDate)] ?? const [];
    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedback.lightImpact();
        final mk = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}';
        _futuresLoadedMonths.remove(mk);
        await _loadFuturesMonth(_selectedDate);
      },
      child: games.isEmpty
          ? ListView(
              padding: EdgeInsets.only(bottom: _listBottomPad(context)),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                Center(
                    child: Text('경기 없음',
                        style: TextStyle(fontSize: Typo.body, color: Pal.sub(isDark)))),
              ],
            )
          : ListView.builder(
              controller: _gameScrollController,
              padding: EdgeInsets.fromLTRB(12, 8, 12, _listBottomPad(context)),
              itemCount: games.length,
              itemBuilder: (_, i) {
                final g = games[i] as Map;
                return FuturesGameCard(
                  game: g,
                  isDark: isDark,
                  onTap: g['has_box'] == true
                      ? () => showFuturesBoxSheet(context, g['game_id'] as String)
                      : null,
                );
              },
            ),
    );
  }
```

- [ ] **Step 6: analyze 확인 + 커밋 (Task 2 변경 동반 커밋)**

Run: `cd app && flutter analyze lib`
Expected: `No issues found!`
```bash
git add app/lib/screens/home/home_screen.dart
git commit -m "feat(futures): home 1군/퓨처스 toggle, date-strip + list branching"
```

---

### Task 4: 순위 탭 퓨처스 탭 제거 + futures_screen 삭제

**Files:**
- Modify: `app/lib/screens/team/team_screen.dart`
- Delete: `app/lib/screens/futures/futures_screen.dart`

**Interfaces:**
- Consumes: 없음. `FuturesScreen` 참조 제거 후 카드 로직은 Task 1 위젯이 대체.

- [ ] **Step 1: team_screen 탭 5→4**

`_tabController = TabController(length: 5, vsync: this);` (현 53) → `length: 4`.
`tabs: const [...]` 목록(현 192-198)에서 `Tab(text: '퓨처스'),` 줄 삭제.
`TabBarView ... children:` (현 205-211)에서 `const FuturesScreen(),` 줄 삭제.

- [ ] **Step 2: FuturesScreen import 제거**

`team_screen.dart` 상단에서 `futures_screen.dart` import 줄 삭제.
Run: `grep -n "futures_screen" app/lib/screens/team/team_screen.dart`
Expected: 결과 없음 (import 제거 확인).

- [ ] **Step 3: futures_screen.dart 삭제 + 잔여 참조 확인**

```bash
git rm app/lib/screens/futures/futures_screen.dart
grep -rn "FuturesScreen" app/lib
```
Expected: `FuturesScreen` 잔여 참조 0 (홈은 `FuturesGameCard`만 사용, `FuturesScreen` 미참조).

- [ ] **Step 4: analyze 확인 + 커밋**

Run: `cd app && flutter analyze lib`
Expected: `No issues found!`
```bash
git add app/lib/screens/team/team_screen.dart
git commit -m "refactor(futures): remove redundant 순위탭 퓨처스 tab + futures_screen"
```

---

### Task 5: 전체 검증 + 웹 빌드/배포

**Files:** 없음(검증/배포).

- [ ] **Step 1: analyze + 전체 테스트(골든 회귀 포함)**

Run:
```bash
cd app && flutter analyze lib && flutter test
```
Expected: analyze `No issues found!`; test = 신규 `futures_group_test` PASS + 기존 골든 PASS (골든은 `@Tags(['golden'])` 포함 시 로컬 실행).

- [ ] **Step 2: 웹 wasm 빌드**

Run:
```bash
cd app && MSYS_NO_PATHCONV=1 flutter build web --wasm --release --base-href "/app/" --no-web-resources-cdn --pwa-strategy=none
```
Expected: 빌드 성공, `build/web` 생성.

- [ ] **Step 3: 웹 배포 (rsync) + 검증**

Run (서버 배포 — 기존 관행, SSH 키 사용):
```bash
KEY="C:\\Users\\qq772\\Downloads\\ssh-key-2026-03-28 (2).key"
cd app/build && tar czf /tmp/pbweb.tgz web && \
scp -i "$KEY" /tmp/pbweb.tgz ubuntu@168.107.36.158:/tmp/ && \
ssh -i "$KEY" ubuntu@168.107.36.158 "cd /tmp && tar xzf pbweb.tgz && sudo rsync -a --delete web/ /var/www/playball_web/ && curl -s -o /dev/null -w '%{http_code}' https://playball.duckdns.org/app/"
```
Expected: 마지막 출력 `200`.

- [ ] **Step 4: 스모크 + 수동 스팟체크 안내**

Run: `ssh -i "$KEY" ubuntu@168.107.36.158 "bash ~/playball/scripts/smoke.sh | tail -5"`
Expected: `ALL PASS` (서버/엔드포인트 무변경이라 통과).

수동 검증(사용자 디바이스/웹 — Flutter canvas 헤드리스 관찰 불가):
- 홈 토글 `[1군|퓨처스]` 표시, 퓨처스 클릭 → 날짜 스트립 2군 경기일만 활성·카드 표시·박스 시트 진입.
- 1군 복귀 → 오늘 1군 일정 정상, 필터/간략 토글 재표시.
- 순위 탭 = 4개 탭(퓨처스 없음).

- [ ] **Step 5: 최종 커밋(스펙/플랜 포함) + CLAUDE.md 변경이력 1줄**

스펙/플랜 문서와 CLAUDE.md 변경이력 엔트리를 커밋(웹 빌드 산출물 `build/`는 커밋 제외 — `.gitignore` 확인).
```bash
git add docs/superpowers/specs/2026-06-30-futures-home-toggle-design.md \
        docs/superpowers/plans/2026-06-30-futures-home-toggle.md
# CLAUDE.md 변경이력 엔트리 추가 후:
git add CLAUDE.md
git commit -m "docs(futures): home toggle spec/plan + 변경이력"
```

> ⚠️ git 환경: 로컬 클론이 origin/main보다 1247 커밋 뒤처짐(헌 클론, fcm fix를 worktree로 push한 상태). 이 플랜의 커밋도 **origin/main 기준 worktree에서 수행**해 push 한다 — 헌 로컬 HEAD에 직접 커밋/force-push 금지(origin의 최신 작업 유실 위험). 절차: `git worktree add --detach <scratch> origin/main` → 변경 파일 복사 → 커밋 → `git push origin HEAD:main` → worktree 제거.

## Self-Review

**1. Spec coverage:**
- 토글(헤더 상단/날짜점프 근처) → Task 3 Step 1-2 (월/날짜 스트립 컨테이너 최상단). ✅
- 1군 레이아웃 전체를 퓨처스 데이터로 → Task 2(로딩) + Task 3(스트립/리스트 분기). ✅
- 백엔드 무변경 → 기존 `getFuturesGames` 재사용. ✅
- 라이브/폴링/LIVE pill 미적용 → Task 2 Step 4(타이머/`_loadGames` 가드). ✅
- 1군 컨트롤 숨김 → Task 3 Step 4. ✅
- 카드 추출/공용 위젯 → Task 1. ✅
- 순위탭 퓨처스 탭 제거 + futures_screen 삭제 → Task 4. ✅
- box 시트 유지 → Task 3 Step 5(`showFuturesBoxSheet`). ✅
- 영속 X / 풀히어로/마이팀필터 비목표 → 미구현(의도). ✅
- 웹 동반 배포 → Task 5. ✅

**2. Placeholder scan:** 모든 코드 스텝에 실제 코드 포함. `SemColor.warning`·패키지명은 원본 확인 지시로 명시(가정 아님). 가짜 placeholder 없음. ✅

**3. Type consistency:** `FuturesGameCard({Map game, bool isDark, VoidCallback? onTap})` — Task 1 정의 = Task 3 호출 일치. `groupFuturesGamesByDate(List)→Map<String,List>` 일치. `_loadFuturesMonth(DateTime)`/`_futuresByDate[_dateKey(...)]` 일치. `_dateKey` 기존 헬퍼 재사용. ✅
