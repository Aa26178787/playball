import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api/api_service.dart';
import '../../utils/team_theme.dart';
import '../player/player_detail_screen.dart';

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
  bool _playersLoading = true;
  bool _gamesLoading = false;
  bool _rosterLoading = false;
  bool _newsLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
    });
    _loadPlayers();
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [Tab(text: '선수'), Tab(text: '최근경기'), Tab(text: '등록말소'), Tab(text: '뉴스')],
        ),
      ),
      body: Column(
        children: [
          _buildHeader(team, code, color, wins, losses, draws, hr, ar),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildPlayers(), _buildGames(), _buildRosterChanges(), _buildNews()],
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

                return Padding(
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
                    ],
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

  void _openUrl(String url) async {
    if (url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
