import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../utils/design_tokens.dart';
import '../../utils/team_theme.dart'; // TeamLogo, teamColor

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

/// Naver 2군 포지션 약어 → 한글. 한자(一二三)·교대조합(주유=대주→유격) 정리.
/// 교대 시 마지막 문자 = 최종 수비위치 기준.
String futuresPosLabel(dynamic pos) {
  const m = {
    '一': '1루', '二': '2루', '三': '3루',
    '유': '유격', '좌': '좌익', '중': '중견', '우': '우익',
    '포': '포수', '투': '투수', '지': '지명', '주': '대주', '타': '대타',
  };
  final s = '${pos ?? ''}'.trim();
  if (s.isEmpty) return '';
  final last = s.substring(s.length - 1);
  return m[last] ?? m[s] ?? s;
}

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
          return NestedScrollView(
            headerSliverBuilder: (_, _) => [
              SliverToBoxAdapter(child: _scoreboardCard(meta, sb, isDark)),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  isDark: isDark,
                  child: TabBar(
                    controller: _tab,
                    labelColor: Pal.ink(isDark),
                    unselectedLabelColor: Pal.sub(isDark),
                    indicatorColor: Pal.ink(isDark),
                    indicatorWeight: 2,
                    labelStyle: const TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra),
                    tabs: const [Tab(text: '타자'), Tab(text: '투수')],
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tab,
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.xxl),
                  children: [
                    _batterTable(aLabel, meta['away_code'], awayB, isDark),
                    const SizedBox(height: Space.xl),
                    _batterTable(hLabel, meta['home_code'], homeB, isDark),
                    const SizedBox(height: Space.xl),
                    _summaryCard(summary, isDark),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.xxl),
                  children: [
                    _pitcherTable(aLabel, meta['away_code'], awayP, isDark),
                    const SizedBox(height: Space.xl),
                    _pitcherTable(hLabel, meta['home_code'], homeP, isDark),
                    const SizedBox(height: Space.xl),
                    _summaryCard(summary, isDark),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── 통합 스코어보드 카드 (히어로 + 라인스코어) ──
  Widget _scoreboardCard(Map meta, Map sb, bool isDark) {
    final aS = meta['away_score'], hS = meta['home_score'];
    final cancelled = meta['status'] == '취소';
    final done = meta['status'] == '종료';
    final awayWon = done && aS is num && hS is num && aS > hS;
    final homeWon = done && aS is num && hS is num && hS > aS;

    Widget teamCol(String code, String label, bool won) => Expanded(
          child: Column(children: [
            Opacity(
              opacity: (awayWon || homeWon) && !won ? 0.4 : 1.0,
              child: TeamLogo(teamCode: code, size: 56),
            ),
            const SizedBox(height: Space.sm),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: Typo.subtitle,
                    fontWeight: won ? Typo.extra : Typo.bold,
                    color: Pal.ink(isDark))),
          ]),
        );

    Widget scoreCenter() {
      if (cancelled) {
        return Text('취소',
            style: TextStyle(fontSize: Typo.h1, fontWeight: Typo.extra, color: Pal.ink3(isDark)));
      }
      if (aS is! num || hS is! num) {
        return Text('예정',
            style: TextStyle(fontSize: Typo.h2, fontWeight: Typo.extra, color: Pal.ink(isDark)));
      }
      TextStyle st(bool won) => TextStyle(
          fontSize: 40,
          height: 1.0,
          fontWeight: Typo.black,
          color: won ? Pal.ink(isDark) : Pal.ink3(isDark),
          fontFeatures: const [FontFeature.tabularFigures()]);
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('$aS', style: st(awayWon)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(':',
                style: TextStyle(fontSize: Typo.h2, fontWeight: Typo.medium, color: Pal.ink3(isDark))),
          ),
          Text('$hS', style: st(homeWon)),
        ],
      );
    }

    final caption = [meta['game_date'], meta['stadium'], meta['status']]
        .where((e) => e != null && '$e'.isNotEmpty)
        .join('  ·  ');

    return Container(
      margin: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.sm),
      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.lg),
      decoration: BoxDecoration(
        color: Pal.paper(isDark),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: Pal.line(isDark)),
      ),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          teamCol('${meta['away_code'] ?? ''}', '${meta['away_label'] ?? ''}', awayWon),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm),
            child: scoreCenter(),
          ),
          teamCol('${meta['home_code'] ?? ''}', '${meta['home_label'] ?? ''}', homeWon),
        ]),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          Text(caption, style: TextStyle(fontSize: Typo.caption, color: Pal.sub(isDark))),
        ],
        const SizedBox(height: Space.md),
        _lineScore(sb, isDark),
      ]),
    );
  }

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
            const SizedBox(height: 6),
            Text(aV,
                style: TextStyle(
                    fontSize: Typo.caption, fontWeight: bold ? Typo.extra : Typo.medium, color: ink)),
            const SizedBox(height: 5),
            Text(hV,
                style: TextStyle(
                    fontSize: Typo.caption, fontWeight: bold ? Typo.extra : Typo.medium, color: ink)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(color: Pal.paper2(isDark), borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 40,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 15),
            Text('${away['team'] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.extra, color: ink)),
            const SizedBox(height: 5),
            Text('${home['team'] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.extra, color: ink)),
          ]),
        ),
        for (int i = 0; i < n; i++) col('${i + 1}', c(aInn, i), c(hInn, i)),
        Container(width: 1, height: 46, color: line, margin: const EdgeInsets.symmetric(horizontal: 5)),
        col('R', '${away['r'] ?? '-'}', '${home['r'] ?? '-'}', bold: true),
        col('H', '${away['h'] ?? '-'}', '${home['h'] ?? '-'}'),
        col('E', '${away['e'] ?? '-'}', '${home['e'] ?? '-'}'),
      ]),
    );
  }

  Widget _sectionHeader(String label, dynamic code, bool isDark) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: Space.sm),
        child: Row(children: [
          Container(
            width: 4, height: 15,
            decoration: BoxDecoration(
                color: teamColor('$code'), borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: Space.sm),
          Text(label,
              style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra, color: Pal.ink(isDark))),
        ]),
      );

  Widget _sectionHeaderPlain(String label, bool isDark) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: Space.sm),
        child: Text(label,
            style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra, color: Pal.ink(isDark))),
      );

  // 타자 표: 타순 위치 이름 타수 안타 타점 득점 타율 (zebra)
  Widget _batterTable(String label, dynamic code, List rows, bool isDark) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final ink = Pal.ink(isDark), sub = Pal.sub(isDark);
    Widget numC(String t, double w, {bool head = false}) => SizedBox(
        width: w,
        child: Text(t,
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: Typo.caption,
                fontWeight: head ? Typo.bold : Typo.medium,
                color: head ? sub : ink,
                fontFeatures: const [FontFeature.tabularFigures()])));
    Widget leftC(String t, double w, {bool head = false}) => SizedBox(
        width: w,
        child: Text(t,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: Typo.caption, fontWeight: head ? Typo.bold : Typo.medium, color: head ? sub : ink)));
    Color rowBg(int i, bool head) => head
        ? Pal.paper2(isDark)
        : (i.isEven ? Pal.paper(isDark) : Pal.paper2(isDark).withValues(alpha: 0.5));
    Widget rowW(Row cells, int i, {bool head = false}) => Container(
          color: rowBg(i, head),
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 6),
          child: cells,
        );
    Row cells(Map b, {bool head = false}) => Row(children: [
          leftC(head ? '순' : '${b['order'] ?? ''}', 20, head: head),
          const SizedBox(width: 4),
          leftC(head ? '위치' : futuresPosLabel(b['pos']), 40, head: head),
          Expanded(
              child: Text(head ? '이름' : '${b['name'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: Typo.caption,
                      fontWeight: head ? Typo.bold : Typo.semibold,
                      color: head ? sub : ink))),
          numC(head ? '타수' : '${b['ab'] ?? '-'}', 32, head: head),
          numC(head ? '안타' : '${b['h'] ?? '-'}', 32, head: head),
          numC(head ? '타점' : '${b['rbi'] ?? '-'}', 32, head: head),
          numC(head ? '득점' : '${b['r'] ?? '-'}', 32, head: head),
          numC(head ? '타율' : futuresAvgLabel(b['avg']), 42, head: head),
        ]);
    final list = rows.cast<Map>().toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(label, code, isDark),
      ClipRRect(
        borderRadius: BorderRadius.circular(Radii.md),
        child: Column(children: [
          rowW(cells(const {}, head: true), 0, head: true),
          for (int i = 0; i < list.length; i++) rowW(cells(list[i]), i),
        ]),
      ),
    ]);
  }

  // 투수 표: [결과+이름] 좌측 고정 + 스탯 가로스크롤 (zebra)
  Widget _pitcherTable(String label, dynamic code, List rows, bool isDark) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final ink = Pal.ink(isDark), sub = Pal.sub(isDark);
    Color bg(int i, bool head) => head
        ? Pal.paper2(isDark)
        : (i.isEven ? Pal.paper(isDark) : Pal.paper2(isDark).withValues(alpha: 0.5));
    Widget leftCell(String res, String name, int i, {bool head = false}) => Container(
          width: 108,
          color: bg(i, head),
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 7),
          child: Row(children: [
            SizedBox(
                width: 28,
                child: Text(head ? '' : res,
                    style: TextStyle(
                        fontSize: Typo.micro, fontWeight: Typo.bold, color: SemColor.brand(context)))),
            Expanded(
                child: Text(head ? '투수' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: Typo.caption,
                        fontWeight: head ? Typo.bold : Typo.semibold,
                        color: head ? sub : ink))),
          ]),
        );
    const cols = <(String, String, double)>[
      ('이닝', 'ip', 46), ('투구', 'pitches', 42), ('상대', 'batters', 42),
      ('피안타', 'h', 46), ('실점', 'r', 40), ('자책', 'er', 40),
      ('볼넷', 'bb_hbp', 42), ('삼진', 'so', 40), ('홈런', 'hr', 40), ('평자책', 'era', 54),
    ];
    String valOf(Map p, String k) => k == 'era'
        ? ((p['era'] is num) ? (p['era'] as num).toStringAsFixed(2) : '-')
        : '${p[k] ?? '-'}';
    Widget statRow(Map p, int i, {bool head = false}) => Container(
          color: bg(i, head),
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            for (final c in cols)
              SizedBox(
                width: c.$3,
                child: Text(head ? c.$1 : valOf(p, c.$2),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: Typo.caption,
                        fontWeight: head ? Typo.bold : Typo.medium,
                        color: head ? sub : ink,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            const SizedBox(width: Space.md),
          ]),
        );
    final list = rows.cast<Map>().toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(label, code, isDark),
      ClipRRect(
        borderRadius: BorderRadius.circular(Radii.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            leftCell('', '', 0, head: true),
            for (int i = 0; i < list.length; i++)
              leftCell('${list[i]['result'] ?? ''}', '${list[i]['name'] ?? ''}', i),
          ]),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                statRow(const {}, 0, head: true),
                for (int i = 0; i < list.length; i++) statRow(list[i], i),
              ]),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _summaryCard(Map? s, bool isDark) {
    final items = futuresSummaryEntries(s);
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeaderPlain('주요 기록', isDark),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        decoration: BoxDecoration(
            color: Pal.paper2(isDark), borderRadius: BorderRadius.circular(Radii.md)),
        child: Column(
          children: [
            for (final e in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                      width: 58,
                      child: Text(e.key,
                          style: TextStyle(
                              fontSize: Typo.caption, fontWeight: Typo.bold, color: Pal.sub(isDark)))),
                  Expanded(
                      child: Text('${e.value}',
                          style: TextStyle(fontSize: Typo.caption, color: Pal.ink(isDark), height: 1.35))),
                ]),
              ),
          ],
        ),
      ),
    ]);
  }
}

/// TabBar를 pinned 스크롤 헤더로.
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final bool isDark;
  _TabBarDelegate({required this.child, required this.isDark});
  @override
  double get minExtent => 46;
  @override
  double get maxExtent => 46;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
        color: Pal.paper(isDark),
        alignment: Alignment.centerLeft,
        child: child,
      );
  @override
  bool shouldRebuild(_TabBarDelegate old) => old.child != child || old.isDark != isDark;
}
