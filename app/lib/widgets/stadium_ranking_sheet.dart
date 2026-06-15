import 'package:flutter/material.dart';
import '../api/api_service.dart';
import '../utils/design_tokens.dart';

/// 직관승률 랭킹 바텀시트 — 캘린더/커뮤니티 공용 진입점
class StadiumRankingSheet {
  static Future<void> show(BuildContext context) async {
    final data = await ApiService.getStadiumRanking(limit: 50);
    final ranking = data['ranking'] as List? ?? [];
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (ctx, sc) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.emoji_events, color: SemColor.brand(ctx), size: 18),
                  const SizedBox(width: 6),
                  const Text('직관승률 랭킹', style: TextStyle(fontSize: Typo.title, fontWeight: Typo.bold)),
                  const SizedBox(width: 6),
                  const Text('(최소 5회)', style: TextStyle(fontSize: Typo.small, color: Colors.grey)),
                ],
              ),
            ),
            const Divider(height: 1),
            ranking.isEmpty
                ? const Expanded(child: Center(child: Text('아직 랭킹 데이터가 없습니다', style: TextStyle(color: Colors.grey))))
                : Expanded(
                    child: ListView.builder(
                      controller: sc,
                      itemCount: ranking.length,
                      itemBuilder: (_, i) {
                        final r = ranking[i] as Map;
                        final rank = r['rank'] as int;
                        final winRate = ((r['win_rate'] as num) * 100).toStringAsFixed(1);
                        final medalColor = rank == 1
                            ? const Color(0xFFFFD700)
                            : rank == 2
                                ? const Color(0xFFC0C0C0)
                                : rank == 3
                                    ? const Color(0xFFCD7F32)
                                    : Colors.grey[600]!;
                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: rank <= 3 ? medalColor.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text('$rank',
                                style: TextStyle(
                                    fontSize: Typo.body,
                                    fontWeight: Typo.bold,
                                    color: rank <= 3 ? medalColor : Colors.grey[600])),
                          ),
                          title: Text(r['nickname'] ?? '', style: const TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.medium)),
                          subtitle: Text(
                              '${r['wins']}승 ${r['losses']}패${(r['draws'] as int) > 0 ? ' ${r['draws']}무' : ''} · 총 ${r['total']}회',
                              style: const TextStyle(fontSize: Typo.caption)),
                          trailing: Text('$winRate%',
                              style: TextStyle(
                                  fontSize: Typo.subtitle,
                                  fontWeight: Typo.bold,
                                  color: rank <= 3 ? medalColor : SemColor.brand(ctx))),
                        );
                      },
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
