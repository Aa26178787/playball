import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api/api_service.dart';
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

class _TeamDetailScreenState extends State<TeamDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List _players = [];
  List _games = [];
  List _rosterChanges = [];
  List _news = [];
  List _communityPosts = [];
  List _monthlyStats = [];
  bool _playersLoading = true;
  bool _gamesLoading = false;
  bool _rosterLoading = false;
  bool _newsLoading = false;
  bool _communityLoading = false;
  bool _monthlyLoading = false;
  bool _isFav = false;
  bool _favLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _games.isEmpty && !_gamesLoading) {
        _loadGames();
      }
      if (_tabController.index == 2 && _rosterChanges.isEmpty && !_rosterLoading) {
        _loadRosterChanges();
      }
      if (_tabController.index == 3 && _news.isEmpty && !_newsLoading) {
        _loadNews();
      }
      if (_tabController.index == 4 && _communityPosts.isEmpty && !_communityLoading) {
        _loadCommunityPosts();
      }
      if (_tabController.index == 5 && _monthlyStats.isEmpty && !_monthlyLoading) {
        _loadMonthlyStats();
      }
    });
    _loadPlayers();
    _loadFavStatus();
  }

  Future<void> _loadFavStatus() async {
    try {
      final data = await ApiService.getFavoriteTeams();
      final teams = data['teams'] as List? ?? [];
      final id = widget.team['id'] as int;
      if (mounted) setState(() => _isFav = teams.any((t) => t['id'] == id));
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
    } catch (_) {}
    if (mounted) setState(() => _favLoading = false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPlayers() async {
    try {
      final data = await ApiService.getTeamPlayers(widget.team['id']);
      if (mounted) {
        setState(() {
          _players = data['players'] ?? [];
          _playersLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _playersLoading = false);
    }
  }

  Future<void> _loadGames() async {
    setState(() => _gamesLoading = true);
    try {
      final data = await ApiService.getTeamGames(widget.team['id']);
      if (mounted) {
        setState(() {
          _games = data['games'] ?? [];
          _gamesLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _gamesLoading = false);
    }
  }

  Future<void> _loadRosterChanges() async {
    setState(() => _rosterLoading = true);
    try {
      final data = await ApiService.getTeamRosterChanges(widget.team['id'], days: 30);
      if (mounted) {
        setState(() {
          _rosterChanges = data['changes'] ?? [];
          _rosterLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _rosterLoading = false);
    }
  }

  Future<void> _loadNews() async {
    setState(() => _newsLoading = true);
    try {
      final data = await ApiService.getTeamNews(widget.team['id'] as int, limit: 30);
      if (mounted) {
        setState(() {
          _news = data['news'] ?? [];
          _newsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _newsLoading = false);
    }
  }

  Future<void> _loadCommunityPosts() async {
    setState(() => _communityLoading = true);
    try {
      final data = await ApiService.getPosts(teamId: widget.team['id'] as int, sort: 'latest', page: 1);
      if (mounted) {
        setState(() {
          _communityPosts = data['posts'] ?? [];
          _communityLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _communityLoading = false);
    }
  }

  Future<void> _loadMonthlyStats() async {
    setState(() => _monthlyLoading = true);
    try {
      final data = await ApiService.getTeamMonthlyStats(widget.team['id'] as int);
      if (mounted) {
        setState(() {
          _monthlyStats = data['monthly'] ?? [];
          _monthlyLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _monthlyLoading = false);
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

    return Scaffold(
      appBar: AppBar(
        title: Text(team['name'] ?? ''),
        backgroundColor: color,
        foregroundColor: Colors.white,
        actions: [
          _favLoading
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
              : IconButton(
                  icon: Icon(_isFav ? Icons.star : Icons.star_border, color: Colors.white),
                  onPressed: _toggleFav,
                ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          isScrollable: true,
          tabs: const [Tab(text: '선수'), Tab(text: '최근경기'), Tab(text: '등록말소'), Tab(text: '뉴스'), Tab(text: '커뮤니티'), Tab(text: '월별성적')],
        ),
      ),
      body: Column(
        children: [
          _buildHeader(team, code, color, wins, losses, draws, hr, ar),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildPlayers(), _buildGames(), _buildRosterChanges(), _buildNews(), _buildCommunity(), _buildMonthlyStats()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Map team, String code, Color color,
      int wins, int losses, int draws,
      Map<String, dynamic> hr, Map<String, dynamic> ar) {
    final gb = team['games_behind'];
    final gbText = gb == null ? '-' : (gb as num) == 0 ? '-' : gb.toStringAsFixed(1);

    return Container(
      color: color.withOpacity(0.06),
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
                      '승률 ${(team['win_rate'] as num?)?.toStringAsFixed(3) ?? '-'}  게차 $gbText',
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
                  final homeWinPct = (hw + hl) > 0 ? (hw / (hw + hl)).toStringAsFixed(3) : '-';
                  final pythag = (team['pythag_winpct'] as num?)?.toStringAsFixed(3) ?? '-';
                  return Text(
                    '직관 승률 $homeWinPct  피타고리안 $pythag',
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
    if (_playersLoading) return const Center(child: CircularProgressIndicator());
    if (_players.isEmpty) return const Center(child: Text('선수 정보가 없습니다'));

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
      color: Colors.grey.withOpacity(0.1),
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
        MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: p['id'])),
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
    if (_gamesLoading) return const Center(child: CircularProgressIndicator());
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
          if ((my as num) > (opp as num)) wins++;
          else if (my < opp) losses++;
          else draws++;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.07),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
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
                          color: c.withOpacity(0.12),
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

  Widget _buildRosterChanges() {
    if (_rosterLoading) return const Center(child: CircularProgressIndicator());
    if (_rosterChanges.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('최근 30일 등록말소 내역이 없습니다', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    // 날짜별 그룹핑
    final Map<String, List> byDate = {};
    for (final c in _rosterChanges) {
      final date = c['change_date'] as String? ?? '';
      byDate.putIfAbsent(date, () => []).add(c);
    }
    final sortedDates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sortedDates.length,
      itemBuilder: (context, i) {
        final date = sortedDates[i];
        final items = byDate[date]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: Text(
                date,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
            ),
            ...items.map((c) => _buildChangeItem(c)),
            const Divider(height: 1),
          ],
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
          color: typeColor.withOpacity(0.15),
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
          color: typeColor.withOpacity(0.1),
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

  Widget _buildNews() {
    if (_newsLoading) return const Center(child: CircularProgressIndicator());
    if (_news.isEmpty) {
      return const Center(child: Text('뉴스가 없습니다', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _news.length,
      separatorBuilder: (context2, idx) => const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (_, i) {
        final n = _news[i] as Map;
        final title = n['title'] as String? ?? '';
        final media = n['media'] as String? ?? '';
        final pub = n['published_at'] as String?;
        final url = n['url'] as String? ?? '';

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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  if (media.isNotEmpty) ...[
                    Text(media, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    const SizedBox(width: 8),
                  ],
                  if (dateStr.isNotEmpty)
                    Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCommunity() {
    if (_communityLoading) return const Center(child: CircularProgressIndicator());
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
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
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
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(category,
                            style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
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
                    Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                    const Spacer(),
                    Icon(Icons.visibility_outlined, size: 12, color: Colors.grey[400]),
                    const SizedBox(width: 2),
                    Text('$views', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                    const SizedBox(width: 8),
                    Icon(Icons.favorite_border, size: 12, color: Colors.grey[400]),
                    const SizedBox(width: 2),
                    Text('$likes', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                    const SizedBox(width: 8),
                    Icon(Icons.comment_outlined, size: 12, color: Colors.grey[400]),
                    const SizedBox(width: 2),
                    Text('$comments', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
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
    if (_monthlyLoading) return const Center(child: CircularProgressIndicator());
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
                  getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1),
                  drawVerticalLine: false,
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.withOpacity(0.3)),
                    left: BorderSide(color: Colors.grey.withOpacity(0.3)),
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 0.25,
                      getTitlesWidget: (v, _) => Text(v.toStringAsFixed(2),
                          style: TextStyle(fontSize: 10, color: Colors.grey[600])),
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
                      getDotPainter: (_, __, ___, ____) =>
                          FlDotCirclePainter(radius: 4, color: color, strokeWidth: 1.5, strokeColor: Colors.white),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withOpacity(0.12),
                    ),
                  ),
                  // 5할 기준선
                  LineChartBarData(
                    spots: [FlSpot(0, 0.5), FlSpot((spots.length - 1).toDouble(), 0.5)],
                    isCurved: false,
                    color: Colors.grey.withOpacity(0.5),
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
            border: TableBorder.all(color: Colors.grey.withOpacity(0.2), width: 0.5),
            columnWidths: const {
              0: FlexColumnWidth(1.2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
              4: FlexColumnWidth(1.2),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: color.withOpacity(0.1)),
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
}
