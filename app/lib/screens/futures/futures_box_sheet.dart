import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../utils/design_tokens.dart';

void showFuturesBoxSheet(BuildContext context, String gameId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: _FuturesBoxSheet(gameId: gameId),
    ),
  );
}

class _FuturesBoxSheet extends StatelessWidget {
  final String gameId;
  const _FuturesBoxSheet({required this.gameId});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Pal.paper(isDark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      ),
      child: FutureBuilder<Map<String, dynamic>>(
        future: ApiService.getFuturesBox(gameId),
        builder: (_, snap) {
          if (!snap.hasData) {
            return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
          }
          final d = snap.data!;
          final meta = (d['meta'] as Map?) ?? {};
          final sb = (d['scoreboard'] as Map?) ?? {};
          return Column(children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: Space.sm),
                decoration: BoxDecoration(color: Pal.line2(isDark), borderRadius: BorderRadius.circular(Radii.pill))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Text('${meta['away_label']} vs ${meta['home_label']}  ·  ${meta['game_date'] ?? ''}',
                  style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.bold, color: Pal.ink(isDark))),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.xxl),
                children: [
                  _lineScore(sb, isDark),
                  const SizedBox(height: Space.xl),
                  _batters('타자', d['away_batters'] as List?, d['home_batters'] as List?,
                      meta['away_label'], meta['home_label'], isDark),
                  const SizedBox(height: Space.xl),
                  _pitchers(d['pitchers'] as List?, isDark),
                  const SizedBox(height: Space.xl),
                  _summary(d['summary'] as Map?, isDark),
                ],
              ),
            ),
          ]);
        },
      ),
    );
  }

  // 라인스코어 — game_detail _buildLineScore 미러 (away 위 / home 아래)
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
            Text(aV, style: TextStyle(fontSize: Typo.caption, fontWeight: bold ? Typo.extra : Typo.medium, color: ink)),
            const SizedBox(height: 6),
            Text(hV, style: TextStyle(fontSize: Typo.caption, fontWeight: bold ? Typo.extra : Typo.medium, color: ink)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Pal.paper2(isDark), borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 44,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('팀', style: TextStyle(fontSize: Typo.micro, fontWeight: Typo.bold, color: sub)),
            const SizedBox(height: 7),
            Text('${away['team'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.extra, color: ink)),
            const SizedBox(height: 6),
            Text('${home['team'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
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

  Widget _sectionLabel(String t, bool isDark) => Padding(
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: Text(t, style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra, color: Pal.ink(isDark))),
      );

  Widget _batters(String _, List? away, List? home, awayLabel, homeLabel, bool isDark) {
    Widget side(String label, List? rows) {
      if (rows == null || rows.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: Pal.sub(isDark))),
        const SizedBox(height: Space.sm),
        ...rows.cast<Map>().map((b) => Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Row(children: [
                SizedBox(width: 28, child: Text('${b['pos'] ?? ''}',
                    style: TextStyle(fontSize: Typo.caption, color: Pal.ink3(isDark)))),
                Expanded(child: Text('${b['name'] ?? ''}',
                    style: TextStyle(fontSize: Typo.body, fontWeight: Typo.medium, color: Pal.ink(isDark)))),
                Text('${b['ab'] ?? '-'}타 ${b['h'] ?? '-'}안 ${b['rbi'] ?? '-'}타점',
                    style: TextStyle(fontSize: Typo.caption, color: Pal.sub(isDark))),
                const SizedBox(width: Space.sm),
                SizedBox(width: 40, child: Text(
                    (b['avg'] is num) ? (b['avg'] as num).toStringAsFixed(3).replaceFirst('0.', '.') : '-',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: Pal.ink(isDark)))),
              ]),
            )),
        const SizedBox(height: Space.md),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel('타자 기록', isDark),
      side('$awayLabel (원정)', away),
      side('$homeLabel (홈)', home),
    ]);
  }

  Widget _pitchers(List? pit, bool isDark) {
    if (pit == null || pit.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel('투수 기록', isDark),
      ...pit.cast<Map>().map((p) => Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Row(children: [
              SizedBox(width: 28, child: Text('${p['result'] ?? ''}',
                  style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: Pal.sub(isDark)))),
              Expanded(child: Text('${p['name'] ?? ''}',
                  style: TextStyle(fontSize: Typo.body, fontWeight: Typo.medium, color: Pal.ink(isDark)))),
              Text('${p['ip'] ?? '-'}이닝 ${p['er'] ?? '-'}자책 ${p['so'] ?? '-'}K',
                  style: TextStyle(fontSize: Typo.caption, color: Pal.sub(isDark))),
              const SizedBox(width: Space.sm),
              SizedBox(width: 40, child: Text(
                  (p['era'] is num) ? (p['era'] as num).toStringAsFixed(2) : '-',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: Pal.ink(isDark)))),
            ]),
          )),
    ]);
  }

  Widget _summary(Map? s, bool isDark) {
    if (s == null || s.isEmpty) return const SizedBox.shrink();
    final items = s.entries.where((e) => '${e.value}'.trim().isNotEmpty && e.value != '없음').toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel('주요 기록', isDark),
      ...items.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 56, child: Text('${e.key}',
                  style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: Pal.sub(isDark)))),
              Expanded(child: Text('${e.value}',
                  style: TextStyle(fontSize: Typo.caption, color: Pal.ink(isDark)))),
            ]),
          )),
    ]);
  }
}
