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

  // 라인스코어
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
