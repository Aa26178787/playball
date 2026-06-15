import 'package:flutter/material.dart';

import '../../api/api_service.dart';
import '../../utils/app_config.dart';
import '../../utils/share_card.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/common_widgets.dart';

/// 연말결산 — 시즌 직관/예측/포인트/최애 요약 (메가G). 마이페이지·오프시즌 홈서 진입.
class SeasonWrappedScreen extends StatefulWidget {
  final int? year;
  const SeasonWrappedScreen({super.key, this.year});

  @override
  State<SeasonWrappedScreen> createState() => _SeasonWrappedScreenState();
}

class _SeasonWrappedScreenState extends State<SeasonWrappedScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _error = false;
  final GlobalKey _cardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiService.getSeasonWrapped(year: widget.year);
      if (mounted) setState(() { _data = d; _loading = false; });
    } catch (e) {
      debugPrint('season_wrapped: $e');
      if (mounted) setState(() { _error = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final year = _data?['year'] ?? widget.year ?? DateTime.now().year;
    return Scaffold(
      appBar: AppBar(title: Text('$year 시즌 결산')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : _error
              ? AppErrorView(message: '결산을 불러오지 못했어요', onRetry: () {
                  setState(() { _loading = true; _error = false; });
                  _load();
                })
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RepaintBoundary(key: _cardKey, child: _wrappedCard(isDark, year)),
                      const SizedBox(height: 18),
                      if (AppConfig.enabled('share'))
                        FilledButton.icon(
                          onPressed: _share,
                          icon: const Icon(Icons.ios_share, size: 18),
                          label: const Text('결산 카드 공유'),
                        ),
                    ],
                  ),
                ),
    );
  }

  Future<void> _share() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final year = _data?['year'] ?? DateTime.now().year;
    await showShareCardDialog(context,
        card: _wrappedCard(isDark, year, forShare: true),
        filename: 'playball_wrapped_$year',
        shareText: 'PlayBall $year 시즌 결산 ⚾');
  }

  Widget _wrappedCard(bool isDark, dynamic year, {bool forShare = false}) {
    final v = (_data?['visits'] as Map?) ?? {};
    final p = (_data?['predictions'] as Map?) ?? {};
    final points = (_data?['points'] as num?)?.toInt() ?? 0;
    final attend = (_data?['attendance_days'] as num?)?.toInt() ?? 0;
    final favTeam = _data?['fav_team'] as String?;
    final favPlayer = _data?['fav_player'] as String?;
    final visitsTotal = (v['total'] as num?)?.toInt() ?? 0;
    final wins = (v['wins'] as num?)?.toInt() ?? 0;
    final losses = (v['losses'] as num?)?.toInt() ?? 0;
    final draws = (v['draws'] as num?)?.toInt() ?? 0;
    final stadiums = (v['stadiums'] as num?)?.toInt() ?? 0;
    final predCorrect = (p['correct'] as num?)?.toInt() ?? 0;
    final predTotal = (p['total'] as num?)?.toInt() ?? 0;

    return Container(
      width: forShare ? 340 : null,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1B2A4A), Color(0xFF2D6A4F)],
        ),
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$year 시즌 나의 야구',
              style: const TextStyle(fontSize: Typo.body, fontWeight: Typo.bold, color: Colors.white70)),
          const SizedBox(height: 14),
          _bigStat('직관', '$visitsTotal경기', '$wins승 $losses패${draws > 0 ? ' $draws무' : ''} · $stadiums개 구장'),
          const SizedBox(height: 14),
          _bigStat('승부예측', predTotal > 0 ? '$predCorrect/$predTotal 적중' : '참여 없음',
              predTotal > 0 ? '적중률 ${(predCorrect / predTotal * 100).round()}%' : ''),
          const SizedBox(height: 14),
          _bigStat('포인트', '$points P', '출석 $attend일'),
          if (favTeam != null || favPlayer != null) ...[
            const SizedBox(height: 14),
            _bigStat('최애', favTeam ?? favPlayer ?? '-',
                (favTeam != null && favPlayer != null) ? favPlayer : ''),
          ],
          const SizedBox(height: 16),
          const Text('PlayBall ⚾',
              style: TextStyle(fontSize: Typo.small, fontWeight: Typo.extra, color: Colors.white60)),
        ],
      ),
    );
  }

  Widget _bigStat(String label, String value, String sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: Colors.white54)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: Typo.h1, fontWeight: Typo.black, color: Colors.white)),
        if (sub.isNotEmpty)
          Text(sub, style: const TextStyle(fontSize: Typo.small, fontWeight: Typo.medium, color: Colors.white70)),
      ],
    );
  }
}
