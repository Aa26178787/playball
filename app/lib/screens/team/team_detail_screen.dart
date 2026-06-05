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

    return Scaffold(
      appBar: AppBar(
        title: Text(team['name'] ?? ''),
        backgroundColor: color,
        foregroundColor: Colors.white,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          _favLoading
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
              : IconButton(
                  icon: Icon(_isFav ? Icons.star : Icons.star_border, color: Colors.white),
                  onPressed: _toggleFav,
                ),
        ],
      ),
      body: Stack(
        children: [
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
        ],
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
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0, 4))],
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
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(team, code, color, wins, losses, draws, hr, ar),
          if (_seasonStats != null) _buildSeasonStatsBar(),
          const SizedBox(height: 4),
          // 등록말소 섹션
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: const Text('최근 등록말소', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          if (_rosterLoading)
            Padding(padding: const EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).brightness == Brightness.dark ? AppColors.primaryDark : SemColor.panelDark)))
          else if (_rosterChanges.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text('최근 30일 등록말소 내역이 없습니다', style: TextStyle(color: Colors.grey, fontSize: 13)),
            )
          else
            ..._rosterChanges.take(5).map((c) => _buildChangeItem(Map<String, dynamic>.from(c as Map))),
          const Divider(height: 1),
          // 뉴스 섹션
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: const Text('최근 뉴스', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          if (_newsLoading)
            Padding(padding: const EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).brightness == Brightness.dark ? AppColors.primaryDark : SemColor.panelDark)))
          else if (_news.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text('뉴스가 없습니다', style: TextStyle(color: Colors.grey, fontSize: 13)),
            )
          else
            ..._news.take(5).map((n) => _buildNewsItem(n as Map)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildNewsItem(Map n) {
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
    return InkWell(
      onTap: () => _openUrl(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thumbnail.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: thumbnail,
                  width: 72, height: 54, fit: BoxFit.cover,
                  placeholder: (_, _) => Container(width: 72, height: 54, color: Colors.grey[200]),
                  errorWidget: (_, _, _) => Container(width: 72, height: 54, color: Colors.grey[100],
                      child: const Icon(Icons.article_outlined, color: Colors.grey, size: 20)),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.4),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(children: [
                    if (media.isNotEmpty) ...[
                      Text(media, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      const SizedBox(width: 6),
                    ],
                    if (dateStr.isNotEmpty)
                      Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
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
    const subLabels = ['최근경기', '월별성적', '상대전적', '타순별'];
    return Column(
      children: [
        Container(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
                          color: selected
                              ? (isDark ? AppColors.primaryDark : SemColor.panelDark)
                              : Colors.transparent,
                          width: 2.5,
                        )),
                      ),
                      child: Text(subLabels[i], style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                        color: selected
                            ? (isDark ? AppColors.primaryDark : SemColor.panelDark)
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

  Widget _buildSeasonStatsBar() {
    final bat = (_seasonStats!['batting'] as Map?)?.cast<String, dynamic>() ?? {};
    final pit = (_seasonStats!['pitching'] as Map?)?.cast<String, dynamic>() ?? {};
    final rec = (_seasonStats!['record'] as Map?)?.cast<String, dynamic>() ?? {};
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? Colors.grey[850] : Colors.grey[50],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statBlock('팀타율', (bat['avg'] as num?)?.toStringAsFixed(3) ?? '-'),
          _divider(),
          _statBlock('팀방어율', (pit['era'] as num?)?.toStringAsFixed(2) ?? '-'),
          _divider(),
          _statBlock('WHIP', (pit['whip'] as num?)?.toStringAsFixed(2) ?? '-'),
          _divider(),
          _statBlock('득점', '${rec['runs_scored'] ?? '-'}'),
          _divider(),
          _statBlock('실점', '${rec['runs_allowed'] ?? '-'}'),
          _divider(),
          _statBlock('팀홈런', '${bat['home_runs'] ?? '-'}'),
        ],
      ),
    );
  }

  Widget _statBlock(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ],
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 28, color: Colors.grey.withValues(alpha: 0.25));
  }

  Widget _buildHeader(Map team, String code, Color color,
      int wins, int losses, int draws,
      Map<String, dynamic> hr, Map<String, dynamic> ar) {
    final gb = _gamesBehind ?? team['games_behind'] as num?;
    final gbText = gb == null ? '-' : gb == 0 ? '-' : gb.toStringAsFixed(1);

    return Container(
      color: color.withValues(alpha: 0.06),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          TeamLogo(teamCode: code, size: 64, logoUrl: team['logo_url']),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${team['rank'] ?? '-'}위',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '승률 ${(team['win_rate'] as num?)?.toStringAsFixed(3) ?? '-'}  게임차 $gbText',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '전체  $wins승 $losses패 $draws무',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _recordChip('홈', hr['wins'] ?? 0, hr['losses'] ?? 0),
                    const SizedBox(width: 12),
                    _recordChip('원정', ar['wins'] ?? 0, ar['losses'] ?? 0),
                  ],
                ),
                const SizedBox(height: 4),
                Builder(builder: (_) {
                  final hw = (hr['wins'] as int? ?? 0);
                  final hl = (hr['losses'] as int? ?? 0);
                  final aw = (ar['wins'] as int? ?? 0);
                  final al = (ar['losses'] as int? ?? 0);
                  final homeWinPct = (hw + hl) > 0 ? (hw / (hw + hl)).toStringAsFixed(3) : '-';
                  final awayWinPct = (aw + al) > 0 ? (aw / (aw + al)).toStringAsFixed(3) : '-';
                  final pythag = (team['pythag_winpct'] as num?)?.toStringAsFixed(3) ?? '-';
                  return Text(
                    '홈 승률 $homeWinPct  원정 승률 $awayWinPct  피타고리안 $pythag',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordChip(String label, int w, int l) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12, color: Colors.black87),
        children: [
          TextSpan(
            text: '$label  ',
            style: TextStyle(color: Colors.grey[600]),
          ),
          TextSpan(
            text: '$w',
            style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
          ),
          const TextSpan(text: '승 '),
          TextSpan(
            text: '$l',
            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          const TextSpan(text: '패'),
        ],
      ),
    );
  }

  Widget _buildPlayers() {
    if (_playersLoading) return Center(child: CircularProgressIndicator(color: Theme.of(context).brightness == Brightness.dark ? AppColors.primaryDark : SemColor.panelDark, strokeWidth: 2.5));
    if (_players.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPlayers,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 180),
            Center(child: Text('선수 정보가 없습니다\n아래로 당겨서 새로고침',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
          ],
        ),
      );
    }

    final pitchers = _players.where((p) => p['player_type'] == '투수').toList();
    final batters = _players.where((p) => p['player_type'] == '타자').toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (pitchers.isNotEmpty) ...[
          _sectionHeader('투수'),
          ...pitchers.map((p) => _playerRow(p)),
        ],
        if (batters.isNotEmpty) ...[
          _sectionHeader('타자'),
          ...batters.map((p) => _playerRow(p)),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey.withValues(alpha: 0.1),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }

  Widget _playerRow(Map p) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PlayerDetailScreen(
          playerId: p['id'],
          initialData: {'name': p['name'], 'team': widget.team['name'], 'profile_image': p['profile_image'], 'position': p['position'], 'player_type': p['player_type'], 'number': p['number']},
        )),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(
                '#${p['number'] ?? '-'}',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),
            Expanded(
              child: Text(
                p['name'] ?? '',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
            Text(
              p['position'] ?? '',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
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
    if (_gamesLoading) return Center(child: CircularProgressIndicator(color: Theme.of(context).brightness == Brightness.dark ? AppColors.primaryDark : SemColor.panelDark, strokeWidth: 2.5));
    if (_games.isEmpty) return const Center(child: Text('경기 정보가 없습니다'));

    final teamName = widget.team['name'] as String? ?? '';
    final seriesList = _groupIntoSeries(_games, teamName);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.07),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Text('vs $oppName',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const Spacer(),
                    if (wins > 0)
                      Text('$wins승 ', style: const TextStyle(color: Colors.blue, fontSize: 13, fontWeight: FontWeight.bold)),
                    if (losses > 0)
                      Text('$losses패', style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold)),
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
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(width: 10),
                        Text(isHome ? '홈' : '원정',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        const Spacer(),
                        Text(dateStr, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
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


  Widget _buildChangeItem(Map<String, dynamic> c) {
    final changeType = c['change_type'] as String? ?? '';
    final playerName = c['player_name'] as String? ?? '';
    final reason = c['reason'] as String? ?? '';
    final position = c['position'] as String? ?? '';
    final playerId = c['player_id'] as int?;

    Color typeColor;
    IconData typeIcon;
    switch (changeType) {
      case '1군등록':
        typeColor = Colors.blue;
        typeIcon = Icons.arrow_upward;
        break;
      case '등록말소':
        typeColor = Colors.orange;
        typeIcon = Icons.arrow_downward;
        break;
      case '부상자명단':
        typeColor = Colors.red;
        typeIcon = Icons.local_hospital;
        break;
      case '임의탈퇴':
        typeColor = Colors.grey;
        typeIcon = Icons.person_off;
        break;
      default:
        typeColor = Colors.grey;
        typeIcon = Icons.swap_horiz;
    }

    return ListTile(
      dense: true,
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: typeColor.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(typeIcon, size: 16, color: typeColor),
      ),
      title: Row(children: [
        Text(playerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        if (position.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(position, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ],
      ]),
      subtitle: reason.isNotEmpty ? Text(reason, style: const TextStyle(fontSize: 11)) : null,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: typeColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(changeType, style: TextStyle(fontSize: 11, color: typeColor, fontWeight: FontWeight.bold)),
      ),
      onTap: playerId != null
          ? () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: playerId)))
          : null,
    );
  }


  Widget _buildCommunity() {
    if (_communityLoading) return Center(child: CircularProgressIndicator(color: Theme.of(context).brightness == Brightness.dark ? AppColors.primaryDark : SemColor.panelDark, strokeWidth: 2.5));
    if (_communityPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('커뮤니티 글이 없습니다', style: TextStyle(color: Colors.grey)),
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
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _communityPosts.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
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
              final now = DateTime.now();
              final diff = now.difference(dt);
              if (diff.inMinutes < 60) {
                dateStr = '${diff.inMinutes}분 전';
              } else if (diff.inHours < 24) {
                dateStr = '${diff.inHours}시간 전';
              } else {
                dateStr = '${dt.month}/${dt.day}';
              }
            } catch (_) {}
          }

          return InkWell(
            onTap: postId != null
                ? () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)))
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    if (category.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(category,
                            style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(title,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Text(nickname, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    const SizedBox(width: 8),
                    Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    const Spacer(),
                    Icon(Icons.visibility_outlined, size: 12, color: Colors.grey[600]),
                    const SizedBox(width: 2),
                    Text('$views', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    const SizedBox(width: 8),
                    Icon(Icons.favorite_border, size: 12, color: Colors.grey[600]),
                    const SizedBox(width: 2),
                    Text('$likes', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    const SizedBox(width: 8),
                    Icon(Icons.comment_outlined, size: 12, color: Colors.grey[600]),
                    const SizedBox(width: 2),
                    Text('$comments', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
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
