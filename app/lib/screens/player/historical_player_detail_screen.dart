import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../utils/design_tokens.dart';
import '../../utils/team_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/career_extras_section.dart';

/// 은퇴/역대 선수 상세 (라이브 데이터 없음 — bio+통산+시즌별+PS+수상+스플릿+franchise).
/// 현역 상세(player_detail_screen)와 별도: 존히트맵/구종/트렌드/비교/투표 섹션 미존재.
class HistoricalPlayerDetailScreen extends StatefulWidget {
  final int kboPlayerId;
  final String? initialName;
  const HistoricalPlayerDetailScreen(
      {super.key, required this.kboPlayerId, this.initialName});
  @override
  State<HistoricalPlayerDetailScreen> createState() =>
      _HistoricalPlayerDetailScreenState();
}

class _HistoricalPlayerDetailScreenState
    extends State<HistoricalPlayerDetailScreen> {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _extras;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService.getHistoricalPlayer(widget.kboPlayerId),
        ApiService.getHistoricalCareerExtras(widget.kboPlayerId)
            .catchError((_) => <String, dynamic>{}),
      ]);
      if (mounted) {
        setState(() {
          _data = results[0];
          _extras = results[1];
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('historical_detail: $e');
      if (mounted) setState(() { _error = true; _loading = false; });
    }
  }

  String _r3(Object? v) => v == null ? '-'
      : (v is num ? v.toStringAsFixed(3).replaceFirst('0.', '.') : '$v');
  String _r2(Object? v) => v == null ? '-' : (v is num ? v.toStringAsFixed(2) : '$v');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Pal.paper(isDark),
      appBar: AppBar(title: Text(widget.initialName ?? '역대 선수')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error || _data == null
              ? AppErrorView(onRetry: () {
                  setState(() { _loading = true; _error = false; });
                  _load();
                })
              : _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    final bio = (_data!['bio'] as Map?) ?? {};
    final career = (_data!['career'] as Map?) ?? {};
    final stats = (_data!['stats'] as List?) ?? [];
    final awards = (_data!['awards'] as List?) ?? [];
    final post = (_data!['postseason'] as List?) ?? [];
    final fr = (_data!['franchise_path'] as List?) ?? [];
    final isPitcher = bio['player_type'] == '투수';
    final code = bio['team_code'] as String? ?? '';
    final accent = adjustTeamColor(teamColor(code), isDark);
    return ListView(padding: const EdgeInsets.all(Space.lg), children: [
      _hero(bio, isDark),
      if (career.isNotEmpty) _careerCard(career, isPitcher, isDark),
      if (_extras != null) ...[
        const SizedBox(height: Space.lg),
        CareerExtrasSection(extras: _extras!, isDark: isDark, accent: accent),
      ],
      if (stats.isNotEmpty) _seasonTable(stats.cast<Map>(), isPitcher, isDark),
      if (post.isNotEmpty) _postseasonCard(post.cast<Map>(), isPitcher, isDark),
      if (awards.isNotEmpty) _awardsCard(awards.cast<Map>(), isDark),
      if (fr.isNotEmpty) _franchiseCaption(fr.cast<Map>(), isDark),
      const SizedBox(height: Space.xl),
    ]);
  }

  Widget _hero(Map bio, bool isDark) {
    final code = bio['team_code'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
          color: teamColor(code).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Radii.lg)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(bio['name'] ?? '',
            style: TextStyle(
                fontSize: Typo.h2, fontWeight: Typo.black, color: Pal.ink(isDark))),
        const SizedBox(height: Space.xs),
        Text(
            [
              bio['team'],
              bio['position'],
              if (bio['debut_year'] != null)
                '${bio['debut_year']}~${bio['final_year'] ?? ''}',
            ].where((e) => e != null && e != '').join(' · '),
            style: TextStyle(fontSize: Typo.small, color: Pal.sub(isDark))),
        if (bio['throws'] != null || bio['bats'] != null) ...[
          const SizedBox(height: Space.xs),
          Text('투타 ${bio['throws'] ?? '-'}/${bio['bats'] ?? '-'}'
              '${bio['height'] != null ? ' · ${bio['height']}cm' : ''}'
              '${bio['weight'] != null ? ' ${bio['weight']}kg' : ''}',
              style: TextStyle(fontSize: Typo.caption, color: Pal.ink3(isDark))),
        ],
        if (bio['draft_info'] != null) ...[
          const SizedBox(height: Space.xs),
          Text('지명 ${bio['draft_info']}',
              style: TextStyle(fontSize: Typo.caption, color: Pal.ink3(isDark))),
        ],
        if (bio['career_text'] != null) ...[
          const SizedBox(height: Space.xs),
          Text('${bio['career_text']}',
              style: TextStyle(fontSize: Typo.caption, color: Pal.sub(isDark))),
        ],
      ]),
    );
  }

  Widget _careerCard(Map c, bool isPitcher, bool isDark) {
    final items = isPitcher
        ? [
            ('경기', '${c['games'] ?? '-'}'),
            ('승', '${c['wins'] ?? '-'}'),
            ('패', '${c['losses'] ?? '-'}'),
            ('SV', '${c['saves'] ?? '-'}'),
            ('이닝', '${c['innings_pitched'] ?? '-'}'),
            ('ERA', _r2(c['era'])),
            ('탈삼진', '${c['strikeouts_pitched'] ?? '-'}'),
            ('WHIP', _r2(c['whip'])),
          ]
        : [
            ('경기', '${c['games'] ?? '-'}'),
            ('타율', _r3(c['avg'])),
            ('안타', '${c['hits'] ?? '-'}'),
            ('홈런', '${c['home_runs'] ?? '-'}'),
            ('타점', '${c['rbis'] ?? '-'}'),
            ('도루', '${c['stolen_bases'] ?? '-'}'),
            ('OPS', _r3(c['ops'])),
            ('출루', _r3(c['obp'])),
          ];
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('통산',
            style: TextStyle(
                fontSize: Typo.subtitle, fontWeight: Typo.extra, color: Pal.ink(isDark))),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          for (final it in items)
            Container(
              width: 78,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: Pal.paper2(isDark),
                  borderRadius: BorderRadius.circular(Radii.sm)),
              child: Column(children: [
                Text(it.$2,
                    style: TextStyle(
                        fontSize: Typo.subtitle,
                        fontWeight: Typo.black,
                        color: Pal.ink(isDark))),
                Text(it.$1,
                    style: TextStyle(fontSize: Typo.micro, color: Pal.sub(isDark))),
              ]),
            ),
        ]),
      ]),
    );
  }

  Widget _seasonTable(List<Map> rows, bool isPitcher, bool isDark) {
    final headers = isPitcher
        ? ['시즌', '팀', '경기', '승', '패', 'ERA', '이닝', 'K']
        : ['시즌', '팀', '경기', '타율', 'HR', '타점', 'OPS'];
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('시즌별',
            style: TextStyle(
                fontSize: Typo.subtitle, fontWeight: Typo.extra, color: Pal.ink(isDark))),
        const SizedBox(height: Space.sm),
        Table(
          border: TableBorder(horizontalInside: BorderSide(color: Pal.line(isDark))),
          columnWidths: const {0: FixedColumnWidth(52), 1: FlexColumnWidth(1.4)},
          children: [
            TableRow(children: [for (final h in headers) _cell(h, isDark, head: true)]),
            for (final r in rows)
              TableRow(
                  children: isPitcher
                      ? [
                          _cell('${r['season']}', isDark),
                          _cell('${r['team_name'] ?? ''}', isDark),
                          _cell('${r['games'] ?? ''}', isDark),
                          _cell('${r['wins'] ?? ''}', isDark),
                          _cell('${r['losses'] ?? ''}', isDark),
                          _cell(_r2(r['era']), isDark),
                          _cell('${r['innings_pitched'] ?? ''}', isDark),
                          _cell('${r['strikeouts_pitched'] ?? ''}', isDark),
                        ]
                      : [
                          _cell('${r['season']}', isDark),
                          _cell('${r['team_name'] ?? ''}', isDark),
                          _cell('${r['games'] ?? ''}', isDark),
                          _cell(_r3(r['avg']), isDark),
                          _cell('${r['home_runs'] ?? ''}', isDark),
                          _cell('${r['rbis'] ?? ''}', isDark),
                          _cell(_r3(r['ops']), isDark),
                        ]),
          ],
        ),
      ]),
    );
  }

  Widget _postseasonCard(List<Map> rows, bool isPitcher, bool isDark) =>
      _simpleListCard(
          '포스트시즌',
          [
            for (final r in rows)
              '${r['season']} ${r['series_type']}: '
              '${isPitcher ? 'ERA ${_r2(r['era'])} ${r['innings_pitched'] ?? ''}이닝' : '${_r3(r['avg'])} ${r['home_runs'] ?? 0}HR ${r['rbis'] ?? 0}타점'}',
          ],
          isDark);

  Widget _awardsCard(List<Map> awards, bool isDark) => Padding(
        padding: const EdgeInsets.only(top: Space.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('수상',
              style: TextStyle(
                  fontSize: Typo.subtitle, fontWeight: Typo.extra, color: Pal.ink(isDark))),
          const SizedBox(height: Space.sm),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            for (final a in awards)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: Pal.paper2(isDark),
                    borderRadius: BorderRadius.circular(Radii.sm)),
                child: Text('${a['season'] ?? ''} ${a['award'] ?? ''}'.trim(),
                    style: TextStyle(
                        fontSize: Typo.small,
                        color: Pal.ink(isDark),
                        fontWeight: Typo.semibold)),
              ),
          ]),
        ]),
      );

  Widget _franchiseCaption(List<Map> fr, bool isDark) => Padding(
        padding: const EdgeInsets.only(top: Space.lg),
        child: Text(
            '구단 계보: ${fr.map((f) => '${f['team_name']}(${f['start_year']}~${f['end_year'] ?? ''})').join(' → ')}',
            style: TextStyle(fontSize: Typo.caption, color: Pal.sub(isDark))),
      );

  Widget _simpleListCard(String title, List<String> lines, bool isDark) => Padding(
        padding: const EdgeInsets.only(top: Space.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  fontSize: Typo.subtitle, fontWeight: Typo.extra, color: Pal.ink(isDark))),
          const SizedBox(height: Space.sm),
          for (final l in lines)
            Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l,
                    style: TextStyle(fontSize: Typo.small, color: Pal.ink3(isDark)))),
        ]),
      );

  Widget _cell(String t, bool isDark, {bool head = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Text(t,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: Typo.mini,
                fontWeight: head ? Typo.extra : Typo.regular,
                color: head ? Pal.sub(isDark) : Pal.ink(isDark))),
      );
}
