import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import '../../utils/app_theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../api/api_service.dart';
import '../../utils/local_cache.dart';
import '../../utils/team_theme.dart';
import '../../services/widget_service.dart';
import '../player/player_detail_screen.dart';
import '../game/game_detail_screen.dart';
import '../community/post_detail_screen.dart';

class TeamDetailScreen extends StatefulWidget {
  final Map<String, dynamic> team;
  const TeamDetailScreen({required this.team, super.key});

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  int _mainTabIndex = 0;
  int _gameSubIndex = 0;
  List _players = [];
  List _games = [];
  List _rosterChanges = [];
  List _news = [];
  List _communityPosts = [];
  List _monthlyStats = [];
  List _h2hRecords = [];
  List _battingOrderStats = [];
  Map<String, dynamic>? _seasonStats;
  bool _playersLoading = true;
  bool _gamesLoading = false;
  bool _rosterLoading = false;
  bool _newsLoading = false;
  bool _communityLoading = false;
  bool _monthlyLoading = false;
  bool _h2hLoading = false;
  bool _battingOrderLoading = false;
  bool _isFav = false;
  bool _favLoading = false;
  num? _gamesBehind;

  @override
  void initState() {
    super.initState();
    _loadPlayers();
    _loadFavStatus();
    _loadSeasonStats();
    _loadGamesBehind();
    _loadRosterChanges();
    _loadNews();
  }

  void _onMainTabChange(int idx) {
    setState(() => _mainTabIndex = idx);
    if (idx == 2 && _games.isEmpty && !_gamesLoading) _loadGames();
    if (idx == 3 && _communityPosts.isEmpty && !_communityLoading) _loadCommunityPosts();
  }

  void _onGameSubChange(int idx) {
    setState(() => _gameSubIndex = idx);
    if (idx == 1 && _monthlyStats.isEmpty && !_monthlyLoading) _loadMonthlyStats();
    if (idx == 2 && _h2hRecords.isEmpty && !_h2hLoading) _loadH2H();
    if (idx == 3 && _battingOrderStats.isEmpty && !_battingOrderLoading) _loadBattingOrder();
  }

  Future<void> _loadGamesBehind() async {
    // widget.team에 games_behind 있으면 그대로 사용
    final existing = widget.team['games_behind'];
    if (existing != null) {
      if (mounted) setState(() => _gamesBehind = existing as num);
      return;
    }
    // 없으면 team_rankings 캐시에서 보완
    final cached = await LocalCache.getStale('team_rankings') as List?;
    if (cached != null) {
      final teamId = widget.team['id'];
      try {
        final found = cached.firstWhere((t) => t['id'] == teamId, orElse: () => null);
        if (found != null && found['games_behind'] != null && mounted) {
          setState(() => _gamesBehind = found['games_behind'] as num);
          return;
        }
      } catch (_) {}
    }
    // 캐시도 없으면 API 호출
    try {
      final data = await ApiService.getTeamRankings();
      final rankings = data['rankings'] as List? ?? [];
      await LocalCache.set('team_rankings', rankings);
      final teamId = widget.team['id'];
      final found = rankings.firstWhere((t) => t['id'] == teamId, orElse: () => null);
      if (found != null && mounted) setState(() => _gamesBehind = found['games_behind'] as num?);
    } catch (_) {}
  }

  Future<void> _loadFavStatus() async {
    final cached = await LocalCache.get('favorite_teams') as List?;
    final id = widget.team['id'] as int;
    if (cached != null && mounted) {
      setState(() => _isFav = cached.any((t) => (t as Map)['id'] == id));
    }
    try {
      final data = await ApiService.getFavoriteTeams();
      final teams = data['teams'] as List? ?? [];
      await LocalCache.set('favorite_teams', teams);
      if (mounted) setState(() => _isFav = teams.any((t) => t['id'] == id));
    } catch (_) {}
  }

  Future<void> _loadSeasonStats() async {
    final teamId = widget.team['id'] as int;
    final ck = 'team_season_stats_$teamId';
    final cached = await LocalCache.get(ck, maxAgeSeconds: 1800) as Map?;
    if (cached != null && mounted) setState(() => _seasonStats = Map<String, dynamic>.from(cached));
    try {
      final data = await ApiService.getTeamSeasonStats(teamId);
      await LocalCache.set(ck, data);
      if (mounted) setState(() => _seasonStats = data);
    } catch (_) {}
  }

