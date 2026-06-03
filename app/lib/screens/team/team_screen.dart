import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shimmer/shimmer.dart';
import '../../api/api_service.dart';
import '../../utils/team_theme.dart';
import '../../utils/local_cache.dart';
import '../player/player_detail_screen.dart';
import '../mypage/my_page_screen.dart';
import 'team_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  List _teams = [];
  bool _isLoading = true;
  Set<int> _favoriteTeamIds = {};
  List _odds = [];
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ApiService.favoriteTeamsChanged.addListener(_loadFavoriteTeams);
    _tabController = TabController(length: 3, vsync: this);
    _loadTeams();
    _loadFavoriteTeams();
    _loadOdds();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ApiService.favoriteTeamsChanged.removeListener(_loadFavoriteTeams);
    _autoRefreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadTeams();
      _loadOdds();
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 120), (_) {
      if (!mounted) return;
      _loadTeams();
    });
  }

  Future<void> _loadTeams() async {
    final cached = await LocalCache.get('team_rankings') as List?;
    if (cached != null && mounted) {
      setState(() { _teams = cached; _isLoading = false; });
    } else {
      if (mounted) setState(() => _isLoading = true);
    }
    try {
      final data = await ApiService.getTeamRankings();
      final rankings = data['rankings'] as List? ?? [];
      await LocalCache.set('team_rankings', rankings);
      if (mounted) setState(() { _teams = rankings; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadOdds() async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final data = await ApiService.getPostseasonOdds();
        final odds = (data['odds'] as List? ?? []).cast<Map>();
        if (mounted) setState(() => _odds = odds);
        return;
      } catch (_) {
        if (attempt < 2) await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _loadFavoriteTeams() async {
    try {
      final data = await ApiService.getFavoriteTeams();
      final teams = (data['teams'] as List? ?? []);
      if (mounted) {
        setState(() {
          _favoriteTeamIds = teams.map((t) => t['id'] as int).toSet();
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        title: const Text('순위'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: '마이페이지',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyPageScreen())),
          ),
        ],
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF1A237E),
          indicatorWeight: 2.5,
          labelColor: const Color(0xFF1A237E),
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: '팀 순위'),
            Tab(text: '부문별 순위'),
            Tab(text: '팀 기록'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTeamRankings(),
          const PlayerRankingsTab(),
          const TeamStatsTab(),
        ],
      ),
    );
  }

  Widget _buildTeamShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, 12, 12, (ApiService.myTeamData.value.isNotEmpty ? 144.0 : 92.0) + MediaQuery.of(context).padding.bottom),
      itemCount: 10,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(width: 28, height: 28, color: Colors.white),
              const SizedBox(width: 10),
              Container(width: 36, height: 36, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 60, height: 13, color: Colors.white),
                  const SizedBox(height: 5),
                  Container(width: 80, height: 10, color: Colors.white),
                ],
              )),
              Container(width: 50, height: 13, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeamRankings() {
    if (_isLoading) return _buildTeamShimmer();
    final rankCounts = <int, int>{};
    for (final t in _teams) {
      final r = t['rank'] as int? ?? 0;
      rankCounts[r] = (rankCounts[r] ?? 0) + 1;
    }
    return RefreshIndicator(
      onRefresh: () async { await _loadTeams(); await _loadOdds(); },
      child: ListView(
        padding: EdgeInsets.fromLTRB(12, 12, 12, (ApiService.myTeamData.value.isNotEmpty ? 144.0 : 92.0) + MediaQuery.of(context).padding.bottom),
        children: [
          ..._teams.map((team) {
            final r = team['rank'] as int? ?? 0;
            return _buildTeamRow(team, isTied: (rankCounts[r] ?? 1) > 1);
          }),
          if (_odds.isNotEmpty) _buildPostseasonOdds(),
        ],
      ),
    );
  }

  Widget _buildPostseasonOdds() {
    // 단계별 색상 (상위 → 하위)
    const Color cKs = Color(0xFFFFB300);    // KS 직행 (1위) — 금색
    const Color cPo = Color(0xFF1565C0);    // PO 직행 (2위) — 진파랑
    const Color cSpo = Color(0xFF1976D2);   // 준PO 직행 (3위) — 파랑
    const Color cWc4 = Color(0xFF26A69A);   // WC 4위 — 청록
    const Color cWc5 = Color(0xFF66BB6A);   // WC 5위 — 연두
    const Color cOut = Color(0xFFBDBDBD);   // 탈락 — 회색
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            const Text('포스트시즌 진출 확률', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('Monte Carlo 100,000회', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          ],
        ),
        const SizedBox(height: 10),
        ..._odds.map((o) {
          final code = o['short_name'] as String? ?? '';
          final color = teamColor(code);
          final ks = ((o['ks_direct_prob'] as num? ?? o['ks_prob'] as num? ?? 0) * 100).toDouble();
          final po = ((o['po_direct_prob'] as num? ?? 0) * 100).toDouble();
          final spo = ((o['spo_direct_prob'] as num? ?? 0) * 100).toDouble();
          final wc4 = ((o['wc_seed4_prob'] as num? ?? 0) * 100).toDouble();
          final wc5 = ((o['wc_seed5_prob'] as num? ?? 0) * 100).toDouble();
          final ps = ks + po + spo + wc4 + wc5;
          final out = (100.0 - ps).clamp(0.0, 100.0);
          final elo = (o['elo'] as num? ?? 1500).toDouble();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TeamLogo(teamCode: code, size: 30),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(o['name'] as String? ?? '',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 6),
                          Text('Elo ${elo.toStringAsFixed(0)}',
                              style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                          const Spacer(),
                          Text('PS ${ps.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold,
                                color: ps >= 90 ? color : (ps >= 50 ? color.withValues(alpha: 0.7) : Colors.grey),
                              )),
                        ],
                      ),
                      const SizedBox(height: 5),
                      // 단계별 누적 horizontal stacked bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 12,
                          child: Row(
                            children: [
                              if (ks > 0) Flexible(flex: (ks * 100).round(), child: Container(color: cKs)),
                              if (po > 0) Flexible(flex: (po * 100).round(), child: Container(color: cPo)),
                              if (spo > 0) Flexible(flex: (spo * 100).round(), child: Container(color: cSpo)),
                              if (wc4 > 0) Flexible(flex: (wc4 * 100).round(), child: Container(color: cWc4)),
                              if (wc5 > 0) Flexible(flex: (wc5 * 100).round(), child: Container(color: cWc5)),
                              if (out > 0) Flexible(flex: (out * 100).round(),
                                  child: Container(color: cOut.withValues(alpha: 0.3))),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 단계별 % 텍스트
                      Wrap(
                        spacing: 6, runSpacing: 2,
                        children: [
                          if (ks >= 10) _stagePct('한국시리즈', ks, cKs),
                          if (po >= 10) _stagePct('플레이오프', po, cPo),
                          if (spo >= 10) _stagePct('준플레이오프', spo, cSpo),
                          if (wc4 >= 10) _stagePct('와일드카드 홈', wc4, cWc4),
                          if (wc5 >= 10) _stagePct('와일드카드 원정', wc5, cWc5),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('* Elo 레이팅 + 남은 schedule(홈/원정/상대 강도 반영) · 표기 임계값 10% (미만 단계는 막대에만 반영)',
              style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ),
      ],
    );
  }

  Widget _legendChip(Color c, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[700])),
    ]);
  }

  Widget _stagePct(String label, double pct, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: c.withValues(alpha: 0.4), width: 0.6),
      ),
      child: Text('$label ${pct.toStringAsFixed(1)}%',
          style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w700)),
    );
  }

  String _streakText(int streak) {
    if (streak > 0) return '$streak연승';
    if (streak < 0) return '${-streak}연패';
    return '-';
  }

  Color _streakColor(int streak) {
    if (streak > 0) return Colors.blue;
    if (streak < 0) return Colors.red;
    return Colors.grey;
  }

  Color _seriesLabelColor(String label) {
    if (label.contains('스윕 승')) return const Color(0xFF1565C0);
    if (label.contains('위닝')) return const Color(0xFF1976D2);
    if (label.contains('스플릿')) return Colors.grey;
    if (label.contains('루징')) return const Color(0xFFE53935);
    if (label.contains('스윕 패')) return const Color(0xFFC62828);
    return Colors.grey;
  }

  Widget _buildTeamRow(Map<String, dynamic> team, {bool isTied = false}) {
    final code = team['short_name'] as String? ?? '';
    final gb = team['games_behind'];
    final gbNum = gb as num?;
    final gbText = gbNum == null || gbNum == 0 ? '-' : gbNum.toStringAsFixed(1);
    final recent5 = (team['recent_5'] as List?)?.cast<String>() ?? [];
    final wins = team['wins'] as int? ?? 0;
    final losses = team['losses'] as int? ?? 0;
    final draws = team['draws'] as int? ?? 0;
    final totalGames = team['total_games'] as int? ?? 0;
    final streak = team['streak'] as int? ?? 0;
    final rank = team['rank'] as int? ?? 0;
    final winRate = (team['win_rate'] as num?)?.toStringAsFixed(3) ?? '-';

    final Color rankBg;
    if (isTied) {
      rankBg = const Color(0xFFF57F17); // 주황 (공동순위)
    } else if (rank <= 5) {
      rankBg = const Color(0xFF1565C0); // 파랑 (상위 5)
    } else {
      rankBg = const Color(0xFF78909C); // 회색 (하위 5)
    }

    final isFav = _favoriteTeamIds.contains(team['id'] as int? ?? -1);
    final pythag = (team['pythag_winpct'] as num?)?.toStringAsFixed(3) ?? '-';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isFav ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isFav
            ? const BorderSide(color: Color(0xFF1A237E), width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TeamDetailScreen(team: team)),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── 헤더: 순위 + 로고 + 팀명 ───
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 30,
                    decoration: BoxDecoration(color: rankBg, borderRadius: BorderRadius.circular(15)),
                    alignment: Alignment.center,
                    child: Text(
                      '$rank위',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TeamLogo(teamCode: code, size: 36, logoUrl: team['logo_url']),
                  const SizedBox(width: 10),
                  Text(
                    team['name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (isFav) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.star, size: 16, color: Color(0xFF1A237E)),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, thickness: 0.5),
              const SizedBox(height: 10),
              // ─── 스탯 행: G / 승-패-무 / 승률 / GB ───
              Row(
                children: [
                  _statCell('경기', '$totalGames'),
                  _statDivider(),
                  _statCell('승', '$wins', valueColor: const Color(0xFF1565C0)),
                  _statDivider(),
                  _statCell('패', '$losses', valueColor: const Color(0xFFC62828)),
                  _statDivider(),
                  _statCell('무', '$draws'),
                  _statDivider(),
                  _statCell('승률', winRate),
                  _statDivider(),
                  _statCell('게임차', gbText),
                  _statDivider(),
                  _statCell('피타', pythag),
                ],
              ),
              const SizedBox(height: 8),
              // ─── 승패 분할 바 ───
              if (totalGames > 0) ...[
                Row(
                  children: [
                    Text('$wins승', style: const TextStyle(fontSize: 11, color: Color(0xFF1565C0), fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (draws > 0)
                      Text('$draws무', style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
                    if (draws > 0) const Spacer(),
                    Text('$losses패', style: const TextStyle(fontSize: 11, color: Color(0xFFC62828), fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        Flexible(
                          flex: wins > 0 ? wins : 0,
                          child: Container(color: const Color(0xFF1565C0)),
                        ),
                        if (draws > 0)
                          Flexible(
                            flex: draws,
                            child: Container(color: const Color(0xFF90A4AE)),
                          ),
                        Flexible(
                          flex: losses > 0 ? losses : 0,
                          child: Container(color: const Color(0xFFC62828)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              // ─── 최근 5경기 + 연승 ───
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Text('최근 5경기',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                    const SizedBox(width: 10),
                    ...recent5.map((r) => _recentDot(r)),
                    const Spacer(),
                    Text(
                      _streakText(streak),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _streakColor(streak),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCell(String label, String value, {Color? valueColor}) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: valueColor)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(width: 0.5, height: 28, color: Colors.grey[300]);
  }

  Widget _recentDot(String result) {
    Color color;
    String label;
    switch (result) {
      case 'W': color = const Color(0xFF1565C0); label = '승'; break;
      case 'L': color = const Color(0xFFC62828); label = '패'; break;
      default:  color = Colors.grey; label = '무';
    }
    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      alignment: Alignment.center,
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}


Widget _buildSegmentControl(bool isDark, List<String> labels, TabController ctrl) {
  return Container(
    margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
    height: 36,
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: List.generate(labels.length, (i) {
        final selected = ctrl.index == i;
        return Expanded(
          child: GestureDetector(
            onTap: () => ctrl.animateTo(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: selected
                    ? (isDark ? const Color(0xFF3A3A3C) : Colors.white)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                boxShadow: selected
                    ? [const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))]
                    : [],
              ),
              alignment: Alignment.center,
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'Pretendard',
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? const Color(0xFF1A237E) : Colors.grey,
                ),
              ),
            ),
          ),
        );
      }),
    ),
  );
}

// ===== 팀 기록 탭 =====

class TeamStatsTab extends StatefulWidget {
  const TeamStatsTab({super.key});

  @override
  State<TeamStatsTab> createState() => _TeamStatsTabState();
}

class _TeamStatsTabState extends State<TeamStatsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _teams = [];
  bool _loading = true;
  bool _error = false;

  static const _battingCategories = [
    {'value': 'avg',           'label': '타율',    'isLow': false},
    {'value': 'home_runs',     'label': '홈런',    'isLow': false},
    {'value': 'rbis',          'label': '타점',    'isLow': false},
    {'value': 'hits',          'label': '안타',    'isLow': false},
    {'value': 'runs',          'label': '득점',    'isLow': false},
    {'value': 'stolen_bases',  'label': '도루',    'isLow': false},
    {'value': 'ops',           'label': 'OPS',     'isLow': false},
    {'value': 'strikeouts',    'label': '삼진',    'isLow': true},
    {'value': 'walks',         'label': '볼넷',    'isLow': false},
  ];

  static const _pitchingCategories = [
    {'value': 'era',            'label': '방어율',   'isLow': true},
    {'value': 'whip',           'label': 'WHIP',    'isLow': true},
    {'value': 'strikeouts',     'label': '탈삼진',  'isLow': false},
    {'value': 'wins',           'label': '승리',    'isLow': false},
    {'value': 'saves',          'label': '세이브',  'isLow': false},
    {'value': 'holds',          'label': '홀드',    'isLow': false},
    {'value': 'innings_pitched','label': '이닝',    'isLow': false},
    {'value': 'losses',         'label': '패배',    'isLow': true},
  ];

  String _battingSort = 'avg';
  String _pitchingSort = 'era';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() { if (mounted) setState(() {}); });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _error = false; });
    // Phase 1: 캐시 즉시 표시 (TTL 600초로 단축 — 필드명 캐시 문제 방지)
    final cached = await LocalCache.get('team_all_stats', maxAgeSeconds: 600) as Map?;
    if (cached != null && mounted) {
      setState(() {
        _teams = List<Map<String, dynamic>>.from(cached['teams'] ?? []);
        _loading = false;
      });
    } else {
      if (mounted) setState(() => _loading = true);
    }
    // Phase 2: 백그라운드 갱신
    try {
      final data = await ApiService.getTeamAllStats();
      if (!mounted) return;
      await LocalCache.set('team_all_stats', data);
      setState(() {
        _teams = List<Map<String, dynamic>>.from(data['teams'] ?? []);
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; if (_teams.isEmpty) _error = true; });
    }
  }

  String _fmtBatting(Map batting, String sort) {
    final v = batting[sort];
    if (v == null) return '-';
    if (sort == 'avg' || sort == 'ops') return (v as num).toStringAsFixed(3);
    return '$v';
  }

  String _fmtPitching(Map pitching, String sort) {
    final v = pitching[sort];
    if (v == null) return '-';
    if (sort == 'era' || sort == 'whip') return (v as num).toStringAsFixed(2);
    if (sort == 'innings_pitched') return (v as num).toStringAsFixed(1);
    return '$v';
  }

  List<Map<String, dynamic>> _sortedTeams(String field, bool isBatting, bool isLow) {
    final sorted = List<Map<String, dynamic>>.from(_teams);
    sorted.sort((a, b) {
      final av = ((isBatting ? a['batting'] : a['pitching']) ?? {})[field] ?? 0;
      final bv = ((isBatting ? b['batting'] : b['pitching']) ?? {})[field] ?? 0;
      final cmp = (av as num).compareTo(bv as num);
      return isLow ? cmp : -cmp;
    });
    return sorted;
  }

  Widget _buildCategoryChips(List<Map<String, dynamic>> cats, String selected, Function(String) onSelect) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        itemCount: cats.length,
        itemBuilder: (_, i) {
          final cat = cats[i];
          final sel = selected == cat['value'];
          return GestureDetector(
            onTap: () => onSelect(cat['value'] as String),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFF1A237E) : Colors.grey.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                cat['label'] as String,
                style: TextStyle(
                  fontSize: 12,
                  color: sel ? Colors.white : null,
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTeamStatList(List<Map<String, dynamic>> cats, String selected, bool isBatting) {
    final catMap = cats.firstWhere((c) => c['value'] == selected);
    final isLow = catMap['isLow'] as bool;
    final label = catMap['label'] as String;
    final sorted = _sortedTeams(selected, isBatting, isLow);
    final best = sorted.first;
    final bestVal = ((isBatting ? best['batting'] : best['pitching']) ?? {})[selected];

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, 8, 12, (ApiService.myTeamData.value.isNotEmpty ? 144.0 : 92.0) + MediaQuery.of(context).padding.bottom),
      itemCount: sorted.length,
      itemBuilder: (_, i) {
        final t = sorted[i];
        final stats = (isBatting ? t['batting'] : t['pitching']) as Map? ?? {};
        final rawVal = stats[selected];
        final displayVal = isBatting
            ? _fmtBatting(stats, selected)
            : _fmtPitching(stats, selected);
        final isBest = i == 0;
        final code = t['short_name'] as String? ?? '';
        final color = teamColor(code);

        // 바 너비 비율
        double barFraction = 0;
        if (rawVal != null && bestVal != null && (bestVal as num) != 0) {
          final ratio = (rawVal as num) / bestVal;
          barFraction = isLow ? (bestVal / (rawVal as num)) : ratio.toDouble();
          barFraction = barFraction.clamp(0.05, 1.0);
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isBest
                ? const Color(0xFF1A237E).withOpacity(0.06)
                : Colors.grey.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: isBest
                ? Border.all(color: const Color(0xFF1A237E).withOpacity(0.2))
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '${i + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isBest ? const Color(0xFF1A237E) : Colors.grey[600],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TeamLogo(teamCode: code, size: 30, logoUrl: t['logo_url']),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t['name'] as String? ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isBest ? const Color(0xFF1A237E) : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    LayoutBuilder(builder: (_, box) {
                      return Stack(
                        children: [
                          Container(
                            height: 5,
                            width: box.maxWidth,
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          Container(
                            height: 5,
                            width: box.maxWidth * barFraction,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    displayVal,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isBest ? const Color(0xFF1A237E) : null,
                    ),
                  ),
                  Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E), strokeWidth: 2.5));
    }
    if (_error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('데이터를 불러오지 못했습니다', style: TextStyle(color: Colors.grey[500])),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        _buildSegmentControl(isDark, ['타격', '투수'], _tabController),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              Column(children: [
                _buildCategoryChips(
                  List<Map<String, dynamic>>.from(_battingCategories),
                  _battingSort,
                  (v) => setState(() => _battingSort = v),
                ),
                const SizedBox(height: 4),
                Expanded(child: RefreshIndicator(
                  onRefresh: _load,
                  child: _buildTeamStatList(
                    List<Map<String, dynamic>>.from(_battingCategories),
                    _battingSort,
                    true,
                  ),
                )),
              ]),
              Column(children: [
                _buildCategoryChips(
                  List<Map<String, dynamic>>.from(_pitchingCategories),
                  _pitchingSort,
                  (v) => setState(() => _pitchingSort = v),
                ),
                const SizedBox(height: 4),
                Expanded(child: RefreshIndicator(
                  onRefresh: _load,
                  child: _buildTeamStatList(
                    List<Map<String, dynamic>>.from(_pitchingCategories),
                    _pitchingSort,
                    false,
                  ),
                )),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

// ===== 부문별 선수 순위 탭 =====

class PlayerRankingsTab extends StatefulWidget {
  const PlayerRankingsTab({super.key});

  @override
  State<PlayerRankingsTab> createState() => _PlayerRankingsTabState();
}

class _PlayerRankingsTabState extends State<PlayerRankingsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const List<Map<String, String>> _hitterCategories = [
    {'value': 'avg',          'label': '타율'},
    {'value': 'home_runs',    'label': '홈런'},
    {'value': 'rbis',         'label': '타점'},
    {'value': 'hits',         'label': '안타'},
    {'value': 'stolen_bases', 'label': '도루'},
    {'value': 'ops',          'label': '출루장타율'},
    {'value': 'war',          'label': '대체승리기여'},
  ];

  static const List<Map<String, String>> _pitcherCategories = [
    {'value': 'era',        'label': '평균자책점'},
    {'value': 'wins',       'label': '승리'},
    {'value': 'strikeouts', 'label': '탈삼진'},
    {'value': 'saves',      'label': '세이브'},
    {'value': 'holds',      'label': '홀드'},
    {'value': 'whip',       'label': '이닝당출루'},
    {'value': 'war',        'label': '대체승리기여'},
  ];

  String _hitterSort = 'avg';
  String _pitcherSort = 'era';

  final Map<String, List> _hitterCache = {};
  final Map<String, List> _pitcherCache = {};
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() { if (mounted) setState(() {}); });
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (mounted) setState(() => _error = false);
    // Phase 1: 캐시에서 즉시 표시
    final cached = await LocalCache.get('player_rankings') as Map?;
    if (cached != null && mounted) {
      final h = (cached['hitters'] as Map?) ?? {};
      final p = (cached['pitchers'] as Map?) ?? {};
      setState(() {
        for (final c in _hitterCategories) {
          _hitterCache[c['value']!] = (h[c['value']!] as List?) ?? [];
        }
        for (final c in _pitcherCategories) {
          _pitcherCache[c['value']!] = (p[c['value']!] as List?) ?? [];
        }
        _loading = false;
      });
    } else {
      if (mounted) setState(() => _loading = true);
    }
    // Phase 2: 백그라운드 갱신
    try {
      final data = await ApiService.getPlayerRankings();
      if (!mounted) return;
      await LocalCache.set('player_rankings', data);
      final h = (data['hitters'] as Map?) ?? {};
      final p = (data['pitchers'] as Map?) ?? {};
      setState(() {
        for (final c in _hitterCategories) {
          _hitterCache[c['value']!] = (h[c['value']!] as List?) ?? [];
        }
        for (final c in _pitcherCategories) {
          _pitcherCache[c['value']!] = (p[c['value']!] as List?) ?? [];
        }
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        final allEmpty = _hitterCache.values.every((l) => l.isEmpty);
        if (allEmpty) _error = true;
      });
    }
  }

  Future<List> _fetchHitter(String sort) async {
    final qualified = sort == 'avg' || sort == 'ops';
    try {
      final data = await ApiService.getHitters(sortBy: sort, limit: 10, qualified: qualified);
      return data['hitters'] ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<List> _fetchPitcher(String sort) async {
    final qualified = sort == 'era' || sort == 'whip';
    try {
      final data = await ApiService.getPitchers(sortBy: sort, limit: 10, qualified: qualified);
      return data['pitchers'] ?? [];
    } catch (_) {
      return [];
    }
  }

  String _hitterStatValue(Map p) {
    switch (_hitterSort) {
      case 'avg':          return (p['avg'] as num?)?.toStringAsFixed(3) ?? '-';
      case 'home_runs':    return '${p['home_runs'] ?? '-'}';
      case 'rbis':         return '${p['rbis'] ?? '-'}';
      case 'hits':         return '${p['hits'] ?? '-'}';
      case 'stolen_bases': return '${p['stolen_bases'] ?? '-'}';
      case 'ops':          return (p['ops'] as num?)?.toStringAsFixed(3) ?? '-';
      case 'war':          return (p['war'] as num?)?.toStringAsFixed(1) ?? '-';
      default:             return '-';
    }
  }

  String _pitcherStatValue(Map p) {
    switch (_pitcherSort) {
      case 'era':        return (p['era'] as num?)?.toStringAsFixed(2) ?? '-';
      case 'wins':       return '${p['wins'] ?? '-'}';
      case 'strikeouts': return '${p['strikeouts'] ?? '-'}';
      case 'saves':      return '${p['saves'] ?? '-'}';
      case 'holds':      return '${p['holds'] ?? '-'}';
      case 'whip':       return (p['whip'] as num?)?.toStringAsFixed(2) ?? '-';
      case 'war':        return (p['war'] as num?)?.toStringAsFixed(1) ?? '-';
      default:           return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        _buildSegmentControl(isDark, ['타자', '투수'], _tabController),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildHitterRankings(),
              _buildPitcherRankings(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChips(List<Map<String, String>> categories, String selected, Function(String) onSelect) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = selected == cat['value'];
          return GestureDetector(
            onTap: () => onSelect(cat['value']!),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1A237E) : Colors.grey.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                cat['label']!,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected ? Colors.white : null,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPodium(List players, String Function(Map) statValue) {
    if (players.length < 3) return const SizedBox.shrink();
    final p1 = players[0] as Map;
    final p2 = players[1] as Map;
    final p3 = players[2] as Map;

    Widget slot(Map p, int rank, double height, Color medalColor) {
      final img = p['profile_image'] as String?;
      return GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => PlayerDetailScreen(
              playerId: p['id'],
              initialData: {'name': p['name'], 'team': p['team_name'], 'profile_image': p['profile_image'], 'position': p['position'], 'player_type': p['player_type']},
            ))),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                CircleAvatar(
                  radius: rank == 1 ? 32 : 24,
                  backgroundImage: (img != null && img.isNotEmpty) ? CachedNetworkImageProvider(img) : null,
                  backgroundColor: medalColor.withValues(alpha: 0.15),
                  child: (img == null || img.isEmpty)
                      ? Icon(Icons.person, size: rank == 1 ? 28 : 20, color: medalColor)
                      : null,
                ),
                Positioned(
                  bottom: -6, right: -6,
                  child: Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      color: medalColor, shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [BoxShadow(color: medalColor.withValues(alpha: 0.4), blurRadius: 3)],
                    ),
                    alignment: Alignment.center,
                    child: Text('$rank', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(p['name'] ?? '',
                style: TextStyle(fontSize: rank == 1 ? 13 : 11, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
            Text(p['team'] ?? '',
                style: TextStyle(fontSize: 9, color: Colors.grey[600]), textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(statValue(p),
                style: TextStyle(fontSize: rank == 1 ? 16 : 14, fontWeight: FontWeight.bold, color: medalColor),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Container(
              width: rank == 1 ? 90 : 72,
              height: height,
              decoration: BoxDecoration(
                color: medalColor.withValues(alpha: 0.18),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
              alignment: Alignment.center,
              child: Text('$rank위', style: TextStyle(fontSize: 11, color: medalColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(child: slot(p2, 2, 52, const Color(0xFFC0C0C0))),
          Expanded(child: slot(p1, 1, 80, const Color(0xFFFFD700))),
          Expanded(child: slot(p3, 3, 38, const Color(0xFFCD7F32))),
        ],
      ),
    );
  }

  Widget _buildErrorRetry() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text('데이터를 불러오지 못했습니다', style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }

  Widget _buildRankingsContent(List players, String Function(Map) statValue, String label) {
    final top3 = players.take(3).toList();
    final rest = players.skip(3).toList();
    return ListView(
      padding: EdgeInsets.only(bottom: (ApiService.myTeamData.value.isNotEmpty ? 144.0 : 92.0) + MediaQuery.of(context).padding.bottom),
      children: [
        if (top3.length >= 3) ...[
          _buildPodium(top3, statValue),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const SizedBox(width: 32, child: Text('순위', style: TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center)),
              const SizedBox(width: 56),
              const Expanded(child: Text('선수', style: TextStyle(fontSize: 11, color: Colors.grey))),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(width: 8),
            ]),
          ),
          const Divider(height: 8),
        ],
        ...rest.asMap().entries.map((e) {
          final p = e.value as Map;
          return _buildRankRow(
            rank: e.key + 4,
            playerId: p['id'],
            name: p['name'] ?? '',
            team: p['team'] ?? '',
            teamCode: p['team_code'] ?? '',
            profileImage: p['profile_image'] as String?,
            label: label,
            value: statValue(p),
          );
        }),
      ],
    );
  }

  Widget _buildHitterRankings() {
    final label = _hitterCategories.firstWhere((c) => c['value'] == _hitterSort)['label']!;
    final rankings = _hitterCache[_hitterSort] ?? [];
    return Column(
      children: [
        _buildCategoryChips(_hitterCategories, _hitterSort,
            (val) => setState(() => _hitterSort = val)),
        const SizedBox(height: 4),
        Expanded(
          child: _loading
              ? _buildRankShimmer()
              : _error
                  ? _buildErrorRetry()
                  : rankings.isEmpty
                      ? const Center(child: Text('데이터가 없습니다'))
                      : _buildRankingsContent(rankings, _hitterStatValue, label),
        ),
      ],
    );
  }

  Widget _buildPitcherRankings() {
    final label = _pitcherCategories.firstWhere((c) => c['value'] == _pitcherSort)['label']!;
    final rankings = _pitcherCache[_pitcherSort] ?? [];
    return Column(
      children: [
        _buildCategoryChips(_pitcherCategories, _pitcherSort,
            (val) => setState(() => _pitcherSort = val)),
        const SizedBox(height: 4),
        Expanded(
          child: _loading
              ? _buildRankShimmer()
              : _error
                  ? _buildErrorRetry()
                  : rankings.isEmpty
                      ? const Center(child: Text('데이터가 없습니다'))
                      : _buildRankingsContent(rankings, _pitcherStatValue, label),
        ),
      ],
    );
  }

  Widget _buildRankShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, 8, 12, (ApiService.myTeamData.value.isNotEmpty ? 144.0 : 92.0) + MediaQuery.of(context).padding.bottom),
      itemCount: 10,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(width: 32, height: 15, color: Colors.white),
              const SizedBox(width: 8),
              Container(width: 36, height: 36, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 70, height: 13, color: Colors.white),
                  const SizedBox(height: 5),
                  Container(width: 45, height: 10, color: Colors.white),
                ],
              )),
              Container(width: 40, height: 18, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRankRow({
    required int rank,
    required int playerId,
    required String name,
    required String team,
    required String teamCode,
    required String label,
    required String value,
    String? profileImage,
  }) {
    final isTop3 = rank <= 3;
    final rankColors = [Colors.amber, Colors.grey[600]!, Colors.brown];
    final color = teamColor(teamCode);

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: playerId)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isTop3
              ? rankColors[rank - 1].withOpacity(0.08)
              : Colors.grey.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isTop3 ? rankColors[rank - 1] : Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 선수 사진 (없으면 팀 컬러 이니셜)
            CircleAvatar(
              radius: 18,
              backgroundColor: color,
              backgroundImage: (profileImage != null && profileImage.isNotEmpty)
                  ? CachedNetworkImageProvider(profileImage)
                  : null,
              child: (profileImage == null || profileImage.isEmpty)
                  ? Text(
                      teamDisplayName(teamCode).substring(0, teamDisplayName(teamCode).length.clamp(0, 2)),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(team, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
