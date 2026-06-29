import 'package:flutter/material.dart';
import '../utils/design_tokens.dart';

/// 선수 상세확장 공유 섹션 — 타이틀 이력 / 팀 변천 / 마일스톤 / 통산 스플릿.
/// 현역(player_detail) + 은퇴(historical_player_detail) 공통 사용. 이미지 미사용 = 웹안전.
/// 빈 섹션은 자동 숨김, 전부 비면 SizedBox.shrink.
class CareerExtrasSection extends StatelessWidget {
  final Map<String, dynamic> extras;
  final bool isDark;
  final Color accent;
  const CareerExtrasSection({
    super.key,
    required this.extras,
    required this.isDark,
    required this.accent,
  });

  static String _yy(int? y) =>
      y == null ? '' : "'${(y % 100).toString().padLeft(2, '0')}";

  @override
  Widget build(BuildContext context) {
    final titles = (extras['titles'] as List?) ?? const [];
    final timeline = (extras['team_timeline'] as List?) ?? const [];
    final ms = (extras['milestones'] as Map?) ?? const {};
    final reached = (ms['reached'] as List?) ?? const [];
    final approaching = (ms['approaching'] as List?) ?? const [];
    final splits = (extras['splits'] as Map?) ?? const {};

    final blocks = <Widget>[];
    if (titles.isNotEmpty) blocks.add(_titlesBlock(titles));
    if (timeline.isNotEmpty) blocks.add(_timelineBlock(timeline));
    if (reached.isNotEmpty || approaching.isNotEmpty) {
      blocks.add(_milestoneBlock(reached, approaching));
    }
    if (splits.isNotEmpty) blocks.add(_splitsBlock(splits));
    final futures = (extras['futures_stats'] as List?) ?? const [];
    if (futures.isNotEmpty) blocks.add(_futuresBlock(futures));
    if (blocks.isEmpty) return const SizedBox.shrink();

    final out = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      if (i > 0) out.add(const SizedBox(height: Space.xl));
      out.add(blocks[i]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: out);
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: Text(t,
            style: TextStyle(
                fontSize: Typo.subtitle,
                fontWeight: Typo.extra,
                color: Pal.ink(isDark))),
      );

