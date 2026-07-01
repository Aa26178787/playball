# 퓨처스 경기 상세 풀스크린 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 퓨처스 경기 상세를 바텀시트에서 KBO 1군 detail 느낌의 풀스크린(히어로 스코어보드 + 라인스코어 + 타자/투수 기록 탭 + 주요기록)으로 개선한다.

**Architecture:** 신규 `FuturesGameDetailScreen`가 기존 `GET /futures/games/{id}/box`를 fetch. 히어로+라인스코어+탭바 상단 고정, `Expanded(TabBarView)` [타자|투수] 각 독립 ListView(팀별 표 + 주요기록). 투수표는 이름 고정 + 스탯 가로스크롤. 홈 퓨처스 카드 탭이 시트 대신 이 화면을 push. 백엔드 무변경.

**Tech Stack:** Flutter/Dart, `ApiService.getFuturesBox`, 디자인 토큰(Typo/Pal/SemColor/Radii/Space), `TeamLogo`, `TabController`.

## Global Constraints
- `flutter analyze lib` = 0 (매 태스크 끝).
- 디자인 토큰만: `Typo`/`Pal`/`SemColor`/`Radii`/`Space`. 인라인 hex 지양(대형 폰트 34 등 off-scale 리터럴은 1군 카드 관례대로 허용).
- 한글 파일 편집 = Edit/Write 도구만.
- `TeamLogo` 파라미터 = `teamCode`. NetworkImage 금지(웹). 이 화면은 TeamLogo만 사용(개별 선수 이미지 없음).
- 골든 회귀 통과. 웹 동반 빌드+배포(마지막 태스크).
- 데이터 형식(실측): pitcher `side` ∈ {"away","home"} · `result` ∈ {"승","패","세","홀드",""} · batter `avg`=num(0~1) · `pos`=한자문자열 · pitcher `ip`=문자열("1 1/3") · `era`=num.
- 패키지명 `playball` (import `package:playball/...`).

---

### Task 1: FuturesGameDetailScreen 신규 (풀스크린 + 순수 헬퍼 TDD)

**Files:**
- Create: `app/lib/screens/futures/futures_game_detail_screen.dart`
- Create: `app/test/futures_detail_helpers_test.dart`

**Interfaces:**
- Produces:
  - `class FuturesGameDetailScreen extends StatefulWidget` — `FuturesGameDetailScreen({Key?, required String gameId})`.
  - `List<MapEntry<String, dynamic>> futuresSummaryEntries(Map? summary)` — 빈 문자열/‘없음’ 값 제외한 주요기록 엔트리.
  - `String futuresAvgLabel(dynamic avg)` — num이면 소수 3자리 `.XXX`(0. 제거), 아니면 `-`.
- Consumes: `ApiService.getFuturesBox(String) → Future<Map<String,dynamic>>` (기존).

- [ ] **Step 1: 순수 헬퍼 실패 테스트 작성**

`app/test/futures_detail_helpers_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:playball/screens/futures/futures_game_detail_screen.dart';

void main() {
  test('futuresSummaryEntries drops empty and 없음 values', () {
    final e = futuresSummaryEntries({
      '결승타': '유로결(1회)', '홈런': '', '2루타': '없음', '심판': '정은재',
    });
    expect(e.map((x) => x.key).toList(), ['결승타', '심판']);
  });

  test('futuresSummaryEntries handles null', () {
    expect(futuresSummaryEntries(null), isEmpty);
  });

  test('futuresAvgLabel formats number as .XXX', () {
    expect(futuresAvgLabel(0.5), '.500');
    expect(futuresAvgLabel(0.333), '.333');
    expect(futuresAvgLabel(1.0), '1.000');
    expect(futuresAvgLabel(null), '-');
    expect(futuresAvgLabel('x'), '-');
  });
}
```

- [ ] **Step 2: 테스트 실행 → 실패 확인**

Run: `cd C:/Users/qq772/playball-fut/app && flutter test test/futures_detail_helpers_test.dart`
Expected: FAIL — `Target of URI doesn't exist` (파일 없음).

