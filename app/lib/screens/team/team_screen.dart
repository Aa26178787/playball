import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import '../../utils/app_theme.dart';
import '../../utils/web_safe_area.dart';
import 'dart:async';
import 'package:shimmer/shimmer.dart';
import '../../api/api_service.dart';
import '../../widgets/common_widgets.dart';
import '../../utils/team_theme.dart';
import '../../utils/local_cache.dart';
import '../player/player_detail_screen.dart';
import '../player/historical_player_detail_screen.dart';
import '../mypage/my_page_screen.dart';
import '../stadium/stadium_screen.dart';
import 'team_detail_screen.dart';
import '../futures/futures_screen.dart';
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
    _tabController = TabController(length: 5, vsync: this);
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
    final paper = Pal.paper(isDark);
    final ink   = Pal.ink(isDark);
    final ink3  = Pal.ink3(isDark);
    final sub   = Pal.sub(isDark);
    final line  = Pal.line(isDark);
    final line2 = Pal.line2(isDark);
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
                // bottom 12→4: 탭바 위 여백 과다 (06-13)
                padding: EdgeInsets.fromLTRB(18, headerTopGap(context), 18, 4),
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
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(text: '팀 순위'),
                  Tab(text: '팀 기록'),
                  Tab(text: '부문별 순위'),
                  Tab(text: '역대 기록실'),
                  Tab(text: '퓨처스'),
                ],
              ),
            ]),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTeamRankings(),
                const TeamStatsTab(),
                const PlayerRankingsTab(),
                const PlayerRankingsTab(historical: true),
                const FuturesScreen(),
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
            borderRadius: BorderRadius.circular(Radii.md),
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
            const SizedBox(height: Space.sm),
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
            const SizedBox(height: Space.sm),
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
                  fontSize: Typo.small, fontWeight: Typo.medium,
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
                  fontSize: Typo.small, fontWeight: Typo.medium,
                  color: active ? (isDark ? Colors.black : Colors.white) : sub)),
        ),
      );
    }

    return HScrollFade(child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip('${DateTime.now().year} 시즌', 'full'),
        const SizedBox(width: Space.sm),
        chip('전반기', 'first_half'),
        const SizedBox(width: Space.sm),
        chip('최근 10경기', 'last_10'),
        const SizedBox(width: Space.sm),
        psChip(),
      ]),
    ));
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
            style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: ink3)),
        const SizedBox(width: 10),
        Expanded(child: CustomPaint(
          painter: _DashedLinePainter(color: c),
          child: const SizedBox(height: 1),
        )),
      ]),
    );
  }

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
    final paper  = Pal.paper(isDark);
    final paper2 = Pal.paper2(isDark);
    final line   = Pal.line(isDark);
    final line2  = Pal.line2(isDark);
    final ink    = Pal.ink(isDark);
    final ink2   = Pal.ink2(isDark);
    final ink3   = Pal.ink3(isDark);
    final sub    = Pal.sub(isDark);
    final track  = Pal.track(isDark);

    final tc = teamColorOn(code, isDark); // 다크 대비 보정 — 순위숫자/테두리 전경
    final cardBg = isFav ? tc.withValues(alpha: isDark ? 0.18 : 0.07) : paper;
    final cardBd = isFav ? tc.withValues(alpha: isDark ? 0.55 : 0.40) : line;
    final rankCol = isFav ? tc : (rank <= 3 ? ink : sub);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(Radii.lg),
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
                              fontSize: Typo.lg, fontWeight: Typo.extra, color: rankCol,
                              letterSpacing: 0, fontFeatures: const [FontFeature.tabularFigures()],
                            )),
                        const SizedBox(height: Space.xs),
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
                                  style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra, color: ink, letterSpacing: 0)),
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
                                style: TextStyle(fontSize: Typo.body, fontWeight: Typo.semibold, color: ink3,
                                    fontFeatures: const [FontFeature.tabularFigures()])),
                            Container(width: 1, height: 11, margin: const EdgeInsets.symmetric(horizontal: 8), color: line2),
                            Text('$totalGames경기',
                                style: TextStyle(fontSize: Typo.body, fontWeight: Typo.semibold, color: ink3,
                                    fontFeatures: const [FontFeature.tabularFigures()])),
                            Container(width: 1, height: 11, margin: const EdgeInsets.symmetric(horizontal: 8), color: line2),
                            Text(winRatePct,
                                style: TextStyle(fontSize: Typo.body, fontWeight: Typo.bold, color: ink,
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
                                    borderRadius: BorderRadius.circular(Radii.sm),
                                    border: Border.all(color: line),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.place_outlined, size: 14, color: ink),
                                    const SizedBox(width: 5),
                                    Text(_kHomeStadium[code]!.$1,
                                        style: TextStyle(fontSize: Typo.small, fontWeight: Typo.medium, color: ink)),
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
                    const SizedBox(width: Space.sm),
                    // 우측: 게임차 + chevron 토글
                    SizedBox(
                      width: 40,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(gbText,
                              style: TextStyle(
                                fontSize: Typo.title, fontWeight: Typo.extra,
                                color: isLead ? ink : ink2, letterSpacing: 0,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              )),
                          const SizedBox(height: Space.xs),
                          Text('게임차', style: TextStyle(fontSize: 9.5, fontWeight: Typo.medium, color: sub)),
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
          Text(label, style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.medium, color: sub)),
          const SizedBox(height: 5),
          Text(value,
              style: TextStyle(fontSize: Typo.small, fontWeight: Typo.bold, color: ink2,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      );
    }

    Widget formBar() {
      // recent10 = 최근→과거 순(backend). 표시는 오래된(좌)→최신(우) 타임라인으로 reverse + 우측 '최신' 라벨.
      final disp = recent10.reversed.toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('최근 10경기', style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.medium, color: sub)),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            ...List.generate(10, (i) {
              final r = i < disp.length ? disp[i] : '';
              final fill = r == 'W' ? tc : track;
              final newest = i == 9;  // 우측끝 = 최신
              return Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Container(
                  width: 4, height: newest ? 17 : 14,  // 우측끝(최신) 막대 살짝 길게
                  decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(1.5)),
                ),
              );
            }),
          ]),
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
          const SizedBox(height: Space.md),
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
                        fontSize: Typo.small, fontWeight: Typo.bold,
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
      return Text('—', style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: line2));
    }
    if (mv > 0) {
      return Text('▲ $mv',
          style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: ink2));
    }
    if (mv < 0) {
      return Text('▼ ${-mv}',
          style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: sub));
    }
    return Text('—', style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: line2));
  }

  Widget _badge(String text, {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(text, style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.extra, color: fg)),
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
            borderRadius: BorderRadius.circular(Radii.xs),
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
          const SizedBox(width: Space.sm),
          SizedBox(
            width: 44,
            child: Text(
              'PS ${ps.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.extra,
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
    final ink3 = Pal.ink3(isDark);
    final paper = Pal.paper(isDark);
    final line = Pal.line(isDark);

    return [
          Text('포스트시즌 진출 확률 — Monte Carlo 100,000회',
              style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.medium, color: ink3)),
          const SizedBox(height: 14),
          // PS 확률 뷰 시드 가중 정렬 — 단순 합(=PS 진출확률)으로 정렬하면
          // 상위팀이 모두 ~100%로 수렴해 동점→순서 무의미(06-14 보고).
          // 상위 시드일수록 가중치↑ (KS×5>PO×4>준PO×3>WC홈×2>WC원정×1) →
          // 시드 품질순. 동점은 rank로 tiebreak. (기간 필터 rank 따라가면
          // 확률 뷰가 뒤죽박죽이라 rank 단독 정렬도 불가 — 06-13)
          ...(() {
            double psScore(Map t) {
              final o = oddsById[t['id'] as int? ?? -1];
              if (o == null) return -1;
              double p(String k) => (o[k] as num? ?? 0).toDouble();
              return p('ks_direct_prob') * 5 + p('po_direct_prob') * 4 +
                  p('spo_direct_prob') * 3 + p('wc_seed4_prob') * 2 +
                  p('wc_seed5_prob');
            }
            final sorted = _teams.map((t) => t as Map).toList()
              ..sort((a, b) {
                final c = psScore(b).compareTo(psScore(a));
                if (c != 0) return c;
                return (a['rank'] as int? ?? 99).compareTo(b['rank'] as int? ?? 99);
              });
            return sorted;
          })().map((team) {
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
                          style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra, color: tc)),
                    ),
                    TeamLogo(teamCode: code, size: 26, logoUrl: team['logo_url'] as String?),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(team['name'] as String? ?? '',
                          style: const TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra)),
                    ),
                    Text('PS ${ps.toStringAsFixed(1)}%',
                        style: TextStyle(fontSize: Typo.body, fontWeight: Typo.extra,
                            color: ps >= 50 ? tc : ink3,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                  ]),
                  const SizedBox(height: 10),
                  _psStackedBar(ks, po, spo, wc4, wc5, out, ps, tc, height: 12),
                  // 바 아래 항목별 % — 상단 공용 범례 대체 (06-13, 0.05% 미만은 생략)
                  const SizedBox(height: 7),
                  Wrap(spacing: 10, runSpacing: 4, children: [
                    if (ks >= 0.05) _psPctLabel('한국시리즈', ks, _cKs),
                    if (po >= 0.05) _psPctLabel('플레이오프', po, _cPo),
                    if (spo >= 0.05) _psPctLabel('준플레이오프', spo, _cSpo),
                    if (wc4 >= 0.05) _psPctLabel('와일드카드 홈', wc4, _cWc4),
                    if (wc5 >= 0.05) _psPctLabel('와일드카드 원정', wc5, _cWc5),
                    if (ks < 0.05 && po < 0.05 && spo < 0.05 && wc4 < 0.05 && wc5 < 0.05)
                      _psPctLabel('탈락 유력', out, const Color(0xFF9A9AA3)),
                  ]),
                ],
              ),
            );
          }),
        ];
  }

  Widget _psPctLabel(String label, double pct, Color c) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: Space.xs),
        Text('$label ${pct.toStringAsFixed(1)}%',
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: Typo.bold,
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFC9C9D1) : const Color(0xFF5A5A62),
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]);

  // ──────────────── DEPRECATED below ────────────────

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
    paper:  Pal.paper(isDark),
    paper2: Pal.paper2(isDark),
    line:   Pal.line(isDark),
    line2:  Pal.line2(isDark),
    ink:    Pal.ink(isDark),
    ink2:   Pal.ink2(isDark),
    ink3:   Pal.ink3(isDark),
    sub:    Pal.sub(isDark),
    track:  Pal.track(isDark),
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
                borderRadius: BorderRadius.circular(Radii.sm),
                boxShadow: selected
                    ? [const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))]
                    : [],
              ),
              alignment: Alignment.center,
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: Typo.body,
                  fontFamily: 'Pretendard',
                  fontWeight: selected ? Typo.bold : Typo.regular,
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
    return HScrollFade(child: SizedBox(
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
                  fontSize: Typo.small,
                  color: sel ? (isDark ? Colors.black : Colors.white) : t.ink2,
                  fontWeight: sel ? Typo.bold : Typo.regular,
                ),
              ),
            ),
          );
        },
      ),
    ));
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
          final tc = teamColorOn(code, isDark); // 다크 대비 보정 (PS%·순위 전경)

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
              borderRadius: BorderRadius.circular(Radii.lg),
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
                        fontSize: Typo.title, fontWeight: Typo.extra, color: rankCol,
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
                          style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra, color: tk.ink, letterSpacing: 0)),
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
                const SizedBox(width: Space.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(displayVal,
                        style: TextStyle(
                          fontSize: isBest ? 17 : 15, fontWeight: Typo.extra,
                          color: tk.ink, letterSpacing: 0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )),
                    const SizedBox(height: 2),
                    Text(label, style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.medium, color: tk.sub)),
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
                const SizedBox(height: Space.xs),
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
                const SizedBox(height: Space.xs),
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
  /// historical=true → 역대 기록실(통산 리더, /historical/rankings). UI는 동일.
  final bool historical;
  const PlayerRankingsTab({super.key, this.historical = false});

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
    {'value': 'ops',          'label': 'OPS'},
    {'value': 'war',          'label': 'WAR'},
  ];

  static const List<Map<String, String>> _pitcherCategories = [
    {'value': 'era',        'label': 'ERA'},
    {'value': 'wins',       'label': '승'},
    {'value': 'strikeouts', 'label': '탈삼진'},
    {'value': 'saves',      'label': '세이브'},
    {'value': 'holds',      'label': '홀드'},
    {'value': 'whip',       'label': 'WHIP'},
    {'value': 'war',        'label': 'WAR'},
  ];

  // 역대 기록실 카테고리 (통산 카운팅 — /historical/rankings 키와 일치)
  static const List<Map<String, String>> _histHitterCategories = [
    {'value': 'home_runs',    'label': '홈런'},
    {'value': 'hits',         'label': '안타'},
    {'value': 'rbis',         'label': '타점'},
    {'value': 'stolen_bases', 'label': '도루'},
  ];
  static const List<Map<String, String>> _histPitcherCategories = [
    {'value': 'wins',       'label': '승'},
    {'value': 'strikeouts', 'label': '탈삼진'},
    {'value': 'saves',      'label': '세이브'},
  ];

  List<Map<String, String>> get _hCats =>
      widget.historical ? _histHitterCategories : _hitterCategories;
  List<Map<String, String>> get _pCats =>
      widget.historical ? _histPitcherCategories : _pitcherCategories;

  late String _hitterSort = widget.historical ? 'home_runs' : 'avg';
  late String _pitcherSort = widget.historical ? 'wins' : 'era';

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
    final cacheKey = widget.historical ? 'historical_rankings' : 'player_rankings';
    // Phase 1: 캐시에서 즉시 표시
    final cached = await LocalCache.get(cacheKey) as Map?;
    if (cached != null && mounted) {
      final h = (cached['hitters'] as Map?) ?? {};
      final p = (cached['pitchers'] as Map?) ?? {};
      setState(() {
        for (final c in _hCats) {
          _hitterCache[c['value']!] = (h[c['value']!] as List?) ?? [];
        }
        for (final c in _pCats) {
          _pitcherCache[c['value']!] = (p[c['value']!] as List?) ?? [];
        }
        _loading = false;
      });
    } else {
      if (mounted) setState(() => _loading = true);
    }
    // Phase 2: 백그라운드 갱신
    try {
      final data = widget.historical
          ? await ApiService.getHistoricalRankings()
          : await ApiService.getPlayerRankings();
      if (!mounted) return;
      await LocalCache.set(cacheKey, data);
      final h = (data['hitters'] as Map?) ?? {};
      final p = (data['pitchers'] as Map?) ?? {};
      setState(() {
        for (final c in _hCats) {
          _hitterCache[c['value']!] = (h[c['value']!] as List?) ?? [];
        }
        for (final c in _pCats) {
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

  String _hitterStatValue(Map p) {
    if (widget.historical) return '${p['value'] ?? '-'}';
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
    if (widget.historical) return '${p['value'] ?? '-'}';
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
                  fontSize: Typo.small, fontWeight: Typo.medium,
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
      final nameColor = Pal.ink(isDark);
      return GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) {
          // 역대탭 현역(player_id 有)은 활성 선수상세로 — 역대상세 오연결 방지
          if (widget.historical && p['player_id'] == null) {
            return HistoricalPlayerDetailScreen(kboPlayerId: p['kbo_player_id'], initialName: p['name']);
          }
          return PlayerDetailScreen(
            playerId: widget.historical ? p['player_id'] : p['id'],
            initialData: {'name': p['name'], 'team': p['team_name'] ?? p['team'], 'profile_image': p['profile_image'], 'position': p['position'], 'player_type': p['player_type']},
          );
        })),
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
                    child: Text('$rank', style: const TextStyle(color: Colors.white, fontSize: Typo.caption, fontWeight: Typo.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(p['name'] ?? '',
                style: TextStyle(fontSize: rank == 1 ? 13 : 11, fontWeight: Typo.bold, color: nameColor),
                textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
            Text(p['team'] ?? '',
                style: TextStyle(fontSize: Typo.caption, color: isDark ? const Color(0xFF9A9AA3) : Colors.grey[600]), textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(statValue(p),
                style: TextStyle(fontSize: rank == 1 ? 16 : 14, fontWeight: Typo.bold, color: txtColor),
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
              child: Text('$rank위', style: TextStyle(fontSize: Typo.caption, color: txtColor, fontWeight: Typo.bold)),
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
              playerId: widget.historical ? p['kbo_player_id'] : p['id'],
              activePlayerId: widget.historical ? p['player_id'] as int? : null,
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
    final label = _hCats.firstWhere((c) => c['value'] == _hitterSort)['label']!;
    final rankings = _hitterCache[_hitterSort] ?? [];
    return Column(
      children: [
        _buildCategoryChips(_hCats, _hitterSort,
            (val) => setState(() => _hitterSort = val)),
        const SizedBox(height: Space.xs),
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
    final label = _pCats.firstWhere((c) => c['value'] == _pitcherSort)['label']!;
    final rankings = _pitcherCache[_pitcherSort] ?? [];
    return Column(
      children: [
        _buildCategoryChips(_pCats, _pitcherSort,
            (val) => setState(() => _pitcherSort = val)),
        const SizedBox(height: Space.xs),
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
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(
            children: [
              Container(width: 32, height: 15, color: Colors.white),
              const SizedBox(width: Space.sm),
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
    int? activePlayerId, // 역대탭 현역선수 = 활성 player_id (있으면 활성 상세로)
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
          borderRadius: BorderRadius.circular(Radii.lg),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) {
            // 역대탭이라도 현역(activePlayerId 有)은 활성 선수상세로 — 역대상세 오연결 방지
            if (widget.historical && activePlayerId == null) {
              return HistoricalPlayerDetailScreen(kboPlayerId: playerId, initialName: name);
            }
            return PlayerDetailScreen(playerId: activePlayerId ?? playerId);
          })),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            decoration: BoxDecoration(
              color: t.paper,
              borderRadius: BorderRadius.circular(Radii.lg),
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
                        fontSize: Typo.title, fontWeight: Typo.extra, color: rankCol,
                        letterSpacing: 0, fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ),
                const SizedBox(width: Space.md),
                netCircleAvatar(
                  radius: 18,
                  backgroundColor: tc.withValues(alpha: isDark ? 0.35 : 0.18),
                  url: profileImage,
                  child: Text(teamDisplayName(teamCode).substring(0,
                          teamDisplayName(teamCode).length.clamp(0, 2)),
                      style: TextStyle(color: tc, fontSize: Typo.caption, fontWeight: Typo.extra)),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name,
                          style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra,
                              color: t.ink, letterSpacing: 0)),
                      const SizedBox(height: 3),
                      Text(team,
                          style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.semibold, color: t.ink3)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(value,
                        style: TextStyle(
                          fontSize: Typo.title, fontWeight: Typo.extra, color: t.ink,
                          letterSpacing: 0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )),
                    const SizedBox(height: 2),
                    Text(label,
                        style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.medium, color: t.sub)),
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
