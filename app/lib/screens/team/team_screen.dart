import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import '../../utils/app_theme.dart';
import 'dart:async';
import 'package:shimmer/shimmer.dart';
import '../../api/api_service.dart';
import '../../widgets/common_widgets.dart';
import '../../utils/team_theme.dart';
import '../../utils/local_cache.dart';
import '../player/player_detail_screen.dart';
import '../mypage/my_page_screen.dart';
import '../stadium/stadium_screen.dart';
import 'team_detail_screen.dart';
import '../../utils/web_image.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';

// 팀 홈구장 → (구장 전체명, StadiumScreen 인덱스)
const Map<String, (String, int)> _kHomeStadium = {
  'LG': ('잠실야구장', 0), 'OB': ('잠실야구장', 1), 'WO': ('고척스카이돔', 2),
  'KT': ('수원KT위즈파크', 3), 'SK': ('인천SSG랜더스필드', 4), 'HH': ('대전한화생명볼파크', 5),
  'HT': ('광주기아챔피언스필드', 6), 'SS': ('대구삼성라이온즈파크', 7),
  'NC': ('창원NC파크', 8), 'LT': ('사직야구장', 9),
};

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
  final Set<int> _expandedTeamIds = {};
  String _period = 'full'; // 'full' | 'first_half' | 'last_10'
  bool _showPsView = false; // 팀 순위 탭 내 PS 확률 보기 토글
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
    final cacheKey = 'team_rankings_$_period';
    final cached = await LocalCache.get(cacheKey) as List?;
    if (cached != null && mounted) {
      setState(() { _teams = cached; _isLoading = false; });
    } else {
      if (mounted) setState(() => _isLoading = true);
    }
    try {
      final data = await ApiService.getTeamRankings(period: _period);
      final rankings = data['rankings'] as List? ?? [];
      await LocalCache.set(cacheKey, rankings);
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
    } catch (e) { debugPrint('team_screen: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paper = isDark ? const Color(0xFF18181C) : Colors.white;
    final ink   = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final ink3  = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final sub   = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final line  = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
    final line2 = isDark ? const Color(0xFF33333A) : const Color(0xFFE0E0E4);
    Widget hdrBtn({required IconData icon, required String tip, required VoidCallback onTap}) =>
        Tooltip(
          message: tip,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                border: Border.all(color: line2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: ink3),
            ),
          ),
        );
    return Scaffold(
      body: Column(children: [
          // ── 헤더 (탭 공통) — 상태바 영역까지 paper (SafeArea 단차 방지, 06-13) ──
          Container(
            color: paper,
            padding: EdgeInsets.only(top: MediaQuery.of(context).viewPadding.top),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: Row(children: [
                  Text('순위',
                      style: TextStyle(fontSize: Typo.h2, fontWeight: Typo.extra,
                          color: ink, letterSpacing: -0.5)),
                  const Spacer(),
                  hdrBtn(
                    icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                    tip: isDark ? '라이트 모드' : '다크 모드',
                    onTap: () => context.read<ThemeProvider>().toggle(),
                  ),
                  const SizedBox(width: 7),
                  hdrBtn(
                    icon: Icons.person_outline,
                    tip: '마이페이지',
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const MyPageScreen())),
                  ),
                ]),
              ),
              TabBar(
                controller: _tabController,
                labelColor: ink,
                unselectedLabelColor: sub,
                indicatorColor: ink,
                indicatorWeight: 2,
                dividerColor: line,
                labelStyle: const TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra),
                unselectedLabelStyle: const TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.medium),
                tabs: const [
                  Tab(text: '팀 순위'),
                  Tab(text: '부문별 순위'),
                  Tab(text: '팀 기록'),
                ],
              ),
            ]),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTeamRankings(),
                const PlayerRankingsTab(),
                const TeamStatsTab(),
              ],
            ),
          ),
        ]),
    );
  }

  Widget _buildTeamShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, 12, 12, (ApiService.myTeamData.value.isNotEmpty ? 144.0 : 92.0) + MediaQuery.of(context).padding.bottom),
      itemCount: 10,
      itemBuilder: (_, _) => Shimmer.fromColors(
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
    final oddsById = <int, Map>{
      for (final o in _odds) (o['id'] as int? ?? 0): o,
    };
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? SemColor.panelDark : const Color(0xFFFAFAFB);
    return Container(
      color: scaffoldBg,
      child: RefreshIndicator(
        onRefresh: () async { await _loadTeams(); await _loadOdds(); },
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16,
              (ApiService.myTeamData.value.isNotEmpty ? 144.0 : 92.0) + MediaQuery.of(context).padding.bottom),
          children: [
            // ── 필터 chip (stub: mv/전반기/최근10 백엔드 미지원) ──
            _buildFilterChips(isDark),
            const SizedBox(height: 8),
            if (_showPsView)
              // ── PS 확률 보기 (세부 카테고리) ──
              ..._psChildren(isDark)
            else ...[
              // ── 1~5위 ──
              ..._teams.where((t) => (t['rank'] as int? ?? 99) <= 5).map((t) {
                final id = t['id'] as int? ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _buildCardRow(t, oddsById[id], isDark),
                );
              }),
              // ── CutLine (가을야구 진출선) ──
              _buildCutLine(isDark),
              // ── 6~10위 ──
              ..._teams.where((t) => (t['rank'] as int? ?? 0) > 5).map((t) {
                final id = t['id'] as int? ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _buildCardRow(t, oddsById[id], isDark),
                );
              }),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips(bool isDark) {
    final ink = isDark ? Colors.white : SemColor.panelDark;
    final sub = isDark ? Colors.white60 : const Color(0xFF6B6B73);
    final line = isDark ? Colors.white24 : const Color(0xFFE0E0E4);
    Widget chip(String label, String value) {
      final active = _period == value;
      return GestureDetector(
        onTap: () {
          if (_period == value) return;
          setState(() {
            _period = value;
            _expandedTeamIds.clear();
          });
          _loadTeams();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.pill),
            color: active ? ink : Colors.transparent,
            border: Border.all(color: active ? ink : line, width: 1),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: active ? (isDark ? Colors.black : Colors.white) : sub)),
        ),
      );
    }
    // PS 확률 — 기간 필터와 별개 view 토글 chip
    Widget psChip() {
      final active = _showPsView;
      return GestureDetector(
        onTap: () => setState(() => _showPsView = !_showPsView),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.pill),
            color: active ? ink : Colors.transparent,
            border: Border.all(color: active ? ink : line, width: 1),
          ),
          child: Text('PS 확률',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: active ? (isDark ? Colors.black : Colors.white) : sub)),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip('${DateTime.now().year} 시즌', 'full'),
        const SizedBox(width: 8),
        chip('전반기', 'first_half'),
        const SizedBox(width: 8),
        chip('최근 10경기', 'last_10'),
        const SizedBox(width: 8),
        psChip(),
      ]),
    );
  }

  Widget _buildCutLine(bool isDark) {
    final c = isDark ? Colors.white24 : const Color(0xFFE0E0E4);
    final ink3 = isDark ? Colors.white60 : const Color(0xFF6B6B73);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 13),
      child: Row(children: [
        Expanded(child: CustomPaint(
          painter: _DashedLinePainter(color: c),
          child: const SizedBox(height: 1),
        )),
        const SizedBox(width: 10),
        Text('가을야구 진출선',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ink3)),
        const SizedBox(width: 10),
        Expanded(child: CustomPaint(
          painter: _DashedLinePainter(color: c),
          child: const SizedBox(height: 1),
        )),
      ]),
    );
  }

  TextStyle get _hdrStyle => TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700,
        color: Colors.grey[500], letterSpacing: 0.6,
      );

  // 포스트시즌 단계 색상
  static const Color _cKs = Color(0xFFFFB300);
  static const Color _cPo = Color(0xFF1565C0);
  static const Color _cSpo = Color(0xFF1976D2);
  static const Color _cWc4 = Color(0xFF26A69A);
  static const Color _cWc5 = Color(0xFF66BB6A);

  // ──────────────── CARD ROW (mockup hi-fi + expand) ────────────────
  Widget _buildCardRow(Map team, Map? odds, bool isDark) {
    final rank = team['rank'] as int? ?? 0;
    final code = team['short_name'] as String? ?? '';
    final id = team['id'] as int? ?? -1;
    final wins = team['wins'] as int? ?? 0;
    final losses = team['losses'] as int? ?? 0;
    final draws = team['draws'] as int? ?? 0;
    final totalGames = team['total_games'] as int? ?? (wins + losses + draws);
    final winRateNum = (team['win_rate'] as num?) ?? 0;
    final winRatePct = '${(winRateNum * 100).round()}%';
    final gbNum = team['games_behind'] as num?;
    final isLead = gbNum == null || gbNum == 0;
    final gbText = isLead ? '–' : gbNum.toStringAsFixed(1);
    final isFav = _favoriteTeamIds.contains(id);
    final isExpanded = _expandedTeamIds.contains(id);

    // (PS 확률 계산 제거 — 'PS 확률' 별도 탭으로 분리, 2026-06-06)

    // 컬러 팔레트 (mockup tokens)
    final paper  = isDark ? const Color(0xFF18181C) : Colors.white;
    final paper2 = isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6);
    final line   = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
    final line2  = isDark ? const Color(0xFF33333A) : const Color(0xFFE0E0E4);
    final ink    = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final ink2   = isDark ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46);
    final ink3   = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final sub    = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final track  = isDark ? const Color(0xFF2C2C33) : const Color(0xFFE8E8EC);

    final tc = teamColor(code);
    final cardBg = isFav ? tc.withValues(alpha: isDark ? 0.18 : 0.07) : paper;
    final cardBd = isFav ? tc.withValues(alpha: isDark ? 0.55 : 0.40) : line;
    final rankCol = isFav ? tc : (rank <= 3 ? ink : sub);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBd, width: 1),
        boxShadow: (!isFav && !isDark) ? [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 2, offset: const Offset(0, 1)),
        ] : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 헤더 (탭 → 팀 상세) ──
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => TeamDetailScreen(team: Map<String, dynamic>.from(team)))),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // rank + ▲▼ (rank_change)
                    SizedBox(
                      width: 24,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('$rank',
                            style: TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w800, color: rankCol,
                              letterSpacing: 0, fontFeatures: const [FontFeature.tabularFigures()],
                            )),
                        const SizedBox(height: 4),
                        _buildMoveIndicator(team['rank_change'] as int?, ink2, sub, line2),
                      ]),
                    ),
                    const SizedBox(width: 13),
                    TeamLogo(teamCode: code, size: 42, logoUrl: team['logo_url'] as String?),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(children: [
                            Flexible(
                              child: Text(team['name'] as String? ?? '',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink, letterSpacing: 0)),
                            ),
                            if (isFav) ...[
                              const SizedBox(width: 6),
                              _badge('마이팀', bg: tc, fg: Colors.white),
                            ],
                            if (isLead) ...[
                              const SizedBox(width: 6),
                              _badge('선두', bg: ink, fg: isDark ? const Color(0xFF0F0F12) : Colors.white),
                            ],
                          ]),
                          const SizedBox(height: 7),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                            Text('$wins승 $losses패${draws > 0 ? ' $draws무' : ''}',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: ink3,
                                    fontFeatures: const [FontFeature.tabularFigures()])),
                            Container(width: 1, height: 11, margin: const EdgeInsets.symmetric(horizontal: 8), color: line2),
                            Text('$totalGames경기',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: ink3,
                                    fontFeatures: const [FontFeature.tabularFigures()])),
                            Container(width: 1, height: 11, margin: const EdgeInsets.symmetric(horizontal: 8), color: line2),
                            Text(winRatePct,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink,
                                    fontFeatures: const [FontFeature.tabularFigures()])),
                          ]),
                          // 홈구장 전체명 + 지도 진입 (좌측 정렬, 버튼)
                          if (_kHomeStadium[code] != null) ...[
                            const SizedBox(height: 7),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => StadiumScreen(initialIndex: _kHomeStadium[code]!.$2))),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: paper2,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: line),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.place_outlined, size: 14, color: ink),
                                    const SizedBox(width: 5),
                                    Text(_kHomeStadium[code]!.$1,
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ink)),
                                    const SizedBox(width: 2),
                                    Icon(Icons.chevron_right, size: 15, color: ink3),
                                  ]),
                                ),
                              ),
                            ),
                          ],
                          // PS bar 제거 — 'PS 확률' 별도 탭으로 분리 (2026-06-06)
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 우측: 게임차 + chevron 토글
                    SizedBox(
                      width: 40,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(gbText,
                              style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800,
                                color: isLead ? ink : ink2, letterSpacing: 0,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              )),
                          const SizedBox(height: 4),
                          Text('게임차', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: sub)),
                          const SizedBox(height: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(7),
                            onTap: () {
                              setState(() {
                                if (isExpanded) {
                                  _expandedTeamIds.remove(id);
                                } else {
                                  _expandedTeamIds.add(id);
                                }
                              });
                            },
                            child: Container(
                              width: 26, height: 22,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(7),
                                color: isExpanded
                                    ? (isFav ? tc.withValues(alpha: 0.15) : paper2)
                                    : Colors.transparent,
                                border: Border.all(color: line2, width: 1),
                              ),
                              child: AnimatedRotation(
                                turns: isExpanded ? 0.5 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(Icons.keyboard_arrow_down, size: 16, color: ink3),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── expand section ──
          if (isExpanded) _buildExpandSection(team, isDark, tc, isFav,
              paper2: paper2, line: line, line2: line2, sub: sub, ink: ink, ink2: ink2, track: track),
        ],
      ),
    );
  }

  Widget _buildExpandSection(Map team, bool isDark, Color tc, bool isFav,
      {required Color paper2, required Color line, required Color line2,
       required Color sub, required Color ink, required Color ink2, required Color track}) {
    String fmtRec(dynamic v) {
      if (v is Map) {
        final w = (v['wins'] as num?) ?? 0;
        final l = (v['losses'] as num?) ?? 0;
        final d = (v['draws'] as num?) ?? 0;
        final base = d > 0 ? '$w-$l-$d' : '$w-$l';
        final tot = w + l;
        if (tot == 0) return base;
        final r = (w / tot).toStringAsFixed(3);
        final rStr = r.startsWith('0') ? r.substring(1) : r;
        return '$base ($rStr)';
      }
      if (v is String) return v;
      return '-';
    }
    final home = fmtRec(team['home_record']);
    final away = fmtRec(team['away_record']);
    final oneRun = team['one_run_pct'] as String?;
    final pyth = (team['pythag_winpct'] as num?);
    final oneRunStr = oneRun ?? (pyth == null ? '-' : pyth.toStringAsFixed(3));
    final oneRunLabel = oneRun != null ? '1점차 승률' : '피타고리안';
    final streak = team['streak'] as int? ?? 0;
    final streakStr = streak > 0 ? '$streak연승' : (streak < 0 ? '${-streak}연패' : '-');
    final ls = team['last_series'] as Map?;
    final lsW = (ls?['wins'] as num?)?.toInt() ?? 0;
    final lsL = (ls?['losses'] as num?)?.toInt() ?? 0;
    final lastSeriesLabel = (lsW + lsL) == 0 ? '-' : '$lsW승 $lsL패';
    final recent10 = (team['recent_10'] as List?)?.cast<String>() ?? [];

    final borderTop = isFav
        ? tc.withValues(alpha: isDark ? 0.40 : 0.25)
        : line;
    final bg = isDark ? paper2 : (isFav ? Colors.transparent : paper2);

    Widget statCell(String label, String value) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sub)),
          const SizedBox(height: 5),
          Text(value,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink2,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      );
    }

    Widget formBar() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('최근 10경기', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sub)),
          const SizedBox(height: 6),
          Row(children: List.generate(10, (i) {
            final r = i < recent10.length ? recent10[i] : '';
            final fill = r == 'W' ? tc : track;
            return Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Container(
                width: 4, height: 14,
                decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(1.5)),
              ),
            );
          })),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: borderTop, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 3-col x 2-row grid
          Row(children: [
            Expanded(child: statCell('홈', home)),
            Expanded(child: statCell('원정', away)),
            Expanded(child: statCell(oneRunLabel, oneRunStr)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: statCell('최근 시리즈', lastSeriesLabel)),
            Expanded(child: statCell('연속', streakStr)),
            Expanded(child: formBar()),
          ]),
          const SizedBox(height: 14),
          // 팀 상세 버튼
          SizedBox(
            width: double.infinity,
            child: Material(
              color: isFav ? tc : ink,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => TeamDetailScreen(team: Map<String, dynamic>.from(team)))),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Text('${team['name'] ?? ''} 팀 상세 보기 →',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: isDark && !isFav ? const Color(0xFF0F0F12) : Colors.white,
                      )),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoveIndicator(int? mv, Color ink2, Color sub, Color line2) {
    if (mv == null) {
      return Text('—', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: line2));
    }
    if (mv > 0) {
      return Text('▲ $mv',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ink2));
    }
    if (mv < 0) {
      return Text('▼ ${-mv}',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sub));
    }
    return Text('—', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: line2));
  }

  Widget _badge(String text, {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
    );
  }
  Widget _buildHeroCardLegacy(Map team, Map? odds) {
    final rank = team['rank'] as int? ?? 0;
    final code = team['short_name'] as String? ?? '';
    final id = team['id'] as int? ?? -1;
    final wins = team['wins'] as int? ?? 0;
    final losses = team['losses'] as int? ?? 0;
    final draws = team['draws'] as int? ?? 0;
    final totalGames = team['total_games'] as int? ?? (wins + losses + draws);
    final streak = team['streak'] as int? ?? 0;
    final winRate = (team['win_rate'] as num?)?.toStringAsFixed(3) ?? '-';
    final gb = team['games_behind'];
    final gbNum = gb as num?;
    final gbText = gbNum == null || gbNum == 0 ? '-' : gbNum.toStringAsFixed(1);
    final recent5 = (team['recent_5'] as List?)?.cast<String>() ?? [];
    final isFav = _favoriteTeamIds.contains(id);
    final color = teamColor(code);
    final medal = rank == 1 ? '🥇' : (rank == 2 ? '🥈' : '🥉');

    // PS 단계 확률
    double pct(String key) => ((odds?[key] as num? ?? 0) * 100).toDouble();
    final ks = pct('ks_direct_prob');
    final po = pct('po_direct_prob');
    final spo = pct('spo_direct_prob');
    final wc4 = pct('wc_seed4_prob');
    final wc5 = pct('wc_seed5_prob');
    final ps = ks + po + spo + wc4 + wc5;
    final out = (100.0 - ps).clamp(0.0, 100.0);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? Colors.grey[900]! : Colors.white;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isFav ? 0.25 : 0.15),
            blurRadius: 12, spreadRadius: 0, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => TeamDetailScreen(team: Map<String, dynamic>.from(team)))),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.18),
                  cardBg,
                  cardBg,
                ],
                stops: const [0.0, 0.7, 1.0],
              ),
              border: isFav ? Border.all(color: color.withValues(alpha: 0.6), width: 1.5) : null,
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(medal, style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 8),
                    Text('$rank위',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
                    const Spacer(),
                    if (isFav) Icon(Icons.star_rounded, color: color, size: 22),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TeamLogo(teamCode: code, size: 44, logoUrl: team['logo_url'] as String?),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        team['name'] as String? ?? '',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // 큰 stats
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _heroStat('$wins승 $losses패${draws > 0 ? ' $draws무' : ''}', '경기 $totalGames'),
                    const SizedBox(width: 16),
                    _heroStat(winRate, '승률'),
                    const SizedBox(width: 16),
                    _heroStat(gbText, '게임차'),
                  ],
                ),
                const SizedBox(height: 12),
                // 최근 5경기 + streak
                Row(
                  children: [
                    Text('최근 5경기',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    ...recent5.asMap().entries.map((e) => _recentDot(e.value,
                        isRecent: e.key == recent5.length - 1,
                        glow: teamColor((team['short_name'] as String?) ?? ''))),
                    const Spacer(),
                    Text(_streakText(streak),
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w900, color: _streakColor(streak),
                        )),
                  ],
                ),
                if (odds != null) ...[
                  const SizedBox(height: 14),
                  _psStackedBar(ks, po, spo, wc4, wc5, out, ps, color, height: 13),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    if (ks >= 10) _stagePct('🥇 한국시리즈', ks, _cKs),
                    if (po >= 10) _stagePct('🥈 플레이오프', po, _cPo),
                    if (spo >= 10) _stagePct('🥉 준플레이오프', spo, _cSpo),
                    if (wc4 >= 10) _stagePct('와일드카드 홈', wc4, _cWc4),
                    if (wc5 >= 10) _stagePct('와일드카드 원정', wc5, _cWc5),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildCompactRowLegacy(Map team, Map? odds) {
    final rank = team['rank'] as int? ?? 0;
    final code = team['short_name'] as String? ?? '';
    final id = team['id'] as int? ?? -1;
    final wins = team['wins'] as int? ?? 0;
    final losses = team['losses'] as int? ?? 0;
    final draws = team['draws'] as int? ?? 0;
    final winRate = (team['win_rate'] as num?)?.toStringAsFixed(3) ?? '-';
    final gb = team['games_behind'];
    final gbNum = gb as num?;
    final gbText = gbNum == null || gbNum == 0 ? '-' : gbNum.toStringAsFixed(1);
    final recent5 = (team['recent_5'] as List?)?.cast<String>() ?? [];
    final streak = team['streak'] as int? ?? 0;
    final isFav = _favoriteTeamIds.contains(id);
    final isPSZone = rank <= 5;
    final color = teamColor(code);
    final bandColor = isPSZone ? color : color.withValues(alpha: 0.35);
    final expanded = _expandedTeamIds.contains(rank);

    double pct(String key) => ((odds?[key] as num? ?? 0) * 100).toDouble();
    final ks = pct('ks_direct_prob');
    final po = pct('po_direct_prob');
    final spo = pct('spo_direct_prob');
    final wc4 = pct('wc_seed4_prob');
    final wc5 = pct('wc_seed5_prob');
    final ps = ks + po + spo + wc4 + wc5;
    final out = (100.0 - ps).clamp(0.0, 100.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: isFav ? Border.all(color: color.withValues(alpha: 0.5), width: 1.2) : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              if (expanded) {
                _expandedTeamIds.remove(rank);
              } else {
                _expandedTeamIds.add(rank);
              }
            });
          },
          onLongPress: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => TeamDetailScreen(team: Map<String, dynamic>.from(team)))),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 5, color: bandColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 26,
                              child: Text('$rank',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                                      color: isPSZone ? color : Colors.grey[600])),
                            ),
                            TeamLogo(teamCode: code, size: 26, logoUrl: team['logo_url'] as String?),
                            const SizedBox(width: 8),
                            Text(team['name'] as String? ?? '',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                            if (isFav) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.star_rounded, size: 14, color: color),
                            ],
                            const Spacer(),
                            Text('$wins-$losses${draws > 0 ? '-$draws' : ''}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            const SizedBox(width: 8),
                            Text(winRate, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            const SizedBox(width: 6),
                            Icon(expanded ? Icons.expand_less : Icons.expand_more,
                                size: 18, color: Colors.grey[500]),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (odds != null)
                          _psStackedBar(ks, po, spo, wc4, wc5, out, ps, color, height: 8, showPctLabel: true),
                        if (expanded) ...[
                          const SizedBox(height: 10),
                          Container(height: 0.5, color: Colors.grey.withValues(alpha: 0.25)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text('게임차 $gbText',
                                  style: TextStyle(fontSize: 11, color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[700])),
                              const SizedBox(width: 10),
                              Text(_streakText(streak),
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                      color: _streakColor(streak))),
                              const Spacer(),
                              ...recent5.asMap().entries.map((e) => _recentDot(e.value, size: 16,
                                  isRecent: e.key == recent5.length - 1,
                                  glow: teamColor((team['short_name'] as String?) ?? ''))),
                            ],
                          ),
                          if (odds != null) ...[
                            const SizedBox(height: 8),
                            Wrap(spacing: 6, runSpacing: 4, children: [
                              if (ks >= 10) _stagePct('🥇 한국시리즈', ks, _cKs),
                              if (po >= 10) _stagePct('🥈 플레이오프', po, _cPo),
                              if (spo >= 10) _stagePct('🥉 준플레이오프', spo, _cSpo),
                              if (wc4 >= 10) _stagePct('와일드카드 홈', wc4, _cWc4),
                              if (wc5 >= 10) _stagePct('와일드카드 원정', wc5, _cWc5),
                            ]),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 포스트시즌 stacked bar (Hero + Compact 공용)
  Widget _psStackedBar(double ks, double po, double spo, double wc4, double wc5,
                       double out, double ps, Color teamColor,
                       {double height = 10, bool showPctLabel = false}) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: height,
              child: Row(
                children: [
                  if (ks > 0) Flexible(flex: (ks * 100).round(), child: Container(color: _cKs)),
                  if (po > 0) Flexible(flex: (po * 100).round(), child: Container(color: _cPo)),
                  if (spo > 0) Flexible(flex: (spo * 100).round(), child: Container(color: _cSpo)),
                  if (wc4 > 0) Flexible(flex: (wc4 * 100).round(), child: Container(color: _cWc4)),
                  if (wc5 > 0) Flexible(flex: (wc5 * 100).round(), child: Container(color: _cWc5)),
                  if (out > 0) Flexible(flex: (out * 100).round(),
                      child: Container(color: Colors.grey.withValues(alpha: 0.15))),
                ],
              ),
            ),
          ),
        ),
        if (showPctLabel) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(
              'PS ${ps.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                  color: ps >= 90 ? teamColor : (ps >= 50 ? teamColor.withValues(alpha: 0.8) : Colors.grey)),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ],
    );
  }

  // ── PS 확률 — 팀 순위 탭 내 세부 카테고리 (chip 토글) ──
  List<Widget> _psChildren(bool isDark) {
    if (_teams.isEmpty || _odds.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Center(child: CircularProgressIndicator(color: SemColor.brand(context), strokeWidth: 2.5)),
        ),
      ];
    }
    final oddsById = <int, Map>{for (final o in _odds) (o['id'] as int? ?? -1): o};
    final ink3 = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final paper = isDark ? const Color(0xFF18181C) : Colors.white;
    final line = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);

    Widget legendDot(String label, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: ink3, fontWeight: FontWeight.w600)),
        ]);

    return [
          Text('포스트시즌 진출 확률 — Monte Carlo 100,000회',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ink3)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 6, children: [
            legendDot('한국시리즈', _cKs),
            legendDot('플레이오프', _cPo),
            legendDot('준PO', _cSpo),
            legendDot('WC 홈', _cWc4),
            legendDot('WC 원정', _cWc5),
          ]),
          const SizedBox(height: 14),
          ..._teams.map((t) {
            final team = t as Map;
            final id = team['id'] as int? ?? -1;
            final code = team['short_name'] as String? ?? '';
            final odds = oddsById[id];
            double pct(String key) => ((odds?[key] as num? ?? 0) * 100).toDouble();
            final ks = pct('ks_direct_prob');
            final po = pct('po_direct_prob');
            final spo = pct('spo_direct_prob');
            final wc4 = pct('wc_seed4_prob');
            final wc5 = pct('wc_seed5_prob');
            final ps = ks + po + spo + wc4 + wc5;
            final out = (100.0 - ps).clamp(0.0, 100.0);
            final tc = teamColor(code);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: paper,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: line, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    SizedBox(
                      width: 22,
                      child: Text('${team['rank'] ?? '-'}',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: tc)),
                    ),
                    TeamLogo(teamCode: code, size: 26, logoUrl: team['logo_url'] as String?),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(team['name'] as String? ?? '',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                    Text('PS ${ps.toStringAsFixed(1)}%',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                            color: ps >= 50 ? tc : ink3,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                  ]),
                  const SizedBox(height: 10),
                  _psStackedBar(ks, po, spo, wc4, wc5, out, ps, tc, height: 12),
                ],
              ),
            );
          }),
        ];
  }

  // ──────────────── DEPRECATED below ────────────────
  // ignore: unused_element
  Widget _buildPostseasonOddsLegacy() {
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
            Text('Monte Carlo 100,000회', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
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
                              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
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
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ),
      ],
    );
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
          style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w700)),
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

  // ignore: unused_element
  Widget _buildTeamRowLegacy(Map<String, dynamic> team, {bool isTied = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final favBorder = isDark ? AppColors.primaryDark : SemColor.panelDark;
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
            ? BorderSide(color: favBorder, width: 1.5)
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
                    Icon(Icons.star, size: 16, color: favBorder),
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

  // ignore: unused_element
  Widget _statCell(String label, String value, {Color? valueColor}) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: valueColor)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _statDivider() {
    return Container(width: 0.5, height: 28, color: Colors.grey[300]);
  }

  Widget _recentDot(String result, {double size = 22, bool isRecent = false, Color? glow}) {
    Color color;
    String label;
    switch (result) {
      case 'W': color = const Color(0xFF1565C0); label = '승'; break;
      case 'L': color = const Color(0xFFC62828); label = '패'; break;
      default:  color = Colors.grey; label = '무';
    }
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle, color: color,
        // 가장 최근 경기 — 팀컬러 glow
        boxShadow: isRecent && glow != null
            ? [BoxShadow(color: glow.withValues(alpha: 0.65), blurRadius: 7, spreadRadius: 1.5)]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(label,
          style: TextStyle(color: Colors.white, fontSize: size * 0.45, fontWeight: FontWeight.bold)),
    );
  }
}