  // ── 타이틀 이력 ──
  Widget _titlesBlock(List titles) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('타이틀'),
      Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: titles.map<Widget>((t) {
          final cat = t['category']?.toString() ?? '';
          final cnt = (t['count'] as num?)?.toInt() ?? 0;
          return Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Space.md, vertical: Space.xs + 2),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Text('$cat $cnt회',
                style: TextStyle(
                    fontSize: Typo.small,
                    fontWeight: Typo.bold,
                    color: accent)),
          );
        }).toList(),
      ),
    ]);
  }

  // ── 팀 변천 ──
  Widget _timelineBlock(List timeline) {
    final segs = <Widget>[];
    for (var i = 0; i < timeline.length; i++) {
      final s = timeline[i] as Map;
      final team = s['team']?.toString() ?? '';
      final start = (s['start'] as num?)?.toInt();
      final end = (s['end'] as num?)?.toInt();
      final yr = (end == null)
          ? "${_yy(start)}~"
          : (end == start ? _yy(start) : "${_yy(start)}~${_yy(end)}");
      if (i > 0) {
        segs.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xs),
          child: Icon(Icons.chevron_right,
              size: Typo.subtitle, color: Pal.sub(isDark)),
        ));
      }
      segs.add(Column(mainAxisSize: MainAxisSize.min, children: [
        Text(team,
            style: TextStyle(
                fontSize: Typo.body,
                fontWeight: Typo.bold,
                color: Pal.ink(isDark))),
        Text(yr,
            style: TextStyle(fontSize: Typo.caption, color: Pal.sub(isDark))),
      ]));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('팀 변천'),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: segs),
      ),
    ]);
  }

  // ── 마일스톤 ──
  Widget _milestoneBlock(List reached, List approaching) {
    final gold = isDark ? const Color(0xFFE3B23C) : const Color(0xFFB8860B);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('마일스톤'),
      if (reached.isNotEmpty)
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: reached.map<Widget>((m) {
            return Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.md, vertical: Space.xs + 2),
              decoration: BoxDecoration(
                color: gold.withValues(alpha: isDark ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.workspace_premium, size: Typo.small, color: gold),
                const SizedBox(width: Space.xs),
                Text(m['label']?.toString() ?? '',
                    style: TextStyle(
                        fontSize: Typo.small,
                        fontWeight: Typo.bold,
                        color: gold)),
              ]),
            );
          }).toList(),
        ),
      if (approaching.isNotEmpty) ...[
        const SizedBox(height: Space.md),
        ...approaching.map<Widget>((a) {
          final label = a['label']?.toString() ?? '';
          final rem = (a['remaining'] as num?)?.toInt();
          final eta = (a['eta_season'] as num?)?.toInt();
          final etaStr = eta != null ? ' · $eta 예상' : '';
          return Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: Text('$label까지 $rem$etaStr',
                style: TextStyle(
                    fontSize: Typo.small, color: Pal.ink3(isDark))),
          );
        }),
      ],
    ]);
  }

  // ── 통산 스플릿 (2023~25 타자 — 축별 value 누적 avg) ──
  Widget _splitsBlock(Map splits) {
    final axisLabels = {
      'home_away': '홈/원정',
      'vs_team': '상대팀별',
      'month': '월별',
    };
    final axisBlocks = <Widget>[];
    splits.forEach((axis, rows) {
      if (rows is! List || rows.isEmpty) return;
      // value별 at_bats/hits 누적 → avg
      final agg = <String, List<int>>{}; // value → [ab, h]
      for (final r in rows) {
        final v = (r as Map)['value']?.toString() ?? '';
        final ab = (r['at_bats'] as num?)?.toInt() ?? 0;
        final h = (r['hits'] as num?)?.toInt() ?? 0;
        final cur = agg.putIfAbsent(v, () => [0, 0]);
        cur[0] += ab;
        cur[1] += h;
      }
      final chips = agg.entries.where((e) => e.value[0] > 0).map<Widget>((e) {
        final avg = e.value[1] / e.value[0];
        final avgStr = avg.toStringAsFixed(3).replaceFirst('0.', '.');
        return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Space.sm + 2, vertical: Space.xs),
          decoration: BoxDecoration(
            color: Pal.paper2(isDark),
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: Pal.line(isDark)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(e.key,
                style: TextStyle(
                    fontSize: Typo.caption, color: Pal.ink3(isDark))),
            const SizedBox(width: Space.sm),
            Text(avgStr,
                style: TextStyle(
                    fontSize: Typo.small,
                    fontWeight: Typo.bold,
                    color: Pal.ink(isDark))),
          ]),
        );
      }).toList();
      if (chips.isEmpty) return;
      axisBlocks.add(Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(axisLabels[axis] ?? axis.toString(),
              style: TextStyle(
                  fontSize: Typo.caption,
                  fontWeight: Typo.bold,
                  color: Pal.sub(isDark))),
          const SizedBox(height: Space.sm),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: chips),
        ]),
      ));
    });
    if (axisBlocks.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('통산 스플릿'),
      ...axisBlocks,
    ]);
  }

  // ── 2군(퓨처스) 시즌 기록 ── 1군 시즌행 룩 미러 (표 형태, 토큰)
  Widget _futuresBlock(List rows) {
    Widget cell(String t, {bool head = false, bool strong = false}) => Expanded(
          child: Text(t,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: head ? Typo.micro : Typo.caption,
                  fontWeight: strong ? Typo.bold : Typo.regular,
                  color: head ? Pal.sub(isDark) : Pal.ink(isDark))),
        );
    // 타자/투수 분리 (한 선수가 둘 다 가능)
    final hit = rows.where((r) => (r as Map)['player_type'] == '타자').toList();
    final pit = rows.where((r) => (r as Map)['player_type'] == '투수').toList();
    final sections = <Widget>[];
    String s3(num? v) => v == null ? '-' : v.toStringAsFixed(3).replaceFirst('0.', '.');
    String s2(num? v) => v == null ? '-' : v.toStringAsFixed(2);
    if (hit.isNotEmpty) {
      sections.add(Padding(
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: Row(children: [
          cell('시즌', head: true), cell('팀', head: true), cell('G', head: true),
          cell('타율', head: true), cell('HR', head: true), cell('OPS', head: true),
        ]),
      ));
      for (final r in hit.cast<Map>()) {
        sections.add(Row(children: [
          cell("'${(r['season'] % 100).toString().padLeft(2, '0')}", strong: true),
          cell(r['team_name']?.toString() ?? '-'),
          cell('${r['games'] ?? '-'}'),
          cell(s3(r['avg'] as num?)),
          cell('${r['home_runs'] ?? '-'}'),
          cell(s3(r['ops'] as num?)),
        ]));
      }
    }
    if (pit.isNotEmpty) {
      if (sections.isNotEmpty) sections.add(const SizedBox(height: Space.md));
      sections.add(Padding(
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: Row(children: [
          cell('시즌', head: true), cell('팀', head: true), cell('G', head: true),
          cell('ERA', head: true), cell('IP', head: true), cell('WHIP', head: true),
        ]),
      ));
      for (final r in pit.cast<Map>()) {
        sections.add(Row(children: [
          cell("'${(r['season'] % 100).toString().padLeft(2, '0')}", strong: true),
          cell(r['team_name']?.toString() ?? '-'),
          cell('${r['games'] ?? '-'}'),
          cell(s2(r['era'] as num?)),
          cell(s2(r['innings_pitched'] as num?)),
          cell(s2(r['whip'] as num?)),
        ]));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('2군 기록'),
      ...sections,
    ]);
  }
}
