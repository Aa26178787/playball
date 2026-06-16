import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../utils/design_tokens.dart';
import '../../utils/team_theme.dart';
import 'historical_player_detail_screen.dart';

/// 역대 기록실(명예의전당) — 통산 리더보드. 카테고리 칩 + TOP N, 행 탭 → 은퇴 상세.
class HistoricalLeadersScreen extends StatefulWidget {
  const HistoricalLeadersScreen({super.key});
  @override
  State<HistoricalLeadersScreen> createState() => _HistoricalLeadersScreenState();
}

class _HistoricalLeadersScreenState extends State<HistoricalLeadersScreen> {
  static const _cats = [
    ('home_runs', '홈런'),
    ('hits', '안타'),
    ('stolen_bases', '도루'),
    ('rbis', '타점'),
    ('wins', '승'),
    ('strikeouts_pitched', '탈삼진'),
    ('saves', '세이브'),
  ];
  String _cat = 'home_runs';
  List _leaders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await ApiService.getHistoricalLeaders(category: _cat, limit: 25);
      if (mounted) setState(() { _leaders = d['leaders'] ?? []; _loading = false; });
    } catch (e) {
      debugPrint('historical_leaders: $e');
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Pal.paper(isDark),
      appBar: AppBar(title: const Text('역대 기록실')),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            children: [
              for (final c in _cats)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: Space.sm),
                  child: ChoiceChip(
                    label: Text(c.$2),
                    selected: _cat == c.$1,
                    onSelected: (_) { setState(() => _cat = c.$1); _load(); },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _leaders.isEmpty
                  ? Center(child: Text('데이터 없음', style: TextStyle(color: Pal.sub(isDark))))
                  : ListView.separated(
                      itemCount: _leaders.length,
                      separatorBuilder: (_, _) => Divider(height: 1, color: Pal.line(isDark)),
                      itemBuilder: (_, i) {
                        final p = _leaders[i] as Map;
                        return ListTile(
                          leading: SizedBox(
                            width: 28,
                            child: Text('${i + 1}',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: Typo.black, color: Pal.sub(isDark))),
                          ),
                          title: Text(p['name'] ?? '',
                              style: TextStyle(color: Pal.ink(isDark), fontWeight: Typo.bold)),
                          subtitle: Text(p['team'] ?? '',
                              style: TextStyle(color: Pal.sub(isDark), fontSize: Typo.mini)),
                          trailing: Text('${p['value']}',
                              style: TextStyle(
                                  fontWeight: Typo.black,
                                  fontSize: Typo.subtitle,
                                  color: teamColor(p['team_code'] ?? ''))),
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => HistoricalPlayerDetailScreen(
                                kboPlayerId: p['kbo_player_id'], initialName: p['name']),
                          )),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