- [ ] **Step 3: 화면 + 헬퍼 구현**

`app/lib/screens/futures/futures_game_detail_screen.dart`:
```dart
import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../utils/design_tokens.dart';
import '../../utils/team_theme.dart'; // TeamLogo

/// 주요기록: 빈 문자열/'없음' 제외.
List<MapEntry<String, dynamic>> futuresSummaryEntries(Map? summary) {
  if (summary == null) return const [];
  return summary.entries
      .where((e) => '${e.value}'.trim().isNotEmpty && e.value != '없음')
      .map((e) => MapEntry(e.key.toString(), e.value))
      .toList();
}

/// 타율 표기: num → .XXX (0. 제거), 그 외 '-'.
String futuresAvgLabel(dynamic avg) =>
    (avg is num) ? avg.toStringAsFixed(3).replaceFirst('0.', '.') : '-';

class FuturesGameDetailScreen extends StatefulWidget {
  final String gameId;
  const FuturesGameDetailScreen({super.key, required this.gameId});
  @override
  State<FuturesGameDetailScreen> createState() => _FuturesGameDetailScreenState();
}

class _FuturesGameDetailScreenState extends State<FuturesGameDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  late final Future<Map<String, dynamic>> _future =
      ApiService.getFuturesBox(widget.gameId);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Pal.paper(isDark),
      appBar: AppBar(
        backgroundColor: Pal.paper(isDark),
        elevation: 0,
        iconTheme: IconThemeData(color: Pal.ink(isDark)),
        title: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (_, snap) {
            final m = (snap.data?['meta'] as Map?) ?? {};
            return Text('${m['away_label'] ?? ''} vs ${m['home_label'] ?? ''}',
                style: TextStyle(
                    fontSize: Typo.title, fontWeight: Typo.extra, color: Pal.ink(isDark)));
          },
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (_, snap) {
          if (snap.hasError) {
            return Center(
                child: Text('기록 없음',
                    style: TextStyle(fontSize: Typo.body, color: Pal.sub(isDark))));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!;
          final meta = (d['meta'] as Map?) ?? {};
          final sb = (d['scoreboard'] as Map?) ?? {};
          final awayB = (d['away_batters'] as List?) ?? const [];
          final homeB = (d['home_batters'] as List?) ?? const [];
          final pit = (d['pitchers'] as List?) ?? const [];
          final awayP = pit.where((p) => (p as Map)['side'] == 'away').toList();
          final homeP = pit.where((p) => (p as Map)['side'] == 'home').toList();
          final summary = (d['summary'] as Map?);
          final aLabel = '${meta['away_label'] ?? ''}';
          final hLabel = '${meta['home_label'] ?? ''}';
          return Column(children: [
            _hero(meta, isDark),
            _lineScore(sb, isDark),
            Container(
              color: Pal.paper(isDark),
              child: TabBar(
                controller: _tab,
                labelColor: Pal.ink(isDark),
                unselectedLabelColor: Pal.sub(isDark),
                indicatorColor: Pal.ink(isDark),
                labelStyle: const TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra),
                tabs: const [Tab(text: '타자'), Tab(text: '투수')],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.xxl),
                    children: [
                      _batterTable('$aLabel (원정)', awayB, isDark),
                      const SizedBox(height: Space.xl),
                      _batterTable('$hLabel (홈)', homeB, isDark),
                      const SizedBox(height: Space.xl),
                      _summary(summary, isDark),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.xxl),
                    children: [
                      _pitcherTable('$aLabel (원정)', awayP, isDark),
                      const SizedBox(height: Space.xl),
                      _pitcherTable('$hLabel (홈)', homeP, isDark),
                      const SizedBox(height: Space.xl),
                      _summary(summary, isDark),
                    ],
                  ),
                ],
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _sectionLabel(String t, bool isDark) => Padding(
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: Text(t,
            style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra, color: Pal.ink(isDark))),
      );

  Widget _hero(Map meta, bool isDark) {
    final aS = meta['away_score'], hS = meta['home_score'];
    final cancelled = meta['status'] == '취소';
    final done = meta['status'] == '종료';
    final awayWon = done && aS != null && hS != null && aS > hS;
    final homeWon = done && aS != null && hS != null && hS > aS;
    Widget teamSide(String code, String label, bool won) => Expanded(
          child: Column(children: [
            Opacity(
              opacity: (awayWon || homeWon) && !won ? 0.45 : 1.0,
              child: TeamLogo(teamCode: code, size: 52),
            ),
            const SizedBox(height: Space.xs),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: Typo.body, fontWeight: Typo.bold, color: Pal.ink(isDark))),
          ]),
        );
    Widget center() {
      if (cancelled) {
        return Text('취소',
            style: TextStyle(fontSize: Typo.h2, fontWeight: Typo.extra, color: Pal.ink3(isDark)));
      }
      if (aS == null || hS == null) {
        return Text('예정',
            style: TextStyle(fontSize: Typo.h2, fontWeight: Typo.extra, color: Pal.ink(isDark)));
      }
      TextStyle s(bool won) => TextStyle(
          fontSize: 34,
          fontWeight: Typo.extra,
          color: won ? Pal.ink(isDark) : Pal.ink2(isDark).withValues(alpha: 0.55),
          fontFeatures: const [FontFeature.tabularFigures()]);
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('$aS', style: s(awayWon)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(':',
                style: TextStyle(fontSize: Typo.h2, fontWeight: Typo.medium, color: Pal.ink3(isDark))),
          ),
          Text('$hS', style: s(homeWon)),
        ],
      );
    }
    final sub = [meta['game_date'], meta['stadium'], meta['status']]
        .where((e) => e != null && '$e'.isNotEmpty)
        .join('  ·  ');
    return Container(
      color: Pal.paper(isDark),
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          teamSide('${meta['away_code'] ?? ''}', '${meta['away_label'] ?? ''}', awayWon),
          center(),
          teamSide('${meta['home_code'] ?? ''}', '${meta['home_label'] ?? ''}', homeWon),
        ]),
        const SizedBox(height: Space.sm),
        Text(sub, style: TextStyle(fontSize: Typo.caption, color: Pal.sub(isDark))),
      ]),
    );
  }

  // 라인스코어 (futures_box_sheet._lineScore 이식)
  Widget _lineScore(Map sb, bool isDark) {
    final away = (sb['away'] as Map?) ?? {};
    final home = (sb['home'] as Map?) ?? {};
    final aInn = (away['innings'] as List?) ?? [];
    final hInn = (home['innings'] as List?) ?? [];
    final n = [aInn.length, hInn.length, 9].reduce((a, b) => a > b ? a : b);
    final ink = Pal.ink(isDark), sub = Pal.ink3(isDark), line = Pal.line(isDark);
    String c(List l, int i) => (i < l.length && l[i] != null) ? '${l[i]}' : '-';
    Widget col(String top, String aV, String hV, {bool bold = false}) => Expanded(
          child: Column(children: [
            Text(top, style: TextStyle(fontSize: Typo.micro, fontWeight: Typo.bold, color: sub)),
            const SizedBox(height: 7),
            Text(aV,
                style: TextStyle(
                    fontSize: Typo.caption, fontWeight: bold ? Typo.extra : Typo.medium, color: ink)),
            const SizedBox(height: 6),
            Text(hV,
                style: TextStyle(
                    fontSize: Typo.caption, fontWeight: bold ? Typo.extra : Typo.medium, color: ink)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Pal.paper2(isDark), borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 44,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('팀', style: TextStyle(fontSize: Typo.micro, fontWeight: Typo.bold, color: sub)),
            const SizedBox(height: 7),
            Text('${away['team'] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.extra, color: ink)),
            const SizedBox(height: 6),
            Text('${home['team'] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.extra, color: ink)),
          ]),
        ),
        for (int i = 0; i < n; i++) col('${i + 1}', c(aInn, i), c(hInn, i)),
        Container(width: 1, height: 44, color: line, margin: const EdgeInsets.symmetric(horizontal: 4)),
        col('R', '${away['r'] ?? '-'}', '${home['r'] ?? '-'}', bold: true),
        col('H', '${away['h'] ?? '-'}', '${home['h'] ?? '-'}'),
        col('E', '${away['e'] ?? '-'}', '${home['e'] ?? '-'}'),
      ]),
    );
  }

  // 타자 표: 타순 위치 이름 타수 안타 타점 득점 타율
  Widget _batterTable(String label, List rows, bool isDark) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final ink = Pal.ink(isDark), sub = Pal.sub(isDark);
    Widget numCell(String t, double w, {bool head = false}) => SizedBox(
        width: w,
        child: Text(t,
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: Typo.caption,
                fontWeight: head ? Typo.bold : Typo.medium,
                color: head ? sub : ink,
                fontFeatures: const [FontFeature.tabularFigures()])));
    Widget leftCell(String t, double w, {bool head = false}) => SizedBox(
        width: w,
        child: Text(t,
            style: TextStyle(
                fontSize: Typo.caption, fontWeight: head ? Typo.bold : Typo.medium, color: head ? sub : ink)));
    Widget row(Map b, {bool head = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            leftCell(head ? '순' : '${b['order'] ?? ''}', 22, head: head),
            leftCell(head ? '위치' : '${b['pos'] ?? ''}', 30, head: head),
            Expanded(
                child: Text(head ? '이름' : '${b['name'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: Typo.caption,
                        fontWeight: head ? Typo.bold : Typo.medium,
                        color: head ? sub : ink))),
            numCell(head ? '타수' : '${b['ab'] ?? '-'}', 34, head: head),
            numCell(head ? '안타' : '${b['h'] ?? '-'}', 34, head: head),
            numCell(head ? '타점' : '${b['rbi'] ?? '-'}', 34, head: head),
            numCell(head ? '득점' : '${b['r'] ?? '-'}', 34, head: head),
            numCell(head ? '타율' : futuresAvgLabel(b['avg']), 44, head: head),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel(label, isDark),
      Container(
        decoration: BoxDecoration(color: Pal.paper2(isDark), borderRadius: BorderRadius.circular(Radii.md)),
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
        child: Column(children: [
          row(const {}, head: true),
          Divider(height: 1, color: Pal.line(isDark)),
          ...rows.cast<Map>().map((b) => row(b)),
        ]),
      ),
    ]);
  }

  // 투수 표: [결과+이름] 고정 좌측 + 스탯 가로스크롤
  Widget _pitcherTable(String label, List rows, bool isDark) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final ink = Pal.ink(isDark), sub = Pal.sub(isDark);
    const rowPad = EdgeInsets.symmetric(vertical: 5);
    Widget leftCell(String res, String name, {bool head = false}) => Padding(
          padding: rowPad,
          child: SizedBox(
            width: 104,
            child: Row(children: [
              SizedBox(
                  width: 30,
                  child: Text(head ? '' : res,
                      style: TextStyle(
                          fontSize: Typo.micro, fontWeight: Typo.bold, color: SemColor.brand(context)))),
              Expanded(
                  child: Text(head ? '투수' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Typo.caption,
                          fontWeight: head ? Typo.bold : Typo.medium,
                          color: head ? sub : ink))),
            ]),
          ),
        );
    // (헤더, 키, 폭)
    const cols = <(String, String, double)>[
      ('이닝', 'ip', 44),
      ('투구', 'pitches', 42),
      ('상대', 'batters', 42),
      ('피안타', 'h', 46),
      ('실점', 'r', 42),
      ('자책', 'er', 42),
      ('볼넷', 'bb_hbp', 42),
      ('삼진', 'so', 42),
      ('홈런', 'hr', 42),
      ('평자책', 'era', 54),
    ];
    String valOf(Map p, String k) => k == 'era'
        ? ((p['era'] is num) ? (p['era'] as num).toStringAsFixed(2) : '-')
        : '${p[k] ?? '-'}';
    Widget statCell(String t, double w, {bool head = false}) => SizedBox(
        width: w,
        child: Text(t,
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: Typo.caption,
                fontWeight: head ? Typo.bold : Typo.medium,
                color: head ? sub : ink,
                fontFeatures: const [FontFeature.tabularFigures()])));
    Widget statRow(Map p, {bool head = false}) => Padding(
          padding: rowPad,
          child: Row(children: [
            for (final c in cols) statCell(head ? c.$1 : valOf(p, c.$2), c.$3, head: head),
          ]),
        );
    final line = Pal.line(isDark);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel(label, isDark),
      Container(
        decoration: BoxDecoration(color: Pal.paper2(isDark), borderRadius: BorderRadius.circular(Radii.md)),
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 좌측 고정 (결과+이름)
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            leftCell('', '', head: true),
            Divider(height: 1, color: line),
            ...rows.cast<Map>().map((p) => leftCell('${p['result'] ?? ''}', '${p['name'] ?? ''}')),
          ]),
          // 우측 가로스크롤 (스탯)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                statRow(const {}, head: true),
                Divider(height: 1, color: line),
                ...rows.cast<Map>().map((p) => statRow(p)),
              ]),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _summary(Map? s, bool isDark) {
    final items = futuresSummaryEntries(s);
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel('주요 기록', isDark),
      ...items.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: 56,
                  child: Text(e.key,
                      style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: Pal.sub(isDark)))),
              Expanded(
                  child: Text('${e.value}',
                      style: TextStyle(fontSize: Typo.caption, color: Pal.ink(isDark)))),
            ]),
          )),
    ]);
  }
}
```