  Future<void> _toggleFav() async {
    setState(() => _favLoading = true);
    try {
      final id = widget.team['id'] as int;
      if (_isFav) {
        await ApiService.removeFavoriteTeam(id);
        final currentWidgetTeam = await WidgetService.getTeamId();
        if (currentWidgetTeam == id) await WidgetService.setTeamId(null);
      } else {
        await ApiService.addFavoriteTeam(id);
        final currentWidgetTeam = await WidgetService.getTeamId();
        if (currentWidgetTeam == null) await WidgetService.setTeamId(id);
      }
      if (mounted) setState(() => _isFav = !_isFav);
      ApiService.favoriteTeamsChanged.value++;
    } catch (_) {}
    if (mounted) setState(() => _favLoading = false);
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadPlayers() async {
    final teamId = widget.team['id'] as int;
    final cacheKey = 'team_players_$teamId';
    final cached = await LocalCache.get(cacheKey, maxAgeSeconds: 300) as List?;
    if (cached != null && mounted) {
      setState(() { _players = cached; _playersLoading = false; });
    }
    try {
      final data = await ApiService.getTeamPlayers(teamId);
      final players = data['players'] as List? ?? [];
      await LocalCache.set(cacheKey, players);
      if (mounted) setState(() { _players = players; _playersLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _playersLoading = false);
    }
  }

  Future<void> _loadGames() async {
    final teamId = widget.team['id'] as int;
    final ck = 'team_games_$teamId';
    final cached = await LocalCache.get(ck, maxAgeSeconds: 600) as List?;
    if (cached != null && mounted) {
      setState(() { _games = cached; _gamesLoading = false; });
    } else if (mounted) {
      setState(() => _gamesLoading = true);
    }
    try {
      final data = await ApiService.getTeamGames(teamId);
      final games = data['games'] as List? ?? [];
      await LocalCache.set(ck, games);
      if (mounted) setState(() { _games = games; _gamesLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _gamesLoading = false);
    }
  }

  Future<void> _loadRosterChanges() async {
    final teamId = widget.team['id'] as int;
    final ck = 'team_roster_changes_$teamId';
    final cached = await LocalCache.get(ck, maxAgeSeconds: 300) as List?;
    if (cached != null && mounted) {
      setState(() { _rosterChanges = cached; _rosterLoading = false; });
    } else if (mounted) {
      setState(() => _rosterLoading = true);
    }
    try {
      final data = await ApiService.getTeamRosterChanges(teamId, days: 30);
      final changes = data['changes'] as List? ?? [];
      await LocalCache.set(ck, changes);
      if (mounted) setState(() { _rosterChanges = changes; _rosterLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _rosterLoading = false);
    }
  }

  Future<void> _loadNews() async {
    final teamId = widget.team['id'] as int;
    final ck = 'team_news_$teamId';
    final cached = await LocalCache.get(ck, maxAgeSeconds: 1800) as List?;
    if (cached != null && mounted) {
      setState(() { _news = cached; _newsLoading = false; });
    } else if (mounted) {
      setState(() => _newsLoading = true);
    }
    try {
      final data = await ApiService.getTeamNews(teamId, limit: 30);
      final news = data['news'] as List? ?? [];
      await LocalCache.set(ck, news);
      if (mounted) setState(() { _news = news; _newsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _newsLoading = false);
    }
  }

  Future<void> _loadCommunityPosts() async {
    final teamId = widget.team['id'] as int;
    final ck = 'team_community_$teamId';
    final cached = await LocalCache.get(ck, maxAgeSeconds: 300) as List?;
    if (cached != null && mounted) {
      setState(() { _communityPosts = cached; _communityLoading = false; });
    } else if (mounted) {
      setState(() => _communityLoading = true);
    }
    try {
      final data = await ApiService.getPosts(teamId: teamId, sort: 'latest', page: 1);
      final posts = data['posts'] as List? ?? [];
      await LocalCache.set(ck, posts);
      if (mounted) setState(() { _communityPosts = posts; _communityLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _communityLoading = false);
    }
  }

  Future<void> _loadMonthlyStats() async {
    final teamId = widget.team['id'] as int;
    final ck = 'team_monthly_$teamId';
    final cached = await LocalCache.get(ck, maxAgeSeconds: 3600) as List?;
    if (cached != null && mounted) {
      setState(() { _monthlyStats = cached; _monthlyLoading = false; });
    } else if (mounted) {
      setState(() => _monthlyLoading = true);
    }
    try {
      final data = await ApiService.getTeamMonthlyStats(teamId);
      final stats = data['monthly'] as List? ?? [];
      await LocalCache.set(ck, stats);
      if (mounted) setState(() { _monthlyStats = stats; _monthlyLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _monthlyLoading = false);
    }
  }

  Future<void> _loadH2H() async {
    final teamId = widget.team['id'] as int;
    final ck = 'team_h2h_$teamId';
    final cached = await LocalCache.get(ck, maxAgeSeconds: 3600) as List?;
    if (cached != null && mounted) {
      setState(() { _h2hRecords = cached; _h2hLoading = false; });
    } else if (mounted) {
      setState(() => _h2hLoading = true);
    }
    try {
      final data = await ApiService.getTeamHeadToHead(teamId);
      final records = data['records'] as List? ?? [];
      await LocalCache.set(ck, records);
      if (mounted) setState(() { _h2hRecords = records; _h2hLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _h2hLoading = false);
    }
  }

  Future<void> _loadBattingOrder() async {
    final teamId = widget.team['id'] as int;
    final ck = 'team_batting_order_$teamId';
    final cached = await LocalCache.get(ck, maxAgeSeconds: 1800) as List?;
    if (cached != null && mounted) {
      setState(() { _battingOrderStats = cached; _battingOrderLoading = false; });
    } else if (mounted) {
      setState(() => _battingOrderLoading = true);
    }
    try {
      final data = await ApiService.getTeamBattingOrder(teamId);
      final stats = data['stats'] as List? ?? [];
      await LocalCache.set(ck, stats);
      if (mounted) setState(() { _battingOrderStats = stats; _battingOrderLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _battingOrderLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = widget.team;
    final code = team['short_name'] as String? ?? '';
    final color = teamColor(code);
    final wins = team['wins'] as int? ?? 0;
    final losses = team['losses'] as int? ?? 0;
    final draws = team['draws'] as int? ?? 0;
    final hr = (team['home_record'] as Map?)?.cast<String, dynamic>() ?? {};
    final ar = (team['away_record'] as Map?)?.cast<String, dynamic>() ?? {};
    final vp = MediaQuery.of(context).viewPadding.bottom;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F12) : const Color(0xFFFAFAFB),
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // ── 팀컬러 헤더 (Option A: 흰색 _Btn32 back/star) ──
          Container(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            color: color,
            child: Row(children: [
              _WhiteBtn32(icon: Icons.chevron_left, onTap: () => Navigator.maybePop(context)),
              const SizedBox(width: 10),
              Expanded(child: Text(team['name'] ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5))),
              _favLoading
                  ? const SizedBox(width: 32, height: 32,
                      child: Padding(padding: EdgeInsets.all(7),
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
                  : _WhiteBtn32(
                      icon: _isFav ? Icons.star_rounded : Icons.star_border_rounded,
                      onTap: _toggleFav),
            ]),
          ),
          Expanded(
            child: Stack(children: [
              Padding(
                padding: EdgeInsets.only(bottom: 64 + vp),
                child: IndexedStack(
                  index: _mainTabIndex,
                  children: [
                    _buildOverviewTab(team, code, color, wins, losses, draws, hr, ar),
                    _buildPlayers(),
                    _buildGamesTab(),
                    _buildCommunity(),
                  ],
                ),
              ),
              Positioned(
                left: 16, right: 16,
                bottom: 12 + vp,
                child: _buildMainFloatingNav(color),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildMainFloatingNav(Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const labels = ['개요', '선수', '경기', '커뮤'];
    const icons = [Icons.home_outlined, Icons.people_outlined, Icons.sports_baseball_outlined, Icons.forum_outlined];
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF18181C) : Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final selected = _mainTabIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => _onMainTabChange(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icons[i], size: 18, color: selected ? color : Colors.grey),
                    const SizedBox(height: 1),
                    Text(labels[i], style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected ? color : Colors.grey,
                    )),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildOverviewTab(Map team, String code, Color color, int wins, int losses, int draws, Map<String, dynamic> hr, Map<String, dynamic> ar) {
    final cs = _C(context);
    final rosters = _rosterChanges.take(6).toList();
    final newsList = _news.take(6).toList();
    return ListView(padding: EdgeInsets.zero, children: [
      _buildHeader(team, code, color, wins, losses, draws, hr, ar),
      // 등록말소
      _SectionLabel(label: '최근 등록말소', cs: cs),
      if (_rosterLoading)
        _CardWrap(cs: cs, child: Padding(padding: const EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: color))))
      else if (rosters.isEmpty)
        _CardWrap(cs: cs, child: Padding(padding: const EdgeInsets.all(16),
            child: Text('최근 30일 등록말소 내역이 없습니다', style: TextStyle(color: cs.sub, fontSize: 12))))
      else
        _CardWrap(cs: cs, child: Column(children: rosters.asMap().entries.map((e) =>
            _buildChangeItem(cs, Map<String, dynamic>.from(e.value as Map), e.key == rosters.length - 1)).toList())),
      // 뉴스
      _SectionLabel(label: '최근 뉴스', cs: cs),
      if (_newsLoading)
        _CardWrap(cs: cs, child: Padding(padding: const EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: color))))
      else if (newsList.isEmpty)
        _CardWrap(cs: cs, child: Padding(padding: const EdgeInsets.all(16),
            child: Text('뉴스가 없습니다', style: TextStyle(color: cs.sub, fontSize: 12))))
      else
        _CardWrap(cs: cs, child: Column(children: newsList.asMap().entries.map((e) =>
            _buildNewsItem(cs, e.value as Map, e.key == newsList.length - 1)).toList())),
      const SizedBox(height: 24),
    ]);
  }

  Widget _buildNewsItem(_C cs, Map n, bool last) {
    final title = n['title'] as String? ?? '';
    final media = n['media'] as String? ?? '';
    final pub = n['published_at'] as String?;
    final url = n['url'] as String? ?? '';
    final thumbnail = n['thumbnail'] as String? ?? '';
    String dateStr = '';
    if (pub != null) {
      try {
        final dt = DateTime.parse(pub).toLocal();
        dateStr = '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }
    return GestureDetector(
      onTap: () => _openUrl(url),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thumbnail.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: thumbnail,
                  width: 72, height: 54, fit: BoxFit.cover,
                  placeholder: (_, _) => Container(width: 72, height: 54, color: cs.paper2),
                  errorWidget: (_, _, _) => Container(width: 72, height: 54, color: cs.paper2,
                      child: Icon(Icons.article_outlined, color: cs.sub, size: 20)),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(fontSize: 12, fontWeight: Typo.medium, color: cs.ink, height: 1.45),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Row(children: [
                    if (media.isNotEmpty) ...[
                      Text(media, style: TextStyle(fontSize: 10, color: cs.sub)),
                      const SizedBox(width: 6),
                    ],
                    if (dateStr.isNotEmpty)
                      Text(dateStr, style: TextStyle(fontSize: 10, color: cs.sub)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGamesTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = teamColor(widget.team['short_name'] as String? ?? '');
    const subLabels = ['최근경기', '월별성적', '상대전적', '타순별'];
    return Column(
      children: [
        Container(
          color: isDark ? const Color(0xFF18181C) : Colors.white,
          child: SizedBox(
            height: 40,
            child: Row(
              children: List.generate(subLabels.length, (i) {
                final selected = _gameSubIndex == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _onGameSubChange(i),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(
                          color: selected ? color : Colors.transparent,
                          width: 2.5,
                        )),
                      ),
                      child: Text(subLabels[i], style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                        color: selected
                            ? color
                            : (isDark ? Colors.grey[400] : Colors.grey),
                      )),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _gameSubIndex,
            children: [_buildGames(), _buildMonthlyStats(), _buildHeadToHead(), _buildBattingOrder()],
          ),
        ),
      ],
    );
  }

  Widget _buildSeasonStatsBar(_C cs) {
    final bat = (_seasonStats!['batting'] as Map?)?.cast<String, dynamic>() ?? {};
    final pit = (_seasonStats!['pitching'] as Map?)?.cast<String, dynamic>() ?? {};
    final rec = (_seasonStats!['record'] as Map?)?.cast<String, dynamic>() ?? {};
    return Container(
      decoration: BoxDecoration(color: cs.paper, border: Border.all(color: cs.line), borderRadius: BorderRadius.circular(Radii.md)),
      child: IntrinsicHeight(child: Row(children: [
        _StatBlock(label: '팀타율', value: (bat['avg'] as num?)?.toStringAsFixed(3) ?? '-', cs: cs),
        VerticalDivider(width: 1, color: cs.line),
        _StatBlock(label: '방어율', value: (pit['era'] as num?)?.toStringAsFixed(2) ?? '-', cs: cs),
        VerticalDivider(width: 1, color: cs.line),
        _StatBlock(label: 'WHIP', value: (pit['whip'] as num?)?.toStringAsFixed(2) ?? '-', cs: cs),
        VerticalDivider(width: 1, color: cs.line),
        _StatBlock(label: '득점', value: '${rec['runs_scored'] ?? '-'}', cs: cs),
        VerticalDivider(width: 1, color: cs.line),
        _StatBlock(label: '실점', value: '${rec['runs_allowed'] ?? '-'}', cs: cs),
        VerticalDivider(width: 1, color: cs.line),
        _StatBlock(label: '홈런', value: '${bat['home_runs'] ?? '-'}', cs: cs),
      ])),
    );
  }

  Widget _buildHeader(Map team, String code, Color color,
      int wins, int losses, int draws,
      Map<String, dynamic> hr, Map<String, dynamic> ar) {
    final cs = _C(context);
    final gb = _gamesBehind ?? team['games_behind'] as num?;
    final gbText = (gb == null || gb == 0) ? '선두' : '${gb.toStringAsFixed(1)} GB';
    final pythag = (team['pythag_winpct'] as num?)?.toStringAsFixed(3);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: cs.dark ? 0.14 : 0.06),
        border: Border(bottom: BorderSide(color: color.withValues(alpha: cs.dark ? 0.3 : 0.15))),
      ),
      child: Column(children: [
        Row(children: [
          TeamLogo(teamCode: code, size: 64, logoUrl: team['logo_url']),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(team['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 20, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.5))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Text('${team['rank'] ?? '-'}위', style: TextStyle(fontSize: 12, fontWeight: Typo.bold, color: color)),
              ),
            ]),
            const SizedBox(height: 5),
            Text('$wins승 $losses패${draws > 0 ? ' $draws무' : ''} · 승률 ${(team['win_rate'] as num?)?.toStringAsFixed(3) ?? '-'} · $gbText',
                style: TextStyle(fontSize: 13, color: cs.ink3)),
            const SizedBox(height: 3),
            Text('홈 ${hr['wins'] ?? 0}-${hr['losses'] ?? 0} · 원정 ${ar['wins'] ?? 0}-${ar['losses'] ?? 0}'
                '${pythag != null ? ' · 피타고리안 $pythag' : ''}',
                style: TextStyle(fontSize: 11, color: cs.sub)),
          ])),
        ]),
        if (_seasonStats != null) ...[
          const SizedBox(height: 14),
          _buildSeasonStatsBar(cs),
        ],
      ]),
    );
  }

  Widget _buildPlayers() {
    final cs = _C(context);
    final color = teamColor(widget.team['short_name'] as String? ?? '');
    if (_playersLoading) return Center(child: CircularProgressIndicator(color: color, strokeWidth: 2.5));
    if (_players.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPlayers,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 180),
            Center(child: Text('선수 정보가 없습니다\n아래로 당겨서 새로고침',
                textAlign: TextAlign.center, style: TextStyle(color: cs.sub))),
          ],
        ),
      );
    }

    final pitchers = _players.where((p) => p['player_type'] == '투수').toList();
    final batters = _players.where((p) => p['player_type'] == '타자').toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (pitchers.isNotEmpty) ...[
          _SectionLabel(label: '투수 ${pitchers.length}', cs: cs),
          _CardWrap(cs: cs, child: Column(children: pitchers.asMap().entries.map((e) =>
              _playerRow(cs, color, e.value as Map, e.key == pitchers.length - 1)).toList())),
        ],
        if (batters.isNotEmpty) ...[
          _SectionLabel(label: '타자 ${batters.length}', cs: cs),
          _CardWrap(cs: cs, child: Column(children: batters.asMap().entries.map((e) =>
              _playerRow(cs, color, e.value as Map, e.key == batters.length - 1)).toList())),
        ],
      ],
    );
  }

  Widget _playerRow(_C cs, Color color, Map p, bool last) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PlayerDetailScreen(
          playerId: p['id'],
          initialData: {'name': p['name'], 'team': widget.team['name'], 'profile_image': p['profile_image'], 'position': p['position'], 'player_type': p['player_type'], 'number': p['number'], 'team_code': widget.team['short_name']},
        )),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: cs.dark ? 0.18 : 0.08),
                border: Border.all(color: color.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Text('#${p['number'] ?? '-'}',
                  style: TextStyle(fontSize: 12, fontWeight: Typo.extra, color: color))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(p['name'] ?? '',
                style: TextStyle(fontSize: 14, fontWeight: Typo.bold, color: cs.ink))),
            Text(p['position'] ?? '', style: TextStyle(fontSize: 11, color: cs.sub)),
          ],
        ),
      ),
    );
  }

  String? _seriesLabel(int wins, int losses, int total) {
    if (losses == 0 && wins >= 3) return '스윕 승';
    if (wins >= 2 && losses > 0 && wins > losses) return '위닝 시리즈';
    if (wins == losses && total >= 2) return '스플릿';
    if (wins == 0 && losses >= 3) return '스윕 패';
    if (losses > wins && losses >= 2) return '루징 시리즈';
    return null;
  }

  Color _seriesLabelColor(String label) {
    if (label.contains('스윕 승')) return const Color(0xFF1565C0);
    if (label.contains('위닝')) return const Color(0xFF1976D2);
    if (label.contains('스플릿')) return Colors.grey;
    if (label.contains('루징')) return const Color(0xFFE53935);
    if (label.contains('스윕 패')) return const Color(0xFFC62828);
    return Colors.grey;
  }

  List<List<Map>> _groupIntoSeries(List games, String teamName) {
    final sorted = List<Map>.from(games)
      ..sort((a, b) => (a['game_date'] as String).compareTo(b['game_date'] as String));

    final series = <List<Map>>[];

    for (final g in sorted) {
      final isHome = g['home_team'] == teamName;
      final opp = isHome ? g['away_team'] : g['home_team'];
      final date = DateTime.tryParse(g['game_date'] as String? ?? '') ?? DateTime(2000);

      if (series.isEmpty) {
        series.add([g]);
        continue;
      }

      final last = series.last;
      final lastG = last.last;
      final lastIsHome = lastG['home_team'] == teamName;
      final lastOpp = lastIsHome ? lastG['away_team'] : lastG['home_team'];
      final lastDate = DateTime.tryParse(lastG['game_date'] as String? ?? '') ?? DateTime(2000);
      final dayDiff = date.difference(lastDate).inDays;

      if (lastOpp == opp && dayDiff <= 3 && last.length < 3) {
        last.add(g);
      } else {
        series.add([g]);
      }
    }

    return series.reversed.toList();
  }

  Widget _buildGames() {
    final cs = _C(context);
    final tColor = teamColor(widget.team['short_name'] as String? ?? '');
    if (_gamesLoading) return Center(child: CircularProgressIndicator(color: tColor, strokeWidth: 2.5));
    if (_games.isEmpty) return Center(child: Text('경기 정보가 없습니다', style: TextStyle(color: cs.sub)));

    final teamName = widget.team['name'] as String? ?? '';
    final seriesList = _groupIntoSeries(_games, teamName);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      itemCount: seriesList.length,
      itemBuilder: (context, idx) {
        final s = seriesList[idx];
        final firstG = s.first;
        final firstIsHome = firstG['home_team'] == teamName;
        final oppName = firstIsHome ? firstG['away_team'] : firstG['home_team'];

        int wins = 0, losses = 0, draws = 0;
        for (final g in s) {
          final isHome = g['home_team'] == teamName;
          final my = isHome ? (g['home_score'] ?? 0) : (g['away_score'] ?? 0);
          final opp = isHome ? (g['away_score'] ?? 0) : (g['home_score'] ?? 0);
          if ((my as num) > (opp as num)) {
            wins++;
          } else if (my < opp) {
            losses++;
          } else {
            draws++;
          }
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: cs.paper,
            border: Border.all(color: cs.line),
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.paper2,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
                ),
                child: Row(
                  children: [
                    Text('vs $oppName',
                        style: TextStyle(fontWeight: Typo.bold, fontSize: 14, color: cs.ink)),
                    const Spacer(),
                    if (wins > 0)
                      Text('$wins승 ', style: const TextStyle(color: Color(0xFF2563EB), fontSize: 13, fontWeight: FontWeight.bold)),
                    if (losses > 0)
                      Text('$losses패', style: TextStyle(color: SemColor.live, fontSize: 13, fontWeight: FontWeight.bold)),
                    if (draws > 0)
                      Text(' $draws무', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    Builder(builder: (_) {
                      final label = _seriesLabel(wins, losses, s.length);
                      if (label == null) return const SizedBox.shrink();
                      final c = _seriesLabelColor(label);
                      return Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: c, width: 0.8),
                        ),
                        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c)),
                      );
                    }),
                  ],
                ),
              ),
              ...s.map((g) {
                final isHome = g['home_team'] == teamName;
                final myScore = isHome ? (g['home_score'] ?? 0) : (g['away_score'] ?? 0);
                final oppScore = isHome ? (g['away_score'] ?? 0) : (g['home_score'] ?? 0);
                final isWin = (myScore as num) > (oppScore as num);
                final isLoss = myScore < oppScore;
                final dateStr = (g['game_date'] as String? ?? '').replaceAll('-', '.');
                final gameId = g['id'] as int?;

                return InkWell(
                  onTap: gameId != null
                      ? () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => GameDetailScreen(gameId: gameId)))
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isWin ? Colors.blue : isLoss ? Colors.red : Colors.grey,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            isWin ? '승' : isLoss ? '패' : '무',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('$myScore : $oppScore',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: cs.ink)),
                        const SizedBox(width: 10),
                        Text(isHome ? '홈' : '원정',
                            style: TextStyle(fontSize: 11, color: cs.sub)),
                        const Spacer(),
                        Text(dateStr, style: TextStyle(fontSize: 12, color: cs.sub)),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right, size: 16, color: cs.sub),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }


  Widget _buildChangeItem(_C cs, Map<String, dynamic> c, bool last) {
    final changeType = c['change_type'] as String? ?? '';
    final playerName = c['player_name'] as String? ?? '';
    final reason = c['reason'] as String? ?? '';
    final position = c['position'] as String? ?? '';
    final playerId = c['player_id'] as int?;

    final typeColor = changeType == '1군등록' ? const Color(0xFF2563EB)
        : changeType == '부상자명단' ? SemColor.live
        : changeType == '임의탈퇴' ? cs.sub
        : SemColor.warning; // 등록말소 등

    return GestureDetector(
      onTap: playerId != null
          ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: playerId)))
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
            child: Text(changeType, style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: typeColor)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Row(children: [
            Flexible(child: Text(playerName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: cs.ink))),
            if (reason.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(child: Text(reason, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: cs.sub))),
            ],
          ])),
          if (position.isNotEmpty) Text(position, style: TextStyle(fontSize: 11, color: cs.sub)),
        ]),
      ),
    );
  }


  Widget _buildCommunity() {
    final cs = _C(context);
    final color = teamColor(widget.team['short_name'] as String? ?? '');
    final teamShort = (widget.team['name'] as String? ?? '').split(' ').first;
    if (_communityLoading) return Center(child: CircularProgressIndicator(color: color, strokeWidth: 2.5));
    if (_communityPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('커뮤니티 글이 없습니다', style: TextStyle(color: cs.sub)),
            const SizedBox(height: 12),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('새로고침'),
              onPressed: () {
                setState(() => _communityPosts = []);
                _loadCommunityPosts();
              },
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _communityPosts = []);
        await _loadCommunityPosts();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(18),
        itemCount: _communityPosts.length,
        itemBuilder: (_, i) {
          final post = _communityPosts[i] as Map;
          final title = post['title'] as String? ?? '';
          final nickname = post['nickname'] as String? ?? '';
          final views = post['views'] as int? ?? 0;
          final likes = post['likes'] as int? ?? 0;
          final comments = post['comment_count'] as int? ?? 0;
          final category = post['category'] as String? ?? '';
          final createdAt = post['created_at'] as String?;
          final postId = post['id'] as int?;

          String dateStr = '';
          if (createdAt != null) {
            try {
              final dt = DateTime.parse(createdAt).toLocal();
              final diff = DateTime.now().difference(dt);
              if (diff.inMinutes < 60) {
                dateStr = '${diff.inMinutes}분 전';
              } else if (diff.inHours < 24) {
                dateStr = '${diff.inHours}시간 전';
              } else {
                dateStr = '${dt.month}/${dt.day}';
              }
            } catch (_) {}
          }

          return GestureDetector(
            onTap: postId != null
                ? () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)))
                : null,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.paper, border: Border.all(color: cs.line),
                borderRadius: BorderRadius.circular(Radii.lg),
                boxShadow: cs.dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 5, children: [
                    _SmallChip(label: teamShort, color: color, bg: color.withValues(alpha: 0.1)),
                    if (category.isNotEmpty)
                      _SmallChip(label: category, color: cs.ink3, bg: cs.paper2, border: cs.line),
                  ]),
                  const SizedBox(height: 7),
                  Text(title,
                      style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: cs.ink, height: 1.45),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Row(children: [
                    Text(nickname, style: TextStyle(fontSize: 10, color: cs.sub)),
                    if (dateStr.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(dateStr, style: TextStyle(fontSize: 10, color: cs.sub)),
                    ],
                    const Spacer(),
                    Icon(Icons.visibility_outlined, size: 12, color: cs.sub),
                    const SizedBox(width: 2),
                    Text('$views', style: TextStyle(fontSize: 10, color: cs.sub)),
                    const SizedBox(width: 8),
                    Icon(Icons.favorite_border, size: 12, color: cs.sub),
                    const SizedBox(width: 2),
                    Text('$likes', style: TextStyle(fontSize: 10, color: cs.sub)),
                    const SizedBox(width: 8),
                    Icon(Icons.mode_comment_outlined, size: 12, color: cs.sub),
                    const SizedBox(width: 2),
                    Text('$comments', style: TextStyle(fontSize: 10, color: cs.sub)),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMonthlyStats() {
    if (_monthlyLoading) return Center(child: CircularProgressIndicator(color: Theme.of(context).brightness == Brightness.dark ? AppColors.primaryDark : SemColor.panelDark, strokeWidth: 2.5));
    if (_monthlyStats.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('월별 성적이 없습니다', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('새로고침'),
              onPressed: () {
                setState(() => _monthlyStats = []);
                _loadMonthlyStats();
              },
            ),
          ],
        ),
      );
    }

    final code = widget.team['short_name'] as String? ?? '';
    final color = teamColor(code);

    final months = _monthlyStats.map((m) => (m['month'] as num).toInt()).toList();
    final winRates = _monthlyStats.map((m) => (m['win_rate'] as num).toDouble()).toList();

    const monthNames = {3:'3월', 4:'4월', 5:'5월', 6:'6월', 7:'7월', 8:'8월', 9:'9월', 10:'10월'};

    final spots = List.generate(winRates.length, (i) => FlSpot(i.toDouble(), winRates[i]));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('월별 승률 추이 (2026)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 1,
                gridData: FlGridData(
                  show: true,
                  horizontalInterval: 0.25,
                  getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.withValues(alpha: 0.2), strokeWidth: 1),
                  drawVerticalLine: false,
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                    left: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 0.25,
                      getTitlesWidget: (v, _) => Text(v.toStringAsFixed(2),
                          style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= months.length) return const SizedBox();
                        return Text(monthNames[months[idx]] ?? '',
                            style: TextStyle(fontSize: 11, color: Colors.grey[700]));
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots.map((s) {
                      final idx = s.x.toInt();
                      final m = monthNames[months[idx]] ?? '';
                      final row = _monthlyStats[idx];
                      return LineTooltipItem(
                        '$m\n${s.y.toStringAsFixed(3)}\n${row['wins']}승 ${row['losses']}패',
                        const TextStyle(fontSize: 12, color: Colors.white),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: color,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (_, _, _, _) =>
                          FlDotCirclePainter(radius: 4, color: color, strokeWidth: 1.5, strokeColor: Colors.white),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withValues(alpha: 0.12),
                    ),
                  ),
                  // 5할 기준선
                  LineChartBarData(
                    spots: [FlSpot(0, 0.5), FlSpot((spots.length - 1).toDouble(), 0.5)],
                    isCurved: false,
                    color: Colors.grey.withValues(alpha: 0.5),
                    barWidth: 1,
                    dotData: const FlDotData(show: false),
                    dashArray: [4, 4],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('월별 세부 성적', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Table(
            border: TableBorder.all(color: Colors.grey.withValues(alpha: 0.2), width: 0.5),
            columnWidths: const {
              0: FlexColumnWidth(1.2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
              4: FlexColumnWidth(1.2),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1)),
                children: ['월', '경기', '승', '패', '승률'].map((h) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Text(h, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                )).toList(),
              ),
              ..._monthlyStats.map((row) {
                final m = monthNames[row['month']] ?? '${row['month']}월';
                final wr = (row['win_rate'] as num).toDouble();
                return TableRow(
                  children: [
                    _tableCell(m),
                    _tableCell('${row['games']}'),
                    _tableCell('${row['wins']}', bold: true, color: Colors.blue[700]),
                    _tableCell('${row['losses']}', bold: true, color: Colors.red[700]),
                    _tableCell(wr.toStringAsFixed(3),
                        bold: true, color: wr >= 0.5 ? Colors.blue[700] : Colors.red[700]),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tableCell(String text, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color,
          )),
    );
  }

  void _openUrl(String url) async {
    if (url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _buildHeadToHead() {
    if (_h2hLoading) return Center(child: CircularProgressIndicator(color: Theme.of(context).brightness == Brightness.dark ? AppColors.primaryDark : SemColor.panelDark, strokeWidth: 2.5));
    if (_h2hRecords.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('상대 전적 데이터가 없습니다', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _loadH2H,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    final code = widget.team['short_name'] as String? ?? '';
    final color = teamColor(code);

    // 전체 합산
    final totalW = _h2hRecords.fold(0, (s, r) => s + (r['wins'] as int? ?? 0));
    final totalL = _h2hRecords.fold(0, (s, r) => s + (r['losses'] as int? ?? 0));
    final totalD = _h2hRecords.fold(0, (s, r) => s + (r['draws'] as int? ?? 0));
    final totalG = totalW + totalL + totalD;
    final totalPct = totalG > 0 ? (totalW / totalG * 100).toStringAsFixed(1) : '-';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 종합 요약 카드
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: color.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _h2hStat('전체', '$totalG경기', Colors.black87),
                _h2hStat('승', '$totalW', Colors.blue),
                _h2hStat('패', '$totalL', Colors.red),
                _h2hStat('무', '$totalD', Colors.grey),
                _h2hStat('승률', totalPct == '-' ? '-' : '$totalPct%', color),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 상대별 행
        ...(_h2hRecords.map((r) => _buildH2HRow(r))),
      ],
    );
  }

  Widget _buildH2HRow(Map r) {
    final wins    = r['wins']    as int? ?? 0;
    final losses  = r['losses']  as int? ?? 0;
    final draws   = r['draws']   as int? ?? 0;
    final total   = r['total']   as int? ?? 0;
    final rs      = r['runs_scored']  as int? ?? 0;
    final ra      = r['runs_allowed'] as int? ?? 0;
    final oppCode = r['opp_code'] as String? ?? '';
    final oppName = r['opp_name'] as String? ?? '';
    final pct     = total > 0 ? (wins / total * 100).toStringAsFixed(1) : '-';

    final Color rowColor;
    if (wins > losses) {
      rowColor = Colors.blue;
    } else if (wins < losses) {
      rowColor = Colors.red;
    } else {
      rowColor = Colors.grey;
    }

    final winBar = total > 0 ? wins / total : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          children: [
            Row(
              children: [
                TeamLogo(teamCode: oppCode, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(oppName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      Text('득점 $rs  실점 $ra',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Text('$wins', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                        Text(' 승  ', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        Text('$losses', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                        Text(' 패', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        if (draws > 0) ...[
                          Text('  $draws', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
                          Text(' 무', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      ],
                    ),
                    Text(
                      pct == '-' ? '-' : '승률 $pct%',
                      style: TextStyle(fontSize: 12, color: rowColor, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
            if (total > 0) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: winBar,
                  backgroundColor: Colors.red.shade100,
                  color: Colors.blue.shade400,
                  minHeight: 6,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _h2hStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _buildBattingOrder() {
    if (_battingOrderLoading) return Center(child: CircularProgressIndicator(color: Theme.of(context).brightness == Brightness.dark ? AppColors.primaryDark : SemColor.panelDark, strokeWidth: 2.5));
    if (_battingOrderStats.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('타순별 성적 데이터가 없습니다', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _loadBattingOrder,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    final code = widget.team['short_name'] as String? ?? '';
    final color = teamColor(code);

    // AVG 범위 계산 (색상 스케일용)
    final avgs = _battingOrderStats.map((s) => (s['avg'] as num).toDouble()).toList();
    final maxAvg = avgs.isNotEmpty ? avgs.reduce((a, b) => a > b ? a : b) : 0.3;
    final minAvg = avgs.isNotEmpty ? avgs.reduce((a, b) => a < b ? a : b) : 0.2;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 헤더 설명
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('2026 시즌 타순별 누적 성적',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
        ),
        // 컬럼 헤더
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              _boHeader('타순', 36, CrossAxisAlignment.center),
              _boHeader('주요 타자', 90, CrossAxisAlignment.start),
              _boHeader('타율', 52, CrossAxisAlignment.end),
              _boHeader('출루율', 52, CrossAxisAlignment.end),
              _boHeader('홈런', 40, CrossAxisAlignment.end),
              _boHeader('타점', 40, CrossAxisAlignment.end),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // 타순별 행
        ..._battingOrderStats.map((s) {
          final order = s['batting_order'] as int;
          final avg = (s['avg'] as num).toDouble();
          final obp = (s['obp'] as num).toDouble();
          final hr = s['home_runs'] as int? ?? 0;
          final rbi = s['rbis'] as int? ?? 0;
          final topPlayer = s['top_player'] as String? ?? '-';
          final topPlayerId = s['top_player_id'] as int?;
          final topPlayerImage = s['top_player_image'] as String?;

          // AVG 기반 배경색 (높을수록 진한 파랑)
          final t = maxAvg > minAvg ? (avg - minAvg) / (maxAvg - minAvg) : 0.5;
          final bgColor = Color.lerp(Colors.grey.shade100, color.withValues(alpha: 0.18), t)!;

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: GestureDetector(
              onTap: topPlayerId != null
                  ? () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => PlayerDetailScreen(playerId: topPlayerId)))
                  : null,
              child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Center(
                    child: Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text('$order',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: color.withValues(alpha: 0.15),
                        backgroundImage: (topPlayerImage != null && topPlayerImage.isNotEmpty)
                            ? CachedNetworkImageProvider(topPlayerImage)
                            : null,
                        child: (topPlayerImage == null || topPlayerImage.isEmpty)
                            ? Icon(Icons.person, size: 13, color: color)
                            : null,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(topPlayer,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
                _boValue(avg.toStringAsFixed(3), 52,
                    avg >= 0.300 ? Colors.blue.shade700 : avg < 0.230 ? Colors.red.shade400 : null),
                _boValue(obp.toStringAsFixed(3), 52,
                    obp >= 0.370 ? Colors.blue.shade700 : null),
                _boValue('$hr', 40, hr >= 5 ? Colors.deepOrange : null),
                _boValue('$rbi', 40, rbi >= 30 ? Colors.deepOrange : null),
              ],
            ),
            ),
          );
        }),
        const SizedBox(height: 12),
        // AVG 바 차트
        const Text('타순별 타율', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _battingOrderStats.map((s) {
              final order = s['batting_order'] as int;
              final avg = (s['avg'] as num).toDouble();
              final barH = maxAvg > 0 ? (avg / maxAvg) * 90 : 0.0;
              return Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(avg.toStringAsFixed(3),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  const SizedBox(height: 2),
                  Container(
                    width: 26,
                    height: barH,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.7),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('$order번',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _boHeader(String label, double width, CrossAxisAlignment align) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: align == CrossAxisAlignment.end
            ? Alignment.centerRight
            : align == CrossAxisAlignment.center
                ? Alignment.center
                : Alignment.centerLeft,
        child: Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
      ),
    );
  }

  Widget _boValue(String value, double width, Color? color) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: color != null ? FontWeight.bold : FontWeight.normal,
                color: color)),
      ),
    );
  }
}

// ── 팀컬러 헤더용 흰색 32px 버튼 (Option A) ──
class _WhiteBtn32 extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _WhiteBtn32({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    ),
  );
}

// ── Option A 공통 소형 위젯 ──────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  final _C cs;
  const _SectionLabel({required this.label, required this.cs});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub, letterSpacing: 0.8)),
  );
}

class _CardWrap extends StatelessWidget {
  final Widget child;
  final _C cs;
  const _CardWrap({required this.child, required this.cs});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: Container(
      decoration: BoxDecoration(
        color: cs.paper, border: Border.all(color: cs.line),
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: cs.dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1))],
      ),
      child: child,
    ),
  );
}

class _StatBlock extends StatelessWidget {
  final String label, value;
  final _C cs;
  const _StatBlock({required this.label, required this.value, required this.cs});
  @override
  Widget build(BuildContext context) => Expanded(child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 13, fontWeight: Typo.extra, color: cs.ink)),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 9, color: cs.sub)),
    ]),
  ));
}

class _SmallChip extends StatelessWidget {
  final String label;
  final Color color, bg;
  final Color? border;
  const _SmallChip({required this.label, required this.color, required this.bg, this.border});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg, borderRadius: BorderRadius.circular(Radii.xs),
      border: border != null ? Border.all(color: border!) : null,
    ),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: color)),
  );
}

// ── 색상 헬퍼 ─────────────────────────────────────────────────────────────────
class _C {
  final Color bg, paper, paper2, ink, ink2, ink3, sub, line, line2, track;
  final bool dark;
  _C(BuildContext ctx)
    : dark   = Theme.of(ctx).brightness == Brightness.dark,
      bg     = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFFAFAFB),
      paper  = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF18181C) : Colors.white,
      paper2 = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6),
      ink    = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFFF4F4F5) : const Color(0xFF111113),
      ink2   = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46),
      ink3   = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73),
      sub    = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2),
      line   = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0),
      line2  = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF33333A) : const Color(0xFFE0E0E4),
      track  = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF2C2C33) : const Color(0xFFE8E8EC);
}
