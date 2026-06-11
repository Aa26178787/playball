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
  bool _loading = true;
  String? _error;

  static const _reasonLabel = {
    'prediction_win': '승부예측 적중',
    'prediction_lose': '승부예측 참여',
    'prediction_draw': '승부예측 (무승부)',
    'attendance': '출석',
    'visit_record': '직관 기록',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService.getMyPoints(),
        ApiService.getPointsLeaderboard(),
      ]);
      if (!mounted) return;
      setState(() {
        _mine = results[0] as Map<String, dynamic>?;
        _leaders =
            ((results[1] as Map<String, dynamic>?)?['leaderboard'] as List?) ?? [];
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
    final cardColor = isDark ? const Color(0xFF18181C) : Colors.white;
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
                                  style: TextStyle(fontSize: 13, color: sub))),
                        ),
                      const SizedBox(height: 20),
                      _buildSection('최근 적립 내역', sub),
                      const SizedBox(height: 8),
                      ..._historyTiles(cardColor, line, sub),
                      const SizedBox(height: 16),
                      Text(
                        '적립: 승부예측 적중 +50 · 참여 +10 · 출석 +5 · 직관 기록 +20',
                        style: TextStyle(fontSize: 11, color: sub),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSection(String label, Color sub) => Text(label,
      style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w800, color: sub, letterSpacing: 0.2));

  Widget _buildMyCard(Color cardColor, Color line, Color sub) {
    final total = (_mine?['total'] as num?)?.toInt() ?? 0;
    final rank = _mine?['rank'];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Row(children: [
        const Icon(Icons.stars_rounded, size: 34, color: Color(0xFFD97706)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('내 포인트', style: TextStyle(fontSize: 12, color: sub)),
            const SizedBox(height: 2),
            Text('${_comma(total)}P',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
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
                    fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFD97706))),
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: top3 ? const Color(0xFFD97706).withValues(alpha: 0.4) : line),
      ),
      child: Row(children: [
        SizedBox(
          width: 30,
          child: top3
              ? Text(medal[rank - 1], style: const TextStyle(fontSize: 16))
              : Text('$rank',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: sub)),
        ),
        netCircleAvatar(
          url: (row['profile_image'] as String?) ?? '',
          radius: 14,
          child: const Icon(Icons.person, size: 15),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(row['nickname'] as String? ?? '?',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis),
        ),
        if ((row['wins'] as num? ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('적중 ${row['wins']}',
                style: TextStyle(fontSize: 11, color: sub)),
          ),
        Text('${_comma((row['total'] as num?)?.toInt() ?? 0)}P',
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w900, color: Color(0xFFD97706))),
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
                  style: TextStyle(fontSize: 13, color: sub, height: 1.5))),
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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: line),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_reasonLabel[reason] ?? reason,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(at.length >= 16 ? at.substring(0, 16) : at,
                  style: TextStyle(fontSize: 11, color: sub)),
            ]),
          ),
          Text('+${m['points']}P',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFFD97706))),
        ]),
      );
    }).toList();
  }

  String _comma(int n) =>
      n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}
