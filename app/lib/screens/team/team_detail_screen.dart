import 'package:flutter/material.dart';
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
  bool _playersLoading = true;
  bool _gamesLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _games.isEmpty && !_gamesLoading) {
        _loadGames();
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
          tabs: const [Tab(text: '선수'), Tab(text: '최근경기')],
        ),
      ),
      body: Column(
        children: [
          _buildHeader(team, code, color, wins, losses, draws, hr, ar),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildPlayers(), _buildGames()],
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

  Widget _buildGames() {
    if (_gamesLoading) return const Center(child: CircularProgressIndicator());
    if (_games.isEmpty) return const Center(child: Text('경기 정보가 없습니다'));

    final teamName = widget.team['name'] as String? ?? '';

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _games.length,
      itemBuilder: (context, index) {
        final g = _games[index];
        final isHome = g['home_team'] == teamName;
        final myScore = isHome ? (g['home_score'] ?? 0) : (g['away_score'] ?? 0);
        final oppScore = isHome ? (g['away_score'] ?? 0) : (g['home_score'] ?? 0);
        final oppName = isHome ? g['away_team'] : g['home_team'];
        final isWin = myScore > oppScore;
        final isLoss = myScore < oppScore;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isWin ? Colors.blue : isLoss ? Colors.red : Colors.grey,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  isWin ? '승' : isLoss ? '패' : '무',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'vs $oppName',
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                    ),
                    Text(
                      '${isHome ? '홈' : '원정'} · ${g['game_date'] ?? ''}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              Text(
                '$myScore : $oppScore',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        );
      },
    );
  }
}
