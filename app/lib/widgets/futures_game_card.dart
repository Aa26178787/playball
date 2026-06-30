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
