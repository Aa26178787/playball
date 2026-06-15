import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../utils/design_tokens.dart';
import '../../utils/web_image.dart';

/// 내 포인트 + 랭킹 (메가B)
class PointsScreen extends StatefulWidget {
  const PointsScreen({super.key});

  @override
  State<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends State<PointsScreen> {
  Map<String, dynamic>? _mine;
  List<dynamic> _leaders = [];
  List<dynamic> _badges = [];
  List<dynamic> _missions = [];
  bool _loading = true;
  String? _error;

  static const _reasonLabel = {
    'prediction_win': '승부예측 적중',
    'prediction_lose': '승부예측 참여',
    'prediction_draw': '승부예측 (무승부)',
    'attendance': '출석',
    'visit_record': '직관 기록',
    'mission_weekly': '주간미션 보상',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final empty = <String, dynamic>{};
      final results = await Future.wait([
        ApiService.getMyPoints(),
        ApiService.getPointsLeaderboard(),
        ApiService.getBadges().catchError((_) => empty),
        ApiService.getWeeklyMissions().catchError((_) => empty),
      ]);
      if (!mounted) return;
      setState(() {
        _mine = results[0];
        _leaders = (results[1]['leaderboard'] as List?) ?? [];
        _badges = (results[2]['badges'] as List?) ?? [];
        _missions = (results[3]['missions'] as List?) ?? [];
        _loading = false;
      });
    } catch (e) {
      debugPrint('points_screen: $e');
      if (mounted) {
        setState(() {
          _error = '포인트를 불러오지 못했어요';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sub = isDark ? const Color(0xFF9A9AA0) : const Color(0xFF707078);
    final cardColor = Pal.paper(isDark);
    final line = isDark ? const Color(0xFF26262C) : const Color(0xFFE8E8EC);

    return Scaffold(
      appBar: AppBar(title: const Text('포인트'), centerTitle: false),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: sub)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
                    children: [
                      _buildMyCard(cardColor, line, sub),
                      if (_missions.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildSection('주간미션 (월요일 초기화)', sub),
                        const SizedBox(height: 8),
                        ..._missions.map((m) => _missionTile(m as Map, cardColor, line, sub)),
                      ],
                      if (_badges.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildSection('뱃지', sub),
                        const SizedBox(height: 8),
                        _badgeGrid(cardColor, line, sub),
                      ],
                      const SizedBox(height: 20),
                      _buildSection('포인트 랭킹 TOP 50', sub),
                      const SizedBox(height: 8),
                      ...List.generate(_leaders.length,
                          (i) => _leaderRow(_leaders[i] as Map, cardColor, line, sub)),
                      if (_leaders.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                              child: Text('아직 랭킹 데이터가 없어요',
                                  style: TextStyle(fontSize: Typo.body, color: sub))),
                        ),
                      const SizedBox(height: 20),
                      _buildSection('최근 적립 내역', sub),
                      const SizedBox(height: 8),
                      ..._historyTiles(cardColor, line, sub),
                      const SizedBox(height: 16),
                      Text(
                        '적립: 승부예측 적중 +50 · 참여 +10 · 출석 +5 · 직관 기록 +20',
                        style: TextStyle(fontSize: Typo.caption, color: sub),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSection(String label, Color sub) => Text(label,
      style: TextStyle(
          fontSize: Typo.small, fontWeight: Typo.extra, color: sub, letterSpacing: 0.2));

  Widget _buildMyCard(Color cardColor, Color line, Color sub) {
    final total = (_mine?['total'] as num?)?.toInt() ?? 0;
    final rank = _mine?['rank'];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: line),
      ),
      child: Row(children: [
        const Icon(Icons.stars_rounded, size: 34, color: Color(0xFFD97706)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('내 포인트', style: TextStyle(fontSize: Typo.small, color: sub)),
            const SizedBox(height: 2),
            Text('${_comma(total)}P',
                style: const TextStyle(fontSize: Typo.h1, fontWeight: Typo.black)),
          ]),
        ),
        if (rank != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFD97706).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Text('전체 $rank위',
                style: const TextStyle(
                    fontSize: Typo.body, fontWeight: Typo.extra, color: Color(0xFFD97706))),
          ),
      ]),
    );
  }