- [ ] **Step 4: 테스트 실행 → 통과 확인**

Run: `cd C:/Users/qq772/playball-fut/app && flutter test test/futures_detail_helpers_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: analyze + 커밋**

Run: `cd C:/Users/qq772/playball-fut/app && flutter analyze lib`
Expected: `No issues found!`
```bash
git -C C:/Users/qq772/playball-fut add app/lib/screens/futures/futures_game_detail_screen.dart app/test/futures_detail_helpers_test.dart
git -C C:/Users/qq772/playball-fut commit -m "feat(futures): full-screen game detail (hero + linescore + 타자/투수 tabs)"
```

---

### Task 2: 홈 연결 + 바텀시트 제거

**Files:**
- Modify: `app/lib/screens/home/home_screen.dart`
- Delete: `app/lib/screens/futures/futures_box_sheet.dart`

**Interfaces:**
- Consumes: `FuturesGameDetailScreen({required String gameId})` (Task 1).

- [ ] **Step 1: 홈 import 교체**

`home_screen.dart` 상단에서 `import '../futures/futures_box_sheet.dart';` 를 다음으로 교체:
```dart
import '../futures/futures_game_detail_screen.dart';
```

- [ ] **Step 2: `_buildFuturesList` onTap 교체**

`_buildFuturesList` 내부의 `FuturesGameCard(... onTap: ...)` 에서 박스시트 호출을 풀스크린 push로 교체. 기존:
```dart
                  onTap: g['has_box'] == true
                      ? () => showFuturesBoxSheet(context, g['game_id'] as String)
                      : null,