// 공통 디자인 토큰 (mockup hi-fi)
class _Tok {
  final Color paper, paper2, line, line2, ink, ink2, ink3, sub, track;
  const _Tok({
    required this.paper, required this.paper2,
    required this.line, required this.line2,
    required this.ink, required this.ink2, required this.ink3, required this.sub,
    required this.track,
  });
  factory _Tok.of(bool isDark) => _Tok(
    paper:  isDark ? const Color(0xFF18181C) : Colors.white,
    paper2: isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6),
    line:   isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0),
    line2:  isDark ? const Color(0xFF33333A) : const Color(0xFFE0E0E4),
    ink:    isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark,
    ink2:   isDark ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46),
    ink3:   isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73),
    sub:    isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2),
    track:  isDark ? const Color(0xFF2C2C33) : const Color(0xFFE8E8EC),
  );
}

// CutLine 점선 painter
class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const dash = 5.0, gap = 5.0;
    double x = 0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
      x += dash + gap;
    }
  }
  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
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
                  color: selected
                      ? (isDark ? AppColors.primaryDark : SemColor.panelDark)
                      : (isDark ? Colors.grey[400] : Colors.grey),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = _Tok.of(isDark);
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        itemCount: cats.length,
        itemBuilder: (_, i) {
          final cat = cats[i];
          final sel = selected == cat['value'];
          return GestureDetector(
            onTap: () => onSelect(cat['value'] as String),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: sel ? t.ink : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.pill),
                border: Border.all(color: sel ? t.ink : t.line2, width: 1),
              ),
              child: Text(
                cat['label'] as String,
                style: TextStyle(
                  fontSize: 12,
                  color: sel ? (isDark ? Colors.black : Colors.white) : t.ink2,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tk = _Tok.of(isDark);
    final catMap = cats.firstWhere((c) => c['value'] == selected);
    final isLow = catMap['isLow'] as bool;
    final label = catMap['label'] as String;
    final sorted = _sortedTeams(selected, isBatting, isLow);
    if (sorted.isEmpty) return const SizedBox.shrink();
    final best = sorted.first;
    final bestVal = ((isBatting ? best['batting'] : best['pitching']) ?? {})[selected];

    final favIds = ApiService.myTeamData.value
        .map((m) => (m['id'] as int?) ?? -1).toSet();

    return Container(
      color: isDark ? SemColor.panelDark : const Color(0xFFFAFAFB),
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 8, 16, (ApiService.myTeamData.value.isNotEmpty ? 144.0 : 92.0) + MediaQuery.of(context).padding.bottom),
        itemCount: sorted.length,
        itemBuilder: (_, i) {
          final t = sorted[i];
          final stats = (isBatting ? t['batting'] : t['pitching']) as Map? ?? {};
          final rawVal = stats[selected];
          final displayVal = isBatting
              ? _fmtBatting(stats, selected)
              : _fmtPitching(stats, selected);
          final rank = i + 1;
          final isBest = rank == 1;
          final code = t['short_name'] as String? ?? '';
          final id = t['id'] as int? ?? -1;
          final isFav = favIds.contains(id);
          final tc = teamColor(code);

          double barFraction = 0;
          if (rawVal is num && bestVal is num && bestVal != 0) {
            final ratio = rawVal / bestVal;
            barFraction = isLow ? (bestVal / rawVal) : ratio.toDouble();
            barFraction = barFraction.clamp(0.05, 1.0);
          }

          final cardBg = isFav ? tc.withValues(alpha: isDark ? 0.18 : 0.07) : tk.paper;
          final cardBd = isFav ? tc.withValues(alpha: isDark ? 0.55 : 0.40) : tk.line;
          final rankCol = isFav ? tc : (isBest ? tk.ink : tk.sub);

          return Container(
            margin: const EdgeInsets.only(bottom: 9),
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBd, width: 1),
              boxShadow: (!isFav && !isDark) ? [
                BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 2, offset: const Offset(0, 1)),
              ] : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text('$rank',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800, color: rankCol,
                        letterSpacing: 0, fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ),
                const SizedBox(width: 13),
                TeamLogo(teamCode: code, size: 36, logoUrl: t['logo_url']),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t['name'] as String? ?? '',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: tk.ink, letterSpacing: 0)),
                      const SizedBox(height: 7),
                      LayoutBuilder(builder: (_, box) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.pill),
                          child: Container(
                            height: 6, width: box.maxWidth, color: tk.track,
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: barFraction,
                              child: Container(decoration: BoxDecoration(color: tc, borderRadius: BorderRadius.circular(Radii.pill))),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(displayVal,
                        style: TextStyle(
                          fontSize: isBest ? 17 : 15, fontWeight: FontWeight.w800,
                          color: tk.ink, letterSpacing: 0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )),
                    const SizedBox(height: 2),
                    Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tk.sub)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_loading) {
      return Center(child: CircularProgressIndicator(
          color: isDark ? AppColors.primaryDark : SemColor.panelDark, strokeWidth: 2.5));
    }
    if (_error) {
      return AppErrorView(message: '데이터를 불러오지 못했습니다', onRetry: _load, icon: Icons.wifi_off);
    }
    return Container(
      color: isDark ? SemColor.panelDark : const Color(0xFFFAFAFB),
      child: Column(
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
    ),
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
      if (mounted) {
        setState(() {
        _loading = false;
        final allEmpty = _hitterCache.values.every((l) => l.isEmpty);
        if (allEmpty) _error = true;
      });
      }
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
    return Container(
      color: isDark ? SemColor.panelDark : const Color(0xFFFAFAFB),
      child: Column(
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
      ),
    );
  }

  Widget _buildCategoryChips(List<Map<String, String>> categories, String selected, Function(String) onSelect) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = _Tok.of(isDark);
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = selected == cat['value'];
          return GestureDetector(
            onTap: () => onSelect(cat['value']!),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected ? t.ink : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.pill),
                border: Border.all(color: isSelected ? t.ink : t.line2, width: 1),
              ),
              child: Text(
                cat['label']!,
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: isSelected ? (isDark ? Colors.black : Colors.white) : t.ink3,
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
      final isDark = Theme.of(context).brightness == Brightness.dark;
      // 금/은색은 라이트 배경서 저대비 → 텍스트는 어둡게(라이트)/그대로(다크)
      final txtColor = isDark ? medalColor : Color.lerp(medalColor, Colors.black, 0.42)!;
      final nameColor = isDark ? const Color(0xFFF4F4F5) : const Color(0xFF111113);
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
                netCircleAvatar(
                  radius: rank == 1 ? 32 : 24,
                  url: img,
                  backgroundColor: medalColor.withValues(alpha: 0.15),
                  child: Icon(Icons.person, size: rank == 1 ? 28 : 20, color: medalColor),
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
                    child: Text('$rank', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(p['name'] ?? '',
                style: TextStyle(fontSize: rank == 1 ? 13 : 11, fontWeight: FontWeight.bold, color: nameColor),
                textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
            Text(p['team'] ?? '',
                style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF9A9AA3) : Colors.grey[600]), textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(statValue(p),
                style: TextStyle(fontSize: rank == 1 ? 16 : 14, fontWeight: FontWeight.bold, color: txtColor),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Container(
              width: rank == 1 ? 90 : 72,
              height: height,
              decoration: BoxDecoration(
                color: medalColor.withValues(alpha: isDark ? 0.28 : 0.20),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
              alignment: Alignment.center,
              child: Text('$rank위', style: TextStyle(fontSize: 11, color: txtColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F24) : Colors.grey.withValues(alpha: 0.06),
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
    return AppErrorView(message: '데이터를 불러오지 못했습니다', onRetry: _loadAll, icon: Icons.wifi_off);
  }

  Widget _buildRankingsContent(List players, String Function(Map) statValue, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final top3 = players.take(3).toList();
    final rest = players.skip(3).toList();
    return Container(
      color: isDark ? SemColor.panelDark : const Color(0xFFFAFAFB),
      child: ListView(
        padding: EdgeInsets.only(top: 8, bottom: (ApiService.myTeamData.value.isNotEmpty ? 144.0 : 92.0) + MediaQuery.of(context).padding.bottom),
        children: [
          if (top3.length >= 3) ...[
            _buildPodium(top3, statValue),
            const SizedBox(height: 14),
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
      ),
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
      itemBuilder: (_, _) => Shimmer.fromColors(
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = _Tok.of(isDark);
    final tc = teamColor(teamCode);
    final isTop3 = rank <= 3;
    const medal1 = Color(0xFFFFB300);
    const medal2 = Color(0xFFC0C0C0);
    const medal3 = Color(0xFFCD7F32);
    final medal = rank == 1 ? medal1 : (rank == 2 ? medal2 : medal3);
    final rankCol = isTop3 ? medal : t.sub;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 9),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: playerId))),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            decoration: BoxDecoration(
              color: t.paper,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.line, width: 1),
              boxShadow: !isDark ? [
                BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 2, offset: const Offset(0, 1)),
              ] : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text('$rank',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800, color: rankCol,
                        letterSpacing: 0, fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ),
                const SizedBox(width: 12),
                netCircleAvatar(
                  radius: 18,
                  backgroundColor: tc.withValues(alpha: isDark ? 0.35 : 0.18),
                  url: profileImage,
                  child: Text(teamDisplayName(teamCode).substring(0,
                          teamDisplayName(teamCode).length.clamp(0, 2)),
                      style: TextStyle(color: tc, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                              color: t.ink, letterSpacing: 0)),
                      const SizedBox(height: 3),
                      Text(team,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: t.ink3)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(value,
                        style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, color: t.ink,
                          letterSpacing: 0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )),
                    const SizedBox(height: 2),
                    Text(label,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.sub)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