  Widget _leaderRow(Map row, Color cardColor, Color line, Color sub) {
    final rank = row['rank'] as int? ?? 0;
    final top3 = rank <= 3;
    final medal = ['🥇', '🥈', '🥉'];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: top3 ? const Color(0xFFD97706).withValues(alpha: 0.4) : line),
      ),
      child: Row(children: [
        SizedBox(
          width: 30,
          child: top3
              ? Text(medal[rank - 1], style: const TextStyle(fontSize: Typo.title))
              : Text('$rank',
                  style: TextStyle(fontSize: Typo.body, fontWeight: Typo.extra, color: sub)),
        ),
        netCircleAvatar(
          url: (row['profile_image'] as String?) ?? '',
          radius: 14,
          child: const Icon(Icons.person, size: 15),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(row['nickname'] as String? ?? '?',
              style: const TextStyle(fontSize: 13.5, fontWeight: Typo.bold),
              overflow: TextOverflow.ellipsis),
        ),
        if ((row['wins'] as num? ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('적중 ${row['wins']}',
                style: TextStyle(fontSize: Typo.caption, color: sub)),
          ),
        Text('${_comma((row['total'] as num?)?.toInt() ?? 0)}P',
            style: const TextStyle(
                fontSize: 13.5, fontWeight: Typo.black, color: Color(0xFFD97706))),
      ]),
    );
  }

  List<Widget> _historyTiles(Color cardColor, Color line, Color sub) {
    final history = (_mine?['history'] as List?) ?? [];
    if (history.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
              child: Text('아직 적립 내역이 없어요\n경기 예측·출석·직관 기록으로 포인트를 모아보세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: Typo.body, color: sub, height: 1.5))),
        ),
      ];
    }
    return history.map<Widget>((h) {
      final m = h as Map;
      final reason = m['reason'] as String? ?? '';
      final at = (m['at'] as String? ?? '').replaceFirst('T', ' ');
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: line),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_reasonLabel[reason] ?? reason,
                  style: const TextStyle(fontSize: Typo.body, fontWeight: Typo.bold)),
              const SizedBox(height: 2),
              Text(at.length >= 16 ? at.substring(0, 16) : at,
                  style: TextStyle(fontSize: Typo.caption, color: sub)),
            ]),
          ),
          Text('+${m['points']}P',
              style: const TextStyle(
                  fontSize: Typo.subtitle, fontWeight: Typo.black, color: Color(0xFFD97706))),
        ]),
      );
    }).toList();
  }

  Widget _missionTile(Map m, Color cardColor, Color line, Color sub) {
    final done = m['done'] == true;
    final progress = (m['progress'] as num?)?.toInt() ?? 0;
    final goal = (m['goal'] as num?)?.toInt() ?? 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
            color: done ? const Color(0xFF16A34A).withValues(alpha: 0.45) : line),
      ),
      child: Row(children: [
        Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 20, color: done ? const Color(0xFF16A34A) : sub),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m['name'] as String? ?? '',
                style: const TextStyle(fontSize: Typo.body, fontWeight: Typo.bold)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.pill),
              child: LinearProgressIndicator(
                value: goal > 0 ? progress / goal : 0,
                minHeight: 5,
                backgroundColor: line,
                color: done ? const Color(0xFF16A34A) : const Color(0xFFD97706),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$progress/$goal',
              style: TextStyle(fontSize: 11.5, fontWeight: Typo.bold, color: sub)),
          Text('+${m['reward']}P',
              style: const TextStyle(
                  fontSize: Typo.small, fontWeight: Typo.black, color: Color(0xFFD97706))),
        ]),
      ]),
    );
  }

  Widget _badgeGrid(Color cardColor, Color line, Color sub) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.74),
      itemCount: _badges.length,
      itemBuilder: (_, i) {
        final b = _badges[i] as Map;
        final earned = b['earned'] == true;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
                color: earned ? const Color(0xFFD97706).withValues(alpha: 0.5) : line),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Opacity(
              opacity: earned ? 1 : 0.3,
              child: Text(b['emoji'] as String? ?? '🏅',
                  style: const TextStyle(fontSize: Typo.h2)),
            ),
            const SizedBox(height: 4),
            Text(b['name'] as String? ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: Typo.mini, fontWeight: Typo.bold,
                    color: earned ? null : sub)),
            const SizedBox(height: 2),
            Text(earned ? '획득!' : '${b['progress']}/${b['goal']}',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: Typo.medium,
                    color: earned ? const Color(0xFFD97706) : sub)),
          ]),
        );
      },
    );
  }

  String _comma(int n) =>
      n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}