```
→
```dart
                  onTap: g['has_box'] == true
                      ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => FuturesGameDetailScreen(gameId: g['game_id'] as String)))
                      : null,
```

- [ ] **Step 3: 바텀시트 파일 삭제 + 잔여 참조 확인**

```bash
git -C C:/Users/qq772/playball-fut rm app/lib/screens/futures/futures_box_sheet.dart
grep -rn "showFuturesBoxSheet\|futures_box_sheet" C:/Users/qq772/playball-fut/app/lib
```
Expected: grep 결과 없음.

- [ ] **Step 4: analyze + 커밋**

Run: `cd C:/Users/qq772/playball-fut/app && flutter analyze lib`
Expected: `No issues found!`
```bash
git -C C:/Users/qq772/playball-fut add app/lib/screens/home/home_screen.dart app/lib/screens/futures/futures_box_sheet.dart
git -C C:/Users/qq772/playball-fut commit -m "feat(futures): home opens full-screen detail, remove box sheet"
```

---

### Task 3: 검증 + 웹 빌드/배포

**Files:** 없음(검증/배포).

- [ ] **Step 1: analyze + 전체 테스트(골든 포함)**

Run: `cd C:/Users/qq772/playball-fut/app && flutter analyze lib && flutter test`
Expected: analyze `No issues found!`; test = 신규 helper 3 PASS + 기존(futures_group 3 + 골든 5) PASS.

- [ ] **Step 2: 웹 wasm 빌드**

Run:
```bash
cd C:/Users/qq772/playball-fut/app && MSYS_NO_PATHCONV=1 flutter build web --wasm --release --base-href "/app/" --no-web-resources-cdn --pwa-strategy=none
```
Expected: 빌드 성공.

- [ ] **Step 3: 배포 + 검증**

Run:
```bash
KEY="/c/Users/qq772/Downloads/ssh-key-2026-03-28 (2).key"
SC="/c/Users/qq772/AppData/Local/Temp/claude/C--Users-qq772-playball/6c23dd04-75df-4fd9-b488-7f42556d63a4/scratchpad"
rm -f "$SC/pbweb.tgz"
tar --force-local -C "C:/Users/qq772/playball-fut/app/build" -czf "$SC/pbweb.tgz" web
scp -i "$KEY" "$SC/pbweb.tgz" ubuntu@168.107.36.158:/tmp/pbweb.tgz
ssh -i "$KEY" ubuntu@168.107.36.158 "sudo rm -rf /tmp/pbweb_x && mkdir -p /tmp/pbweb_x && tar xzf /tmp/pbweb.tgz -C /tmp/pbweb_x && sudo rsync -a --delete /tmp/pbweb_x/web/ /var/www/playball_web/ && rm -rf /tmp/pbweb_x && curl -s -o /dev/null -w '%{http_code}\n' https://playball.duckdns.org/app/"
```
Expected: `200`.

- [ ] **Step 4: smoke**

Run: `ssh -i "$KEY" ubuntu@168.107.36.158 "bash ~/playball/scripts/smoke.sh | tail -4"`
Expected: `ALL PASS`.

수동 스팟체크(헤드리스 렌더 불가): 순위 탭 없이 홈 퓨처스 카드 탭 → 풀스크린(히어로/라인스코어/타자·투수 탭/투수 가로스크롤/주요기록), 뒤로가기.

## Self-Review

**1. Spec coverage:**
- 풀스크린 화면 → Task 1 (FuturesGameDetailScreen). ✅
- 히어로(로고+스코어 승팀강조+날짜/구장/상태) → `_hero`. ✅
- 라인스코어 이식 → `_lineScore`. ✅
- 탭 [타자|투수] 상단 고정+Expanded(TabBarView) → build. ✅
- 타자 표(타순/위치/이름/타수/안타/타점/득점/타율) → `_batterTable`. ✅
- 투수 표(결과/이름 고정 + 스탯 가로스크롤, 전 컬럼) → `_pitcherTable`. ✅
- 주요기록 각 탭 tail 공유 위젯 → `_summary`. ✅
- 바텀시트 제거 + 홈 push 교체 → Task 2. ✅
- 백엔드 무변경 / 데이터 부재 비목표(필드뷰/중계 등) → 미포함. ✅
- 웹 동반 배포 → Task 3. ✅

**2. Placeholder scan:** 전 스텝 실제 코드. 데이터 형식은 실측값(side away/home, avg num, ip 문자열) 반영. placeholder 없음. ✅

**3. Type consistency:** `FuturesGameDetailScreen({required String gameId})` Task 1 정의 = Task 2 호출 일치. `futuresSummaryEntries(Map?)`/`futuresAvgLabel(dynamic)` 정의=사용 일치. `getFuturesBox(String)` 기존 시그니처 일치. 레코드 `(String,String,double)` cols는 `_pitcherTable` 내부 지역. ✅
