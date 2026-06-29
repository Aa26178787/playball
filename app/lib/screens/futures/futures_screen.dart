import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../utils/design_tokens.dart';
import '../../utils/team_theme.dart'; // TeamLogo
import 'futures_box_sheet.dart';

class FuturesScreen extends StatefulWidget {
  const FuturesScreen({super.key});
  @override
  State<FuturesScreen> createState() => _FuturesScreenState();
}

class _FuturesScreenState extends State<FuturesScreen> {
  int _season = 2026;
  int? _month;
  List _games = [];
  List<int> _months = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await ApiService.getFuturesGames(_season, month: _month);
      final months = ((d['months'] as List?) ?? []).cast<int>();
      // 첫 진입/시즌전환(_month=null): months만 받아 최신월 확정 후 그 월로 1회 재요청
      // (재요청 안 하면 전체 시즌 경기가 표시되는데 월칩은 최신월만 선택 = 리스트↔필터 모순)
      if (_month == null && months.isNotEmpty) {
        if (!mounted) return;
        setState(() => _months = months);
        _month = months.last;
        return _load(); // _month != null → 재귀 1회로 종료
      }
      if (!mounted) return;
      setState(() {
        _games = (d['games'] as List?) ?? [];
        _months = months;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      _monthBar(isDark),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _games.isEmpty
                ? Center(child: Text('경기 없음',
                    style: TextStyle(color: Pal.sub(isDark), fontSize: Typo.body)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.xxl),
                    itemCount: _games.length,
                    itemBuilder: (_, i) => _gameCard(_games[i] as Map, isDark),
                  ),
      ),
    ]);
  }

  Widget _monthBar(bool isDark) {
    final yrs = [2026, 2025];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
      child: Row(children: [
        DropdownButton<int>(
          value: _season,
          underline: const SizedBox.shrink(),
          items: yrs.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() { _season = v; _month = null; _months = []; });
            _load();
          },
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _months.map((m) {
                final sel = m == _month;
                return Padding(
                  padding: const EdgeInsets.only(right: Space.sm),
                  child: GestureDetector(
                    onTap: () { setState(() => _month = m); _load(); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
                      decoration: BoxDecoration(
                        color: sel ? Pal.ink(isDark) : Pal.paper2(isDark),
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      child: Text('$m월',
                          style: TextStyle(
                              fontSize: Typo.caption,
                              fontWeight: Typo.bold,
                              color: sel ? Pal.paper(isDark) : Pal.sub(isDark))),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ]),
    );
  }

  // compact GameCard 미러: HOME-left / AWAY-right
  Widget _gameCard(Map g, bool isDark) {
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
          onTap: g['has_box'] == true
              ? () => showFuturesBoxSheet(context, g['game_id'] as String)
              : null,
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
